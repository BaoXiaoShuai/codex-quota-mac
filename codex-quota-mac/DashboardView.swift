// macOS 毛玻璃视图
import AppKit
// SwiftUI 界面框架
import SwiftUI

struct DashboardView: View {
    // 当前系统配色，用于调整毛玻璃叠色。
    @Environment(\.colorScheme) private var colorScheme
    // 额度状态仓库。
    @ObservedObject var store: QuotaStore
    // 用户显示配置。
    @ObservedObject private var settings: AppSettings
    // 设置窗口展示管理器。
    @StateObject private var settingsWindowPresenter = SettingsWindowPresenter()

    /// 创建主界面视图。
    /// - Parameter store: 额度状态仓库。
    init(store: QuotaStore) {
        self.store = store
        settings = store.settings
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
            LinearGradient(
                colors: backgroundGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // 内容直接撑开，不使用 ScrollView，让高度自动适配
            VStack(alignment: .leading, spacing: 16) {
                header
                quotaGrid
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        // 固定宽度 360，高度由内容自然撑起
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.primary)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Codex Quota")
                    .font(.system(size: 20, weight: .semibold))
                Text(lastUpdatedText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // 设置入口暂时隐藏，只保留刷新按钮
            refreshButton
        }
    }

    private var refreshButton: some View {
        Button {
            store.refresh(reason: "main-window")
        } label: {
            ZStack {
                if store.isRefreshing {
                    // 刷新中：旋转 loading 动画
                    ProgressView()
                        .controlSize(.small)
                        .progressViewStyle(.circular)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(.white.opacity(colorScheme == .dark ? 0.10 : 0.54))
                    .background(.thinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.70), lineWidth: 0.8))
            )
        }
        .buttonStyle(.plain)
        .disabled(store.isRefreshing)
        .help("刷新额度")
    }

    private var settingsButton: some View {
        Button {
            settingsWindowPresenter.show(store: store)
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(.white.opacity(colorScheme == .dark ? 0.10 : 0.54))
                        .background(.thinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.70), lineWidth: 0.8))
                )
        }
        .buttonStyle(.plain)
        .help("设置")
    }

    private var quotaGrid: some View {
        VStack(spacing: 10) {
            QuotaCardView(
                title: "5 小时额度",
                subtitle: resetText(for: store.snapshot?.fiveHourWindow),
                iconName: "clock.fill",
                window: store.snapshot?.fiveHourWindow,
                accent: Color(red: 0.35, green: 0.70, blue: 0.54),
                store: store
            )
            QuotaCardView(
                title: "7 天额度",
                subtitle: resetText(for: store.snapshot?.weeklyWindow),
                iconName: "calendar",
                window: store.snapshot?.weeklyWindow,
                accent: Color(red: 0.38, green: 0.58, blue: 0.86),
                store: store
            )
        }
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.58))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text("读取原理")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.62))
                Text("本应用会在本机启动 codex app-server，并通过 stdio JSON-RPC 调用 account/rateLimits/read，读取 usedPercent 后计算剩余额度。")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var lastUpdatedText: String {
        guard let lastUpdatedAt = store.lastUpdatedAt else {
            return "最后更新 --:--"
        }
        return "最后更新 \(lastUpdatedAt.formatted(date: .omitted, time: .shortened))"
    }

    /// 根据系统配色生成窗口底色渐变。
    /// - Returns: 背景渐变颜色数组。
    private var backgroundGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.12, green: 0.15, blue: 0.18).opacity(0.88),
                Color(red: 0.26, green: 0.36, blue: 0.48).opacity(0.30),
                Color(red: 0.28, green: 0.48, blue: 0.40).opacity(0.18)
            ]
        }
        return [
            Color(red: 0.97, green: 0.99, blue: 1.0),
            Color(red: 0.84, green: 0.93, blue: 1.0).opacity(0.66),
            Color(red: 0.82, green: 0.96, blue: 0.90).opacity(0.58)
        ]
    }

    /// 格式化窗口重置时间。
    /// - Parameter window: 额度窗口。
    /// - Returns: 重置时间展示文案。
    private func resetText(for window: QuotaWindow?) -> String {
        guard let resetsAt = window?.resetsAt else {
            return "重置时间未知"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return "重置时间 \(formatter.string(from: resetsAt))"
    }
}

final class SettingsWindowPresenter: ObservableObject {
    private var windowController: NSWindowController?

    /// 展示设置窗口，已存在时直接聚焦。
    /// - Parameter store: 额度状态仓库，用于向设置窗口传递状态和用户配置。
    func show(store: QuotaStore) {
        if let window = windowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = SettingsWindowView(store: store, settings: store.settings)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "设置"
        window.setContentSize(NSSize(width: 360, height: 270))
        window.minSize = NSSize(width: 340, height: 250)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsWindowView: View {
    // 当前系统配色，用于调整设置窗口底色。
    @Environment(\.colorScheme) private var colorScheme
    // 额度状态仓库。
    @ObservedObject var store: QuotaStore
    // 用户显示配置。
    @ObservedObject var settings: AppSettings

    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
            LinearGradient(
                colors: backgroundGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            settingsPanel
                .padding(22)
        }
        .frame(width: 360, height: 270)
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("状态栏显示")
                    .font(.system(size: 16, weight: .semibold))
                Text(store.statusBarTitle())
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }

            Toggle("显示 5 小时额度", isOn: $settings.showFiveHour)
            Toggle("显示 7 天额度", isOn: $settings.showWeekly)
            Toggle("显示综合状态", isOn: $settings.showSummary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("刷新间隔")
                    Spacer()
                    Text("\(Int(settings.refreshIntervalMinutes)) 分钟")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.refreshIntervalMinutes, in: 1...30, step: 1)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(18)
        .background(panelBackground(cornerRadius: 14, material: .contentBackground))
    }

    /// 根据系统配色生成设置窗口底色渐变。
    /// - Returns: 背景渐变颜色数组。
    private var backgroundGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.12, green: 0.15, blue: 0.18).opacity(0.88),
                Color(red: 0.26, green: 0.36, blue: 0.48).opacity(0.30),
                Color(red: 0.28, green: 0.48, blue: 0.40).opacity(0.18)
            ]
        }
        return [
            Color(red: 0.97, green: 0.99, blue: 1.0),
            Color(red: 0.84, green: 0.93, blue: 1.0).opacity(0.66),
            Color(red: 0.82, green: 0.96, blue: 0.90).opacity(0.58)
        ]
    }

    /// 创建随系统配色调整的轻量面板背景。
    /// - Parameters:
    ///   - cornerRadius: 面板圆角大小。
    ///   - material: macOS 原生毛玻璃材质。
    /// - Returns: 面板背景视图。
    private func panelBackground(cornerRadius: CGFloat, material: NSVisualEffectView.Material = .contentBackground) -> some View {
        GlassPanelBackground(cornerRadius: cornerRadius, material: material, tintOpacity: colorScheme == .dark ? 0.08 : 0.30)
    }
}

struct QuotaCardView: View {
    // 卡片标题。
    let title: String
    // 卡片副标题。
    let subtitle: String
    // 卡片业务图标名称。
    let iconName: String
    // 额度窗口。
    let window: QuotaWindow?
    // 进度强调色。
    let accent: Color
    // 额度状态仓库。
    let store: QuotaStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(accent.opacity(0.15))
                        Image(systemName: iconName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(window.map { store.formatPercent($0.remainingPercent) } ?? "--")
                        .font(.system(size: 28, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(window.map { "已用 \(store.formatPercent($0.usedPercent))" } ?? "已用 --")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(accent.opacity(0.12))
                                .overlay(Capsule().stroke(accent.opacity(0.18), lineWidth: 0.7))
                        )
                }
                .frame(minWidth: 104, idealWidth: 104, maxWidth: 104, minHeight: 52, alignment: .trailing)
                .offset(y: -4)
            }
            .frame(minHeight: 52, alignment: .center)

            QuotaProgressView(
                usedPercent: window?.usedPercent ?? 0,
                accent: accent
            )

            HStack(spacing: 8) {
                // 左侧实线：从靠近文字侧向外渐隐
                FadingDivider(fadeEnd: .leading)
                Text(remainingDurationText)
                    .font(.system(size: 11, weight: .semibold))
                // 右侧实线：从靠近文字侧向外渐隐
                FadingDivider(fadeEnd: .trailing)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
        }
        .padding(14)
        .background(GlassPanelBackground(cornerRadius: 6, material: .contentBackground, tintOpacity: 0.28, strokeOpacity: 0.26))
    }

    private var remainingDurationText: String {
        guard let resetsAt = window?.resetsAt else {
            return "约 --"
        }
        let seconds = max(0, Int(resetsAt.timeIntervalSince(Date())))
        let days = seconds / 86_400
        let hours = seconds % 86_400 / 3_600
        let minutes = seconds % 3_600 / 60
        if days > 0 {
            return "约 \(days) 天 \(hours) 小时"
        }
        if hours > 0 {
            return "约 \(hours) 小时 \(minutes) 分钟"
        }
        return "约 \(minutes) 分钟"
    }

}

struct QuotaProgressView: View {
    // 已用额度百分比。
    let usedPercent: Double
    // 进度强调色。
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // 已用百分比限制在 0-100 内，至少保持 6pt 宽度避免圆角崩塌
            let safeUsedPercent = min(max(usedPercent, 0), 100)
            let progressWidth = max(6, width * safeUsedPercent / 100)
            // 剩余 ≤ 10% 时切换为警示红
            let isWarning = safeUsedPercent >= 90
            let barColors: [Color] = isWarning
                ? [Color(red: 0.95, green: 0.25, blue: 0.20).opacity(0.75),
                   Color(red: 0.85, green: 0.10, blue: 0.10)]
                : [accent.opacity(0.50), accent.opacity(0.90)]
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.07))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: barColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: progressWidth)
                    .mask(Capsule().frame(width: progressWidth))
            }
        }
        .frame(height: 9)
    }
}

struct FadingDivider: View {
    /// 消失方向：.leading 表示向左消失（用于文字左侧），.trailing 表示向右消失（用于文字右侧）。
    var fadeEnd: UnitPoint

    var body: some View {
        Rectangle()
            .fill(.secondary.opacity(0.30))
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
            // 从靠近文字侧不透明，向外侧渐变至透明
            .mask(
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: fadeEnd == .leading ? .trailing : .leading,
                    endPoint: fadeEnd
                )
            )
    }
}

struct GlassPanelBackground: View {
    // 当前系统配色，用于控制毛玻璃叠色强度。
    @Environment(\.colorScheme) private var colorScheme
    // 面板圆角。
    let cornerRadius: CGFloat
    // 毛玻璃材质。
    let material: NSVisualEffectView.Material
    // 面板叠色透明度。
    let tintOpacity: Double
    // 面板细边透明度。
    let strokeOpacity: Double

    /// 创建通用毛玻璃面板背景。
    /// - Parameters:
    ///   - cornerRadius: 面板圆角大小。
    ///   - material: macOS 原生毛玻璃材质。
    ///   - tintOpacity: 面板叠色透明度。
    ///   - strokeOpacity: 面板细边透明度。
    init(cornerRadius: CGFloat, material: NSVisualEffectView.Material = .contentBackground, tintOpacity: Double = 0.24, strokeOpacity: Double = 0.26) {
        self.cornerRadius = cornerRadius
        self.material = material
        self.tintOpacity = tintOpacity
        self.strokeOpacity = strokeOpacity
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.clear)
            .background(
                VisualEffectView(material: material, blendingMode: .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(effectiveTintOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(effectiveStrokeOpacity), lineWidth: 0.8)
            )
    }

    /// 获取当前配色下的面板叠色透明度。
    /// - Returns: 适配 light / dark mode 的透明度。
    private var effectiveTintOpacity: Double {
        colorScheme == .dark ? min(tintOpacity, 0.10) : tintOpacity
    }

    /// 获取当前配色下的面板细边透明度。
    /// - Returns: 适配 light / dark mode 的透明度。
    private var effectiveStrokeOpacity: Double {
        colorScheme == .dark ? min(strokeOpacity, 0.16) : strokeOpacity
    }
}

struct VisualEffectView: NSViewRepresentable {
    // 毛玻璃材质。
    let material: NSVisualEffectView.Material
    // 毛玻璃混合模式。
    let blendingMode: NSVisualEffectView.BlendingMode

    /// 创建 macOS 毛玻璃视图。
    /// - Parameter context: SwiftUI 视图上下文。
    /// - Returns: NSVisualEffectView 实例。
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    /// 更新 macOS 毛玻璃视图配置。
    /// - Parameters:
    ///   - nsView: 待更新的 NSVisualEffectView。
    ///   - context: SwiftUI 视图上下文。
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}
