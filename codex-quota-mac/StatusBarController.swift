// macOS 原生应用框架
import AppKit
// SwiftUI 状态订阅能力
import Combine
// SwiftUI 界面框架
import SwiftUI

final class StatusBarController: NSObject {
    private let store: QuotaStore
    private let statusItem: NSStatusItem
    private var menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()

    /// 弹出面板，内嵌 DashboardView，懒加载避免启动时初始化 SwiftUI 树。
    private lazy var popover: NSPopover = {
        let p = NSPopover()
        p.contentViewController = NSHostingController(rootView: DashboardView(store: store))
        // 宽度与 DashboardView 一致，高度由 NSHostingController 根据内容自动计算
        p.contentSize = NSSize(width: 360, height: 100)
        // 点击面板外部自动关闭
        p.behavior = .transient
        p.animates = true
        return p
    }()

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
        guard let button = statusItem.button else { return }
        button.title = "Codex"
        button.target = self
        button.action = #selector(handleClick)
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

    /// 处理状态栏点击：左键切换 Popover 显隐，右键弹出菜单。
    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            statusItem.popUpMenu(menu)
            return
        }
        togglePopover()
    }

    /// 切换 Popover 显隐，显示时定位到状态栏按钮正下方。
    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // 确保 Popover 窗口获得焦点，可接受键盘输入
            popover.contentViewController?.view.window?.makeKey()
        }
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
