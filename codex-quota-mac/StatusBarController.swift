// macOS 原生应用框架
import AppKit
// SwiftUI 状态订阅能力
import Combine

final class StatusBarController: NSObject {
    var onOpenMainWindow: (() -> Void)?

    private let store: QuotaStore
    private let statusItem: NSStatusItem
    private var menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()

    /// 创建 macOS 状态栏控制器。
    /// - Parameter store: 额度状态仓库。
    init(store: QuotaStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        bindStore()
        rebuildMenu()
    }

    /// 配置状态栏按钮的基础行为。
    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }
        button.title = "Codex"
        button.target = self
        button.action = #selector(openMainWindow)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Codex Quota Mac"
    }

    /// 订阅额度和设置变化，实时刷新状态栏文字。
    private func bindStore() {
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshTitle()
                    self?.rebuildMenu()
                }
            }
            .store(in: &cancellables)

        store.settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshTitle()
                    self?.rebuildMenu()
                }
            }
            .store(in: &cancellables)
    }

    /// 刷新状态栏显示文本。
    private func refreshTitle() {
        statusItem.button?.title = store.statusBarTitle()
    }

    /// 重建右键菜单，保持配置状态与当前设置一致。
    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开主界面", action: #selector(openMainWindow), keyEquivalent: "o", target: self))
        menu.addItem(NSMenuItem(title: "刷新额度", action: #selector(refreshQuota), keyEquivalent: "r", target: self))
        menu.addItem(.separator())

        let fiveHourItem = NSMenuItem(title: "状态栏显示 5 小时额度", action: #selector(toggleFiveHour), keyEquivalent: "")
        fiveHourItem.target = self
        fiveHourItem.state = store.settings.showFiveHour ? .on : .off
        menu.addItem(fiveHourItem)

        let weeklyItem = NSMenuItem(title: "状态栏显示 7 天额度", action: #selector(toggleWeekly), keyEquivalent: "")
        weeklyItem.target = self
        weeklyItem.state = store.settings.showWeekly ? .on : .off
        menu.addItem(weeklyItem)

        let summaryItem = NSMenuItem(title: "状态栏显示综合状态", action: #selector(toggleSummary), keyEquivalent: "")
        summaryItem.target = self
        summaryItem.state = store.settings.showSummary ? .on : .off
        menu.addItem(summaryItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q", target: self))
        self.menu = menu
    }

    /// 打开主界面。
    @objc private func openMainWindow() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.popUpMenu(menu)
            return
        }
        onOpenMainWindow?()
    }

    /// 手动刷新额度。
    @objc private func refreshQuota() {
        store.refresh(reason: "status-menu")
    }

    /// 切换 5 小时额度状态栏展示。
    @objc private func toggleFiveHour() {
        store.settings.showFiveHour.toggle()
    }

    /// 切换 7 天额度状态栏展示。
    @objc private func toggleWeekly() {
        store.settings.showWeekly.toggle()
    }

    /// 切换综合状态状态栏展示。
    @objc private func toggleSummary() {
        store.settings.showSummary.toggle()
    }

    /// 退出应用。
    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private extension NSMenuItem {
    /// 便捷创建带 target 的菜单项。
    /// - Parameters:
    ///   - title: 菜单标题。
    ///   - action: 点击动作。
    ///   - keyEquivalent: 快捷键。
    ///   - target: 菜单响应对象。
    convenience init(title: String, action: Selector?, keyEquivalent: String, target: AnyObject) {
        self.init(title: title, action: action, keyEquivalent: keyEquivalent)
        self.target = target
    }
}
