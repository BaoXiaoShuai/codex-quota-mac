// macOS 进程与文件能力
import Foundation

enum CodexQuotaClientError: LocalizedError {
    case codexUnavailable
    case launchFailed(String)
    case timeout(String)
    case invalidResponse
    case missingDashboardData
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
        case .missingDashboardData:
            return "Codex 未返回账号、Token 用量或额度数据。"
        case .missingQuota:
            return "Codex 未返回可用的额度窗口。"
        case .invalidWindow:
            return "Codex 额度窗口缺少 usedPercent 或 reset 时间格式异常。"
        }
    }
}

final class CodexQuotaClient {
    private let timeoutSeconds: TimeInterval
    private let localUsageReader: LocalCodexUsageReader

    /// 创建 Codex 额度读取客户端。
    /// - Parameters:
    ///   - timeoutSeconds: 单次 JSON-RPC 请求等待秒数。
    ///   - localUsageReader: 本机 Codex 会话 Token 读取器。
    init(
        timeoutSeconds: TimeInterval = 12,
        localUsageReader: LocalCodexUsageReader = LocalCodexUsageReader()
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.localUsageReader = localUsageReader
    }

    /// 调用本机 Codex app-server 读取账号、Token 用量和额度快照。
    /// - Parameter completion: 返回规范化后的仪表盘快照或错误。
    func fetchDashboard(completion: @escaping (Result<CodexDashboardSnapshot, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let snapshot = try self.readDashboard()
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

    /// 执行 Codex JSON-RPC 初始化和仪表盘数据读取流程。
    /// - Returns: 规范化后的账号、Token 用量和额度快照。
    private func readDashboard() throws -> CodexDashboardSnapshot {
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

        try send(id: 2, method: "account/read", params: ["refreshToken": false], to: stdin)
        try send(id: 3, method: "account/usage/read", params: nil, to: stdin)
        try send(id: 4, method: "account/rateLimits/read", params: nil, to: stdin)

        let accountResponse = try? collector.waitForResponse(
            id: 2,
            method: "account/read",
            timeoutSeconds: timeoutSeconds
        )
        let usageResponse = try? collector.waitForResponse(
            id: 3,
            method: "account/usage/read",
            timeoutSeconds: timeoutSeconds
        )
        let quotaResponse = try? collector.waitForResponse(
            id: 4,
            method: "account/rateLimits/read",
            timeoutSeconds: timeoutSeconds
        )

        let account = resultPayload(from: accountResponse).flatMap(normalizeAccountPayload)
        let officialTokenUsage = resultPayload(from: usageResponse).flatMap(normalizeTokenUsagePayload)
        let localTokenUsage = localUsageReader.readToday()
        let tokenUsage = localTokenUsage?.merging(into: officialTokenUsage) ?? officialTokenUsage
        let quota = resultPayload(from: quotaResponse).flatMap { payload in
            try? normalizeQuotaPayload(payload)
        }

        // 三类数据相互独立：单个接口不可用时保留其余已读取内容，全部为空才视为失败。
        guard account != nil || tokenUsage != nil || quota != nil else {
            let message = [accountResponse, usageResponse, quotaResponse]
                .compactMap(rpcErrorMessage)
                .first
            if let message {
                throw CodexQuotaClientError.launchFailed(message)
            }
            throw CodexQuotaClientError.missingDashboardData
        }

        return CodexDashboardSnapshot(
            account: account,
            tokenUsage: tokenUsage,
            quota: quota,
            fetchedAt: Date()
        )
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
            "/Applications/ChatGPT.app/Contents/Resources/codex",
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

    /// 提取 JSON-RPC 成功响应中的 result 对象。
    /// - Parameter response: JSON-RPC 原始响应。
    /// - Returns: result 字典；响应为空或失败时返回 nil。
    private func resultPayload(from response: [String: Any]?) -> [String: Any]? {
        response?["result"] as? [String: Any]
    }

    /// 提取 JSON-RPC 错误文案。
    /// - Parameter response: JSON-RPC 原始响应。
    /// - Returns: 服务端错误文案；不存在时返回 nil。
    private func rpcErrorMessage(from response: [String: Any]?) -> String? {
        let error = response?["error"] as? [String: Any]
        return error?["message"] as? String
    }

    /// 将 account/read 返回转换为账号信息。
    /// - Parameter payload: account/read 返回数据。
    /// - Returns: 当前账号信息；未登录时返回 nil。
    private func normalizeAccountPayload(_ payload: [String: Any]) -> CodexAccount? {
        guard let account = payload["account"] as? [String: Any],
              let type = account["type"] as? String else {
            return nil
        }
        return CodexAccount(
            type: type,
            email: account["email"] as? String,
            planType: account["planType"] as? String
        )
    }

    /// 将 account/usage/read 返回转换为每日与累计 Token 数据。
    /// - Parameter payload: account/usage/read 返回数据。
    /// - Returns: Token 用量信息；响应结构不完整时返回 nil。
    private func normalizeTokenUsagePayload(_ payload: [String: Any]) -> AccountTokenUsage? {
        guard let summaryPayload = payload["summary"] as? [String: Any] else {
            return nil
        }

        let buckets = (payload["dailyUsageBuckets"] as? [[String: Any]] ?? []).compactMap { bucket -> TokenUsageDailyBucket? in
            guard let startDate = bucket["startDate"] as? String,
                  let tokens = integerValue(bucket["tokens"]) else {
                return nil
            }
            return TokenUsageDailyBucket(startDate: startDate, tokens: tokens)
        }

        let summary = AccountTokenUsageSummary(
            currentStreakDays: integerValue(summaryPayload["currentStreakDays"]),
            lifetimeTokens: integerValue(summaryPayload["lifetimeTokens"]),
            longestRunningTurnSec: integerValue(summaryPayload["longestRunningTurnSec"]),
            longestStreakDays: integerValue(summaryPayload["longestStreakDays"]),
            peakDailyTokens: integerValue(summaryPayload["peakDailyTokens"])
        )
        return AccountTokenUsage(dailyUsageBuckets: buckets, summary: summary)
    }

    /// 将 Codex 原始返回转换为应用内部快照。
    /// - Parameter payload: account/rateLimits/read 返回数据。
    /// - Returns: 规范化后的额度快照。
    private func normalizeQuotaPayload(_ payload: [String: Any]) throws -> QuotaSnapshot {
        guard let quota = payload["rateLimits"] as? [String: Any] else {
            throw CodexQuotaClientError.missingQuota
        }

        let primary = try normalizeWindow(quota["primary"])
        let secondary = try normalizeWindow(quota["secondary"])
        guard let activeWindow = primary ?? secondary else {
            throw CodexQuotaClientError.missingQuota
        }

        return QuotaSnapshot(
            limitId: quota["limitId"] as? String ?? "codex",
            limitName: quota["limitName"] as? String ?? "Codex",
            planType: quota["planType"] as? String ?? "unknown",
            reachedType: quota["rateLimitReachedType"] as? String,
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

    /// 从 JSON 动态值提取 Int64。
    /// - Parameter value: JSONSerialization 解析后的任意值。
    /// - Returns: 可转换时返回 Int64，否则返回 nil。
    private func integerValue(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let string = value as? String {
            return Int64(string)
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
