// macOS 进程与文件能力
import Foundation

enum CodexQuotaClientError: LocalizedError {
    case codexUnavailable
    case launchFailed(String)
    case timeout(String)
    case invalidResponse
    case missingQuota
    case invalidWindow

    var errorDescription: String? {
        switch self {
        case .codexUnavailable:
            return "未找到 codex 命令，请确认 Codex CLI 已安装并已登录。"
        case let .launchFailed(message):
            return "Codex app-server 启动失败：\(message)"
        case let .timeout(method):
            return "Codex 请求超时：\(method)"
        case .invalidResponse:
            return "Codex 返回了无法解析的数据。"
        case .missingQuota:
            return "Codex 未返回可用的额度窗口。"
        case .invalidWindow:
            return "Codex 额度窗口缺少 usedPercent 或 reset 时间格式异常。"
        }
    }
}

final class CodexQuotaClient {
    private let timeoutSeconds: TimeInterval

    /// 创建 Codex 额度读取客户端。
    /// - Parameter timeoutSeconds: 单次 JSON-RPC 请求等待秒数。
    init(timeoutSeconds: TimeInterval = 12) {
        self.timeoutSeconds = timeoutSeconds
    }

    /// 调用本机 Codex app-server 读取额度快照。
    /// - Parameter completion: 返回规范化后的额度快照或错误。
    func fetchQuota(completion: @escaping (Result<QuotaSnapshot, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let snapshot = try self.readQuota()
                DispatchQueue.main.async {
                    completion(.success(snapshot))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// 执行 Codex JSON-RPC 初始化和额度读取流程。
    /// - Returns: 规范化后的额度快照。
    private func readQuota() throws -> QuotaSnapshot {
        guard let codexPath = resolvedCodexPath() else {
            throw CodexQuotaClientError.codexUnavailable
        }

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        let collector = RPCResponseCollector()

        configureProcess(process, codexPath: codexPath)
        process.arguments = launchArguments()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            collector.append(data: data)
        }

        do {
            try process.run()
        } catch {
            throw CodexQuotaClientError.launchFailed(error.localizedDescription)
        }

        defer {
            stdout.fileHandleForReading.readabilityHandler = nil
            if process.isRunning {
                process.terminate()
            }
        }

        try send(
            id: 1,
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "codex-quota-mac",
                    "title": "Codex Quota Mac",
                    "version": "0.1.0"
                ],
                "capabilities": NSNull()
            ],
            to: stdin
        )
        _ = try collector.waitForResponse(id: 1, method: "initialize", timeoutSeconds: timeoutSeconds)

        try send(id: 2, method: "account/rateLimits/read", params: nil, to: stdin)
        let result = try collector.waitForResponse(
            id: 2,
            method: "account/rateLimits/read",
            timeoutSeconds: timeoutSeconds
        )

        if let errorMessage = result["error"] as? [String: Any],
           let message = errorMessage["message"] as? String {
            throw CodexQuotaClientError.launchFailed(message)
        }

        guard let payload = result["result"] as? [String: Any] else {
            throw CodexQuotaClientError.invalidResponse
        }
        return try normalizeQuotaPayload(payload)
    }

    /// 配置 Codex app-server 的启动路径。
    /// - Parameter process: 待启动的系统进程。
    private func configureProcess(_ process: Process, codexPath: String) {
        process.executableURL = URL(fileURLWithPath: codexPath)
    }

    /// 返回启动 Codex app-server 所需参数。
    /// - Returns: app-server 启动参数列表。
    private func launchArguments() -> [String] {
        ["app-server", "--listen", "stdio://"]
    }

    /// 解析 Codex CLI 的常见安装路径。
    /// - Returns: 找到可执行文件时返回绝对路径，否则返回 nil。
    private func resolvedCodexPath() -> String? {
        let environment = ProcessInfo.processInfo.environment
        let fixedCandidates = [
            environment["CODEX_CLI_PATH"],
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(NSHomeDirectory())/.npm-global/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex"
        ]
        let pathCandidates: [String?] = environment["PATH"]?
            .split(separator: ":")
            .map { "\($0)/codex" } ?? []

        return (fixedCandidates + pathCandidates)
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// 向 Codex app-server 写入一条 JSON-RPC 请求。
    /// - Parameters:
    ///   - id: 请求 id。
    ///   - method: JSON-RPC 方法名。
    ///   - params: 请求参数。
    ///   - pipe: 标准输入管道。
    private func send(id: Int, method: String, params: [String: Any]?, to pipe: Pipe) throws {
        var payload: [String: Any] = [
            "id": id,
            "method": method
        ]
        if let params {
            payload["params"] = params
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        pipe.fileHandleForWriting.write(data)
        pipe.fileHandleForWriting.write(Data("\n".utf8))
    }

    /// 将 Codex 原始返回转换为应用内部快照。
    /// - Parameter payload: account/rateLimits/read 返回数据。
    /// - Returns: 规范化后的额度快照。
    private func normalizeQuotaPayload(_ payload: [String: Any]) throws -> QuotaSnapshot {
        guard let limits = payload["rateLimitsByLimitId"] as? [String: Any],
              let codex = limits["codex"] as? [String: Any] else {
            throw CodexQuotaClientError.missingQuota
        }

        let primary = try normalizeWindow(codex["primary"])
        let secondary = try normalizeWindow(codex["secondary"])
        guard let activeWindow = primary ?? secondary else {
            throw CodexQuotaClientError.missingQuota
        }

        return QuotaSnapshot(
            limitId: codex["limitId"] as? String ?? "codex",
            limitName: codex["limitName"] as? String ?? "Codex",
            planType: codex["planType"] as? String ?? "unknown",
            reachedType: codex["rateLimitReachedType"] as? String,
            primary: primary,
            secondary: secondary,
            remainingPercent: activeWindow.remainingPercent,
            usedPercent: activeWindow.usedPercent,
            resetsAt: activeWindow.resetsAt,
            fetchedAt: Date()
        )
    }

    /// 规范化 Codex 单个额度窗口。
    /// - Parameter value: Codex 返回的 primary 或 secondary 窗口。
    /// - Returns: 应用内部额度窗口；窗口为空时返回 nil。
    private func normalizeWindow(_ value: Any?) throws -> QuotaWindow? {
        guard let window = value as? [String: Any] else {
            return nil
        }
        guard let usedPercent = numberValue(window["usedPercent"]) else {
            throw CodexQuotaClientError.invalidWindow
        }
        let resetSeconds = numberValue(window["resetsAt"])
        let resetDate = resetSeconds.map { Date(timeIntervalSince1970: $0) }
        let remainingPercent = max(0, min(100, 100 - usedPercent))

        return QuotaWindow(
            usedPercent: round1(max(0, min(100, usedPercent))),
            remainingPercent: round1(remainingPercent),
            windowDurationMins: numberValue(window["windowDurationMins"]),
            resetsAt: resetDate
        )
    }

    /// 从 JSON 动态值提取 Double。
    /// - Parameter value: JSONSerialization 解析后的任意值。
    /// - Returns: 可转换时返回 Double，否则返回 nil。
    private func numberValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    /// 保留一位小数，避免 UI 出现冗长数字。
    /// - Parameter value: 原始数值。
    /// - Returns: 一位小数数值。
    private func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

final class RPCResponseCollector {
    private let lock = NSLock()
    private var buffer = Data()
    private var responses: [Int: [String: Any]] = [:]

    /// 追加 stdout 数据并按行解析 JSON-RPC 响应。
    /// - Parameter data: Codex app-server stdout 数据。
    func append(data: Data) {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(data)
        while let newlineRange = buffer.firstRange(of: Data("\n".utf8)) {
            let line = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)

            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = (object["id"] as? NSNumber)?.intValue ?? object["id"] as? Int else {
                continue
            }
            responses[id] = object
        }
    }

    /// 等待指定 id 的 JSON-RPC 响应。
    /// - Parameters:
    ///   - id: 请求 id。
    ///   - method: 方法名，用于错误提示。
    ///   - timeoutSeconds: 最大等待时间。
    /// - Returns: JSON-RPC 响应对象。
    func waitForResponse(id: Int, method: String, timeoutSeconds: TimeInterval) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            lock.lock()
            if let response = responses.removeValue(forKey: id) {
                lock.unlock()
                return response
            }
            lock.unlock()
            Thread.sleep(forTimeInterval: 0.03)
        }
        throw CodexQuotaClientError.timeout(method)
    }
}
