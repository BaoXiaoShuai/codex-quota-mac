// 基础数据类型
import Foundation

struct CodexAccount: Codable, Equatable {
    let type: String
    let email: String?
    let planType: String?
}

struct TokenUsageDailyBucket: Codable, Equatable, Identifiable {
    let startDate: String
    let tokens: Int64

    var id: String {
        startDate
    }
}

struct AccountTokenUsageSummary: Codable, Equatable {
    let currentStreakDays: Int64?
    let lifetimeTokens: Int64?
    let longestRunningTurnSec: Int64?
    let longestStreakDays: Int64?
    let peakDailyTokens: Int64?
}

struct AccountTokenUsage: Codable, Equatable {
    let dailyUsageBuckets: [TokenUsageDailyBucket]
    let summary: AccountTokenUsageSummary

    /// 返回按日期升序排列的每日 Token 数据。
    /// - Returns: 日期从早到晚的每日 Token 数组。
    var sortedDailyBuckets: [TokenUsageDailyBucket] {
        dailyUsageBuckets.sorted { $0.startDate < $1.startDate }
    }
}

struct CodexDashboardSnapshot: Codable, Equatable {
    let account: CodexAccount?
    let tokenUsage: AccountTokenUsage?
    let quota: QuotaSnapshot?
    let fetchedAt: Date
}

struct QuotaWindow: Codable, Equatable {
    let usedPercent: Double
    let remainingPercent: Double
    let windowDurationMins: Double?
    let resetsAt: Date?

    /// 根据窗口时长判断是否接近 7 天额度窗口。
    var isWeeklyWindow: Bool {
        guard let windowDurationMins else {
            return false
        }
        return windowDurationMins >= 24 * 60
    }

    /// 根据窗口时长判断是否接近 5 小时额度窗口。
    var isFiveHourWindow: Bool {
        guard let windowDurationMins else {
            return false
        }
        return windowDurationMins < 24 * 60
    }
}

struct QuotaSnapshot: Codable, Equatable {
    let limitId: String
    let limitName: String
    let planType: String
    let reachedType: String?
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    let remainingPercent: Double
    let usedPercent: Double
    let resetsAt: Date?
    let fetchedAt: Date

    /// 选择较长周期窗口作为 7 天额度展示数据。
    var weeklyWindow: QuotaWindow? {
        let windows = [primary, secondary].compactMap { $0 }
        return windows.first(where: { $0.isWeeklyWindow })
    }

    /// 选择较短周期窗口作为 5 小时额度展示数据。
    var fiveHourWindow: QuotaWindow? {
        let windows = [primary, secondary].compactMap { $0 }
        return windows.first(where: { $0.isFiveHourWindow })
    }
}

struct QuotaWindowPace: Equatable {
    let remainingPercent: Double
    let idealRemainingPercent: Double?
    let paceDelta: Double?
    let status: PaceStatus
}

struct QuotaPace: Equatable {
    let fiveHour: QuotaWindowPace?
    let weekly: QuotaWindowPace?
    let summary: PaceStatus
}

enum PaceStatus: String, Equatable {
    case accelerate
    case normal
    case recentFast
    case slow
    case critical
    case unknown

    var title: String {
        switch self {
        case .accelerate:
            return "余量充足"
        case .normal:
            return "节奏正常"
        case .recentFast:
            return "近期偏快"
        case .slow:
            return "建议减速"
        case .critical:
            return "接近耗尽"
        case .unknown:
            return "无法判断"
        }
    }
}

enum QuotaLoadStatus: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

struct QuotaCachePayload: Codable {
    let version: Int
    let savedAt: Date
    let quota: QuotaSnapshot
}

struct DashboardCachePayload: Codable {
    let version: Int
    let savedAt: Date
    let account: CodexAccount?
    let tokenUsage: AccountTokenUsage?
    let quota: QuotaSnapshot?
}

struct QuotaHistoryPayload: Codable {
    let version: Int
    let samples: [QuotaSnapshot]
}
