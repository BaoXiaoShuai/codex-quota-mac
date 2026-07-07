// macOS 原生应用框架
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = QuotaStore()
    private var statusBarController: StatusBarController?
    private var mainWindowController: MainWindowController?

    /// 应用启动时初始化额度状态、状态栏入口和主窗口。
    /// - Parameter notification: macOS 应用启动通知。
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(store: store)
        mainWindowController = MainWindowController(store: store)
        statusBarController?.onOpenMainWindow = { [weak self] in
            self?.showMainWindow()
        }
        store.loadCache()
        store.startAutoRefresh()
        store.refresh(reason: "startup")
        showMainWindow()
    }

    /// Dock 或系统激活应用时展示主窗口。
    /// - Parameters:
    ///   - sender: 触发激活的系统对象。
    ///   - flag: 当前是否已有可见窗口。
    /// - Returns: 返回 true 让系统继续处理 reopen 行为。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    /// 应用退出前停止定时刷新任务。
    /// - Parameter notification: macOS 应用终止通知。
    func applicationWillTerminate(_ notification: Notification) {
        store.stopAutoRefresh()
    }

    /// 展示并聚焦主界面窗口。
    private func showMainWindow() {
        mainWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
