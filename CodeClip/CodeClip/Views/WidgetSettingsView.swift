import SwiftUI
import WidgetKit

// MARK: ============================================================================
// 桌面小组件（我的 › 设置 › 二级页）
//
// 回答「我的小组件为什么长这样 / 能不能少显示点东西」：
//   1. **效果预览**（置顶 · 2026-09-23 主人要求上移）：与桌面**同一份渲染代码**，
//      喂**示例数据**（见下），并**跟着下面的显示设置实时变**；
//   2. **显示内容**：二级信息行显示哪几项 —— 四个预设模板四选一，
//      取件码**不参与配置**。原先的「自定义显示项」三勾选已删
//      （2026-09-24 主人定：与模板选择重复，互相联动看着混乱）；
//      历史上拧出的自由组合在进页时归一为「完整信息」。
//   3. **小组件效果**：各尺寸铺开，同样用示例数据。
//
// 🔴 **总开关已删除**（2026-09-23 主人定调：「没啥意义」）：
//    原先有一个"桌面小组件"总开关，关掉后桌面渲染停用态。它的价值是负的 ——
//    用户不想要这个小组件，直接从桌面移除即可，不需要 App 里再给一个会
//    让桌面变成「已关闭」的开关；而一旦关掉又找不到开关（二级入口深）就成死局。
//    ⚠️ 连带影响：`WidgetSwitch` 的**读侧门控也已一并拆掉**（见 `PickupWidget`），
//    否则历史用户的持久化值还是 `false`，拆了 UI 就永远解不开。
//
// 🔴 **勾选框 = 圆形单选**（2026-09-24 起唯一形态）：四个模板四选一。
//    原先「模板圆勾选 + 自定义方勾选」两套控件的统一史结束于自定义区整体删除。
//
// ⚠️ 显示设置落 App Group（`WidgetDisplayOptions`），改完必须 reloadAllTimelines ——
//    否则桌面还是旧画面，用户会以为设置坏了。
// ============================================================================

final class WidgetSettingsModel: ObservableObject {
    /// 用户**存下来**的字段组合（落 App Group）。
    ///
    /// ⚠️ 它不等于"当前生效的组合" —— 免费版的读侧会被夹成 `.full`。
    ///    这里只负责**写**；要判断"现在是什么样子"请用视图层的 `effectiveOptions`。
    @Published var options = WidgetDisplayOptions.load()

    /// 套用一个预设模板。
    ///
    /// ⚠️ **付费校验不在这一层做**：锁定态在视图层就换成了 `NavigationLink`
    /// （点不进这个方法），这里再判一次只会让"谁在守门"变得含糊。
    func select(_ preset: WidgetDisplayPreset) {
        guard let target = preset.options else { return }
        apply(target)
    }

    /// 🔴 **老数据归一**（2026-09-24 删自定义勾选行时引入）：
    ///    自定义勾选 UI 删除后，显示组合只剩四个模板 —— 历史上用三个勾选框
    ///    拧出的「不属于任何模板」的组合（`matchedPreset == .custom`）在页面上
    ///    会是四个模板行全不选中，自己和自己矛盾。归一到「完整信息」：
    ///    页面与桌面渲染从此永远一致。
    init() {
        if WidgetDisplayOptions.load().matchedPreset == .custom {
            apply(.full)
        }
    }

    private func apply(_ next: WidgetDisplayOptions) {
        options = next
        WidgetDisplayOptions.save(next)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct WidgetSettingsView: View {
    @EnvironmentObject private var store: PickupStore
    @StateObject private var model = WidgetSettingsModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 🔴 顺序 = 先看效果、再调设置（2026-09-23 主人要求）：
                //    进这一页的人首先想知道"我的小组件长什么样"，
                //    把预览压在四个模板下面等于让人先读选项再猜结果。
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

    // MARK: 显示内容（模板 + 自定义）

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "显示内容")

            VStack(spacing: 0) {
                ForEach(Array(WidgetDisplayPreset.selectable.enumerated()),
                        id: \.element.rawValue) { index, preset in
                    if index > 0 { SettingsDivider(style: .plain) }

                    templateRow(preset)
                }
            }
            .cardSurface()

            // 说明放卡外（iOS 二级设置页口径：标题在卡内、说明在卡外）
            Text("取件码永远显示，不参与选择 —— 它是这个小组件存在的意义。\n四个模板全部开放，选哪个立即生效。".richText)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .padding(.horizontal, 16)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 一个模板行（2026-10-14 全功能化：锁与 VIP 跳转退役，四行全部可选）。
    ///
    /// 🔴 选中态读的是 `effectiveOptions`（**实际生效**的组合）而不是 `model.options`
    ///    （用户存下来的组合），两者现在恒等 —— 读侧不再有「免费版夹成 `.full`」的分支。
    private func templateRow(_ preset: WidgetDisplayPreset) -> some View {
        let isSelected = effectiveOptions.matchedPreset == preset

        return Button {
            model.select(preset)
        } label: {
            WidgetTemplateRow(preset: preset, isSelected: isSelected, isLocked: false)
        }
        .buttonStyle(.plain)
    }

    // MARK: 效果预览（实时反映上面的选择）

    /// 🔴 **实际生效**的显示组合 —— 这一页里所有"描述当前状态"的地方都以它为准。
    ///
    /// 2026-10-14 全功能化：不再有免费档读侧夹逼，这里直接就是用户选的组合。
    private var effectiveOptions: WidgetDisplayOptions {
        model.options
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "效果预览")

            VStack(alignment: .leading, spacing: 10) {
                WidgetCanvas(.medium) {
                    WidgetPagedContent(snapshot: .preview(),
                                       pageSize: WidgetPageSize.rowCount(family: "m"),
                                       familyKey: "m",
                                       options: effectiveOptions)
                }

                Text("示例数据 · 桌面小组件会按这套显示设置渲染你自己的记录")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .cardSurface()
        }
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

    // MARK: 添加指引

    private var guideSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "添加到桌面")

            VStack(alignment: .leading, spacing: 8) {
                Text("长按桌面空白处 → 左上角「+」→ 搜索「码夹」→ 选「待取件」。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }
}

// MARK: - 模板行

/// 「显示内容」里的一行模板。
///
/// 左侧的方框里放**版式示意图标**（数字 / 箱子 / 楼 / 滑杆），
/// 而不是随便挑一个 SF Symbol —— 这一页的四个选项差别就在"显示什么"，
/// 图标要能直接对应上那件事。
struct WidgetTemplateRow: View {
    let preset: WidgetDisplayPreset
    let isSelected: Bool
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? AppTheme.accent.opacity(0.14)
                                     : Color(.tertiarySystemFill))
                    .frame(width: 38, height: 38)

                Image(systemName: preset.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.accent : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.title)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)

                Text(preset.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.amber)
            } else {
            WidgetCheckBox(isOn: isSelected)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(.rect)
    }
}

// MARK: - 勾选框

/// 「显示内容」里的勾选控件 —— 模板行的**圆形单选**（四选一）。
///
/// 🔴 尺寸与未选中态颜色沿用 2026-09-23 定下的视觉（19pt / `quaternaryLabel`）。
///    原先的方形多选（自定义显示项三勾选）已随该区一起删除（2026-09-24 主人定：
///    与模板选择重复 —— 两套控件表达同一件事，互相联动看着混乱）。
struct WidgetCheckBox: View {
    let isOn: Bool

    var body: some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 19))
            .foregroundStyle(isOn ? AppTheme.accent : Color(.quaternaryLabel))
    }
}
