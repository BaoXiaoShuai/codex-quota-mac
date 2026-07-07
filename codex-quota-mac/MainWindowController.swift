// macOS 原生应用框架
import AppKit
// SwiftUI 界面框架
import SwiftUI

final class MainWindowController: NSWindowController {
    private let store: QuotaStore

    /// 创建主窗口控制器。
    /// - Parameter store: 额度状态仓库。
    init(store: QuotaStore) {
        self.store = store
        let rootView = DashboardView(store: store)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Codex Quota Mac"
        window.setContentSize(NSSize(width: 480, height: 560))
        window.minSize = NSSize(width: 430, height: 500)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.hasShadow = true
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// 展示窗口并居中到当前屏幕。
    /// - Parameter sender: 触发展示的对象。
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
    }
}
