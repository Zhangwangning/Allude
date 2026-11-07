import SwiftUI
import WidgetKit

// MARK: ============================================================================
// 桌面小组件（我的 › 设置 › 二级页）
//
// 回答「我的小组件为什么长这样 / 能不能少显示点东西」：
//   1. **效果预览**（置顶）：与桌面**同一份渲染代码**，喂示例数据，
//      并**跟着下面的开关实时变**；
//   2. **显示内容**：五个开关 —— 完整信息 / 取件地址 / 快递公司 / 驿站 / 快递柜·货架。
//      取件码**不参与配置**；「完整信息」= 其余四项全开，与它们天然互斥。
//   3. **小组件效果**：各尺寸铺开，同样用示例数据。
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
        // 🔴 升级归一（2026-10-27）：
        //    旧版「完整信息」= 公司 + 地址（驿站关着），而新页面的「完整信息」判定是
        //    四项全开 —— 老用户进页面会看到一个自己从没关过的开关是灭的，自相矛盾。
        //    这里把旧组合补齐成 `.full`：视觉上没有任何变化（站名被地址盖住，见
        //    `widgetSubtitle` 的互斥规则），但开关状态回到"我一直选的就是完整信息"。
        let loaded = WidgetDisplayOptions.load()
        if loaded.showsCompany, loaded.showsAddress, !loaded.showsStation {
            apply(.full)
        }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 🔴 顺序 = 先看效果、再调设置：
                //    进这一页的人首先想知道"我的小组件长什么样"。
                previewSection
                displaySection
                gallerySection
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

            // 小组件本体直接浮在页面灰底上，宽度与下方卡片**同宽**（左右 16pt 对齐）
            WidgetCanvas(.medium, expandsToFill: true) {
                WidgetPagedContent(snapshot: .preview(),
                                   pageSize: WidgetPageSize.rowCount(family: "m"),
                                   familyKey: "m",
                                   options: effectiveOptions)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text("示例数据 · 桌面小组件会按这套显示设置渲染你自己的记录")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 显示内容（五个开关）

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "显示内容")

            VStack(spacing: 0) {
                ForEach(Array(WidgetField.allCases.enumerated()), id: \.element) { index, field in
                    if index > 0 { SettingsDivider(style: .plain) }
                    toggleRow(field)
                }
            }
            .cardSurface()

            // 说明放卡外（iOS 二级设置页口径：标题在卡内、说明在卡外）
            Text("取件码永远显示，不参与开关 —— 它是这个小组件存在的意义。\n"
                 + "「完整信息」与下面四项互斥：四项全开时它自动亮起，关掉任一项它自动熄灭。\n"
                 + "快递公司、驿站、取件地址是三件不同的事：谁承运 / 谁保管 / 去哪取，可同时显示。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .padding(.horizontal, 16)
                .fixedSize(horizontal: false, vertical: true)
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
                    .frame(width: 38, height: 38)

                Image(systemName: field.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(field.tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(field.title.L)
                    .font(.system(size: 16, weight: field == .complete ? .semibold : .regular))
                    .foregroundStyle(.primary)

                Text(field.subtitle.L)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: binding(for: field))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(AppTheme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private func binding(for field: WidgetField) -> Binding<Bool> {
        if field == .complete {
            return Binding(get: { effectiveOptions.isComplete },
                           set: { model.setComplete($0) })
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

            WidgetGalleryContent(options: effectiveOptions)
        }
    }
}

// MARK: - 五个开关的字段定义

/// 「显示内容」里的五个开关。顺序即页面顺序（主人 2026-10-27 给的顺序）。
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

    var title: String {
        switch self {
        case .complete: "完整信息"
        case .address:  "显示取件地址"
        case .company:  "显示快递公司"
        case .station:  "显示驿站"
        case .locker:   "显示快递柜/货架"
        }
    }

    var subtitle: String {
        switch self {
        case .complete: "四项全开，与下面的开关互斥"
        case .address:  "完整门牌，如「馨月湖小区南门」"
        case .company:  "如「圆通快递」；判别不出时显示短信平台"
        case .station:  "如「菜鸟驿站」「兔喜生活」，取自短信原文"
        case .locker:   "取件码后面的定位信息，如「2号柜」「货架3」"
        }
    }

    var symbol: String {
        switch self {
        case .complete: "list.bullet.rectangle"
        case .address:  "mappin.and.ellipse"
        case .company:  "shippingbox"
        case .station:  "storefront"
        case .locker:   "square.grid.2x2"
        }
    }

    var tint: Color {
        switch self {
        case .complete: AppTheme.accent
        case .address:  AppTheme.sky
        case .company:  AppTheme.indigo
        case .station:  AppTheme.violet
        case .locker:   AppTheme.doneTint
        }
    }

    /// 对应 `WidgetDisplayOptions` 的字段；`.complete` 由 `isComplete` 聚合而来，没有单一字段。
    var keyPath: WritableKeyPath<WidgetDisplayOptions, Bool>? {
        switch self {
        case .complete: nil
        case .address:  \.showsAddress
        case .company:  \.showsCompany
        case .station:  \.showsStation
        case .locker:   \.showsLocker
        }
    }
}
