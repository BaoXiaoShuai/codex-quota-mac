// macOS 原生应用框架
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = QuotaStore()
    private var statusBarController: StatusBarController?

    /// 应用启动时隐藏 Dock 图标、初始化额度状态和状态栏入口。
    /// - Parameter notification: macOS 应用启动通知。
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置为后台 Agent 模式：隐藏 Dock 图标和 Cmd+Tab 入口，纯状态栏应用体验
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(store: store)
        store.loadCache()
        store.startAutoRefresh()
        store.refresh(reason: "startup", force: true)
    }

    /// 应用退出前停止定时刷新任务。
    /// - Parameter notification: macOS 应用终止通知。
    func applicationWillTerminate(_ notification: Notification) {
        store.stopAutoRefresh()
    }
}
