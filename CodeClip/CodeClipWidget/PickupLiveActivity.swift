import ActivityKit
import SwiftUI
import WidgetKit

// MARK: ============================================================================
// 实时活动（Live Activity）注册
//
// 本文件只做「装配」：把锁屏卡片与灵动岛的四块区域接到 ActivityKit 上。
// 具体版式在 `CodeClipShared/PickupActivityAttributes.swift` —— 放共享层是为了
// 让 App 内能用同一份 View 造预览（锁屏与灵动岛都无法脚本化截图）。
//
// 版式口径（与 App 列表卡片同源）：
//   · 取件码是唯一主角，锁屏 27pt / 展开态 21pt；平台名、地址、待取数量只做上下文；
//   · 🔴 **灵动岛是纯展示，不放任何按钮**（2026-09-22 主人定调）：岛面积只有
//     十几个点、又贴在屏幕顶端，误触代价高；「标记已取」只剩两条入口 ——
//     锁屏卡片与桌面／锁屏小组件的勾选框；
//   · 灵动岛紧凑态面积以十几个点计 = **左 App 图标 / 右「待取 N」**（2026-09-22 定调），
//     最小态只剩 App 图标。🔴 这两处的图标读的是 `AppMark` 资源，
//     必须在 App 与扩展**两个 target 各存一份**（见共享层同名注释）；
//   · 颜色取当前这条的品牌色 —— 实时活动与 App 卡片是同一家公司的同一种色。
//
// ⚠️ 本文件不得使用 SwiftUI 宏（#Preview / @State），原因见 DesignSystem.swift 顶部。
// ============================================================================

struct PickupLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PickupActivityAttributes.self) { context in

            ActivityLockScreenCard(state: context.state)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                // 卡面背景与系统操作按钮的着色都由活动层出，内容层不自己铺底 ——
                // 否则会和系统给活动卡片的圆角与材质打架。
                // 🔴 两处 tint 都走 `islandTint` 亮度插值（2026-09-24）：暗色锁屏的
                //    卡底是深色材质，顺丰这类纯黑主色直接叠上去整卡糊成黑团、
                //    取件码黑上黑 —— 亮化到可读亮度后色相保留、氛围不变。
                .activityBackgroundTint(islandTint(context.state.item.tint).opacity(0.10))
                .activitySystemActionForegroundColor(islandTint(context.state.item.tint))

        } dynamicIsland: { context in

            DynamicIsland {
                // 展开态只用 bottom 区：leading / trailing 被挖孔夹在两侧、
                // 各只占约 1/3 岛宽，品牌图标与取件码都会被压到看不全（真机实测），
                // 而 bottom 是全岛最宽的区域 —— 图标、取件码、地址都有了余量。
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedContent(state: context.state)
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
