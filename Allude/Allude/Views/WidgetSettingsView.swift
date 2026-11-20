import SwiftUI
import WidgetKit

// MARK: ============================================================================
// 桌面小组件（我的 › 设置 › 二级页）
//
// 回答「我的小组件为什么长这样 / 能不能少显示点东西」：
//   1. **显示内容**：六个开关 —— 完整信息 / 取件地址 / 快递公司 / 驿站 / 快递柜·货架 /
//      显示占位符。取件码**不参与配置**；「完整信息」= 其余四项全开，与它们天然互斥。
//   2. **效果预览**：与桌面**同一份渲染代码**，喂示例数据，
//      并**跟着上面的开关实时变**；
//   3. **小组件效果**：各尺寸铺开，同样用示例数据。
//
// 🔴 **2026-11-16 形态变更**（主人：「将显示占位符与上面的 5 个合并到一起……
//    显示内容的开关和上面的效果预览互相换一下位置」）：
//    顺序改成「先开关、后预览」，「空位」分组取消，占位符并入显示内容。
//    预览仍与桌面共用一份渲染代码，实时跟随全部开关。
//
// 🔴 **2026-11-20 文案收口**（主人：「提示文字能少则少，非必要不提示，用户压根不看」）：
//    删掉三段说明（「取件码永远显示…」「关掉占位符后…」、预览下方「示例数据…」），
//    改成两张卡自证结构 ——「完整信息」单独一张，其余五项一张；
//    行标题同时去掉冗余的「显示」前缀（分组标题已经写了「显示内容」）。
//
// 🔴 **2026-10-27 形态变更**（主人：「下面的显示内容的开关勾选直接做成开关……
//    完整信息与下面的互斥，事实上与之前一样，但是形式变了」）：
//    原先是四个模板**圆形单选**（完整信息 / 只要取件码 / 码+平台 / 码+驿站）。
//    单选表达不了「我要平台+柜、不要地址」这种组合，而且四行文案要用户自己
//    在脑子里翻译成字段。改成开关后每个字段独立可见，组合能力自然覆盖原四模板：
//      · 全关 = 只要取件码
//      · 只开公司 = 码 + 快递平台
//      · 公司 + 驿站 = 码 + 驿站
//      · 全开 = 完整信息
//    「完整信息」不做禁用联动 —— 它的开关状态就是"四项是否全开"这一个事实，
//    用户关掉任一项它自己熄灭，打开它四项一起亮，状态本身就是唯一真相。
//
// 🔴 **总开关已删除**（2026-09-23 主人定调：「没啥意义」）：
//    用户不想要这个小组件，直接从桌面移除即可；App 里再给一个会让桌面变成
//    「已关闭」死牌子的开关，一旦关掉又找不到入口就是死局。
//
// ⚠️ 显示设置落 App Group（`WidgetDisplayOptions`），改完必须 reloadAllTimelines ——
//    否则桌面还是旧画面，用户会以为设置坏了。
// ============================================================================

final class WidgetSettingsModel: ObservableObject {
    /// 用户**存下来**的字段组合（落 App Group）。
    @Published var options = WidgetDisplayOptions.load()

    init() {
        // 🔴 升级归一（2026-10-27）只跑一次（2026-11-14 修）：
        //    旧版「完整信息」= 公司 + 地址（驿站关着），新页面判定是四项全开。
        //    但这套"补成 .full"的逻辑如果每次都跑，用户**主动关掉「显示驿站」**
        //    后，下次进页面又会被当成老数据补回来 —— 表现为"关了不记住"。
        //    因此加一次性标记：迁移完就不再干预用户的组合。
        let store = UserDefaults(suiteName: PickupStorage.appGroupID)
        let migratedKey = "allude.widget.migratedComplete"
        guard store?.bool(forKey: migratedKey) != true else { return }
        let loaded = WidgetDisplayOptions.load()
        if loaded.showsCompany, loaded.showsAddress, !loaded.showsStation {
            apply(.full)
        }
        store?.set(true, forKey: migratedKey)
    }

    /// 单项开关。`keyPath` 由视图层的字段枚举给出，模型不重复维护字段清单。
    func set(_ keyPath: WritableKeyPath<WidgetDisplayOptions, Bool>, to value: Bool) {
        guard options[keyPath: keyPath] != value else { return }
        var next = options
        next[keyPath: keyPath] = value
        apply(next)
    }

    /// 「完整信息」：开 = 四项全开，关 = 四项全关（只剩取件码）。
    ///
    /// 关掉时为什么是全关而不是"恢复到上次的组合"：这个开关的语义是
    /// 「要不要完整信息」，关掉就是"不要"，退到最干净的形态最符合直觉；
    /// 想只留一两项，用户直接在下面四项里点 —— 那条路更精确。
    func setComplete(_ on: Bool) {
        apply(on ? .full : .codeOnly)
    }

    private func apply(_ next: WidgetDisplayOptions) {
        options = next
        WidgetDisplayOptions.save(next)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct WidgetSettingsView: View {
    @StateObject private var model = WidgetSettingsModel()

    /// 空槽（灰色骨架行）开关；默认开，与历史行为一致。
    /// 🔴 用 `@AppStorage` 直接读写 App Group：`@State` 只在页面生命周期内记值，
    ///    离开再进来会回到默认值（2026-11-14 主人反馈"关了不记住"）。
    @AppStorage(WidgetPlaceholderSetting.key,
                store: UserDefaults(suiteName: PickupStorage.appGroupID))
    private var showsPlaceholders = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sections
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 6)
            .padding(.bottom, 60)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("桌面小组件")
        .cloaksTabBar()
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var sections: some View {
        Group {
            // 🔴 2026-11-16 主人：把「显示内容」开关与「效果预览」互换位置 ——
            //    先调设置、再看效果；同时「显示占位符」并入上面那张卡，
            //    不再单列「空位」分组。
            displaySection
            previewSection
            gallerySection
        }
    }

    // MARK: 效果预览

    /// 🔴 **不再套白色卡片**（2026-10-27 主人：「不要这个白色的矩形，直接把小组件
    /// 放在这里就行，文字介绍在小组件下方」）。
    ///
    /// `WidgetCanvas` 自带实体底 + 顶部主色氛围渐变 + 24pt 圆角，本身就是桌面小组件
    /// 的完整外观；外面再包一层 `cardSurface()` 等于给小组件又套了个相框 ——
    /// 边界重复、还白吃一圈 16pt 内边距，视觉上变成"卡片里的卡片"。
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "效果预览")

            // 🔴 2026-11-08 主人：顶部这张比真机宽 —— 原来用 `expandsToFill` 吃满页面宽度，
            //    而真机中尺寸是固定 338pt。改成与「桌面小组件」页里的中尺寸预览同宽、居中。
            WidgetCanvas(.medium) {
                // 🔴 2026-11-14 主人：顶部预览只放 **2 条**取件码 ——
                //    中尺寸一页 3 行，留出来的第 3 行正好演示「空位」开关的效果
                //    （开=灰色骨架，关=留白）。放满 3 条就看不到占位行。
                WidgetPagedContent(snapshot: .previewTwoRows(),
                                   pageSize: WidgetPageSize.rowCount(family: "m"),
                                   familyKey: "m",
                                   options: effectiveOptions,
                                   showsPlaceholders: showsPlaceholders)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 显示内容（完整信息 + 五项）

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "显示内容")

            // 2026-11-20 主人：「提示文字能少则少，非必要不提示，用户压根不看」。
            // 改为两张卡自证结构：「完整信息」一键，其余五项一组 —— 不再写任何说明。
            VStack(spacing: 0) {
                toggleRow(.complete)
            }
            .settingsCard()

            VStack(spacing: 0) {
                ForEach(Array(WidgetField.detailFields.enumerated()), id: \.element) { index, field in
                    if index > 0 { SettingsDivider(style: .plain) }
                    toggleRow(field)
                }
            }
            .settingsCard()
        }
    }

    /// 一行开关。
    ///
    /// 🔴 用 `HStack { 标签; Spacer; Toggle("", …).labelsHidden() }` 而**不是**
    /// `Toggle(isOn:) { 标签 }`：后者把标签塞进 Toggle 自己的布局里，ideal 宽度
    /// 由「标签单行 + 开关」算出来 —— 副标题一长，整行就比屏幕宽，
    /// `cardSurface()` 跟着溢到屏幕右缘之外（2026-10-27 实测截图卡片被切）。
    /// 拆成 HStack 后宽度吃满可用区，副标题在 VStack 里正常折行。
    private func toggleRow(_ field: WidgetField) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(field.tint.opacity(0.14))
                    .frame(width: 34, height: 34)

                Image(systemName: field.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(field.tint)
            }

            Text(field.title.L)
                .font(field == .complete
                      ? AppTheme.TypeScale.rowTitle.weight(.semibold)
                      : AppTheme.TypeScale.rowTitle)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Toggle("", isOn: binding(for: field))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(AppTheme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private func binding(for field: WidgetField) -> Binding<Bool> {
        if field == .complete {
            return Binding(get: { effectiveOptions.isComplete },
                           set: { model.setComplete($0) })
        }
        if field == .placeholders {
            // 占位符不在 WidgetDisplayOptions 里，走 App Group 的 @AppStorage；
            // 改完同样要重画时间线（原先在单独分组的 onChange 里做）。
            return Binding(
                get: { self.showsPlaceholders },
                set: { newValue in
                    self.showsPlaceholders = newValue
                    WidgetCenter.shared.reloadAllTimelines()
                })
        }
        guard let keyPath = field.keyPath else { return .constant(false) }
        return Binding(get: { effectiveOptions[keyPath: keyPath] },
                       set: { model.set(keyPath, to: $0) })
    }

    /// 🔴 **实际生效**的显示组合 —— 这一页里所有"描述当前状态"的地方都以它为准。
    private var effectiveOptions: WidgetDisplayOptions {
        model.options
    }

    // MARK: 全部尺寸效果（直接铺开，不再跳转）

    /// 与桌面小组件同一份视图代码（`WidgetGalleryContent`），
    /// 按当前设备渲染全部可用尺寸 —— iPhone 上不出 iPad 超大那一块。
    private var gallerySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "小组件效果")

            WidgetGalleryContent(options: effectiveOptions,
                                 showsPlaceholders: showsPlaceholders)
        }
    }
}

// MARK: - 六个开关的字段定义

/// 「显示内容」里的六个开关。顺序即页面顺序
/// （前五个是主人 2026-10-27 给的顺序，第六个「显示占位符」2026-11-16 并入）。
///
/// 图标不是随便挑的 SF Symbol：这一页的选项差别就在"显示什么"，
/// 图标要能一眼对上那件事（地址=定位针、公司=箱子、驿站=店铺、柜=格口网格）。
private enum WidgetField: CaseIterable {
    /// 快捷全开 / 全关，不直接对应某一个字段
    case complete
    case address
    case company
    case station
    case locker
    /// 空槽骨架行（2026-11-16 主人：从「空位」分组并进这一张卡）
    case placeholders

    var title: String {
        switch self {
        case .complete:     "完整信息"
        case .address:      "取件地址"
        case .company:      "快递公司"
        case .station:      "驿站"
        case .locker:       "快递柜 / 货架"
        case .placeholders: "占位符"
        }
    }

    var symbol: String {
        switch self {
        case .complete:     "list.bullet.rectangle"
        case .address:      "mappin.and.ellipse"
        case .company:      "shippingbox"
        case .station:      "storefront"
        case .locker:       "square.grid.2x2"
        case .placeholders: "rectangle.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .complete:     AppTheme.accent
        case .address:      AppTheme.sky
        case .company:      AppTheme.indigo
        case .station:      AppTheme.violet
        case .locker:       AppTheme.doneTint
        case .placeholders: AppTheme.sky
        }
    }

    /// 第二张卡里的五项（`.complete` 单独一张卡，不在这里）。
    static var detailFields: [WidgetField] {
        allCases.filter { $0 != .complete }
    }

    /// 对应 `WidgetDisplayOptions` 的字段；`.complete` 由 `isComplete` 聚合而来，
    /// `.placeholders` 走 `@AppStorage`，两者都没有单一 keyPath。
    var keyPath: WritableKeyPath<WidgetDisplayOptions, Bool>? {
        switch self {
        case .complete, .placeholders: nil
        case .address:  \.showsAddress
        case .company:  \.showsCompany
        case .station:  \.showsStation
        case .locker:   \.showsLocker
        }
    }
}
