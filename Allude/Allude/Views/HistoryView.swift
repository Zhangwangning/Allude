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
    /// 刚复制成功的取件码（非 nil 时页面底部弹「已复制 xxx」）
    @Published var copiedCode: String?

    // MARK: 批量编辑
    @Published var isEditing = false
    @Published var selection: Set<UUID> = []

    /// 非 nil 时弹出分享预览面板（长按菜单「分享卡片」传单条）。
    /// 🔴 面板由**页面**承载：挂进长按浮层会在菜单收起时一起被销毁（见 CardMenu.swift）。
    @Published var shareRecords: [PickupRecord]?

    private var copyTask: Task<Void, Never>?

    // MARK: 单条删除（2026-11-11 内测反馈）
    //
    // 已取页此前只有「选择 → 批量删除」一条路，长按菜单里没有删除项，
    // 用户想删一条只能先进编辑模式 —— 反馈为「已取页面无法进行删除」。
    // 现在长按菜单直接给「删除记录」，并给 4 秒撤销条（与待取页同口径）。
    @Published var deleteUndoRecord: PickupRecord?
    @Published var showDeleteUndo = false
    private var deleteUndoTask: Task<Void, Never>?

    /// 删除单条并给出撤销机会。
    func delete(_ record: PickupRecord, in store: PickupStore) {
        withAnimation(.snappy) { store.delete(record) }
        deleteUndoRecord = record
        withAnimation(.snappy) { showDeleteUndo = true }
        deleteUndoTask?.cancel()
        deleteUndoTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { showDeleteUndo = false }
        }
    }

    /// 撤销刚才的单条删除：必须 `insert` 回整表，`restore` 找不到已摘掉的记录。
    func undoDelete(in store: PickupStore) {
        deleteUndoTask?.cancel()
        if let record = deleteUndoRecord {
            withAnimation(.snappy) { store.insert([record]) }
        }
        deleteUndoRecord = nil
        withAnimation(.snappy) { showDeleteUndo = false }
    }

    func copy(_ record: PickupRecord) {
        UIPasteboard.general.string = record.code
        // 与待取页同口径：复制后必须给回执（2026-10-25 主人要求）
        withAnimation(.snappy) { copiedCode = record.code }
        copyTask?.cancel()
        copyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if !Task.isCancelled { withAnimation(.snappy) { copiedCode = nil } }
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

    /// 宽屏（iPhone Duo 展开态）判定 —— 与待取页同一口径。
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// 分栏右栏当前显示的记录 id；nil = 还没点过 → 回落第一条（见 `splitDetailRecord`）。
    @State private var splitSelection: PickupRecord.ID?
    /// 当前页可用宽度（只量不改布局）
    @State private var paneWidth: CGFloat = 0

    /// 通知点击待打开的记录 id（2026-10-25）
    @StateObject private var notificationRouter = NotificationRouter.shared

    /// 当前打开侧滑的行（自绘侧滑，2026-10-25）
    @State private var openSwipeRow: UUID?

    var body: some View {
        // 📱 2026-10-25：宽屏走平行视图（左列表 / 右详情），常规 iPhone 仍单栈。
        Group {
            // 与待取页同口径：按实际宽度分栏（iPad mini 竖屏 744pt 不分栏）。
            if PadLayout.isPad, paneWidth >= 900 {
                splitLayout
            } else {
                stackedLayout
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: AlludePaneWidthKey.self, value: geo.size.width)
            }
        }
        .onPreferenceChange(AlludePaneWidthKey.self) { paneWidth = $0 }
        // 长按景深：整个界面轻微后退（模糊 + 缩放），被按的卡片由浮层里的「替身」接管。
        .blur(radius: cardMenu.openID == nil ? 0 : CardMenuMetrics.backgroundBlur)
        .scaleEffect(cardMenu.openID == nil ? 1 : CardMenuMetrics.backgroundScale)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: cardMenu.openID)
        .overlay { cardMenuLayer }
        // 通知点击 → 打开对应记录的详情（2026-10-25）
        .onAppear { consumeNotificationTarget() }
        .onChange(of: notificationRouter.pendingRecordID) { _, _ in consumeNotificationTarget() }
    }

    /// 与待取页同口径：只认属于本页（已取集合）的 id，谁匹配谁清空。
    private func consumeNotificationTarget() {
        guard let id = notificationRouter.pendingRecordID,
              let record = store.pickedUpRecords.first(where: { $0.id == id }) else { return }
        notificationRouter.pendingRecordID = nil
        if PadLayout.isPad, horizontalSizeClass == .regular {
            splitSelection = record.id
        } else {
            model.path.append(record)
        }
    }

    /// 单栈布局（常规 iPhone）：与历史版本完全一致。
    private var stackedLayout: some View {
        NavigationStack(path: $model.path) {
            listPane
                .navigationDestination(for: PickupRecord.self) { record in
                    RecordDetailView(record: record)
                }
        }
    }

    /// 平行视图（宽屏）：左列表 / 右详情 —— 与待取页同一口径：
    /// 右栏**常驻详情**、不 push（无返回箭头）；未选中时默认显示第一条；
    /// 列宽左右等分（主人 2026-10-25 已否掉「按铰链中轴分列」）。
    private var splitLayout: some View {
        GoldenSplit {
            NavigationStack { listPane }
        } right: {
            if let record = splitDetailRecord {
                // 与待取页同口径：绑定 id，避免编辑草稿串到下一条（2026-10-25 审查修）
                RecordDetailView(record: record)
                    .id(record.id)
            } else {
                SplitDetailPlaceholder()
            }
        }
    }

    /// 分栏右栏要显示的记录：选中的那条优先，没选中就显示第一条（同待取页口径）。
    private var splitDetailRecord: PickupRecord? {
        if let id = splitSelection,
           let hit = list.first(where: { $0.id == id }) {
            return hit
        }
        return list.first
    }

    /// 打开详情：宽屏只切右栏（不 push），窄屏照旧推栈。
    private func openDetail(_ record: PickupRecord) {
        if PadLayout.isPad, horizontalSizeClass == .regular {
            splitSelection = record.id
        } else {
            model.path.append(record)
        }
    }

    /// 列表本体（两种布局共用）。`navigationDestination` 由各布局挂到自己的栈上。
    private var splitPane: Bool { PadLayout.isPad && paneWidth >= 900 }

    private var listPane: some View {
        listBody
    }

    private var listBody: some View {
        List {
            Section {
                PageHeader(title: "已取")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if splitPane {
                Section {

                }
            }
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
            // 复制回执（2026-10-25）：右滑直接复制后必须有提示，
            // 否则用户不知道复制上没有 —— 与待取页同款玻璃胶囊。
            .overlay(alignment: .bottom) {
                if let code = model.copiedCode {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(AppTheme.accent)

                        Text("已复制 \(code)")
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .appGlass(.capsule)
                    .padding(.horizontal, AppTheme.hInset)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
                }
            }
            // 删除撤销条（2026-11-11）：与待取页同款，4 秒内可放回
            .overlay(alignment: .bottom) {
                if model.showDeleteUndo {
                    UndoToast(message: model.deleteUndoRecord.map { "已删除 \($0.company) \($0.code)" } ?? "已删除",
                              actionTitle: "撤销") {
                        model.undoDelete(in: store)
                    }
                    .padding(.horizontal, AppTheme.hInset)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // 📱 宽屏（iPhone Duo 展开态）内容限宽居中，与待取页同一口径
            .frame(maxWidth: splitPane ? .infinity : AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            .contentMargins(.horizontal, AppTheme.hInset, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
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

                // 工具栏回到顶部右侧（2026-10-25 主人最终定：不再做左侧竖栏）
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

    // MARK: 记录行

    @ViewBuilder
    private func row(for record: PickupRecord) -> some View {
        // ⚠️ 这里只能有**一份** `HistoryRow`（包在 `SwipeActionRow` 的尾闭包里）。
        // 2026-10-25 改造时漏删了原表达式，`@ViewBuilder` 把两份并列返回，
        // 结果是每行渲染两张一样的卡片（实测：8 条记录显示成 16 张卡）。
        //
        // 与待取页同口径改用自绘侧滑（2026-10-25）：系统 `.swipeActions` 的
        // 「卡片 ↔ 按钮」间距是写死的 29pt，收不紧；这里压到 8pt，
        // 且卡片不再被推开一大截。
        // 方向与待取页一致：**向右滑 = 直接复制**；向左滑 = 展开「恢复」需确认。
        SwipeActionRow(
            rowID: record.id,
            openRowID: $openSwipeRow,
            leading: model.isEditing ? [] : [
                SwipeActionItem(title: "复制", symbol: "doc.on.doc",
                                tint: AppTheme.accent) { model.copy(record) },
            ],
            trailing: model.isEditing ? [] : [
                SwipeActionItem(title: "恢复", symbol: "arrow.uturn.backward",
                                tint: AppTheme.pendingTint) {
                    withAnimation(.snappy) { store.toggle(record) }
                },
            ],
            enabled: !model.isEditing,
            autoPerformSide: .leading,
            debugAllowsForcedOpen: ProcessInfo.processInfo.environment["SWIPE_OPEN"] != nil
        ) {
            HistoryRow(
                record: record,
                showsSelection: model.isEditing,
                isSelected: model.selection.contains(record.id),
                onToggle: {
                    withAnimation(.snappy) { store.toggle(record) }
                }
            )
            .contentShape(.rect)
            .onTapGesture {
                if model.isEditing {
                    withAnimation(.snappy) { model.toggleSelection(record) }
                } else {
                    // 宽屏只切右栏（不 push）、窄屏照旧推栈 —— 见 openDetail
                    openDetail(record)
                }
            }
        }
        // 编辑模式下完全不挂长按手势（`enabled: false`）
        .cardLongPress(for: record.id, state: cardMenu, enabled: !model.isEditing)
        // 🔴 行背景 / 分隔符 / insets 必须是链尾（写在前面会落到内层容器失效）。
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
                         action: { SharePresenter.shared.present([record]) }),
            CardMenuItem(title: "恢复为待取",
                         symbol: "arrow.uturn.backward",
                         tint: AppTheme.pendingTint,
                         action: { withAnimation(.snappy) { store.toggle(record) } }),
            // 单条删除（2026-11-11 内测反馈补）：此前已取页只有批量删除，长按没有删除项。
            CardMenuItem(title: "删除记录",
                         symbol: "trash",
                         tint: .red,
                         role: .destructive,
                         showsSeparatorBefore: true,
                         action: { model.delete(record, in: store) }),
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
                           showsSelection: false,
                           isSelected: false,
                           onToggle: {})
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

    /// 宽屏（Duo 展开）判定：决定统计卡排成两列还是一列。
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        // 🔴 必须自带 NavigationStack：四个标签页里本页是唯一裸放的，
        // 之前漏包导致 navigationTitle 没有栈环境，大标题「统计」根本不显示
        // （待取/已取各自内部有栈、设置有 SettingsTabRoot 包装）。
        NavigationStack {
            // 截图脚手架：`SIMCTL_CHILD_SCROLL=freq|hour|company|kind|eff` 滚到对应统计卡。
            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if horizontalSizeClass == .regular {
                            // 📊 宽屏（2026-10-25 主人：「统计页面也分列显示」）：
                            //    总览三格**独占一行全宽**（它是仪表盘主视觉，不该被挤成半宽），
                            //    下面五张分析卡两列并排。867pt 可用宽下每列约 400pt。
                            VStack(alignment: .leading, spacing: 16) {
                                PageHeader(title: "统计")
                                    .padding(.horizontal, -20)
                                overviewCard.id("top")

                                if !stats.isEmpty {
                                    // 用两个 VStack 手工分列，而不是 LazyVGrid：
                                    // 五张卡高度差很大（快递统计会长到一两屏），网格按行等高
                                    // 会在矮卡下方留大片空白；手工分列各自堆叠，观感紧实。
                                    HStack(alignment: .top, spacing: 16) {
                                        VStack(spacing: 16) {
                                            frequencyCard.id("freq")
                                            companyCard.id("company")
                                        }
                                        .frame(maxWidth: .infinity, alignment: .top)

                                        VStack(spacing: 16) {
                                            // 2026-10-28 主人：效率是「结论」，要放在上面，
                                            // 时段分布是明细，往下排。
                                            efficiencyCard.id("eff")
                                            hourlyCard.id("hour")
                                        }
                                        .frame(maxWidth: .infinity, alignment: .top)
                                    }
                                } else {
                                    emptyStats
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                // ① 总览三格：累计入库 / 累计取走 / 当前待取
                                overviewCard
                                    .id("top")

                                // ② 取件习惯分析（五张卡）
                                if !stats.isEmpty {
                                    // 2026-10-28 主人：把「取件效率」上移 ——
                                    // 它是最能一眼看出"我取件快不快"的结论卡，不该压在最底。
                                    frequencyCard.id("freq")
                                    efficiencyCard.id("eff")
                                    hourlyCard.id("hour")
                                    companyCard.id("company")
                                } else {
                                    emptyStats
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.hInset)
                    // 宽屏铺到 1200 上限（两列需要宽度）；窄屏仍是 700 居中列
                    .frame(maxWidth: horizontalSizeClass == .regular
                           ? 1200 : AppTheme.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 0)
                    .padding(.bottom, 110)
                }
                .background(Color(.systemGroupedBackground))
                .onAppear {
                    scrollFromScaffold(proxy)
                    TabBarCloak.shared.reveal()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// 无数据占位（两种布局共用）
    private var emptyStats: some View {
        EmptyStateView(symbol: "chart.bar.xaxis",
                       title: "还没有数据",
                       hint: "取几件之后，这里会长出你的取件画像")
            .padding(.top, 40)
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
                    Text(trend.L)
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
            Text(value.L)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title.L)
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
                    Text(peakText.L)
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
    /// 编辑模式：码行右端换成「选择圆圈」，勾选框退场
    var showsSelection: Bool = false
    var isSelected: Bool = false
    let onToggle: () -> Void

    /// 卡片强调色 —— 与待取页同一口径（2026-10-29）：
    /// **卡面、图标、取件码三者同源**，都取「快递公司 > 驿站 > 平台」。
    private var brand: Color { iconBrand }

    /// 取件码颜色**恒跟图标主题色**（2026-10-20 主人定）：与图标（快递公司>驿站>平台）同色。
    private var iconBrand: Color { CourierBrand.color(for: titleIconSource) }

    /// 与待取页 PickupCard v2 同一口径（26pt，图标下沉到取件码行）
    private static let iconSize: CGFloat = 26

    /// 驿站名称库（内置 + 用户自定义），订阅以便用户在设置页增删后卡片即时刷新
    @ObservedObject private var stationDirectory = StationDirectory.shared

    /// 卡面命名 —— **统一走 `PickupNaming`**（与待取卡 / 详情页 / 分享卡同一真源）。
    private var naming: PickupNaming {
        record.naming(station: stationDirectory.matchedName(in: [record.rawMessage]))
    }
    private var titlePrimary: String { naming.primary }
    private var titleSecondary: String? { naming.secondary }
    /// 行 1 图标匹配串随主名走 —— 与「图标 = 第一行第一个字段」同源
    private var titleIconSource: String { naming.iconSource }
    /// 快递柜格口（与待取卡同口径）：有值就跟在快递驿站后面做胶囊标签
    private var lockerName: String? {
        let l = record.locker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return l.isEmpty ? nil : l
    }


    /// 码行左侧品牌图标（26pt，底部与取件码持平）
    private var logoBlock: some View {
        Group {
            // 只有「主名本身就是驿站」这一种极端情况（courier 与 company 都空）才用驿站图标；
            // 其余一律按主名取品牌色 —— 与「图标 = 第一行第一个字段」一致。
            if naming.isStationPrimary, let stationName = naming.station {
                StationLogo(name: stationName, size: Self.iconSize)
            } else {
                CourierLogo(company: titleIconSource, size: Self.iconSize)
            }
        }
        .frame(width: Self.iconSize, height: Self.iconSize)
    }

    var body: some View {
        // 2026-10-20：版式与待取页 PickupCard v2 对齐 ——
        // 26pt 图标下沉到取件码行（底部与码持平），上半文字左对齐到内容左缘；
        // 左侧不再有独立勾选列，勾选 / 选择圈都挪到码行右端。
        VStack(alignment: .leading, spacing: 0) {
                    // 行 1：主名（快递公司 > 驿站 > 平台）+「| 取件平台」+ 时间
                    HStack(spacing: 6) {
                        Text(titlePrimary.L)
                            .font(.system(size: 15.5, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(record.isPickedUp ? .secondary : .primary)

                        if let secondary = titleSecondary {
                            Text("|")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.secondary.opacity(0.45))
                            Text(secondary.L)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .foregroundStyle(record.isPickedUp ? .tertiary : .secondary)
                        }

                        // 快递柜标签（2026-10-28 主人定）：紧跟快递驿站，胶囊样式
                        if let lockerName {
                            Text(lockerName.L)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(brand)
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(brand.opacity(0.14), in: .capsule)
                        }

                        Spacer(minLength: 6)

                        // 入库日期时间（2026-10-20 主人定：所有入库时间统一为日期时间格式；
                        // 由原来的 clockTime「HH:mm」升为 shortTime「M月d日 HH:mm」，跨天可辨）
                        Text(record.shortTime.L)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    // 行 2：取件地址（图标已上移行 1，不再重复）
                    if !addressLine.isEmpty {
                        HStack(spacing: 6) {
                            Text(addressLine.L)
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

                    // 行 3：图标 + 取件码 + 右端 复制 / 勾选
                    // 图标与码**视觉居中**对齐（2026-10-28 同待取卡口径：
                    // `.lastTextBaseline` 会让图标沉到基线以下约 4pt）
                    HStack(alignment: .center, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            logoBlock

                            record.emphasizedCodeText(isDone: record.isPickedUp, tint: iconBrand)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .monospaced()
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                // 已取 → 划线（与详情页已取态同口径）
                                .strikethrough(record.isPickedUp, color: .secondary)
                        }

                        Spacer(minLength: 6)

                        if showsSelection {
                            // 编辑模式：右端换成选择圈（点按选中交给整行手势）。
                            // 🔴 高度必须与 CompleteButton 的 44pt 一致（历史教训：36pt
                            // 会让行高被右侧控件压矮 8pt，整卡"变小"——2026-10-20 主人实测）
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(isSelected ? brand : Color.secondary.opacity(0.45))
                                .frame(width: 44, height: 44)
                        } else {
                            CompleteButton(isDone: record.isPickedUp, tint: brand, action: onToggle)
                        }
                    }
                    .padding(.top, 7)
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
