// SwiftUI 状态能力
import Combine
// 数据持久化基础库
import Foundation

final class QuotaStore: ObservableObject {
    // 当前读取状态。
    @Published private(set) var status: QuotaLoadStatus = .idle
    // 当前额度快照。
    @Published private(set) var snapshot: QuotaSnapshot?
    // 当前节奏分析结果。
    @Published private(set) var pace = QuotaPace(fiveHour: nil, weekly: nil, summary: .unknown)
    // 最近更新时间。
    @Published private(set) var lastUpdatedAt: Date?
    // 是否正在刷新。
    @Published private(set) var isRefreshing = false

    let settings: AppSettings

    private let client: CodexQuotaClient
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let cacheURL: URL
    private let historyURL: URL

    /// 创建额度状态仓库。
    /// - Parameters:
    ///   - client: Codex 额度读取客户端。
    ///   - settings: 用户配置仓库。
    init(client: CodexQuotaClient = CodexQuotaClient(), settings: AppSettings = AppSettings()) {
        self.client = client
        self.settings = settings

        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("CodexQuotaMac", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CodexQuotaMac", isDirectory: true)
        cacheURL = directory.appendingPathComponent("quota-cache.json")
        historyURL = directory.appendingPathComponent("quota-history.json")

        settings.$refreshIntervalMinutes
            .sink { [weak self] _ in
                self?.restartAutoRefresh()
            }
            .store(in: &cancellables)
    }

    /// 从本地缓存读取上次额度快照。
    func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let payload = try? JSONDecoder.codexQuota.decode(QuotaCachePayload.self, from: data) else {
            return
        }
        snapshot = payload.quota
        lastUpdatedAt = payload.savedAt
        status = .ready
        pace = QuotaAnalyzer.analyze(snapshot: payload.quota)
    }

    /// 开启自动刷新定时器。
    func startAutoRefresh() {
        restartAutoRefresh()
    }

    /// 停止自动刷新定时器。
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// 手动或自动刷新 Codex 额度。
    /// - Parameter reason: 刷新来源，用于调试定位。
    func refresh(reason: String = "manual") {
        if isRefreshing {
            return
        }

        isRefreshing = true
        status = snapshot == nil ? .loading : .ready
        client.fetchQuota { [weak self] result in
            guard let self else {
                return
            }
            self.isRefreshing = false
            switch result {
            case let .success(snapshot):
                self.snapshot = snapshot
                self.lastUpdatedAt = snapshot.fetchedAt
                self.status = .ready
                self.pace = QuotaAnalyzer.analyze(snapshot: snapshot)
                self.saveCache(snapshot)
                self.recordHistory(snapshot)
            case let .failure(error):
                self.status = .failed(error.localizedDescription)
            }
        }
    }

    /// 生成状态栏标题文本。
    /// - Returns: 根据用户配置拼出的状态栏文本。
    func statusBarTitle() -> String {
        guard let snapshot else {
            switch status {
            case .loading:
                return "Codex ..."
            case .failed:
                return "Codex --"
            default:
                return "Codex"
            }
        }

        var parts: [String] = []
        if settings.showFiveHour, let fiveHour = snapshot.fiveHourWindow {
            parts.append("5h \(formatPercent(fiveHour.remainingPercent))")
        }
        if settings.showWeekly, let weekly = snapshot.weeklyWindow {
            parts.append("7d \(formatPercent(weekly.remainingPercent))")
        }
        if settings.showSummary, pace.summary != .unknown {
            parts.append(pace.summary.title)
        }
        if parts.isEmpty {
            parts.append("Codex \(formatPercent(snapshot.remainingPercent))")
        }
        return parts.joined(separator: " · ")
    }

    /// 返回用于展示的百分比文本。
    /// - Parameter value: 百分比数值。
    /// - Returns: 无多余小数的百分比字符串。
    func formatPercent(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))%"
        }
        return String(format: "%.1f%%", value)
    }

    /// 重新创建自动刷新定时器。
    private func restartAutoRefresh() {
        stopAutoRefresh()
        let minutes = max(1, min(30, settings.refreshIntervalMinutes))
        refreshTimer = Timer.scheduledTimer(withTimeInterval: minutes * 60, repeats: true) { [weak self] _ in
            self?.refresh(reason: "scheduled")
        }
    }

    /// 保存最新额度缓存。
    /// - Parameter snapshot: 最新额度快照。
    private func saveCache(_ snapshot: QuotaSnapshot) {
        let payload = QuotaCachePayload(version: 1, savedAt: Date(), quota: snapshot)
        writeJSON(payload, to: cacheURL)
    }

    /// 记录额度历史样本，demo 保留最近 14 天。
    /// - Parameter snapshot: 最新额度快照。
    private func recordHistory(_ snapshot: QuotaSnapshot) {
        var samples: [QuotaSnapshot] = []
        if let data = try? Data(contentsOf: historyURL),
           let payload = try? JSONDecoder.codexQuota.decode(QuotaHistoryPayload.self, from: data) {
            samples = payload.samples
        }

        let cutoff = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        samples = samples.filter { $0.fetchedAt >= cutoff && $0.fetchedAt != snapshot.fetchedAt }
        samples.append(snapshot)
        samples = Array(samples.suffix(4096))

        let payload = QuotaHistoryPayload(version: 1, samples: samples)
        writeJSON(payload, to: historyURL)
    }

    /// 写入 JSON 文件并自动创建父目录。
    /// - Parameters:
    ///   - value: 可编码对象。
    ///   - url: 写入目标路径。
    private func writeJSON<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try JSONEncoder.codexQuota.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            // 缓存失败不影响实时额度展示。
        }
    }
}

extension JSONEncoder {
    static var codexQuota: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var codexQuota: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
