import ActivityKit
import SwiftUI
import WidgetKit

// MARK: ============================================================================
// 实时活动（Live Activity）注册
//
// 本文件只做「装配」：把锁屏卡片与灵动岛的四块区域接到 ActivityKit 上。
// 具体版式在 `AlludeShared/PickupActivityAttributes.swift` —— 放共享层是为了
// 让 App 内能用同一份 View 造预览（锁屏与灵动岛都无法脚本化截图）。
//
// 版式口径（与 App 列表卡片同源）：
//   · 取件码是唯一主角，锁屏 27pt / 展开态 21pt；平台名、地址、待取数量只做上下文；
//   · 🔴 **灵动岛是纯展示，不放任何按钮**（2026-09-22 主人定调）：岛面积只有
//     十几个点、又贴在屏幕顶端，误触代价高；「标记已取」只剩两条入口 ——
//     锁屏卡片与桌面／锁屏小组件的勾选框；
//   · 灵动岛紧凑态面积以十几个点计 = **左 App 图标 / 右待取数量**（2026-11-01 去掉文字标签、>99 显示 99+），
//     最小态只剩 App 图标。🔴 这两处的图标读的是 `AppMark` 资源，
//     必须在 App 与扩展**两个 target 各存一份**（见共享层同名注释）；
//   · 颜色取当前这条的品牌色 —— 实时活动与 App 卡片是同一家公司的同一种色。
//
// ⚠️ 本文件不得使用 SwiftUI 宏（#Preview / @State），原因见 DesignSystem.swift 顶部。
// ============================================================================

struct PickupLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PickupActivityAttributes.self) { context in

            // 🔴 2026-10-28：玻璃与内容**必须分层**。
            //    直接给「内容 + padding」套 `.glassEffect`，真机上整块玻璃会把内容吃掉
            //    （卡片只剩一块空的液态玻璃，字全没了 —— 真机实证）。
            //    正确做法：玻璃贴在一个占位的透明层上，内容用 ZStack 叠在它上面。
            ZStack {
                Color.clear
                    .appGlass(.rect(cornerRadius: 26))

                ActivityLockScreenCard(state: context.state)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .zIndex(1)          // 明确压到玻璃之上，避免被玻璃层遮掉
            }
            .activityBackgroundTint(.clear)
            .activitySystemActionForegroundColor(islandInk(context.state.item.tint))

        } dynamicIsland: { context in

            DynamicIsland {
                // 🔴 2026-10-28 主人：「整体内容靠下显示了，空间也大着呢，为啥要往下挤」。
                // 根因：以前**只用 `.bottom` 一个区** —— 挖孔（TrueDepth）左右那两块
                // 可画区域是空的，系统又把 bottom 放在挖孔之下，于是上半截全黑、
                // 内容全堆在下半截。
                //
                // 现在按系统设计用满三个区：
                //   · leading  = 品牌图标 + 快递公司／驿站（挖孔左侧，约 120pt，4–5 字够用）
                //   · trailing = 待取数量（挖孔右侧，窄，右对齐）
                //   · bottom   = 取件码（+ 柜位）+ 取件地址，各一整行
                // 顶部那一行被利用起来后，整岛高度跟着降下来，内容不再"沉底"。
                DynamicIslandExpandedRegion(.leading) {
                    IslandExpandedLeading(state: context.state)
                        // 与取件码左缘对齐（系统给 leading 的左边距比 bottom 少 15pt）
                        .padding(.leading, IslandExpandedMetrics.leadingInset)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandExpandedTrailing(state: context.state)
                        // 待取计数从贴边往左收一点
                        .padding(.trailing, IslandExpandedMetrics.trailingInset)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(state: context.state)
                        .padding(.horizontal, IslandExpandedMetrics.hInset)
                        .padding(.bottom, 2)
                }
            } compactLeading: {
                IslandCompactLeading(state: context.state)
            } compactTrailing: {
                IslandCompactTrailing(state: context.state)
            } minimal: {
                IslandMinimal(state: context.state)
            }
            // 灵动岛外圈描边走品牌色 —— 与锁屏卡片的着色口径一致。
            // 🔴 同样走 `islandTint`：顺丰纯黑主色的描边贴着任何深色壁纸都隐形，
            //    亮化后轮廓才真正可见。
            .keylineTint(islandTint(context.state.item.tint))
        }
    }
}
