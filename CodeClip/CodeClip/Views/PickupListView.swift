import SwiftUI
import UIKit

// MARK: - 排序方式

enum PickupSortMode: String, CaseIterable, Identifiable {
    case newest = "最近收到"
    case oldest = "最早收到"
    case company = "按快递公司"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .newest: "arrow.down"
        case .oldest: "arrow.up"
        case .company: "building.2"
        }
    }
}

// MARK: - 列表组织方式（2026-10-14，参照取件喵「按驿站归类」）

/// 待取件的两种组织维度：
///  · **时间流**：按收到短信的时间分组（今天/昨天/更早）——回答「刚来了什么」；
///  · **按驿站**：按取件地点聚拢 —— 回答「到了这家店要取哪几件」。
/// 取件喵的用户口碑证明后者才是真实取件路径：用户是「顺路到某驿站、取走它的 N 件」，
/// 时间流里这些件散落在不同的日子里，到店场景要来回翻。
enum PickupGroupMode: String, CaseIterable, Identifiable {
    case timeline = "时间流"
    case station = "按驿站"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .timeline: "clock"
        case .station: "storefront"
        }
    }
}

// MARK: - 撤销动作

/// 记下「撤销」要撤销的到底是哪一件事。
///
/// 三种动作最终都落到 `records` 上，但方向相反：完成是把记录翻成已取、
/// 恢复是翻回待取、删除是把记录整条摘掉（撤销删除必须**放回**，只翻状态是放不回来的）。
/// 仅靠 `undoRecords` 反推不出是哪种，所以显式记一笔。
enum PickupUndoAction {
    case completed
    case deleted
    case restored
}

// MARK: - 首页状态

/// 首页的局部状态。放在 ObservableObject 里而不是 @State —— 这样工程在
/// 「Xcode GUI」与「命令行 xcodebuild」两条链路下都能编译（本机 Xcode 27 beta
/// 的 swift-plugin-server 在命令行下对 SwiftUI 宏返回 malformed response）。
final class PickupListModel: ObservableObject {
    @Published var path = NavigationPath()

    // 检索
    @Published var query = ""
    @Published var companyFilter: String?
    @Published var kindFilter: PickupKind?
    @Published var sort: PickupSortMode = .newest

    /// 组织方式（时间流 / 按驿站）。
    /// 手写 UserDefaults 持久化而非 @AppStorage —— 本工程在命令行 xcodebuild 下
    /// 不走 Swift 宏链路（见类注释），手写读写最稳。
    @Published var groupMode: PickupGroupMode = {
        let raw = UserDefaults.standard.string(forKey: "pickup.groupMode") ?? ""
        return PickupGroupMode(rawValue: raw) ?? .timeline
    }() {
        didSet {
            guard oldValue != groupMode else { return }
            UserDefaults.standard.set(groupMode.rawValue, forKey: "pickup.groupMode")
        }
    }

    // 交互反馈
    @Published var completing: Set<UUID> = []
    @Published var copiedID: UUID?
    @Published var undoRecords: [PickupRecord] = []
    @Published var undoAction: PickupUndoAction = .completed
    @Published var showUndo = false

    // 添加入口（手动粘贴 / 扫描识别）
    @Published var showAdd = false
    @Published var showScan = false
    @Published var addedToast: String?

    // 多选（2026-09-23）：进多选 → 点卡片勾选 → 顶栏「分享」出图。
    @Published var selectionMode = false
    @Published var selectedIDs: Set<UUID> = []
    /// 非 nil 时弹出分享预览面板：单条（长按菜单「分享卡片」）传 `[record]`，
    /// 多条传选中集（按当前排序）—— 两个入口共用同一个面板，体验一致。
    @Published var shareRecords: [PickupRecord]?

    private var copyTask: Task<Void, Never>?
    private var undoTasks: [Task<Void, Never>] = []
    private var hideTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    init() {}

    var hasActiveFilter: Bool {
        companyFilter != nil || kindFilter != nil
    }

    var activeFilterSummary: String {
        var parts: [String] = []
        if let companyFilter { parts.append(companyFilter) }
        if let kindFilter { parts.append(kindFilter.label) }
        return parts.joined(separator: " · ")
    }

    func clearFilters() {
        companyFilter = nil
        kindFilter = nil
    }

    // MARK: 多选分享

    func enterSelection(startingWith id: UUID) {
        selectionMode = true
        selectedIDs = [id]
    }

    func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func exitSelection() {
        selectionMode = false
        selectedIDs = []
    }

    // MARK: 反馈

    func copy(_ record: PickupRecord) {
        UIPasteboard.general.string = record.code
        copiedID = record.id
        copyTask?.cancel()
        copyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if !Task.isCancelled { copiedID = nil }
        }
    }

    /// 卡片内直接完成取件：先播放勾选反馈，再移出待取列表，最后给一次撤销机会。
    func complete(_ record: PickupRecord, in store: PickupStore) {
        guard !completing.contains(record.id) else { return }
        withAnimation(.snappy) { _ = completing.insert(record.id) }

        undoTasks.forEach { $0.cancel() }
        undoTasks.removeAll()

        undoTasks.append(Task { @MainActor in
            try? await Task.sleep(nanoseconds: 380_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                store.markPicked(record)
                completing.remove(record.id)
            }
            armUndo([record], action: .completed)
        })
    }

    func completeAll(in store: PickupStore) {
        let changed = store.markAllPendingAsPicked()
        guard !changed.isEmpty else { return }
        armUndo(changed, action: .completed)
    }

    /// 多选模式下把选中条目批量标记为已取（2026-10-14，参照取件喵「一键标记已取」）。
    /// 与单条 `complete(_:in:)` 同口径：直接落库 + 撤销条兜底（多选里没有勾选动画，
    /// 撤销条是唯一的后悔药）。只处理真正未取的条目，已取的混进选中集也不翻状态。
    func complete(_ records: [PickupRecord], in store: PickupStore) {
        let changed = records.filter { !$0.isPickedUp }
        guard !changed.isEmpty else { return }
        withAnimation(.snappy) {
            for record in changed { store.markPicked(record) }
        }
        armUndo(changed, action: .completed)
    }

    /// 「已取件」列表里把记录恢复为待取件 —— 首页已不再展示已取件，
    /// 恢复动作只住在「取件库」，这里不再需要。

    func undo(in store: PickupStore) {
        hideTask?.cancel()
        switch undoAction {
        case .completed:
            withAnimation(.snappy) { store.restore(undoRecords) }
        case .deleted:
            // 撤销删除必须把记录**放回** `records`：`restore` 只在已有记录上翻状态，
            // 找不到刚被摘掉的那条 —— 原实现在这里其实是失效的，本轮一并修掉。
            withAnimation(.snappy) { store.insert(undoRecords) }
        case .restored:
            for record in undoRecords { store.markPicked(record) }
        }
        undoRecords = []
        withAnimation(.snappy) { showUndo = false }
    }

    /// 删除并给出撤销机会
    func delete(_ record: PickupRecord, in store: PickupStore) {
        withAnimation(.snappy) { store.delete(record) }
        armUndo([record], action: .deleted)
    }

    /// 弹出撤销条并在 4 秒后收起。三个动作共用同一套时序与计时器，
    /// 顺便把 `undoAction` 一并记下 —— 漏记会让撤销按上一个动作的方向执行。
    ///
    /// ⚠️ 自动隐藏的计时器单独放 `hideTask`，**不并入** `undoTasks`：
    /// `complete` 是在 `undoTasks` 里某个任务**内部**调用本方法的，
    /// 若这里再 `undoTasks.forEach { $0.cancel() }`，会把正在执行的那个任务一起取消，
    /// 结果是撤销条永远不自动消失。
    private func armUndo(_ changed: [PickupRecord], action: PickupUndoAction) {
        undoRecords = changed
        undoAction = action
        withAnimation(.snappy) { showUndo = true }

        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { withAnimation(.snappy) { showUndo = false } }
        }
    }

    // MARK: 添加后的收尾

    /// 新条目写进列表后要保证「用户能立刻看见它」。
    ///
    /// 若当前挂着检索词或筛选条件，新条目很可能被过滤掉 —— 用户会以为添加失败、
    /// 再点一次，于是触发去重拦下、更加困惑。所以这里直接清空过滤条件并把排序
    /// 切回「最近收到」，让新条目必定出现在第一屏。
    ///
    /// 范围也要拉回「待取件」：新进来的条目一定是待取件。（首页只有待取件一屏，
    /// 无需再切范围，清空检索与筛选即可保证新条目可见。）
    func revealNewest() {
        withAnimation(.snappy) {
            query = ""
            clearFilters()
            sort = .newest
        }
    }

    func flashAdded(_ outcome: IngestOutcome) {
        toastTask?.cancel()

        withAnimation(.snappy) { addedToast = outcome.dialog }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if !Task.isCancelled { withAnimation(.snappy) { addedToast = nil } }
        }
    }
}

// MARK: - 首页视图

struct PickupListView: View {
    @EnvironmentObject private var store: PickupStore
    @StateObject private var model = PickupListModel()
    /// 长按菜单（自绘，替代系统 contextMenu —— 见 CardMenu.swift 的说明）
    @StateObject private var cardMenu = CardMenuState()

    // MARK: 列表作用域

    /// 首页**只服务待取件**（已取件的回执统一住在「取件库」）。
    private var scopedPending: [PickupRecord] {
        store.records.filter { !$0.isPickedUp }
    }

    /// 已取件 —— 首页列表不再展示，只给「今日已取」统计用。
    private var scopedPicked: [PickupRecord] {
        store.records.filter(\.isPickedUp)
    }

    /// 按免费版上限裁剪后的待办
    private var scopedList: [PickupRecord] {
        Array(scopedPending
            .sorted { $0.receivedAt > $1.receivedAt }
            .prefix(store.visibleLimit))
    }

    private var scopedHiddenCount: Int {
        max(0, scopedPending.count - store.visibleLimit)
    }

    private var scopedTodayNewCount: Int {
        scopedPending.filter { Calendar.current.isDateInToday($0.receivedAt) }.count
    }

    private var scopedTodayPickedCount: Int {
        scopedPicked.filter { Calendar.current.isDateInToday($0.receivedAt) }.count
    }

    /// 先按分类、范围与免费上限裁剪，再套用搜索 / 筛选 / 排序
    private var displayed: [PickupRecord] {
        let base = store.filtered(scopedList,
                                  query: model.query,
                                  company: model.companyFilter,
                                  kind: model.kindFilter)
        switch model.sort {
        case .newest:
            return base.sorted { $0.receivedAt > $1.receivedAt }
        case .oldest:
            return base.sorted { $0.receivedAt < $1.receivedAt }
        case .company:
            return base.sorted {
                $0.company == $1.company ? $0.receivedAt > $1.receivedAt : $0.company < $1.company
            }
        }
    }

    private var groups: [(group: DayGroup, items: [PickupRecord])] {
        store.grouped(displayed)
    }

    /// 按驿站聚拢的分组：组头 = 驿站短名（`station` 从地址裁出），组内按时间倒序。
    /// 件数多的驿站排前面（到店场景先看件最多的那家）；提不出站名的归「其他位置」垫底。
    private var stationGroups: [(station: String, items: [PickupRecord])] {
        var buckets: [(station: String, items: [PickupRecord])] = []
        var others: [PickupRecord] = []

        for record in displayed {
            let name = record.station
            guard !name.isEmpty else {
                others.append(record)
                continue
            }
            if let index = buckets.firstIndex(where: { $0.station == name }) {
                buckets[index].items.append(record)
            } else {
                buckets.append((name, [record]))
            }
        }

        buckets.sort { $0.items.count > $1.items.count }
        if !others.isEmpty { buckets.append(("其他位置", others)) }
        return buckets
    }

    var body: some View {
        NavigationStack(path: $model.path) {
            List {
                // 顶部统计卡：待取 / 今日新增 / 今日已取 三格一组，只报数不切页。
                Section {
                    PendingStatsCard(pending: scopedPending.count,
                                     todayNew: scopedTodayNewCount,
                                     todayPicked: scopedTodayPickedCount)
                    .listRowInsets(EdgeInsets(top: 2, leading: AppTheme.hInset,
                                              bottom: 12, trailing: AppTheme.hInset))
                    .listRowBackground(Color(.systemGroupedBackground))
                    .listRowSeparator(.hidden)

                    if model.hasActiveFilter {
                        FilterBar(summary: model.activeFilterSummary,
                                  count: displayed.count,
                                  onClear: { withAnimation(.snappy) { model.clearFilters() } })
                            .listRowInsets(EdgeInsets(top: -4, leading: AppTheme.hInset,
                                                      bottom: 6, trailing: AppTheme.hInset))
                            .listRowBackground(Color(.systemGroupedBackground))
                            .listRowSeparator(.hidden)
                    }

                    // 组织方式切换（时间流 / 按驿站）已收进筛选菜单（2026-10-14）——
                    // 原列表头的整条灰底胶囊分段视觉过重，且与顶栏筛选功能语义重复。
                }

                content

                if scopedHiddenCount > 0 && !model.hasActiveFilter && model.query.isEmpty {
                    Section {
                        HiddenHint(count: scopedHiddenCount)
                            .listRowInsets(EdgeInsets(top: 2, leading: AppTheme.hInset,
                                                      bottom: 8, trailing: AppTheme.hInset))
                            .listRowBackground(Color(.systemGroupedBackground))
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(AppTheme.listSpacing)
            .scrollContentBackground(.hidden)
            // 🔴 页面底 = 浅灰，且**行背景必须显式写成同一个浅灰**（2026-09-23 二次修正）。
            //
            // 第一版只把 `.scrollContentBackground(.hidden)` + `.background(浅灰)`
            // 补上，行背景留 `Color.clear` 想"透出页面底" —— 实测**记录行仍然透出系统白**
            // （像素采样：统计卡区左边缘 #F2F2F7，记录卡片区左边缘 #FFFFFF），
            // 上半浅灰、下半白，比原来还难看。原因就是 `.plain` 样式下行的默认底是
            // `systemBackground`，`clear` 并不能可靠地透到 List 视图背景那一层。
            // 改成显式同色后，行区域不再依赖任何透明传递。
            .background(Color(.systemGroupedBackground))
            .contentMargins(.bottom, 88, for: .scrollContent)
            .searchable(text: $model.query,
                        placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: "取件码 / 快递公司 / 地址")
            // 🔴 2026-10-08 结构重构：浏览（已取件）独立成 Tab 后，取件页不再需要
            //    分段切换器 —— 回归系统导航栏（大标题「取件」+ drawer 搜索 + 系统
            //    toolbar）。此前为「分段居中于标题位」做的自绘顶栏随分段一起退役。
            .navigationTitle("待取")
            .navigationDestination(for: PickupRecord.self) { record in
                RecordDetailView(record: record)
            }
            .toolbar { toolbarContent }
            .overlay(alignment: .bottom) { bottomOverlay }
            .sheet(isPresented: $model.showAdd) {
                AddPickupSheet(onClose: { model.showAdd = false },
                               onAdded: handleAdded)
                    .environmentObject(store)
            }
            .sheet(isPresented: $model.showScan) {
                ScanPickupSheet(onClose: { model.showScan = false },
                                onAdded: handleAdded)
                    .environmentObject(store)
            }
            // 分享预览面板：单条（长按菜单「分享卡片」）与多条（多选后顶栏「分享」）
            // 共用 —— 内容 = 记录渲染成的一张分享卡图。
            // 🔴 必须挂在页面这一层：它的呈现者要活得比长按浮层久。
            //    挂进浮层的话，菜单一关浮层即销毁，面板根本弹不出来（见 CardMenu.swift）。
            // 分享预览面板：单条（长按菜单「分享卡片」）与多条（多选后顶栏「分享」）
            // 共用 —— 内容 = 记录渲染成的一张分享卡图。
            // 🔴 必须挂在页面这一层：它的呈现者要活得比长按浮层久。
            //    挂进浮层的话，菜单一关浮层即销毁，面板根本弹不出来（见 CardMenu.swift）。
            .sheet(isPresented: Binding(
                get: { model.shareRecords != nil },
                set: { if !$0 { model.shareRecords = nil } })) {
                if let records = model.shareRecords {
                    SharePreviewSheet(records: records)
                }
            }
            // 通知权限在这里才问：用户已经看见「待取件」列表长什么样了，
            // 此时解释「新短信进来时提醒你」才讲得通。冷启动就弹只会被随手拒掉。
            .onAppear {
                // 截图脚手架：`SIMCTL_CHILD_SKIP_PERM=1` 时不弹系统通知授权。
                // 那个弹窗会盖住屏幕中部，验收图上什么都看不见 —— 而 simctl
                // 点不到「允许」，只能从源头绕开。
                if ProcessInfo.processInfo.environment["SKIP_PERM"] == nil {
                    PickupNotifier.requestAuthorizationIfNeeded()
                }
                openMenuFromScaffold()
                // 多选分享截图脚手架：`SIMCTL_CHILD_SELECT_MODE=1` 启动即进多选
                // 并预选前三条 —— 命令行点不到卡片，选择圈与顶栏只能这样拍。
                if ProcessInfo.processInfo.environment["SELECT_MODE"] == "1",
                   !model.selectionMode {
                    let ids = displayed.map(\.id)
                    if let first = ids.first {
                        model.enterSelection(startingWith: first)
                        for id in ids.prefix(3) { model.selectedIDs.insert(id) }
                    }
                }
                // 🔴 回到标签根页 → 露出标签栏（TabBarCloak 计数归零兜底，
                //    pop 转场开始即触发，滑回动画与转场并行）
                TabBarCloak.shared.reveal()
            }
        }
        // 长按景深：整个界面轻微后退（模糊 + 缩放），被按的卡片由浮层里的「替身」
        // 接管 —— 替身与菜单都在下面这个 overlay 里，因此始终清晰。
        .blur(radius: cardMenu.openID == nil ? 0 : CardMenuMetrics.backgroundBlur)
        .scaleEffect(cardMenu.openID == nil ? 1 : CardMenuMetrics.backgroundScale)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: cardMenu.openID)
        .overlay { cardMenuLayer }
    }

    /// 两个添加入口共用的收尾：成功则解除过滤让新条目可见，同时给一条轻反馈。
    private func handleAdded(_ outcome: IngestOutcome) {
        if !outcome.added.isEmpty { model.revealNewest() }
        model.flashAdded(outcome)
    }

    // MARK: 列表内容

    @ViewBuilder
    private var content: some View {
        // 空态看的是「范围底稿」而不是「过滤后的结果」：前者空 = 真的没有，
        // 后者空但底稿非空 = 有记录、只是被检索词筛掉了，两种要给不同的提示。
        if scopedList.isEmpty {
            Section {
                EmptyStateView(symbol: "shippingbox",
                               title: "暂无待取件",
                               hint: "收到快递短信后，取件信息会自动出现在这里")
                    .listRowInsets(EdgeInsets(top: 40, leading: AppTheme.hInset,
                                              bottom: 0, trailing: AppTheme.hInset))
                    .listRowBackground(Color(.systemGroupedBackground))
                    .listRowSeparator(.hidden)
            }
        } else if displayed.isEmpty {
            Section {
                NoResultView(query: model.query, filterSummary: model.activeFilterSummary)
                    .listRowInsets(EdgeInsets(top: 36, leading: AppTheme.hInset,
                                              bottom: 0, trailing: AppTheme.hInset))
                    .listRowBackground(Color(.systemGroupedBackground))
                    .listRowSeparator(.hidden)
            }
        } else {
            switch model.groupMode {
            case .timeline:
                // 时间流：今天 / 昨天 / 更早
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

            case .station:
                // 按驿站：组头挂品牌色 storefront 图标，组内保持时间倒序
                ForEach(stationGroups, id: \.station) { bucket in
                    Section {
                        ForEach(bucket.items) { record in
                            row(for: record)
                        }
                    } header: {
                        SectionHeader(title: bucket.station,
                                      trailing: "\(bucket.items.count) 件",
                                      symbol: "storefront.fill",
                                      tint: CourierBrand.info(for: bucket.station).color)
                            .padding(.horizontal, AppTheme.hInset)
                            .padding(.top, 4)
                            .padding(.bottom, 6)
                            .textCase(nil)
                    }
                }
            }
        }
    }

    // MARK: 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if model.selectionMode {
            // 多选模式：顶栏换成「取消 · 已取 · 分享」，隐藏添加 / 扫描 / 筛选 / 头像
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") { model.exitSelection() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.complete(selectedRecords, in: store)
                    model.exitSelection()
                } label: {
                    Text(model.selectedIDs.isEmpty
                         ? "已取"
                         : "已取 \(model.selectedIDs.count)")
                        .fontWeight(.semibold)
                }
                .disabled(model.selectedIDs.isEmpty)
                .tint(AppTheme.doneTint)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.shareRecords = selectedRecords
                } label: {
                    Text(model.selectedIDs.isEmpty
                         ? "分享"
                         : "分享 \(model.selectedIDs.count)")
                        .fontWeight(.semibold)
                }
                .disabled(model.selectedIDs.isEmpty)
            }
        } else {
            // 顶栏三胶囊（借鉴 Apple 邮件/提醒事项的工具栏口径，2026-10-14）：
            //   「+」菜单聚合两个添加入口（原「添加」「扫描」两个等权胶囊合并，
            //    对齐系统 App「一个 + 收纳多种新建方式」的惯例）；
            //   筛选菜单里管排序/分组/过滤；
            //   「选择」走照片 App 的文字按钮口径（checkmark 图标语义太弱）。
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        model.showAdd = true
                    } label: {
                        Label("粘贴解析添加", systemImage: "doc.on.clipboard")
                    }

                    Button {
                        model.showScan = true
                    } label: {
                        Label("扫描识别添加", systemImage: "viewfinder")
                    }
                } label: {
                    // 与全局同一套矢量还原（圆圈加号），颜色走系统默认前景色
                    AddGlyph(size: 21)
                }
                .accessibilityLabel("添加取件信息")

                filterMenu

                // 多选入口（2026-09-24 主人定）：双指手势体验不稳，改常规按钮。
                Button {
                    model.selectionMode = true
                } label: {
                    Text("选择")
                }
                .accessibilityLabel("选择多条记录")
            }

            // 🔴 2026-10-14：顶栏头像入口退役 —— 设置已升格为底部第 4 个标签页
            // （原「我的」面板整体重构进设置页，见 RootView / ProfileView）。
        }
    }

    /// 多选分享的记录集：按当前显示顺序（排序 / 检索后的顺序）取
    private var selectedRecords: [PickupRecord] {
        displayed.filter { model.selectedIDs.contains($0.id) }
    }

    private var filterMenu: some View {
        Menu {
            // 列表分组（时间流 / 按驿站）——原列表头的整条胶囊分段退役后收编至此
            // （借鉴 Apple 提醒事项：视图组织方式归入「⋯」菜单，带 ✓ 勾选态）。
            Picker("列表分组", selection: $model.groupMode) {
                ForEach(PickupGroupMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
                }
            }

            Picker("排序", selection: $model.sort) {
                ForEach(PickupSortMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
                }
            }

            Picker("快递公司", selection: $model.companyFilter) {
                Text("全部快递公司").tag(String?.none)
                ForEach(store.companiesByVolume, id: \.name) { item in
                    Text("\(item.name)（\(item.count)）").tag(String?.some(item.name))
                }
            }

            // 「信息类别」= 凭证形态（取件码 / 运单号 / 尾号 / 特殊码）
            Picker("信息类别", selection: $model.kindFilter) {
                Text("全部类别").tag(PickupKind?.none)
                ForEach(PickupKind.allCases) { kind in
                    Text(kind.label).tag(PickupKind?.some(kind))
                }
            }

            if model.hasActiveFilter {
                Divider()
                Button {
                    withAnimation(.snappy) { model.clearFilters() }
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
            }

            if !store.pending.isEmpty {
                Divider()
                Button {
                    model.completeAll(in: store)
                } label: {
                    Label("全部标记为已取", systemImage: "checkmark.circle")
                }
            }

            if !store.pickedUpRecords.isEmpty {
                Button(role: .destructive) {
                    withAnimation(.snappy) { store.clearPickedUp() }
                } label: {
                    Label("清空已取件记录", systemImage: "trash")
                }
                .tint(.red)
            }
        } label: {
            Image(systemName: model.hasActiveFilter
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("筛选与排序")
    }

    // MARK: 底部浮层（新条目提示 / 撤销）

    @ViewBuilder
    private var bottomOverlay: some View {
        if let message = model.addedToast {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.doneTint)

                Text(message)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, AppTheme.hInset)
            .padding(.bottom, 92)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if model.showUndo {
            UndoToast(message: undoMessage, actionTitle: "撤销") {
                model.undo(in: store)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.bottom, 92)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// 撤销条的文案按**动作**取，而不是靠 `undoRecords` 反推 ——
    /// 同一条记录在"完成"与"恢复"里长的一模一样，反推不出方向。
    private var undoMessage: String {
        switch model.undoAction {
        case .completed:
            return model.undoRecords.count > 1
                ? "已标记 \(model.undoRecords.count) 条为已取"
                : "已标记为已取"
        case .deleted:
            return model.undoRecords.first.map { "已删除 \($0.company) \($0.code)" } ?? "已删除"
        case .restored:
            return "已恢复为待取件"
        }
    }

    // MARK: 单个卡片行

    /// 首页只有待取件一种行：`PickupCard`（卡内勾选即完成）。
    @ViewBuilder
    private func row(for record: PickupRecord) -> some View {
        let isDone = record.isPickedUp || model.completing.contains(record.id)
        let isCopied = model.copiedID == record.id

        rowChrome(record, content: PickupCard(record: record,
                                              isDone: isDone,
                                              isCopied: isCopied,
                                              onToggle: { model.complete(record, in: store) },
                                              onCopy: { model.copy(record) },
                                              selectionState: model.selectionMode
                                                  ? model.selectedIDs.contains(record.id)
                                                  : nil))
    }

    /// 行外壳：内边距、点击进详情、左右侧滑、长按菜单。
    ///
    /// 抽出来的理由：两种卡片内容要的是**同一套操作**，只有动作名随状态不同。
    /// 复制两份迟早出现「其中一份忘了改」—— 这种漂移在 UI 上极难发现
    /// （得分别左滑、右滑、长按各比一遍才看得出来）。
    ///
    /// 多选模式（2026-09-23）：点击 = 勾选/取消，侧滑与长按菜单全部停用 ——
    /// 分享流程里不该有删除这类破坏性操作混进来。链尾三件套（背景 / 分隔符 /
    /// insets）两种模式共用一份，保证写法始终在链尾。
    private func rowChrome<Content: View>(_ record: PickupRecord,
                                          content: Content) -> some View {
        let base = content
            .contentShape(.rect)
            .onTapGesture {
                if model.selectionMode {
                    model.toggleSelection(record.id)
                } else {
                    model.path.append(record)
                }
            }

        return Group {
            if model.selectionMode {
                base
            } else {
                base
                    // 左右侧滑与长按菜单只在常规模式存在
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button { model.complete(record, in: store) } label: {
                            Label("已取", systemImage: "checkmark.circle.fill")
                        }
                        .tint(AppTheme.doneTint)

                        Button(role: .destructive) { model.delete(record, in: store) } label: {
                            Label("删除", systemImage: "trash.fill")
                        }
                        .tint(.red)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button { model.copy(record) } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .tint(AppTheme.accent)

                        Button { model.path.append(record) } label: {
                            Label("详情", systemImage: "info.circle")
                        }
                        .tint(AppTheme.indigo)
                    }
                    // 长按菜单：按住回弹 → 卡片放大浮起 + 描边，菜单贴着卡片弹出。
                    // 不再用系统 `.contextMenu` —— 它会给卡片套一层白色圆角背景板。
                    .cardLongPress(for: record.id, state: cardMenu)
            }
        }
        // 🔴 **`.listRowBackground` 必须写在整条链的最末尾**（2026-09-23 实测结论）。
            //
            // 症状：统计卡区是浅灰、记录卡片区却是白，页面上下两截颜色对不上。
            // 根因是**它写在了 `.swipeActions` 前面**：`.swipeActions` 会把行容器
            // 重新包一层，写在它之前的行级 modifier 就落到了被包住的**内层**，
            // 作用不到真正的行上 —— 行便回落到 cell 默认的白色底
            // （像素采样实测：那一截左边缘是 #FFFFFF）。
            //
            // ⚠️ 中途试过"把 insets 归零、改由内容自己铺底色"，**不要走这条路**：
            //    `.listRowInsets(EdgeInsets())` 的全零值会被系统当成"没设置"，
            //    行仍回落到默认 **16pt 水平内边距** —— 内容底色只铺到 x=16…385，
            //    左右各留 16pt 白边；同时内容还要再加一份 `hInset` 的 padding，
            //    结果卡片被整整挤进去 16pt（实测左边缘 16pt → 32pt）。
            //    正解就是这一行：insets 照常给，行背景放链尾。
            .listRowBackground(Color(.systemGroupedBackground))
            // 🔴 行分隔符同样必须在链尾（与 listRowBackground 同一个坑）：
            //    写在 `.swipeActions` 之前会落到被重新包住的内层而失效，
            //    系统那条 0.5pt 灰线就会漏出来横在两张卡片之间
            //    （2026-09-23 主人截图指认）。
            .listRowSeparator(.hidden)
            // 🔴 **listRowInsets 也在同一张"必须链尾"名单里**（2026-09-23 探针实测）：
            //    写在 swipeActions 之前同样落内层失效 —— 卡片间距 29.3pt 改不动，
            //    根因就是它（改的值从未生效，吃的全是系统默认行边距）。
            // 挪到链尾后真正生效：上下各 7.5pt = 卡片间实距 15pt，
            // 即主人要求的"原来 29.3pt 的一半"。
            .listRowInsets(EdgeInsets(top: 7.5, leading: AppTheme.hInset,
                                      bottom: 7.5, trailing: AppTheme.hInset))
    }

    // MARK: 长按菜单

    /// 菜单内容与顺序对齐原系统菜单：复制 / 分享 / 完成 / 详情 /（分隔）删除。
    private func menuItems(for record: PickupRecord) -> [CardMenuItem] {
        [
            CardMenuItem(title: "复制取件码",
                         symbol: "doc.on.doc",
                         action: { model.copy(record) }),
            // 分享由页面级 `.sheet` 承载（见 body 里的 shareRecords）——
            // 🔴 菜单项**不能**自己弹面板：面板的呈现者会随浮层一起被销毁。
            CardMenuItem(title: "分享卡片",
                         symbol: "square.and.arrow.up",
                         action: { model.shareRecords = [record] }),
            // 多选分享：进入多选模式并预选被长按的这一条（2026-09-23）
            CardMenuItem(title: "多选分享",
                         symbol: "checkmark.circle",
                         action: { model.enterSelection(startingWith: record.id) }),
            CardMenuItem(title: "标记为已取",
                         symbol: "checkmark.circle",
                         action: { model.complete(record, in: store) }),
            // 编辑收进了详情页（2026-10-14 主人定稿：不弹二级编辑页），
            // 菜单不再放「编辑」—— 「查看详情」进详情页后工具栏就是「编辑」。
            CardMenuItem(title: "查看详情",
                         symbol: "info.circle",
                         action: { model.path.append(record) }),
            CardMenuItem(title: "删除记录",
                         symbol: "trash",
                         tint: Color(uiColor: .systemRed),
                         role: .destructive,
                         showsSeparatorBefore: true,
                         action: { model.delete(record, in: store) }),
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
                PickupCard(record: record,
                           isDone: record.isPickedUp,
                           isCopied: false,
                           onToggle: {},
                           onCopy: {})
            }
        }
    }

    // MARK: 截图脚手架

    /// `SIMCTL_CHILD_MENU_OPEN=<序号>`：启动后自动打开列表第 N 条的菜单。
    ///
    /// 命令行无法脚本化「长按」这一手势（`simctl` 没有触摸注入接口），
    /// 而菜单的定位与高亮恰恰只有真渲染才看得出对错 —— 所以留这个后门：
    /// 走的是与长按完全相同的 `cardMenu.open(_:)`，只是触发者从手指换成定时器。
    ///
    /// `SIMCTL_CHILD_SHARE_HIT=<序号>`：菜单打开后再自动「点」一次其中的
    /// 「分享卡片」行 —— 执行的就是该行 Button 的闭包体（收起菜单 + 交出记录），
    /// 只差一次 UIKit 手势识别，而那一环与本缺陷无关（菜单里其它行都正常触发）。
    /// 用来验证「点分享 → 预览面板弹出」这条呈现链路：缺陷正是**面板根本不出现**，
    /// 而它只在真渲染时暴露，所以必须留一个可脚本化的触发入口。
    private func openMenuFromScaffold() {
        let env = ProcessInfo.processInfo.environment
        let tapsShareRow = env["SHARE_HIT"] != nil
        guard let raw = env["SHARE_HIT"] ?? env["MENU_OPEN"],
              let index = Int(raw) else { return }

        Task { @MainActor in
            // 等卡片坐标上报（最多 3 秒）：首帧布局与几何上报有先后差，
            // 开得太早会拿不到锚点 —— 菜单会落到回落位置而不是卡片旁边。
            var waited = 0
            while cardMenu.frames.isEmpty && waited < 30 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }

            let list = displayed
            guard list.indices.contains(index) else { return }
            let record = list[index]
            cardMenu.open(record.id)

            guard tapsShareRow else { return }
            // 等菜单入场动画走完再点，否则拍到的还是菜单在飞的中间帧。
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let action = menuItems(for: record)
                .first(where: { $0.title == "分享卡片" })?.action else { return }
            cardMenu.close()   // == 手指点击该行时的 onDismiss()
            action()           // == 手指点击该行时的 item.action?()
        }
    }
}

// MARK: - 筛选状态条

struct FilterBar: View {
    let summary: String
    let count: Int
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 12, weight: .semibold))
            Text("\(summary) · \(count) 条")
                .font(.footnote.weight(.medium))
            Spacer(minLength: 6)
            Button(action: onClear) {
                Text("清除")
                    .font(.footnote.weight(.semibold))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(AppTheme.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.accent.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 无匹配结果

struct NoResultView: View {
    let query: String
    let filterSummary: String

    var body: some View {
        VStack(spacing: 14) {
            IconBadge(symbol: "magnifyingglass", tint: AppTheme.sky, size: 66)

            VStack(spacing: 6) {
                Text("没有匹配的取件信息")
                    .font(.headline)
                Text(query.isEmpty
                     ? "试试换个筛选条件"
                     : "没有找到包含「\(query)」的记录")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }
}

// MARK: - 组织方式切换（时间流 / 按驿站）

// MARK: - 顶部 Hero 统计卡（设计语言 v2，2026-10-14）
//
/// 「待取件」顶部的**主视觉仪表盘**，参考 Apple 健康/钱包的「大数字卡」版式：
///  · 左侧主数字：待取件数 46pt rounded bold + accent 渐变 —— 进门第一眼就是它；
///  · 右侧次级列：今日新增 / 今日已取 两行小格，各带语义色图标，退居辅助位。
/// 与旧版「三格均分」的本质区别：主次有了层级 —— 旧版三个数字一样大，
/// 用户分不清哪个才是「现在要做的事」。
struct PendingStatsCard: View {
    let pending: Int
    let todayNew: Int
    let todayPicked: Int

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // —— 主数字区：待取件 ——
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(pending)")
                        .font(.system(size: AppTheme.heroNumber, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(
                            LinearGradient(colors: [AppTheme.accent, AppTheme.accentLight],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                        )
                    Text("件待取")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 9, weight: .medium))
                    Text("顺路去取，码在这里")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            // —— 次级列：今日新增 / 今日已取 ——
            VStack(alignment: .leading, spacing: 10) {
                miniStat("今日新增", value: todayNew,
                         tint: AppTheme.todayTint, symbol: "arrow.down.circle.fill")
                miniStat("今日已取", value: todayPicked,
                         tint: AppTheme.doneTint, symbol: "checkmark.circle.fill")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        // Hero 卡用独立大圆角 + 稍强的主色氛围（主色即「待取」语义色，
        // 氛围强度走统一约束，不会退化成整卡染色）
        .cardSurface(radius: AppTheme.heroRadius, tint: AppTheme.accent)
    }

    private func miniStat(_ title: String, value: Int, tint: Color, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .frame(minWidth: 14, alignment: .trailing)
        }
    }
}

// MARK: - 取件码卡片（卡片内可直接完成取件）

struct PickupCard: View {
    let record: PickupRecord
    let isDone: Bool
    let isCopied: Bool
    let onToggle: () -> Void
    let onCopy: () -> Void
    /// 多选分享模式（2026-09-23）：nil = 常规模式（显示完成按钮）；
    /// true / false = 已选 / 未选（显示选择圈，点击整卡勾选）。
    var selectionState: Bool? = nil

    private var brand: Color { record.brandColor }

    /// 品牌小图标尺寸 —— 与地址行文字（12.5pt）视觉等高，行首起标识作用、不与取件码争焦点。
    private static let logoSize: CGFloat = 20

    /// 驿站名称库（内置 + 用户自定义），订阅以便用户在设置页增删后卡片即时刷新
    @ObservedObject private var stationDirectory = StationDirectory.shared

    /// 行 1 主名优先级：快递公司 > 驿站名（按名称库命中）> 取件平台（2026-10-14 定稿）
    private var courierName: String? {
        let c = record.courier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return c.isEmpty ? nil : c
    }
    private var stationName: String? {
        stationDirectory.matchedName(in: [record.rawMessage])
    }
    private var titlePrimary: String {
        courierName ?? stationName ?? record.company
    }
    /// 管道符后的次名：主名不是平台本身时跟「取件平台」名，避免「微快递 | 微快递」重复
    private var titleSecondary: String? {
        titlePrimary == record.company ? nil : record.company
    }
    /// 行 1 图标匹配串随主名走：快递公司 → 驿站 → 平台
    private var titleIconSource: String {
        courierName ?? stationName ?? record.company
    }

    var body: some View {
        // 左侧品牌色竖条已移除（2026-09-21）：卡片上的颜色锚点已经够多 ——
        // 卡面品牌色氛围渐变、行首品牌图标、品牌色取件码、复制按钮，
        // 再叠一条竖条属于第四遍重复，视觉噪音大于信息量。
        HStack(spacing: 10) {
            if let selected = selectionState {
                selectionCircle(selected)
            } else {
                CompleteButton(isDone: isDone, tint: brand, action: onToggle)
            }

            // 右侧三层信息：平台 / 地址 → 虚线 → 取件码。
            // 品牌图标不再独占左侧一列，改为缩至行高量级、落在地址行首 ——
            // 左侧让出的约 60pt 全部回补给地址与取件码，长地址的截断点明显后移。
            VStack(alignment: .leading, spacing: 0) {
                    // 行 1：图标 + 主名（快递公司 > 驿站 > 平台）+「| 取件平台」+ 时间
                    // （2026-10-14 主人定稿：删类别标签；图标从地址行首挪到主名行首）
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
                            .foregroundStyle(isDone ? .secondary : .primary)

                        if let secondary = titleSecondary {
                            Text("|")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.secondary.opacity(0.45))
                            Text(secondary)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .foregroundStyle(isDone ? .tertiary : .secondary)
                        }

                        Spacer(minLength: 6)

                        Text(record.relativeTime)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    // 行 2：取件地址 + 货架号标签（图标已上移行 1，不再重复）
                    if !addressLine.isEmpty || record.shelf?.isEmpty == false {
                        HStack(spacing: 6) {
                            Text(addressLine)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            // 货架号（参照「码上取」）：到店场景直接定位包裹的那一格
                            if let shelf = record.shelf, !shelf.isEmpty {
                                Text("货架\(shelf)")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(brand)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(brand.opacity(0.14), in: .capsule)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                        }
                        .padding(.top, 4)
                    }

                    // 分界虚线：把「信息层」与「取件码」划开
                    DashedDivider()
                        .padding(.top, 8)
                        .padding(.trailing, 2)

                    // 行 3：取件码 —— 末四位品牌色强调（前段弱化），驿站报码看的就是这段
                    HStack(spacing: 8) {
                        record.emphasizedCodeText(isDone: isDone, tint: brand)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospaced()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)

                        Spacer(minLength: 6)

                        CopyCodeButton(isCopied: isCopied, tint: brand, action: onCopy)
                    }
                    .padding(.top, 7)
            }
        }
        // 去掉竖条后左右内边距取同一值，卡片内不再有「被竖条吃掉」的左侧偏窄感
        .padding(.horizontal, AppTheme.cardPadding)
        .padding(.vertical, 12)
        .cardSurface(tint: brand)
        .opacity(isDone && selectionState == nil ? 0.72 : 1)
    }

    /// 多选圈：与完成按钮同一 27pt 圆的几何，选中 = accent 实心 + 白勾。
    /// 刻意与「标记已取」的品牌色勾区分 —— 勾选态属于分享流程，不与取件状态混淆。
    private func selectionCircle(_ selected: Bool) -> some View {
        ZStack {
            if selected {
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 27, height: 27)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.8)
                    .frame(width: 27, height: 27)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: selected)
    }

    /// 平台名已单独成行，地址行只保留地址本身
    private var addressLine: String {
        record.address.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - 超出免费版展示上限的提示（规格 §二 R3）

struct HiddenHint: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
            Text("还有 \(count) 条记录 · 升级后查看")
                .font(.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .cardSurface(radius: AppTheme.innerRadius)
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let hint: String

    init(symbol: String, title: String, hint: String) {
        self.symbol = symbol
        self.title = title
        self.hint = hint
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: symbol)
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(spacing: 7) {
                Text(title)
                    .font(.headline)
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
    }
}
