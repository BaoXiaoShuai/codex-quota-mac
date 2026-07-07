// SwiftUI 状态能力
import Combine
// 数据持久化基础库
import Foundation

struct StatusBarDisplayOptions: Equatable {
    var showFiveHour: Bool
    var showWeekly: Bool
    var showSummary: Bool
}

final class AppSettings: ObservableObject {
    // 是否在状态栏展示 5 小时额度。
    @Published var showFiveHour: Bool {
        didSet { defaults.set(showFiveHour, forKey: Keys.showFiveHour) }
    }

    // 是否在状态栏展示 7 天额度。
    @Published var showWeekly: Bool {
        didSet { defaults.set(showWeekly, forKey: Keys.showWeekly) }
    }

    // 是否在状态栏展示综合节奏。
    @Published var showSummary: Bool {
        didSet { defaults.set(showSummary, forKey: Keys.showSummary) }
    }

    // 是否在状态栏展示重置时间：5h 显示 HH:mm，7d 显示 M/d。
    @Published var showResetTime: Bool {
        didSet { defaults.set(showResetTime, forKey: Keys.showResetTime) }
    }

    // 自动刷新间隔，单位为分钟。
    @Published var refreshIntervalMinutes: Double {
        didSet { defaults.set(refreshIntervalMinutes, forKey: Keys.refreshIntervalMinutes) }
    }

    private let defaults: UserDefaults

    /// 从 UserDefaults 读取状态栏展示和刷新配置。
    /// - Parameter defaults: 用于持久化用户配置的 UserDefaults。
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showFiveHour = defaults.object(forKey: Keys.showFiveHour) as? Bool ?? true
        showWeekly = defaults.object(forKey: Keys.showWeekly) as? Bool ?? true
        showSummary = defaults.object(forKey: Keys.showSummary) as? Bool ?? false
        showResetTime = defaults.object(forKey: Keys.showResetTime) as? Bool ?? true
        refreshIntervalMinutes = defaults.object(forKey: Keys.refreshIntervalMinutes) as? Double ?? 3
    }

    /// 返回当前状态栏显示配置快照。
    func displayOptions() -> StatusBarDisplayOptions {
        StatusBarDisplayOptions(
            showFiveHour: showFiveHour,
            showWeekly: showWeekly,
            showSummary: showSummary
        )
    }

    private enum Keys {
        static let showFiveHour = "statusBar.showFiveHour"
        static let showWeekly = "statusBar.showWeekly"
        static let showSummary = "statusBar.showSummary"
        static let showResetTime = "statusBar.showResetTime"
        static let refreshIntervalMinutes = "quota.refreshIntervalMinutes"
    }
}
