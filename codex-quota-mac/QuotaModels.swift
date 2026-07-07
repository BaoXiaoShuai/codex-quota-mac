// 基础数据类型
import Foundation

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
        if let window = windows.first(where: { $0.isWeeklyWindow }) {
            return window
        }
        return secondary ?? primary
    }

    /// 选择较短周期窗口作为 5 小时额度展示数据。
    var fiveHourWindow: QuotaWindow? {
        let windows = [primary, secondary].compactMap { $0 }
        if let window = windows.first(where: { $0.isFiveHourWindow }) {
            return window
        }
        return primary == weeklyWindow ? secondary : primary
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

struct QuotaHistoryPayload: Codable {
    let version: Int
    let samples: [QuotaSnapshot]
}
