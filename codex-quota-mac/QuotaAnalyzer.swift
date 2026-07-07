// 基础数据类型
import Foundation

enum QuotaAnalyzer {
    private static let criticalRemainingPercent = 5.0
    private static let paceDeltaThreshold = 15.0

    /// 根据当前时间计算 5 小时和 7 天额度节奏。
    /// - Parameters:
    ///   - snapshot: 当前额度快照。
    ///   - now: 用于计算重置进度的当前时间。
    /// - Returns: 两个额度窗口和综合建议。
    static func analyze(snapshot: QuotaSnapshot?, now: Date = Date()) -> QuotaPace {
        guard let snapshot else {
            return QuotaPace(fiveHour: nil, weekly: nil, summary: .unknown)
        }

        let fiveHour = analyze(window: snapshot.fiveHourWindow, now: now)
        let weekly = analyze(window: snapshot.weeklyWindow, now: now)
        return QuotaPace(
            fiveHour: fiveHour,
            weekly: weekly,
            summary: summarize(fiveHour: fiveHour, weekly: weekly)
        )
    }

    /// 计算单个额度窗口的理想剩余和节奏状态。
    /// - Parameters:
    ///   - window: 额度窗口。
    ///   - now: 当前时间。
    /// - Returns: 单窗口节奏数据。
    private static func analyze(window: QuotaWindow?, now: Date) -> QuotaWindowPace? {
        guard let window else {
            return nil
        }

        var idealRemainingPercent: Double?
        var paceDelta: Double?
        var status: PaceStatus = .unknown

        if let duration = window.windowDurationMins,
           let resetsAt = window.resetsAt,
           duration > 0 {
            let remainingSeconds = max(0, resetsAt.timeIntervalSince(now))
            let ideal = max(0, min(100, remainingSeconds / (duration * 60) * 100))
            idealRemainingPercent = round1(ideal)
            paceDelta = round1(window.remainingPercent - ideal)

            if window.remainingPercent <= criticalRemainingPercent {
                status = .critical
            } else if let paceDelta, paceDelta >= paceDeltaThreshold {
                status = .accelerate
            } else if let paceDelta, paceDelta <= -paceDeltaThreshold {
                status = .slow
            } else {
                status = .normal
            }
        } else if window.remainingPercent <= criticalRemainingPercent {
            status = .critical
        }

        return QuotaWindowPace(
            remainingPercent: window.remainingPercent,
            idealRemainingPercent: idealRemainingPercent,
            paceDelta: paceDelta,
            status: status
        )
    }

    /// 融合短周期和长周期状态生成主建议。
    /// - Parameters:
    ///   - fiveHour: 5 小时节奏。
    ///   - weekly: 7 天节奏。
    /// - Returns: 综合节奏状态。
    private static func summarize(fiveHour: QuotaWindowPace?, weekly: QuotaWindowPace?) -> PaceStatus {
        if fiveHour?.status == .critical || weekly?.status == .critical {
            return .critical
        }
        if weekly?.status == .slow {
            return fiveHour?.status == .slow ? .slow : .recentFast
        }
        if fiveHour?.status == .slow {
            return .recentFast
        }
        if weekly?.status == .accelerate && fiveHour?.status != .slow {
            return .accelerate
        }
        if weekly?.status == .normal || fiveHour?.status == .normal {
            return .normal
        }
        return weekly?.status ?? fiveHour?.status ?? .unknown
    }

    /// 保留一位小数。
    /// - Parameter value: 原始数值。
    /// - Returns: 一位小数数值。
    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
