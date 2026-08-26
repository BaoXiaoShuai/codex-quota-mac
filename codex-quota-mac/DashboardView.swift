// macOS 毛玻璃视图
import AppKit
// SwiftUI 界面框架
import SwiftUI

private enum TokenChartMode: String, CaseIterable {
    case bars
    case line

    var title: String {
        switch self {
        case .bars: return "柱状"
        case .line: return "折线"
        }
    }
}

private struct RecentTokenDay: Identifiable {
    let date: Date
    let tokens: Int64
    let hasRecord: Bool

    var id: TimeInterval {
        date.timeIntervalSinceReferenceDate
    }
}

private enum TelemetryPalette {
    static let canvas = Color(red: 0.95, green: 0.97, blue: 1.0)
    static let panel = Color(red: 0.985, green: 0.99, blue: 1.0).opacity(0.90)
    static let panelRaised = Color.white.opacity(0.88)
    static let ionBlue = Color(red: 0.29, green: 0.48, blue: 0.98)
    static let electricViolet = Color(red: 0.48, green: 0.38, blue: 0.95)
    static let plasmaCyan = Color(red: 0.10, green: 0.66, blue: 0.75)
    static let signalLime = Color(red: 0.23, green: 0.71, blue: 0.45)
    static let warningAmber = Color(red: 0.92, green: 0.56, blue: 0.16)
    static let mutedText = Color(red: 0.31, green: 0.36, blue: 0.46).opacity(0.78)
}

struct DashboardView: View {
    // 是否减少界面动态效果。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Codex 仪表盘状态仓库。
    @ObservedObject var store: QuotaStore
    // 最近 7 天 Token 图表当前展示方式。
    @State private var recentChartMode: TokenChartMode = .bars
    // 是否展示最近 7 天模块，当前暂时隐藏但保留完整实现。
    private let isRecentTokenPanelVisible = false

    /// 创建主界面视图。
    /// - Parameter store: Codex 账号、Token 用量和额度状态仓库。
    init(store: QuotaStore) {
        self.store = store
    }

    var body: some View {
        ZStack {
            TelemetryBackdrop()

            VStack(alignment: .leading, spacing: 12) {
                header

                // Codex 当前登录账号信息区域
                accountPanel

                // 最近 7 天模块暂时隐藏，保留视图与计算逻辑供后续恢复。
                if isRecentTokenPanelVisible {
                    recentTokenPanel
                }

                // Codex 实际返回的额度窗口区域，优先展示在 Token 活动上方。
                if hasQuotaWindow {
                    quotaSection
                }

                // 每日 Token 月历与累计数据区域
                tokenActivityPanel

                statusBanner
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Color.primary)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex 用量")
                    .font(.system(size: 23, weight: .bold, design: .rounded))

                HStack(spacing: 6) {
                    Circle()
                        .fill(store.isRefreshing ? TelemetryPalette.warningAmber : TelemetryPalette.signalLime)
                        .frame(width: 6, height: 6)
                    Text(store.isRefreshing ? "正在同步" : lastUpdatedText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(TelemetryPalette.mutedText)
                }
            }
            Spacer()
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
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(TelemetryPalette.panelRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(TelemetryPalette.ionBlue.opacity(0.42), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(store.isRefreshing)
        .help("刷新 Codex 数据")
    }

    private var accountPanel: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 1)
                .fill(
                    LinearGradient(
                        colors: [TelemetryPalette.plasmaCyan, TelemetryPalette.electricViolet],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(accountDisplayTitle)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(accountTypeTitle)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(TelemetryPalette.mutedText)
            }

            Spacer(minLength: 8)

            Text(planTitle)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(store.account == nil ? TelemetryPalette.mutedText : TelemetryPalette.plasmaCyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(TelemetryPalette.plasmaCyan.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(TelemetryPalette.plasmaCyan.opacity(0.30), lineWidth: 0.7)
                        )
                )
        }
        .padding(14)
        .background(panelBackground())
    }

    private var recentTokenPanel: some View {
        let allBuckets = store.tokenUsage?.sortedDailyBuckets ?? []
        let recentDays = makeRecentSevenDays(allBuckets)
        let sevenDayTotal = recentDays.reduce(Int64(0)) { $0 + $1.tokens }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("最近 7 天")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                    Text("最近 7 个自然日")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TelemetryPalette.electricViolet.opacity(0.90))
                }
                Spacer()
                recentChartModeSelector
            }

            HStack(alignment: .lastTextBaseline, spacing: 7) {
                Text(formatTokenCount(store.tokenUsage == nil ? nil : sevenDayTotal))
                    .font(.system(size: 26, weight: .heavy, design: .monospaced))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                Text("Token 合计")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TelemetryPalette.mutedText)
                    .padding(.bottom, 2)
                Spacer()
            }

            if recentDays.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                    Text(store.isRefreshing ? "正在读取最近 7 天数据" : "Codex 暂未返回最近 7 天数据")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TelemetryPalette.mutedText)
                .frame(maxWidth: .infinity, minHeight: 116)
            } else {
                switch recentChartMode {
                case .bars:
                    // 最近 7 天 Token 柱状图
                    RecentTokenBarChart(days: recentDays)
                        .transition(.opacity)
                case .line:
                    // 最近 7 天 Token 折线图
                    RecentTokenLineChart(days: recentDays)
                        .transition(.opacity)
                }
            }
        }
        .padding(14)
        .background(panelBackground())
    }

    private var tokenActivityPanel: some View {
        let usage = store.tokenUsage
        let allBuckets = usage?.sortedDailyBuckets ?? []

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Token 活动")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                Text("按月查看每日 Token，用左右按钮切换月份")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TelemetryPalette.plasmaCyan.opacity(0.90))
            }

            if allBuckets.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                    Text(store.isRefreshing ? "正在读取每日 Token 数据" : "Codex 暂未返回每日 Token 数据")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TelemetryPalette.mutedText)
                .frame(maxWidth: .infinity, minHeight: 142)
            } else {
                // 按月切换的每日 Token 日历
                TokenActivityCalendar(buckets: allBuckets)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("累计 Token")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TelemetryPalette.plasmaCyan.opacity(0.80))
                    Text(formatTokenCount(usage?.summary.lifetimeTokens))
                        .font(.system(size: 17, weight: .heavy, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(TelemetryPalette.plasmaCyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(TelemetryPalette.plasmaCyan.opacity(0.16), lineWidth: 0.7)
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text("单日峰值")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TelemetryPalette.electricViolet.opacity(0.90))
                    Text(formatTokenCount(usage?.summary.peakDailyTokens))
                        .font(.system(size: 17, weight: .heavy, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(TelemetryPalette.electricViolet.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(TelemetryPalette.electricViolet.opacity(0.18), lineWidth: 0.7)
                )
            }
        }
        .padding(14)
        .background(panelBackground())
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("额度剩余")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                Text("按周期查看 Codex 可用额度")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TelemetryPalette.ionBlue.opacity(0.90))
            }

            // 7 天额度卡片，仅在 Codex 返回该窗口时展示
            if let weekly = store.snapshot?.weeklyWindow {
                QuotaCardView(
                    title: "7 天额度",
                    subtitle: resetText(for: weekly),
                    iconName: "calendar",
                    window: weekly,
                    accent: TelemetryPalette.ionBlue,
                    store: store
                )
            }

            // 5 小时额度卡片，仅在 Codex 返回该窗口时展示
            if let fiveHour = store.snapshot?.fiveHourWindow {
                QuotaCardView(
                    title: "5 小时额度",
                    subtitle: resetText(for: fiveHour),
                    iconName: "clock.fill",
                    window: fiveHour,
                    accent: TelemetryPalette.signalLime,
                    store: store
                )
            }
        }
        .padding(14)
        .background(panelBackground())
    }

    @ViewBuilder
    private var statusBanner: some View {
        if case let .failed(message) = store.status {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(TelemetryPalette.warningAmber)
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(panelBackground())
        }
    }

    private var lastUpdatedText: String {
        guard let lastUpdatedAt = store.lastUpdatedAt else {
            return "最后更新 --:--"
        }
        return "最后更新 \(lastUpdatedAt.formatted(date: .omitted, time: .shortened))"
    }

    private var accountTypeTitle: String {
        // 按 Codex 登录来源转换为用户可识别的账号类型。
        switch store.account?.type {
        case "chatgpt":
            return "ChatGPT 登录"
        case "apiKey":
            return "OpenAI API Key"
        case "amazonBedrock":
            return "Amazon Bedrock"
        default:
            return "本机 Codex"
        }
    }

    private var accountDisplayTitle: String {
        if let email = store.account?.email, !email.isEmpty {
            return email
        }
        // 非 ChatGPT 登录可能没有邮箱，改用账号来源作为主标题。
        switch store.account?.type {
        case "apiKey": return "Codex API Key"
        case "amazonBedrock": return "Amazon Bedrock 账号"
        case "chatgpt": return "ChatGPT 账号"
        default: return "等待 Codex 账号信息"
        }
    }

    private var planTitle: String {
        // 将服务端套餐枚举收敛为适合徽标展示的名称。
        switch store.account?.planType {
        case "free": return "FREE"
        case "go": return "GO"
        case "plus": return "PLUS"
        case "pro": return "PRO"
        case "prolite": return "PRO LITE"
        case "team": return "TEAM"
        case "business", "self_serve_business_prolite", "self_serve_business_usage_based": return "BUSINESS"
        case "enterprise", "enterprise_cbp_automation", "enterprise_cbp_usage_based": return "ENTERPRISE"
        case "edu": return "EDU"
        case .some(let plan): return plan.uppercased()
        case .none: return store.account == nil ? "未读取" : "未提供"
        }
    }

    private var recentChartModeSelector: some View {
        HStack(spacing: 2) {
            ForEach(TokenChartMode.allCases, id: \.self) { mode in
                Button {
                    selectRecentChartMode(mode)
                } label: {
                    Text(mode.title)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(recentChartMode == mode ? Color.white : TelemetryPalette.mutedText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(recentChartMode == mode ? TelemetryPalette.ionBlue.opacity(0.88) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(recentChartMode == mode ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.40))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.7)
                )
        )
    }

    private var hasQuotaWindow: Bool {
        store.snapshot?.weeklyWindow != nil || store.snapshot?.fiveHourWindow != nil
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

    /// 格式化 Token 数量并保留千分位。
    /// - Parameter value: Token 数量。
    /// - Returns: 千分位数字；无数据时返回 --。
    private func formatTokenCount(_ value: Int64?) -> String {
        guard let value else {
            return "--"
        }
        return NumberFormatter.tokenCount.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// 生成包含今天在内的最近 7 个自然日 Token 数据。
    /// - Parameter buckets: 按日期排列的每日 Token 数据。
    /// - Returns: 按日期升序排列的 7 日数据，无记录日期使用 0 并保留状态。
    private func makeRecentSevenDays(_ buckets: [TokenUsageDailyBucket]) -> [RecentTokenDay] {
        guard !buckets.isEmpty else {
            return []
        }
        let calendar = tokenCalendar
        var tokensByDate: [Date: Int64] = [:]

        for bucket in buckets {
            guard let parsedDate = DateFormatter.tokenDay.date(from: String(bucket.startDate.prefix(10))) else {
                continue
            }
            let date = calendar.startOfDay(for: parsedDate)
            tokensByDate[date, default: 0] += max(0, bucket.tokens)
        }

        let today = calendar.startOfDay(for: Date())
        return (-6...0).compactMap { dayOffset -> RecentTokenDay? in
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                return nil
            }
            return RecentTokenDay(
                date: date,
                tokens: tokensByDate[date, default: 0],
                hasRecord: tokensByDate[date] != nil
            )
        }
    }

    /// 切换最近 7 天 Token 图表展示方式。
    /// - Parameter mode: 目标图表模式。
    private func selectRecentChartMode(_ mode: TokenChartMode) {
        if reduceMotion {
            recentChartMode = mode
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            recentChartMode = mode
        }
    }

    /// 创建用于最近 7 天计算的本地日历。
    /// - Returns: 使用本地时区的公历。
    private var tokenCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current
        return calendar
    }

    /// 创建无方向性阴影和渐变的统一模块背景。
    /// - Returns: 6pt 圆角浅色面板。
    private func panelBackground() -> some View {
        TelemetryPanelBackground()
    }
}

private struct TelemetryBackdrop: View {
    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)

            LinearGradient(
                colors: [
                    TelemetryPalette.canvas.opacity(0.90),
                    Color(red: 0.86, green: 0.92, blue: 1.0).opacity(0.72),
                    Color(red: 0.88, green: 0.97, blue: 0.94).opacity(0.62)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [TelemetryPalette.electricViolet.opacity(0.10), Color.clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 340
            )
        }
        .ignoresSafeArea()
    }
}

private struct TelemetryPanelBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(TelemetryPalette.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.085), lineWidth: 0.8)
            )
    }
}

private struct RecentTokenBarChart: View {
    // 按日期升序排列的最近 7 天 Token 数据。
    let days: [RecentTokenDay]

    var body: some View {
        let maxTokens = max(1, days.map(\.tokens).max() ?? 1)

        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                let ratio = Double(day.tokens) / Double(maxTokens)
                let isLatest = index == days.count - 1

                VStack(spacing: 5) {
                    Text(day.hasRecord ? compactTokenCount(day.tokens) : "—")
                        .font(.system(size: 12, weight: isLatest ? .bold : .medium, design: .monospaced))
                        .foregroundStyle(isLatest ? Color.primary : TelemetryPalette.mutedText)
                        .lineLimit(1)

                    Spacer(minLength: 3)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: !day.hasRecord
                                    ? [Color.primary.opacity(0.025), Color.primary.opacity(0.065)]
                                    : isLatest
                                    ? [TelemetryPalette.plasmaCyan, TelemetryPalette.electricViolet]
                                    : [TelemetryPalette.ionBlue.opacity(0.24), TelemetryPalette.ionBlue.opacity(0.68)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: max(day.tokens > 0 ? 5 : 2, 62 * ratio))
                        .shadow(color: isLatest ? TelemetryPalette.electricViolet.opacity(0.16) : Color.clear, radius: 2)

                    Text(DateFormatter.tokenWeekday.string(from: day.date))
                        .font(.system(size: 12, weight: isLatest ? .bold : .medium))
                        .foregroundStyle(isLatest ? Color.primary : TelemetryPalette.mutedText)
                }
                .frame(maxWidth: .infinity)
                .help(recentTokenDayHelpText(day))
                .accessibilityLabel(recentTokenDayHelpText(day))
            }
        }
        .frame(height: 116)
        .padding(.horizontal, 2)
    }
}

private struct RecentTokenLineChart: View {
    // 按日期升序排列的最近 7 天 Token 数据。
    let days: [RecentTokenDay]

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = 8
            let topPadding: CGFloat = 7
            let labelHeight: CGFloat = 22
            let plotWidth = max(1, proxy.size.width - horizontalPadding * 2)
            let plotHeight = max(1, proxy.size.height - topPadding - labelHeight)
            let maxTokens = max(1, days.map(\.tokens).max() ?? 1)
            // 单点时固定在左侧，多点时按可用宽度等距排列。
            let stepX = days.count > 1 ? plotWidth / CGFloat(days.count - 1) : 0
            let points = Array(days.enumerated()).map { index, day in
                let ratio = CGFloat(Double(day.tokens) / Double(maxTokens))
                return CGPoint(
                    x: horizontalPadding + CGFloat(index) * stepX,
                    y: topPadding + plotHeight * (1 - ratio)
                )
            }

            ZStack(alignment: .topLeading) {
                Path { path in
                    for gridIndex in 0...2 {
                        let y = topPadding + plotHeight * CGFloat(gridIndex) / 2
                        path.move(to: CGPoint(x: horizontalPadding, y: y))
                        path.addLine(to: CGPoint(x: horizontalPadding + plotWidth, y: y))
                    }
                }
                .stroke(
                    Color.primary.opacity(0.075),
                    style: StrokeStyle(lineWidth: 0.6, dash: [2, 3])
                )

                Path { path in
                    guard let firstPoint = points.first,
                          let lastPoint = points.last else {
                        return
                    }
                    path.move(to: CGPoint(x: firstPoint.x, y: topPadding + plotHeight))
                    path.addLine(to: firstPoint)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                    path.addLine(to: CGPoint(x: lastPoint.x, y: topPadding + plotHeight))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            TelemetryPalette.electricViolet.opacity(0.28),
                            TelemetryPalette.plasmaCyan.opacity(0.015)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Path { path in
                    guard let firstPoint = points.first else {
                        return
                    }
                    path.move(to: firstPoint)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [
                            TelemetryPalette.plasmaCyan,
                            TelemetryPalette.electricViolet
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )

                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    Circle()
                        .fill(index == days.count - 1 ? TelemetryPalette.electricViolet : TelemetryPalette.plasmaCyan)
                        .overlay(Circle().stroke(TelemetryPalette.canvas.opacity(0.90), lineWidth: 1.2))
                        .frame(width: index == days.count - 1 ? 8 : 6, height: index == days.count - 1 ? 8 : 6)
                        .shadow(color: index == days.count - 1 ? TelemetryPalette.electricViolet.opacity(0.26) : TelemetryPalette.plasmaCyan.opacity(0.18), radius: 2)
                        .position(points[index])
                        .help(recentTokenDayHelpText(day))
                        .accessibilityLabel(recentTokenDayHelpText(day))

                    Text(DateFormatter.tokenWeekday.string(from: day.date))
                        .font(.system(size: 12, weight: index == days.count - 1 ? .bold : .medium))
                        .foregroundStyle(index == days.count - 1 ? Color.primary : TelemetryPalette.mutedText)
                        .position(x: points[index].x, y: proxy.size.height - 8)
                }
            }
        }
        .frame(height: 116)
    }
}

/// 生成最近单日 Token 图表的悬浮提示。
/// - Parameter day: 单日 Token 数据。
/// - Returns: 日期和当日 Token 用量。
private func recentTokenDayHelpText(_ day: RecentTokenDay) -> String {
    let dateText = DateFormatter.tokenDay.string(from: day.date)
    guard day.hasRecord else {
        return "\(dateText)：无记录"
    }
    let tokenText = NumberFormatter.tokenCount.string(from: NSNumber(value: day.tokens)) ?? "\(day.tokens)"
    return "\(dateText)：\(tokenText) Token"
}

/// 将 Token 数量压缩为适合图表展示的短文本。
/// - Parameter value: Token 数量。
/// - Returns: K、M、B 单位短文本。
private func compactTokenCount(_ value: Int64) -> String {
    let number = Double(value)
    if number >= 1_000_000_000 {
        return String(format: "%.1fB", number / 1_000_000_000)
    }
    if number >= 1_000_000 {
        return String(format: "%.1fM", number / 1_000_000)
    }
    if number >= 1_000 {
        return String(format: "%.0fK", number / 1_000)
    }
    return "\(value)"
}

private struct TokenCalendarDay: Identifiable {
    // 当前日期在月历网格中的位置。
    let position: Int
    // 对应自然日；nil 表示月首或月尾的留白格。
    let date: Date?
    // 当日 Token；nil 表示没有记录。
    let tokens: Int64?

    var id: Int {
        position
    }
}

struct TokenActivityCalendar: View {
    // 是否减少月份切换动画。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // 全部按日期升序排列的每日 Token 数据。
    let buckets: [TokenUsageDailyBucket]
    // 相对当前月份的偏移量，0 表示当月。
    @State private var monthOffset = 0
    // 当前鼠标悬浮的日历日期。
    @State private var hoveredDay: TokenCalendarDay?

    // 月历从周一到周日展示。
    private static let weekdayTitles = ["一", "二", "三", "四", "五", "六", "日"]
    // 月历固定为七列。
    private let calendarColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let days = makeMonthDays()
        let maxTokens = max(1, days.compactMap(\.tokens).max() ?? 1)
        let monthTotal = days.compactMap(\.tokens).reduce(Int64(0), +)

        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                monthNavigationButton(
                    systemName: "chevron.left",
                    change: -1,
                    isDisabled: !canNavigatePrevious
                )

                Spacer()

                VStack(spacing: 2) {
                    Text(DateFormatter.tokenMonthTitle.string(from: displayedMonth))
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                    Text(monthTotal > 0 ? "本月 \(compactTokenCount(monthTotal)) Token" : "本月暂无记录")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(TelemetryPalette.mutedText)
                }

                Spacer()

                monthNavigationButton(
                    systemName: "chevron.right",
                    change: 1,
                    isDisabled: !canNavigateNext
                )
            }

            HStack(spacing: 4) {
                ForEach(Self.weekdayTitles, id: \.self) { title in
                    Text(title)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(TelemetryPalette.mutedText)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: calendarColumns, spacing: 5) {
                ForEach(days) { day in
                    calendarDayCell(day, maxTokens: maxTokens)
                }
            }

            Text(hoveredDay.map(dayHelpText) ?? "悬浮日期查看当日 Token")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(hoveredDay == nil ? TelemetryPalette.mutedText : TelemetryPalette.plasmaCyan)
                .lineLimit(1)
                .frame(height: 15)
        }
    }

    /// 创建单个月份的日历网格，并在月首、月尾补齐空白格。
    /// - Returns: 从周一开始排列的月历单元格。
    private func makeMonthDays() -> [TokenCalendarDay] {
        let calendar = activityCalendar
        let month = displayedMonth
        guard let dayRange = calendar.range(of: .day, in: .month, for: month) else {
            return []
        }

        var tokensByDate: [Date: Int64] = [:]
        for bucket in buckets {
            guard let parsedDate = DateFormatter.tokenDay.date(from: String(bucket.startDate.prefix(10))) else {
                continue
            }
            let date = calendar.startOfDay(for: parsedDate)
            tokensByDate[date, default: 0] += max(0, bucket.tokens)
        }

        let firstWeekdayOffset = (calendar.component(.weekday, from: month) + 5) % 7
        // 固定六周高度，切换不同月份时避免面板和边框上下跳动。
        let positionCount = 42

        return (0..<positionCount).map { position in
            let dayNumber = position - firstWeekdayOffset + 1
            guard dayRange.contains(dayNumber),
                  let date = calendar.date(byAdding: .day, value: dayNumber - 1, to: month) else {
                return TokenCalendarDay(position: position, date: nil, tokens: nil)
            }
            let normalizedDate = calendar.startOfDay(for: date)
            return TokenCalendarDay(
                position: position,
                date: normalizedDate,
                tokens: tokensByDate[normalizedDate]
            )
        }
    }

    /// 创建单个日期格，显示日期、Token 强度和当天标记。
    /// - Parameters:
    ///   - day: 月历日期单元格。
    ///   - maxTokens: 当前月份单日最大 Token。
    /// - Returns: 月历日期视图。
    @ViewBuilder
    private func calendarDayCell(_ day: TokenCalendarDay, maxTokens: Int64) -> some View {
        if let date = day.date {
            let isToday = activityCalendar.isDateInToday(date)
            let isFuture = date > activityCalendar.startOfDay(for: Date())
            let isHovered = hoveredDay?.id == day.id

            VStack(alignment: .leading, spacing: 1) {
                Text("\(activityCalendar.component(.day, from: date))")
                    .font(.system(size: 11, weight: isToday ? .heavy : .semibold, design: .monospaced))
                Text(day.tokens.map { compactTokenCount($0) } ?? "·")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(day.tokens == nil ? TelemetryPalette.mutedText : Color.primary.opacity(0.76))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(calendarDayColor(tokens: day.tokens, maxTokens: maxTokens))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(
                        isToday
                            ? TelemetryPalette.ionBlue.opacity(0.90)
                            : isHovered
                            ? TelemetryPalette.plasmaCyan.opacity(0.72)
                            : Color.primary.opacity(0.06),
                        lineWidth: isToday ? 1.2 : 0.7
                    )
            )
            .opacity(isFuture ? 0.48 : 1)
            .contentShape(Rectangle())
            .onHover { isHovering in
                updateHoveredDay(day, isHovering: isHovering)
            }
            .help(dayHelpText(day))
            .accessibilityLabel(dayHelpText(day))
        } else {
            Color.clear
                .frame(height: 32)
        }
    }

    /// 根据当日 Token 占当月峰值的比例返回日历底色。
    /// - Parameters:
    ///   - tokens: 当日 Token；nil 表示该日期没有记录。
    ///   - maxTokens: 当前月份单日最大 Token。
    /// - Returns: 对应强度的日历底色。
    private func calendarDayColor(tokens: Int64?, maxTokens: Int64) -> Color {
        guard let tokens, tokens > 0 else {
            return Color.white.opacity(0.20)
        }
        let ratio = Double(tokens) / Double(maxTokens)
        // 单日用量按低、中、高三档显示，避免月历色彩过碎。
        if ratio <= 0.33 {
            return TelemetryPalette.ionBlue.opacity(0.16)
        }
        if ratio <= 0.66 {
            return TelemetryPalette.electricViolet.opacity(0.20)
        }
        return TelemetryPalette.plasmaCyan.opacity(0.28)
    }

    /// 生成单个日期格的完整 Token 提示。
    /// - Parameter day: 月历日期单元格。
    /// - Returns: 日期及 Token 数量说明。
    private func dayHelpText(_ day: TokenCalendarDay) -> String {
        guard let date = day.date else {
            return "无日期"
        }
        let dateLabel = DateFormatter.tokenDay.string(from: date)
        guard let tokens = day.tokens else {
            return "\(dateLabel)：无记录"
        }
        let value = NumberFormatter.tokenCount.string(from: NSNumber(value: tokens)) ?? "\(tokens)"
        return "\(dateLabel)：\(value) Token"
    }

    /// 根据鼠标进入或离开状态更新日历悬浮信息。
    /// - Parameters:
    ///   - day: 当前交互的月历日期。
    ///   - isHovering: 鼠标是否位于日期格内。
    private func updateHoveredDay(_ day: TokenCalendarDay, isHovering: Bool) {
        if isHovering {
            hoveredDay = day
            return
        }
        // 只有离开的仍是当前日期时才清空，避免快速跨格时覆盖新状态。
        if hoveredDay?.id == day.id {
            hoveredDay = nil
        }
    }

    /// 创建月份左右切换按钮。
    /// - Parameters:
    ///   - systemName: SF Symbols 图标名称。
    ///   - change: 月份偏移变化，-1 为上月，1 为下月。
    ///   - isDisabled: 是否禁用切换。
    /// - Returns: 月份切换按钮。
    private func monthNavigationButton(systemName: String, change: Int, isDisabled: Bool) -> some View {
        Button {
            changeMonth(by: change)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(isDisabled ? 0.16 : 0.42))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.primary.opacity(isDisabled ? 0.04 : 0.08), lineWidth: 0.7)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.46 : 1)
    }

    /// 按指定偏移切换月份，并限制在首个有记录月份到当月之间。
    /// - Parameter change: 月份变化量，-1 为上月，1 为下月。
    private func changeMonth(by change: Int) {
        let targetOffset = monthOffset + change
        guard let targetMonth = activityCalendar.date(byAdding: .month, value: targetOffset, to: currentMonth) else {
            return
        }
        // 同时限制最早有记录月份和当前月份，避免切到无数据的过去或未来。
        guard targetMonth >= earliestMonth, targetMonth <= currentMonth else {
            return
        }

        if reduceMotion {
            monthOffset = targetOffset
            hoveredDay = nil
            return
        }
        withAnimation(.easeInOut(duration: 0.16)) {
            monthOffset = targetOffset
            hoveredDay = nil
        }
    }

    /// 返回当前展示月份的月初日期。
    /// - Returns: 当前月份偏移对应的月初日期。
    private var displayedMonth: Date {
        activityCalendar.date(byAdding: .month, value: monthOffset, to: currentMonth) ?? currentMonth
    }

    /// 返回当前自然月的月初日期。
    /// - Returns: 当前自然月月初。
    private var currentMonth: Date {
        monthStart(for: Date())
    }

    /// 返回每日数据中最早月份的月初日期。
    /// - Returns: 最早有记录的月份；没有有效日期时返回当前月份。
    private var earliestMonth: Date {
        let firstDate = buckets.compactMap {
            DateFormatter.tokenDay.date(from: String($0.startDate.prefix(10)))
        }.min()
        guard let firstDate else {
            return currentMonth
        }
        return min(monthStart(for: firstDate), currentMonth)
    }

    /// 判断是否可以切换到上一个月。
    /// - Returns: 当前月份晚于首个有记录月份时返回 true。
    private var canNavigatePrevious: Bool {
        displayedMonth > earliestMonth
    }

    /// 判断是否可以切换到下一个月。
    /// - Returns: 当前展示月份早于当月时返回 true。
    private var canNavigateNext: Bool {
        displayedMonth < currentMonth
    }

    /// 将日期归一化为所在月份的月初。
    /// - Parameter date: 待归一化日期。
    /// - Returns: 日期所在月份的月初。
    private func monthStart(for date: Date) -> Date {
        let components = activityCalendar.dateComponents([.year, .month], from: date)
        return activityCalendar.date(from: components) ?? activityCalendar.startOfDay(for: date)
    }

    /// 创建以周一为一周起点的本地日历。
    /// - Returns: 用于 Token 月历计算的日历。
    private var activityCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }
}

private extension NumberFormatter {
    /// Token 数量千分位格式化器。
    static let tokenCount: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

private extension DateFormatter {
    /// Token 每日数据日期格式化器。
    static let tokenDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// 最近 7 天图表星期格式化器。
    static let tokenWeekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "EEE"
        return formatter
    }()

    /// Token 月历标题格式化器。
    static let tokenMonthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()
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

            if store.snapshot?.fiveHourWindow != nil {
                Toggle("显示 5 小时额度", isOn: $settings.showFiveHour)
            }
            if store.snapshot?.weeklyWindow != nil {
                Toggle("显示 7 天额度", isOn: $settings.showWeekly)
            }
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
        .background(panelBackground(cornerRadius: 6, material: .contentBackground))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(accent.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(accent.opacity(0.34), lineWidth: 0.8)
                        )
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accent)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TelemetryPalette.mutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(window.map { store.formatPercent($0.remainingPercent) } ?? "--")
                        .font(.system(size: 30, weight: .heavy, design: .monospaced))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                    Text("剩余")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TelemetryPalette.mutedText)
                }
            }

            QuotaProgressView(
                usedPercent: window?.usedPercent ?? 0,
                accent: accent
            )

            HStack(spacing: 6) {
                Text(window.map { "已用 \(store.formatPercent($0.usedPercent))" } ?? "已用 --")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TelemetryPalette.mutedText)
                Spacer()
                Text(remainingDurationText)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent.opacity(0.86))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(TelemetryPalette.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(accent.opacity(0.18), lineWidth: 0.7)
        )
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
    // 已使用额度百分比。
    let usedPercent: Double
    // 进度强调色。
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let segmentCount = 20
            let segmentSpacing: CGFloat = 2
            let safeUsedPercent = min(max(usedPercent, 0), 100)
            let activeSegments = Int(ceil(safeUsedPercent / 100 * Double(segmentCount)))
            let segmentWidth = max(1, (proxy.size.width - CGFloat(segmentCount - 1) * segmentSpacing) / CGFloat(segmentCount))
            let activeColor = safeUsedPercent >= 90 ? Color.red : accent

            HStack(spacing: segmentSpacing) {
                ForEach(0..<segmentCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(index < activeSegments ? activeColor : Color.primary.opacity(0.055))
                        .frame(width: segmentWidth)
                }
            }
        }
        .frame(height: 8)
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
