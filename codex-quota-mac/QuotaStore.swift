// SwiftUI 状态能力
import Combine
// 数据持久化基础库
import Foundation

final class QuotaStore: ObservableObject {
    // 当前读取状态。
    @Published private(set) var status: QuotaLoadStatus = .idle
    // 当前 Codex 账号信息。
    @Published private(set) var account: CodexAccount?
    // 当前每日与累计 Token 用量。
    @Published private(set) var tokenUsage: AccountTokenUsage?
    // 当前额度快照。
    @Published private(set) var snapshot: QuotaSnapshot?
    // 最近额度历史样本，用于控制本地采样频率。
    private var quotaHistory: [QuotaSnapshot] = []
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
    private let historySamplingInterval: TimeInterval = 5 * 60
    private let refreshFreshnessInterval: TimeInterval = 45

    // 5h 重置时间格式：HH:mm
    private let fiveHourTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // 7d 重置时间格式：M/d（月/日）
    private let weeklyDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

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

    /// 从本地缓存读取上次账号、Token 用量和额度快照。
    func loadCache() {
        loadHistory()
        guard let data = try? Data(contentsOf: cacheURL) else {
            return
        }

        if let payload = try? JSONDecoder.codexQuota.decode(DashboardCachePayload.self, from: data) {
            account = payload.account
            tokenUsage = payload.tokenUsage
            snapshot = payload.quota
            lastUpdatedAt = payload.savedAt
            status = .ready
            pace = QuotaAnalyzer.analyze(snapshot: payload.quota)
            return
        }

        // 兼容旧版仅包含额度的数据缓存，升级后首次刷新会写入完整结构。
        if let payload = try? JSONDecoder.codexQuota.decode(QuotaCachePayload.self, from: data) {
            snapshot = payload.quota
            lastUpdatedAt = payload.savedAt
            status = .ready
            pace = QuotaAnalyzer.analyze(snapshot: payload.quota)
        }
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

    /// 刷新 Codex 账号、Token 用量和额度，并跳过短时间内的重复后台请求。
    /// - Parameters:
    ///   - reason: 刷新来源，用于调试定位。
    ///   - force: 是否忽略数据新鲜度并立即刷新。
    func refresh(reason: String = "manual", force: Bool = false) {
        if isRefreshing {
            return
        }
        // 打开面板和自动任务共享新鲜度限制；启动和用户手动操作通过 force 强制刷新。
        if !force,
           let lastUpdatedAt,
           Date().timeIntervalSince(lastUpdatedAt) < refreshFreshnessInterval {
            return
        }

        isRefreshing = true
        status = hasDashboardData ? .ready : .loading
        client.fetchDashboard { [weak self] result in
            guard let self else {
                return
            }
            self.isRefreshing = false
            switch result {
            case let .success(dashboard):
                // 三个接口独立刷新，Token 日期桶还需与本地历史逐日合并，避免不完整响应清空月历。
                let mergedDashboard = CodexDashboardSnapshot(
                    account: dashboard.account ?? self.account,
                    tokenUsage: self.mergeTokenUsage(cached: self.tokenUsage, fresh: dashboard.tokenUsage),
                    quota: dashboard.quota ?? self.snapshot,
                    fetchedAt: dashboard.fetchedAt
                )
                self.account = mergedDashboard.account
                self.tokenUsage = mergedDashboard.tokenUsage
                self.snapshot = mergedDashboard.quota
                self.lastUpdatedAt = mergedDashboard.fetchedAt
                self.status = .ready
                self.pace = QuotaAnalyzer.analyze(snapshot: mergedDashboard.quota)
                self.saveCache(mergedDashboard)
                if let quota = dashboard.quota {
                    self.recordHistory(quota)
                }
            case let .failure(error):
                self.status = .failed(error.localizedDescription)
            }
        }
    }

    /// 生成状态栏标题文本。
    /// 格式：「5h 86% 08:09 | 7d 72% 7/14」，可配置是否显示重置时间。
    /// - Returns: 根据用户配置拼出的状态栏文本。
    func statusBarTitle() -> String {
        guard let snapshot else {
            switch status {
            case .loading: return "Codex ..."
            case .failed: return "Codex --"
            default: return "Codex"
            }
        }

        var parts: [String] = []

        if settings.showFiveHour, let fiveHour = snapshot.fiveHourWindow {
            var text = "5h \(formatPercent(fiveHour.remainingPercent))"
            // 开启显示重置时间时附加 HH:mm
            if settings.showResetTime, let d = fiveHour.resetsAt {
                text += " \(fiveHourTimeFormatter.string(from: d))"
            }
            parts.append(text)
        }

        if settings.showWeekly, let weekly = snapshot.weeklyWindow {
            var text = "7d \(formatPercent(weekly.remainingPercent))"
            // 开启显示重置时间时附加 M/d
            if settings.showResetTime, let d = weekly.resetsAt {
                text += " \(weeklyDateFormatter.string(from: d))"
            }
            parts.append(text)
        }

        if settings.showSummary, pace.summary != .unknown {
            parts.append(pace.summary.title)
        }

        if parts.isEmpty {
            return "Codex \(formatPercent(snapshot.remainingPercent))"
        }
        // 用竖线分隔两个额度窗口
        return parts.joined(separator: " | ")
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

    /// 将实时 Token 数据按日期合入本地缓存，保留接口本次未返回的历史记录。
    /// - Parameters:
    ///   - cached: 本地已缓存的完整 Token 数据。
    ///   - fresh: 本次接口及本地会话读取到的最新 Token 数据。
    /// - Returns: 历史日期不丢失、当天数据持续更新的合并结果。
    private func mergeTokenUsage(
        cached: AccountTokenUsage?,
        fresh: AccountTokenUsage?
    ) -> AccountTokenUsage? {
        guard let fresh else {
            return cached
        }
        guard let cached else {
            return fresh
        }

        var tokensByDate: [String: Int64] = [:]
        for bucket in cached.dailyUsageBuckets + fresh.dailyUsageBuckets {
            let dateKey = String(bucket.startDate.prefix(10))
            guard dateKey.count == 10 else {
                continue
            }
            // 同一日期可能同时存在缓存、官方桶和本地实时值，取最大值避免刷新后倒退或消失。
            tokensByDate[dateKey] = max(tokensByDate[dateKey] ?? 0, max(0, bucket.tokens))
        }

        let mergedBuckets = tokensByDate
            .map { TokenUsageDailyBucket(startDate: $0.key, tokens: $0.value) }
            .sorted { $0.startDate < $1.startDate }
        let cachedSummary = cached.summary
        let freshSummary = fresh.summary
        let mergedSummary = AccountTokenUsageSummary(
            currentStreakDays: freshSummary.currentStreakDays ?? cachedSummary.currentStreakDays,
            lifetimeTokens: maximumValue(cachedSummary.lifetimeTokens, freshSummary.lifetimeTokens),
            longestRunningTurnSec: maximumValue(cachedSummary.longestRunningTurnSec, freshSummary.longestRunningTurnSec),
            longestStreakDays: maximumValue(cachedSummary.longestStreakDays, freshSummary.longestStreakDays),
            peakDailyTokens: maximumValue(cachedSummary.peakDailyTokens, freshSummary.peakDailyTokens)
        )
        return AccountTokenUsage(dailyUsageBuckets: mergedBuckets, summary: mergedSummary)
    }

    /// 返回两个可选数值中的较大有效值。
    /// - Parameters:
    ///   - first: 已缓存数值。
    ///   - second: 最新数值。
    /// - Returns: 两者较大值；均为空时返回 nil。
    private func maximumValue(_ first: Int64?, _ second: Int64?) -> Int64? {
        [first, second].compactMap { $0 }.max()
    }

    /// 保存最新仪表盘缓存。
    /// - Parameter snapshot: 最新账号、Token 用量和额度快照。
    private func saveCache(_ snapshot: CodexDashboardSnapshot) {
        let payload = DashboardCachePayload(
            version: 2,
            savedAt: snapshot.fetchedAt,
            account: snapshot.account,
            tokenUsage: snapshot.tokenUsage,
            quota: snapshot.quota
        )
        writeJSON(payload, to: cacheURL)
    }

    /// 判断当前是否已有任一类可展示数据。
    /// - Returns: 账号、Token 用量或额度任一存在时返回 true。
    private var hasDashboardData: Bool {
        account != nil || tokenUsage != nil || snapshot != nil
    }

    /// 从本地读取最近 14 天额度历史样本。
    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let payload = try? JSONDecoder.codexQuota.decode(QuotaHistoryPayload.self, from: data) else {
            return
        }
        let cutoff = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        quotaHistory = payload.samples
            .filter { $0.fetchedAt >= cutoff }
            .sorted { $0.fetchedAt < $1.fetchedAt }
    }

    /// 记录额度历史样本，按 5 分钟采样并在额度变化时立即追加。
    /// - Parameter snapshot: 最新额度快照。
    private func recordHistory(_ snapshot: QuotaSnapshot) {
        let cutoff = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        var samples = quotaHistory.filter { $0.fetchedAt >= cutoff && $0.fetchedAt != snapshot.fetchedAt }
        if let latest = samples.last {
            let elapsed = snapshot.fetchedAt.timeIntervalSince(latest.fetchedAt)
            // 未达到采样间隔且额度、重置周期都没有变化时，不重复写入相同状态。
            if elapsed < historySamplingInterval, !hasQuotaChanged(from: latest, to: snapshot) {
                quotaHistory = samples
                return
            }
        }
        samples.append(snapshot)
        samples = Array(samples.suffix(4096))
        quotaHistory = samples

        let payload = QuotaHistoryPayload(version: 1, samples: samples)
        writeJSON(payload, to: historyURL)
    }

    /// 判断两个额度快照的窗口用量或重置周期是否发生变化。
    /// - Parameters:
    ///   - previous: 上一个已记录额度快照。
    ///   - current: 当前额度快照。
    /// - Returns: 任一额度窗口发生有效变化时返回 true。
    private func hasQuotaChanged(from previous: QuotaSnapshot, to current: QuotaSnapshot) -> Bool {
        quotaWindowChanged(previous.fiveHourWindow, current.fiveHourWindow)
            || quotaWindowChanged(previous.weeklyWindow, current.weeklyWindow)
    }

    /// 判断单个额度窗口是否发生有效变化。
    /// - Parameters:
    ///   - previous: 上一个额度窗口。
    ///   - current: 当前额度窗口。
    /// - Returns: 窗口新增、移除、用量变化或重置周期变化时返回 true。
    private func quotaWindowChanged(_ previous: QuotaWindow?, _ current: QuotaWindow?) -> Bool {
        if (previous == nil) != (current == nil) {
            return true
        }
        guard let previous, let current else {
            return false
        }
        // 同时比较用量和重置时间，覆盖额度消耗与新周期开始两类变化。
        return abs(previous.usedPercent - current.usedPercent) >= 0.1
            || previous.resetsAt != current.resetsAt
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
