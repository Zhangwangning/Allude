import SwiftUI
import UIKit

// MARK: ============================================================================
// 「已取」+「统计」（2026-10-14 由原「浏览」页拆分，主人定稿四标签信息架构）
//
// 原「浏览」一个页面装三层内容（总览 / 已取列表 / 统计分析），拆成两个标签页：
//   · **PickedUpView（已取）**：取完的回执列表 —— 对账、回看、批量管理；
//   · **StatsTabView（统计）**：总览三格 + 取件习惯分析五张卡 —— 只看数据。
// 组件（StatCard / StatTriple / 图表）留在 StatsView.swift 不动。
// 数字全部来自 `PickupStats`（口径集中在那一个文件里，本页只负责画）。
// ============================================================================

// MARK: - 已取页状态

final class HistoryModel: ObservableObject {
    @Published var path = NavigationPath()
    @Published var copiedID: UUID?

    // MARK: 批量编辑
    @Published var isEditing = false
    @Published var selection: Set<UUID> = []

    /// 非 nil 时弹出分享预览面板（长按菜单「分享卡片」传单条）。
    /// 🔴 面板由**页面**承载：挂进长按浮层会在菜单收起时一起被销毁（见 CardMenu.swift）。
    @Published var shareRecords: [PickupRecord]?

    private var copyTask: Task<Void, Never>?

    func copy(_ record: PickupRecord) {
        UIPasteboard.general.string = record.code
        copiedID = record.id
        copyTask?.cancel()
        copyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if !Task.isCancelled { copiedID = nil }
        }
    }

    /// 进入 / 退出编辑模式。退出时顺手清空选择。
    func setEditing(_ active: Bool) {
        isEditing = active
        if !active { selection.removeAll() }
    }

    func toggleSelection(_ record: PickupRecord) {
        if selection.contains(record.id) {
            selection.remove(record.id)
        } else {
            selection.insert(record.id)
        }
    }

    /// 当前范围下是否全部选中（用于「全选 / 全不选」文案与状态）
    func isAllSelected(of items: [PickupRecord]) -> Bool {
        !items.isEmpty && items.allSatisfy { selection.contains($0.id) }
    }

    /// 全选 / 全不选（只针对当前范围的可见列表）
    func selectAll(of items: [PickupRecord]) {
        if isAllSelected(of: items) {
            items.forEach { selection.remove($0.id) }
        } else {
            items.forEach { selection.insert($0.id) }
        }
    }
}

// MARK: ============================================================================
// 已取页（取完的回执库）
// ============================================================================

struct PickedUpView: View {
    @EnvironmentObject private var store: PickupStore
    @StateObject private var model = HistoryModel()
    /// 长按菜单（自绘，替代系统 contextMenu —— 见 CardMenu.swift 的说明）
    @StateObject private var cardMenu = CardMenuState()

    private var list: [PickupRecord] {
        store.pickedUpRecords
    }

    private var visibleList: [PickupRecord] {
        Array(list.prefix(store.visibleLimit))
    }

    private var hiddenCount: Int {
        max(0, list.count - store.visibleLimit)
    }

    private var groups: [(group: DayGroup, items: [PickupRecord])] {
        store.grouped(visibleList)
    }

    var body: some View {
        NavigationStack(path: $model.path) {
            List {
                if list.isEmpty {
                    Section {
                        EmptyStateView(symbol: "archivebox",
                                       title: "已取件库还是空的",
                                       hint: "取件完成后，记录会留在这里")
                            .listRowInsets(EdgeInsets(top: 40, leading: AppTheme.hInset,
                                                      bottom: 0, trailing: AppTheme.hInset))
                            .listRowBackground(Color(.systemGroupedBackground))
                            .listRowSeparator(.hidden)
                    }
                } else {
                    ForEach(groups, id: \.group) { section in
                        Section {
                            ForEach(section.items) { record in
                                row(for: record)
                            }
                        } header: {
                            SectionHeader(title: section.group.rawValue,
                                          trailing: "\(section.items.count) 件")
                                .padding(.horizontal, AppTheme.hInset)
                                .padding(.top, 4)
                                .padding(.bottom, 6)
                                .textCase(nil)
                        }
                    }

                    if hiddenCount > 0 {
                        Section {
                            HiddenHint(count: hiddenCount)
                                .listRowInsets(EdgeInsets(top: 2, leading: AppTheme.hInset,
                                                          bottom: 8, trailing: AppTheme.hInset))
                                .listRowBackground(Color(.systemGroupedBackground))
                                .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(AppTheme.listSpacing)
            .scrollContentBackground(.hidden)
            // 页面底 = 浅灰，卡片才是白（与全 App 统一口径）
            .background(Color(.systemGroupedBackground))
            .contentMargins(.bottom, 88, for: .scrollContent)
            .navigationTitle("已取")
            .navigationDestination(for: PickupRecord.self) { record in
                RecordDetailView(record: record)
            }
            .toolbar {
                if model.isEditing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(.snappy) { model.selectAll(of: visibleList) }
                        } label: {
                            Text(model.isAllSelected(of: visibleList) ? "全不选" : "全选")
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !list.isEmpty {
                        Button {
                            withAnimation(.snappy) { model.setEditing(!model.isEditing) }
                        } label: {
                            Text(model.isEditing ? "完成" : "选择")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if model.isEditing {
                    BatchDeleteBar(count: model.selection.count) {
                        let targets = list.filter { model.selection.contains($0.id) }
                        withAnimation(.snappy) {
                            store.deleteMany(targets)
                            model.selection.removeAll()
                        }
                    }
                }
            }
            // 分享预览面板（单条）：与待取页共用同一个 `SharePreviewSheet`。
            .sheet(isPresented: Binding(
                get: { model.shareRecords != nil },
                set: { if !$0 { model.shareRecords = nil } })) {
                if let records = model.shareRecords {
                    SharePreviewSheet(records: records)
                }
            }
            .onAppear {
                openMenuFromScaffold()
                // 截图脚手架：`SIMCTL_CHILD_EDIT=1` 启动即进编辑模式。
                if ProcessInfo.processInfo.environment["EDIT"] == "1", !list.isEmpty {
                    model.setEditing(true)
                }
                // 回到标签根页 → 露出标签栏（TabBarCloak 兜底，见 RootView）
                TabBarCloak.shared.reveal()
            }
        }
        // 长按景深：整个界面轻微后退（模糊 + 缩放），被按的卡片由浮层里的「替身」接管。
        .blur(radius: cardMenu.openID == nil ? 0 : CardMenuMetrics.backgroundBlur)
        .scaleEffect(cardMenu.openID == nil ? 1 : CardMenuMetrics.backgroundScale)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: cardMenu.openID)
        .overlay { cardMenuLayer }
    }

    // MARK: 记录行

    @ViewBuilder
    private func row(for record: PickupRecord) -> some View {
        HistoryRow(
            record: record,
            isCopied: model.copiedID == record.id,
            showsSelection: model.isEditing,
            isSelected: model.selection.contains(record.id),
            onToggle: {
                withAnimation(.snappy) { store.toggle(record) }
            },
            onCopy: { model.copy(record) }
        )
        .contentShape(.rect)
        .onTapGesture {
            if model.isEditing {
                withAnimation(.snappy) { model.toggleSelection(record) }
            } else {
                model.path.append(record)
            }
        }
        // 编辑模式下禁用侧滑与长按菜单，行为只剩「选中 / 取消选中」
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !model.isEditing {
                Button {
                    withAnimation(.snappy) { store.toggle(record) }
                } label: {
                    Label("恢复", systemImage: "arrow.uturn.backward")
                }
                .tint(AppTheme.pendingTint)
            }
        }
        // 编辑模式下完全不挂长按手势（`enabled: false`）
        .cardLongPress(for: record.id, state: cardMenu, enabled: !model.isEditing)
        // 🔴 行背景 / 分隔符 / insets 必须写在 `.swipeActions` 之后（链尾规则，
        //    写在前面会落到内层容器失效 —— 见 PickupListView rowChrome 同款注释）。
        .listRowBackground(Color(.systemGroupedBackground))
        .listRowSeparator(.hidden)
        // 上下各 7.5pt = 卡片间实距 15pt，与待取页同口径。
        .listRowInsets(EdgeInsets(top: 7.5, leading: AppTheme.hInset,
                                  bottom: 7.5, trailing: AppTheme.hInset))
    }

    // MARK: 长按菜单

    /// 已取页只有三种操作：复制 / 分享 / 恢复为待取。
    private func menuItems(for record: PickupRecord) -> [CardMenuItem] {
        [
            CardMenuItem(title: "复制取件码",
                         symbol: "doc.on.doc",
                         action: { model.copy(record) }),
            // 分享由页面级 `.sheet` 承载 —— 菜单项不能自己弹面板（见 CardMenu.swift）
            CardMenuItem(title: "分享卡片",
                         symbol: "square.and.arrow.up",
                         action: { model.shareRecords = [record] }),
            CardMenuItem(title: "恢复为待取",
                         symbol: "arrow.uturn.backward",
                         tint: AppTheme.pendingTint,
                         action: { withAnimation(.snappy) { store.toggle(record) } }),
            // 编辑收进详情页（2026-10-14 主人定稿）：本页菜单不再放「编辑」。
        ]
    }

    /// 菜单浮层：贴卡片定位，点空白处收起。
    @ViewBuilder
    private var cardMenuLayer: some View {
        if let id = cardMenu.openID,
           let record = store.records.first(where: { $0.id == id }) {
            CardMenuLayer(anchor: cardMenu.frame(of: id),
                          items: menuItems(for: record),
                          onDismiss: { cardMenu.close() }) {
                // 卡片替身：只负责「被看见」，所有回调留空。
                HistoryRow(record: record,
                           isCopied: false,
                           showsSelection: false,
                           isSelected: false,
                           onToggle: {},
                           onCopy: {})
            }
        }
    }

    // MARK: 截图脚手架

    /// `SIMCTL_CHILD_MENU_OPEN=<序号>`：启动后自动打开列表第 N 条的菜单
    /// （命令行无法脚本化长按手势，这里走同一条 `cardMenu.open(_:)` 路径）。
    /// `SIMCTL_CHILD_SHARE_HIT=<序号>`：再自动「点」一次「分享卡片」行。
    private func openMenuFromScaffold() {
        let env = ProcessInfo.processInfo.environment
        let tapsShareRow = env["SHARE_HIT"] != nil
        guard let raw = env["SHARE_HIT"] ?? env["MENU_OPEN"],
              let index = Int(raw) else { return }

        Task { @MainActor in
            // 等卡片坐标上报（最多 3 秒）。
            var waited = 0
            while cardMenu.frames.isEmpty && waited < 30 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }

            guard visibleList.indices.contains(index) else { return }
            let record = visibleList[index]
            cardMenu.open(record.id)

            guard tapsShareRow else { return }
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let action = menuItems(for: record)
                .first(where: { $0.title == "分享卡片" })?.action else { return }
            cardMenu.close()
            action()
        }
    }
}

// MARK: ============================================================================
// 统计页（取件数据分析）
// ============================================================================

struct StatsTabView: View {
    @EnvironmentObject private var store: PickupStore

    private var stats: PickupStats {
        PickupStats(records: store.records)
    }

    var body: some View {
        // 🔴 必须自带 NavigationStack：四个标签页里本页是唯一裸放的，
        // 之前漏包导致 navigationTitle 没有栈环境，大标题「统计」根本不显示
        // （待取/已取各自内部有栈、设置有 SettingsTabRoot 包装）。
        NavigationStack {
            // 截图脚手架：`SIMCTL_CHILD_SCROLL=freq|hour|company|kind|eff` 滚到对应统计卡。
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // ① 总览三格：累计入库 / 累计取走 / 当前待取
                        overviewCard
                            .id("top")

                        // ② 取件习惯分析（五张卡）
                        if !stats.isEmpty {
                            frequencyCard.id("freq")
                            hourlyCard.id("hour")
                            companyCard.id("company")
                            kindCard.id("kind")
                            efficiencyCard.id("eff")
                        } else {
                            EmptyStateView(symbol: "chart.bar.xaxis",
                                           title: "还没有数据",
                                           hint: "取几件之后，这里会长出你的取件画像")
                                .padding(.top, 40)
                        }
                    }
                    .padding(.horizontal, AppTheme.hInset)
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                }
                .background(Color(.systemGroupedBackground))
                .onAppear {
                    scrollFromScaffold(proxy)
                    TabBarCloak.shared.reveal()
                }
            }
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    /// 截图脚手架：`SIMCTL_CHILD_SCROLL=freq|hour|company|kind|eff` 滚到对应统计卡
    /// （simctl 没有滚动注入通道；默认「top」滚回页首）。
    private func scrollFromScaffold(_ proxy: ScrollViewProxy) {
        let anchor = ProcessInfo.processInfo.environment["SCROLL"] ?? "top"
        guard !anchor.isEmpty, anchor != "top" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    // MARK: ① 总览

    private var overviewCard: some View {
        StatTriple(items: [
            .init(title: "累计入库", value: "\(stats.receivedTotal)",
                  tint: AppTheme.pendingTint, symbol: "shippingbox.fill"),
            .init(title: "累计取走", value: "\(stats.pickedTotal)",
                  tint: AppTheme.doneTint, symbol: "checkmark.circle.fill"),
            .init(title: "当前待取", value: "\(stats.pendingTotal)",
                  tint: AppTheme.todayTint, symbol: "clock.fill"),
        ])
    }

    // MARK: ② 取件习惯分析

    private var frequencyCard: some View {
        StatCard(title: "取件频率",
                 note: "近 \(stats.window) 天 · 按完成取件的时刻统计") {
            VStack(alignment: .leading, spacing: 14) {
                DailyBarChart(points: stats.daily, peak: stats.busiestDayCount)

                Divider()

                HStack(spacing: 0) {
                    summary("日均", String(format: "%.1f", stats.dailyAverage) + " 件")
                    summary("有取件", "\(stats.activeDays) 天")
                    summary("连续", "\(stats.streak) 天")
                }

                if let trend = weekOverWeekText {
                    Text(trend)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 本周与上周的对比。`daily` 恰好是 14 天，后半段是本周、前半段是上周。
    private var weekOverWeekText: String? {
        let points = stats.daily
        guard points.count >= 14 else { return nil }
        let recent = points.suffix(7).reduce(0) { $0 + $1.picked }
        let previous = points.dropLast(7).suffix(7).reduce(0) { $0 + $1.picked }
        guard previous > 0 || recent > 0 else { return nil }

        let diff = recent - previous
        if diff == 0 { return "本周与上周都是 \(recent) 件" }
        let arrow = diff > 0 ? "多" : "少"
        return "本周取走 \(recent) 件，比上周\(arrow) \(abs(diff)) 件"
    }

    private func summary(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var hourlyCard: some View {
        StatCard(title: "取件时段", note: "一天中的取件分布") {
            VStack(alignment: .leading, spacing: 12) {
                HourlyBarChart(buckets: stats.hourly)

                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text(peakText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var peakText: String {
        var parts: [String] = []
        if let range = stats.busiestHourRange { parts.append("高峰 \(range)") }
        if let weekday = stats.busiestWeekday { parts.append("最常在\(weekday)取件") }
        return parts.isEmpty ? "还没有足够的样本" : parts.joined(separator: " · ")
    }

    private var companyCard: some View {
        StatCard(title: "各快递统计",
                 note: "\(stats.companies.count) 家公司 · 按件数排序") {
            VStack(spacing: 0) {
                ForEach(Array(stats.companies.enumerated()), id: \.element.id) { index, company in
                    if index > 0 {
                        Divider().padding(.leading, 36)
                    }
                    CompanyRow(point: company, total: stats.receivedTotal)
                }
            }
        }
    }

    private var kindCard: some View {
        StatCard(title: "凭证类别", note: "取件码 / 运单号 / 尾号 / 特殊码") {
            VStack(spacing: 0) {
                ForEach(Array(stats.kinds.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().padding(.leading, 36)
                    }
                    KindRow(point: item, total: stats.receivedTotal)
                }
            }
        }
    }

    private var efficiencyCard: some View {
        StatCard(title: "取件效率", note: "从收到通知到取走花了多久") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(PickupStats.durationText(stats.averageStay))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.doneTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("平均停留")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 0) {
                    summary("最快一次", PickupStats.durationText(stats.fastestStay))
                    summary("样本", "\(stats.staySampleCount) 件")
                    summary("今日已取", "\(stats.pickedToday) 件")
                }

                if stats.staySampleCount == 0 {
                    Text("还没有记录到取件时刻 —— 从收到通知到勾选「已取」走一遍，这里就会有数。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - 记录行（已取页；同样支持行内恢复）

struct HistoryRow: View {
    let record: PickupRecord
    let isCopied: Bool
    /// 编辑模式下行首换成「选择圆圈」，勾选框与复制按钮退场
    var showsSelection: Bool = false
    var isSelected: Bool = false
    let onToggle: () -> Void
    let onCopy: () -> Void

    private var brand: Color { record.brandColor }

    /// 与待取页 PickupCard 保持同一口径（20pt 行首小图标）
    private static let logoSize: CGFloat = 20

    /// 驿站名称库（内置 + 用户自定义），订阅以便用户在设置页增删后卡片即时刷新
    @ObservedObject private var stationDirectory = StationDirectory.shared

    /// 行 1 主名优先级：快递公司 > 驿站名（按名称库命中）> 取件平台（2026-10-14 定稿）
    private var courierName: String? {
        let c = record.courier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return c.isEmpty ? nil : c
    }
    private var stationName: String? {
        stationDirectory.matchedName(in: [record.address, record.rawMessage])
    }
    private var titlePrimary: String {
        courierName ?? stationName ?? record.company
    }
    private var titleSecondary: String? {
        titlePrimary == record.company ? nil : record.company
    }
    private var titleIconSource: String {
        courierName ?? stationName ?? record.company
    }

    var body: some View {
        HStack(spacing: 10) {
            if showsSelection {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isSelected ? brand : Color.secondary.opacity(0.45))
            } else {
                CompleteButton(isDone: record.isPickedUp, tint: brand, action: onToggle)
            }

                // 三层信息结构，与待取页 PickupCard 逐项对齐（避免两页观感漂移）
                VStack(alignment: .leading, spacing: 0) {
                    // 行 1：图标 + 主名（快递公司 > 驿站 > 平台）+「| 取件平台」+ 时间
                    // （2026-10-14 定稿：与待取页同步——删类别标签，图标上移行首）
                    HStack(spacing: 6) {
                        // 驿站名场景用 StationLogo：自定义图标在卡片同样生效
                        if courierName == nil, let stationName {
                            StationLogo(name: stationName, size: Self.logoSize)
                        } else {
                            CourierLogo(company: titleIconSource, size: Self.logoSize)
                        }

                        Text(titlePrimary)
                            .font(.system(size: 15.5, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(record.isPickedUp ? .secondary : .primary)

                        if let secondary = titleSecondary {
                            Text("|")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.secondary.opacity(0.45))
                            Text(secondary)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .foregroundStyle(record.isPickedUp ? .tertiary : .secondary)
                        }

                        Spacer(minLength: 6)

                        Text(record.clockTime)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    // 行 2：取件地址（图标已上移行 1，不再重复）
                    if !addressLine.isEmpty {
                        HStack(spacing: 6) {
                            Text(addressLine)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.top, 4)
                    }

                    DashedDivider()
                        .padding(.top, 8)
                        .padding(.trailing, 2)

                    // 行 3：取件码（末四位品牌色强调，与待取页同口径）
                    HStack(spacing: 8) {
                        record.emphasizedCodeText(isDone: record.isPickedUp, tint: record.brandColor)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospaced()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            // 已取 → 划线（与详情页已取态同口径）
                            .strikethrough(record.isPickedUp, color: .secondary)

                        Spacer(minLength: 6)

                        if !showsSelection {
                            CopyCodeButton(isCopied: isCopied, tint: brand, action: onCopy)
                        }
                    }
                    .padding(.top, 7)
            }
        }
        .padding(.horizontal, AppTheme.cardPadding)
        .padding(.vertical, 12)
        .cardSurface(tint: brand)
        .opacity(record.isPickedUp ? 0.72 : 1)
    }

    private var addressLine: String {
        record.address.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - 批量删除工具条（编辑模式底部悬浮）

/// 玻璃态底栏：左边已选计数，右边红色删除按钮。0 条时删除置灰。
struct BatchDeleteBar: View {
    let count: Int
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(count > 0 ? "已选 \(count) 条" : "未选择")
                .font(.system(size: 14, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(count > 0 ? Color.primary : Color.secondary)

            Spacer(minLength: 0)

            Button(action: onDelete) {
                Label("删除", systemImage: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(count > 0 ? Color.white : Color.secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(count > 0 ? AnyShapeStyle(Color.red) : AnyShapeStyle(Color.secondary.opacity(0.18)),
                                in: .capsule)
            }
            .disabled(count == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
    }
}
