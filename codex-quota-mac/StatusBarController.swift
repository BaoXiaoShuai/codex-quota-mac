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
        let hostingController = NSHostingController(rootView: DashboardView(store: store))
        p.contentViewController = hostingController
        hostingController.view.layoutSubtreeIfNeeded()
        p.contentSize = NSSize(width: 420, height: hostingController.view.fittingSize.height)
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
        menu.addItem(NSMenuItem(title: "刷新数据", action: #selector(refreshQuota), keyEquivalent: "r", target: self))
        menu.addItem(.separator())

        if store.snapshot?.fiveHourWindow != nil {
            let fiveHourItem = NSMenuItem(title: "显示 5 小时额度", action: #selector(toggleFiveHour), keyEquivalent: "")
            fiveHourItem.target = self
            fiveHourItem.state = store.settings.showFiveHour ? .on : .off
            menu.addItem(fiveHourItem)
        }

        if store.snapshot?.weeklyWindow != nil {
            let weeklyItem = NSMenuItem(title: "显示 7 天额度", action: #selector(toggleWeekly), keyEquivalent: "")
            weeklyItem.target = self
            weeklyItem.state = store.settings.showWeekly ? .on : .off
            menu.addItem(weeklyItem)
        }

        // 重置时间开关：5h 显示 HH:mm，7d 显示 M/d
        let resetTimeItem = NSMenuItem(title: "显示重置时间", action: #selector(toggleResetTime), keyEquivalent: "")
        resetTimeItem.target = self
        resetTimeItem.state = store.settings.showResetTime ? .on : .off
        menu.addItem(resetTimeItem)

        let summaryItem = NSMenuItem(title: "显示综合状态", action: #selector(toggleSummary), keyEquivalent: "")
        summaryItem.target = self
        summaryItem.state = store.settings.showSummary ? .on : .off
        menu.addItem(summaryItem)

        menu.addItem(.separator())

        // 刷新间隔子菜单
        let intervalMenu = NSMenu()
        let currentInterval = Int(store.settings.refreshIntervalMinutes)
        for minutes in [1, 3, 5, 10, 30] {
            let item = NSMenuItem(
                title: "\(minutes) 分钟",
                action: #selector(setRefreshInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = minutes
            // 当前选中的间隔打勾
            item.state = currentInterval == minutes ? .on : .off
            intervalMenu.addItem(item)
        }
        let intervalParent = NSMenuItem(title: "刷新间隔", action: nil, keyEquivalent: "")
        intervalParent.submenu = intervalMenu
        menu.addItem(intervalParent)

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
            // 打开面板时立即同步，避免今日 Token 等到下一个自动刷新周期才出现。
            store.refresh(reason: "status-popover")
            resizePopoverToFit()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // 确保 Popover 窗口获得焦点，可接受键盘输入
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// 按当前仪表盘内容计算弹窗高度，避免内部滚动或内容裁切。
    private func resizePopoverToFit() {
        guard let contentView = popover.contentViewController?.view else {
            return
        }
        contentView.layoutSubtreeIfNeeded()
        let fittingHeight = contentView.fittingSize.height
        guard fittingHeight > 0 else {
            return
        }
        popover.contentSize = NSSize(width: 420, height: fittingHeight)
    }

    /// 手动刷新额度。
    @objc private func refreshQuota() {
        store.refresh(reason: "status-menu", force: true)
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

    /// 切换重置时间状态栏展示。
    @objc private func toggleResetTime() {
        store.settings.showResetTime.toggle()
    }

    /// 设置自动刷新间隔，由菜单项 tag 携带分钟数。
    /// - Parameter sender: 触发的菜单项，tag 值为目标分钟数。
    @objc private func setRefreshInterval(_ sender: NSMenuItem) {
        let minutes = Double(sender.tag)
        guard minutes > 0 else { return }
        store.settings.refreshIntervalMinutes = minutes
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
