import WidgetKit
import SwiftUI

// MARK: ============================================================================
// 小组件壳（时间线 · 尺寸分发 · 容器背景）
//
// 本文件只负责「壳」：具体的版式（勾选框 / 取件码 / 地址行 / 翻页控件）在
// `AlludeShared/WidgetVisuals.swift` —— 放共享层是为了让 App 内能用同一份代码
// 做真实预览（桌面小组件无法脚本化添加）。
//
// 版式口径（2026-09-21 修订）：
//   · **不放快递平台图标** —— 行首图标占宽约 41pt，去掉后全部让给取件码与地址；
//   · **取件码是唯一主角**；**行首圆形勾选框**可直接在桌面点掉；
//   · **中 / 大 / 超大尺寸支持上下翻页**。
//
// 尺寸与翻动：
//   · 小 1 条（不分页）· 中 3 条/页 · 大 6 条/页 · iPad 超大 6 条/页 ·
//     iPhone 竖版超大 10 条/页；
//   · 超过一页时头部出现上/下翻页控件。
//
//   🔴 **小组件不支持原生滚动** —— 已对 iOS 27 SDK 的 WidgetKit 与 SwiftUI 接口
//      逐一核实：不存在任何滚动相关 API。因此「上下翻动查看」用 iOS 17+ 的
//      可交互小组件实现：两个 `Button(intent:)` 改页码后重画时间线。
//
// 刷新策略（三层）：
//   1) **主 App 数据变更即刷新** —— PickupStore.records didSet 调
//      WidgetCenter.reloadAllTimelines()；
//   2) **桌面交互即刷新** —— 勾选 / 翻页意图写回后同样调用；
//   3) **兜底轮询 15 分钟** —— 覆盖跨天、系统内存回收后重新取时间线等场景。
//
// ⚠️ 与 App target 的差异：本文件不得使用 SwiftUI 宏（#Preview / @State），
//    原因见 DesignSystem.swift 顶部说明（本机 Xcode 27 beta 命令行链路限制）。
// ============================================================================

// MARK: - 时间线条目

struct PickupEntry: TimelineEntry {
    let date: Date
    let configuration: PickupWidgetIntent
    let snapshot: WidgetSnapshot
    /// 二级信息行显示哪几项（我的 › 桌面小组件 › 显示内容）。
    ///
    /// 由 provider **每次取时间线时现读**，不是启动时缓存一次 ——
    /// 用户在 App 里改了显示设置会 `reloadAllTimelines()`，
    /// 缓存住就会一直画旧版式。
    let options: WidgetDisplayOptions
}

// MARK: - 时间线提供者

struct PickupTimelineProvider: AppIntentTimelineProvider {
    private static func entry(date: Date,
                              configuration: PickupWidgetIntent,
                              snapshot: WidgetSnapshot) -> PickupEntry {
        // 🔴 **不再按档位夹逼**（2026-10-27）：`effective(isPro:)` 会在非 Pro 时
        //    强制回到「完整信息」，而 App 自 2026-10-14 起已全功能化、没有付费档。
        //    留着它的唯一效果是：极少数残存 `entitlement.json` 且 `isPro=false`
        //    （过期 / 被改坏）的用户，设置页五个开关全部失效，且界面上没有任何提示 ——
        //    用户会以为"开关是坏的"。写侧早就没有锁了，读侧这道也一并拆掉，两侧同口径。
        let options = WidgetDisplayOptions.load()
        // 🔴 这里原先还有一道 `WidgetSwitch.isEnabled` 门控（关掉 → 渲染停用态）。
        //    2026-09-23 主人判定那个总开关「没啥意义」，UI 已删除；**读侧必须一起拆** ——
        //    只删 UI 不删门控的话，历史用户持久化的 `false` 会把桌面永远锁在
        //    「已关闭」，而设置页里再也没有能解开它的入口。停用态这条分支因此整体退场。
        return PickupEntry(date: date,
                           configuration: configuration,
                           snapshot: snapshot,
                           options: options)
    }

    func placeholder(in context: Context) -> PickupEntry {
        Self.entry(date: .now,
                   configuration: PickupWidgetIntent(),
                   snapshot: .preview())
    }

    func snapshot(for configuration: PickupWidgetIntent, in context: Context) async -> PickupEntry {
        // 图库预览用示例数据，真实快照读共享容器 —— 避免用户在小部件图库里
        // 看到自己「只有 0 条」的尴尬空态。
        let snapshot: WidgetSnapshot = context.isPreview ? .preview() : .load()
        return Self.entry(date: .now, configuration: configuration, snapshot: snapshot)
    }

    func timeline(for configuration: PickupWidgetIntent, in context: Context) async -> Timeline<PickupEntry> {
        let entry = Self.entry(date: .now,
                               configuration: configuration,
                               snapshot: .load())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now)
            ?? Date().addingTimeInterval(15 * 60)
        return Timeline(entries: [entry], policy: .after(next))
    }
}

// MARK: - 入口视图（按尺寸与状态分发到共享可视层）

struct PickupWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    var entry: PickupEntry

    private var familyKey: String { WidgetPageSize.key(family) }

    var body: some View {
        let snapshot = entry.snapshot
        let options = entry.options
        let isSmall = family == .systemSmall

        // 🔴 2026-11-11：尺寸集固定为全部（见 WidgetPageSize.supportedFamilies），
        //    免费用户在大尺寸里显示「解锁 Codelumi Pro」占位，而不是空白/空态。
        if !EntitlementSnapshot.licensedPro && !WidgetPageSize.isFreeFamily(family) {
            WidgetLockedContent()
        } else if snapshot.isEmpty {
            WidgetEmptyContent(pickedTodayCount: snapshot.pickedTodayCount,
                               compact: isSmall)
        } else if isSmall {
            // 小尺寸只放 1 条，没有分页余地 —— 翻页控件只出现在中尺寸以上
            WidgetSmallContent(snapshot: snapshot, options: options)
        } else {
            WidgetPagedContent(snapshot: snapshot,
                               pageSize: WidgetPageSize.rowCount(family: familyKey),
                               familyKey: familyKey,
                               options: options)
        }
    }
}

// MARK: - 小组件背景（实体填充，与 App 内容层一致：不给小组件叠玻璃）

struct WidgetSurface: View {
    var body: some View {
        Rectangle()
            .fill(.background.secondary)
            .overlay(alignment: .top) {
                LinearGradient(colors: [AppTheme.accent.opacity(0.10), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 88)
            }
    }
}

// MARK: - 小组件注册

struct PickupWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AlludePickupWidget",
                               intent: PickupWidgetIntent.self,
                               provider: PickupTimelineProvider()) { entry in
            PickupWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) { WidgetSurface() }
        }
        .configurationDisplayName("待取件")
        .description("不打开 App，也能看到最近要取的快递；点上下箭头可翻看更多。")
        .supportedFamilies(WidgetPageSize.supportedFamilies)
    }
}
