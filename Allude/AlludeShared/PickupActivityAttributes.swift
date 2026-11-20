import ActivityKit
import SwiftUI
import WidgetKit

// MARK: ============================================================================
// 实时活动（锁屏卡片 + 灵动岛）的数据契约与版式
//
// 放共享层的两个理由：
//   1) 契约要同时被 App（申请 / 更新 / 结束活动）与小组件扩展（渲染 UI）引用；
//   2) 版式放这里，App 内才能用**同一份 View**造出锁屏与灵动岛的预览 ——
//      锁屏与灵动岛都无法脚本化截图，这是唯一能自查渲染结果的路径
//      （与桌面小组件走 `WidgetVisuals.swift` 是同一套办法）。
//
// ⚠️ 本文件不得引用 App 专属类型（PickupRecord / PickupStore），只吃自己定义的 `Item`。
//    共享层受 `APPLICATION_EXTENSION_API_ONLY` 约束，引用宿主类型会导致扩展编译失败。
// ============================================================================

struct PickupActivityAttributes: ActivityAttributes {

    /// 一条待办的展示快照。
    ///
    /// 为什么不直接塞 `PickupRecord`：那一层带着 `rawMessage`（整条短信原文），
    /// 会让 ContentState 无谓变大 —— ActivityKit 对动态数据有 **4KB** 硬上限，
    /// 且每次更新都要跨进程编码一次。这里只留卡面真正要画的字段。
    struct Item: Codable, Hashable, Identifiable {
        var id: String
        var company: String
        /// 承运方（快递公司）。与 `company`（短信平台）分开存，**与 App 内卡面同口径**：
        /// 「【拼多多】您的圆通快递…」在锁屏上也要显示「圆通快递」而不是「拼多多」
        /// （2026-10-25 审查修，之前只有 company，导致锁屏/灵动岛与列表卡口径不一致）。
        /// Optional + 默认 nil ⇒ 合成 Codable 走 decodeIfPresent，旧 ContentState 照样能解。
        var courier: String? = nil
        /// 快递驿站名（如「河西学院北门圆通妈妈驿站」）。
        ///
        /// 🔴 2026-10-28 主人：首行要「快递公司｜快递驿站」，优先级
        /// **快递驿站 > 快递公司 > 短信平台**。
        /// `StationDirectory` 住在 App target、共享层拿不到，
        /// 所以由 App 侧通过 `PickupActivityController.stationResolver` 注入解析结果。
        /// Optional + 默认 nil ⇒ 旧 ContentState 缺键也能解码。
        var station: String? = nil
        var code: String
        // 🔴 2026-10-28 删掉 `kindLabel`：Allude不再区分凭证类型，锁屏卡与灵动岛
        //    也从来没有渲染过它 —— 留着就是"传了个没人看的字段"，改它等于白改。
        //    旧 ContentState 里多出来的这个键会在解码时被忽略，不影响已发出去的活动。
        var address: String
        var tint: UInt32

        /// 快递柜 / 货架（2026-10-28 主人：灵动岛第三行放地址，取件码后面跟柜位，
        /// 「和小组件一样，有的话」）。已经拼成可直接显示的短串（「2号柜」「货架12-3」）。
        /// 🔴 Optional + 默认 nil ⇒ 旧 ContentState 缺键也能解码，不会让活动解不出来。
        var locker: String? = nil

        /// 卡面命名 —— **直接复用整个Allude唯一的一套规则**（`PickupNaming`）。
        /// `Item` 是 App → 扩展的状态副本，不持有 PickupRecord，但规则必须同源：
        /// ```
        /// 圆通速递 + 妈妈驿站 + 拼多多 → 主名「圆通速递」 后缀「妈妈驿站」
        /// （无快递公司）韵达快递 + 兴裕隆超市 → 主名「韵达快递」 后缀「兴裕隆超市」
        /// 只有短信平台                 → 主名「短信平台」 后缀 nil（不出管道符）
        /// ```
        var naming: PickupNaming {
            PickupNaming(courier: CourierBrand.canonicalName(for: courier ?? ""),
                         platform: company, station: station)
        }

        /// 卡面主名 = `naming.primary`（列表卡 / 详情页 / 分享卡同一个值）
        var displayName: String { naming.primary }

        /// 主名后面那一段（「快递公司｜快递驿站」的右半边）= `naming.secondary`
        var platformSuffix: String? { naming.secondary }
    }

    /// 动态部分：每次待办变动整体替换。
    struct ContentState: Codable, Hashable {
        /// 当前展示的那一条（取最新待办）
        var item: Item
        /// 待办总数
        var pendingCount: Int
        /// 锁屏卡的**列表**（2026-11-08 主人：一张卡放三条，右侧翻页）。
        /// 可选：老的活动快照里没有这个字段，解码为 nil，卡面回落到单条。
        var items: [Item]? = nil

        /// 当前自定义的 App 图标（`AppIconChoice` 的 rawValue），由 **App 侧**写进状态。
        ///
        /// 🔴 为什么不干脆在扩展里读 `AppIconStore.current`（2026-11-15 主人报障后改）：
        ///    灵动岛/锁屏由**小组件进程**渲染，那一侧和 App 之间只有 **App Group**
        ///    一条通路。App Group 一旦不可用（无签名调试包、容器重建、
        ///    扩展读不到共享偏好域），扩展读到的就是 nil，`AppIconStore.current`
        ///    回落到 `AppIconChoice.fallback`（第 7 套「黑盒立体」）——
        ///    于是「桌面图标已经换成快递箱，灵动岛里还是 C 标」，主人一眼看出对不上。
        ///    把选择**随 ContentState 跨进程传**，渲染端就完全不再依赖任何共享存储，
        ///    这条链路上再没有能"读到 nil"的地方。
        /// Optional + 默认 nil ⇒ 旧 ContentState（本次升级前起的活动）缺键照样能解码，
        /// 那种情况下才回落到 `AppIconStore`。
        var appIconRaw: String? = nil

        /// 渲染用：状态里带了就用它，没带才回退到本进程读到的选择。
        var appIcon: AppIconChoice {
            appIconRaw.flatMap { AppIconChoice(rawValue: $0) } ?? AppIconStore.current
        }

        /// 锁屏卡真正要画的一页（最多 3 条）
        var lockPage: [Item] {
            guard let items, !items.isEmpty else { return [item] }
            return Array(items.prefix(LockScreenMetrics.perPage))
        }
    }

    /// 锁屏卡几何：HIG 规定高 84–160pt、标准内边距 14pt、宽 = 屏宽 − 22。
    enum LockScreenMetrics {
        /// 一页放几条
        static let perPage = 3
        /// 内容区高度：三条用满上限（160 − 14×2）
        static let contentHeight: CGFloat = 132
        /// 单条：来源行（公司｜驿站/平台）+ 大码 + 地址三层，内容区 72 → 总高 100，
        /// 仍在 HIG 的 84–160 区间内，且比三条时矮一截。
        static let singleContentHeight: CGFloat = 72
        /// 两条：介于两者之间（118 − 14×2）
        static let doubleContentHeight: CGFloat = 90

        /// 按当前页条数取内容区高度
        static func contentHeight(for rows: Int) -> CGFloat {
            switch rows {
            case 0, 1: singleContentHeight
            case 2:    doubleContentHeight
            default:   contentHeight
            }
        }
        /// 卡内上下左右内边距
        static let inset: CGFloat = 14
    }
}

// MARK: - 灵动岛专用取色
//
// Apple 明文：灵动岛内的实时活动「黑底白字」，且**背景色不可改**
// （`keylineTint(_:)` 只影响描边）。因此岛内所有前景色都必须显式取亮色 ——
// 不能用 `.primary` / `.secondary`：那是**设备外观**的语义色，浅色外观下解析成深灰，
// 落在恒黑的小岛上等于消失。这条是模拟器里用同一份视图预演时实测到的
// （预览页 `ActivityPreviewGallery` 的存在价值正在于此）。

/// 品牌色铺在深底上要保证能读。
///
/// 品牌色大多为中深色相，直接铺在黑底上对比度不足；这里按 sRGB 相对亮度做一次
/// 朝白插值，**只插到刚好可读**（0.55），色相基本保留 —— 顺丰、抖音这类主色
/// 本身就是纯黑（0x000000），必然插成中性灰，这是不可改的黑底上唯一还能读的形态。
///
/// 🔴 **三处共用**（2026-09-24 主人指认暗黑下"一团黑"后收口）：
///   · 灵动岛四块区域（黑底，最初的使用者）；
///   · 锁屏卡片前景（`ActivityLockScreenCard`）—— 暗色锁屏上卡底是深色材质
///     + 品牌色叠层，直接用品牌色时顺丰的取件码就是"黑码落在黑卡上"；
///   · 活动卡底色叠层（`.activityBackgroundTint` / 预览壳 `ActivityCardShell`）——
///     氛围色亮化一点，暗黑下整卡不再糊成纯黑。
func islandTint(_ hex: UInt32) -> Color {
    let r = Double((hex >> 16) & 0xFF) / 255
    let g = Double((hex >> 8) & 0xFF) / 255
    let b = Double(hex & 0xFF) / 255

    let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    guard lum < 0.55 else { return Color(hex: hex) }

    let t = (0.55 - lum) / (1 - lum)
    return Color(.sRGB,
                 red: r + (1 - r) * t,
                 green: g + (1 - g) * t,
                 blue: b + (1 - b) * t,
                 opacity: 1)
}

/// **亮色玻璃上的品牌墨色**（2026-10-28 主人：「就做成亮色的液态玻璃，
/// 取件码的颜色把对比度加深」）。
///
/// 亮玻璃上取件码的着色口径（2026-10-28 主人两次校准后定稿）：
/// **就用图标上那个颜色**，只在过亮时轻微压一档保证可读 —— 不要压成暗橄榄。
/// 阈值 0.62：韵达亮黄 #FABF01 只压到 #D7A401（仍是明显的金黄），
/// 若按 0.35 压会变成 #7D6001 那种发闷的橄榄色，真机上像脏掉的黄。
/// 与 `islandTint`（往亮推，用于深色岛内）是一对反向操作，别混用。
func islandInk(_ hex: UInt32) -> Color {
    let r = Double((hex >> 16) & 0xFF) / 255
    let g = Double((hex >> 8) & 0xFF) / 255
    let b = Double(hex & 0xFF) / 255

    let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    guard lum > 0.62 else { return Color(hex: hex) }

    let t = (lum - 0.62) / lum          // 轻压一档，色彩饱和度不掉
    return Color(.sRGB, red: r * (1 - t), green: g * (1 - t), blue: b * (1 - t), opacity: 1)
}

/// 岛内正文（平台名）：纯白，与系统给岛内文字的口径一致
private let islandPrimary = Color.white
/// 岛内次级文字（地址、"共 N 件"）：白色降不透明度，而不是 `.secondary`
/// 次要文字。系统 `.secondary` 在纯黑底上约等于 white 60% ——
/// 原先 0.72 太亮，地址和「待取」会跟主文字抢注意力。
private let islandSecondary = Color.white.opacity(0.6)

// MARK: - 锁屏卡片

/// 锁屏 / 通知中心里的实时活动卡面。
///
/// 背景与着色交给宿主：`.activityBackgroundTint(...)` 由
/// `ActivityConfiguration` 施在外层，这里只画内容，不要自己铺背景
/// （自己铺会和系统给活动卡片的圆角与材质打架）。
/// 锁屏卡的玻璃**提亮**系数（唯一来源）。
///
/// 2026-10-28 主人定稿：「就做成亮色的液态玻璃，取件码的颜色把对比度加深」——
/// 之前压黑 45% 是把卡做成暗玻璃，视觉上像通知横幅，且与 iOS 的亮玻璃语调不符。
/// 现在反过来：往卡底叠一层白，透过去是乳白磨砂；文字一律用**深色**
/// （码用品牌色的加深版 `islandInk`，其余用深灰）。
/// 调这个数就是调玻璃的「乳白浓度」：
///   0.34 偏实 → 0.18 更透 → **0 = 完全不加白，直接吃系统原生液态玻璃**（2026-10-28 定稿）。
/// 0 的时候连 `activityBackgroundTint` 都不再施加，让系统材质原样呈现。
/// 预览脚手架 `SCREEN=lockPreview` 与真实活动共用。
enum LockCardGlass {
    static let whiten: Double = 0
}

struct ActivityLockScreenCard: View {
    let state: PickupActivityAttributes.ContentState

    /// 卡面文字一律白/亮色 + 深色描影：锁屏卡底透的是**用户的壁纸**，
    /// 语义色在这层玻璃上会跟浅色壁纸糊在一起（2026-10-28 真机实证）。
    private var secondaryInk: Color { .white.opacity(0.80) }
    private var inkShadow: Color { .black.opacity(0.40) }

    /// 一页三条（2026-11-08 主人定）：不解锁手机也要能一次看仨码。
    private var page: [PickupActivityAttributes.Item] { state.lockPage }
    private var totalPages: Int {
        max(1, Int(ceil(Double(state.pendingCount) / Double(PickupActivityAttributes.LockScreenMetrics.perPage))))
    }

    var body: some View {
        if page.count == 1, let only = page.first {
            singleCard(only)
        } else {
            listCard
        }
    }

    /// 单条：**恢复加高之前的版式**（2026-11-08 主人指定）——
    /// 上面一行「快递公司 | 驿站/平台」，中间大码 + 柜位，下面一行地址；
    /// 高度由内容决定（约 78pt），不占满 160。
    /// 码多长算「长」：≥8 位（运单号 13 位、带前缀的 8-2-4031 都算）。
    /// 长码会把同一行挤满，柜位就搬到来源行末尾做标签。
    private func isLongCode(_ code: String) -> Bool { code.count >= 8 }

    /// 柜位标签：白字半透明胶囊，跟在文字后面时不抢主信息
    private func lockerTag(_ locker: String) -> some View {
        Text(locker.L)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(.white.opacity(0.20)))
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
    }

    private func singleCard(_ item: PickupActivityAttributes.Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(item.displayName.L)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: inkShadow, radius: 2, x: 0, y: 0.5)
                    .lineLimit(1)

                if let platform = item.platformSuffix {
                    Text("| \(platform)")
                        .font(.system(size: 14))
                        .lineLimit(1)
                        .foregroundStyle(secondaryInk)
                        .shadow(color: inkShadow, radius: 1.5, x: 0, y: 0.5)
                }

                // 码太长时，柜位以标签形式跟在来源行文字后面（2026-11-08 主人定）
                if isLongCode(item.code), let locker = item.locker, !locker.isEmpty {
                    lockerTag(locker)
                }

                Spacer(minLength: 6)
            }

            HStack(alignment: .center, spacing: 10) {
                CourierLogo(company: item.displayName, size: 28, showsShadow: false, usesStaticAsset: true)

                // 🔴 2026-11-16：不再单独传 0.78。取件码样式改为全端统一读
                //    `CodeAppearanceStyle.current`，岛内只保留 `islandInk` 作为品牌色回落。
                PickupCodeEmphasis.text(item.code, tint: islandInk(item.tint))
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .monospaced()
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .allowsTightening(true)
                    .layoutPriority(1)
                    .shadow(color: inkShadow, radius: 2.5, x: 0, y: 0.5)

                if let locker = item.locker, !locker.isEmpty, !isLongCode(item.code) {
                    Text(locker.L)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(secondaryInk)
                        .truncationMode(.tail)
                        .layoutPriority(0)
                        .shadow(color: inkShadow, radius: 1.5, x: 0, y: 0.5)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 6)

            if !item.address.isEmpty {
                Text(item.address.L)
                    .font(.system(size: 14))
                    .foregroundStyle(secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 多条（2–3）：列表版式，高度用满 160pt 上限
    private var listCard: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(page.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.14))
                            .frame(height: 0.5)
                    }
                    row(item)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右侧翻页：只在超过一页时出现（一页装得下就别给多余控件）
            if state.pendingCount > PickupActivityAttributes.LockScreenMetrics.perPage {
                VStack(spacing: 4) {
                    Button(intent: PreviousPickupIntent()) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(secondaryInk)
                            .frame(width: 34, height: 30)
                            .background(Capsule().fill(.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain)

                    Text("\(state.pendingCount) 条")
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(secondaryInk)

                    Button(intent: NextPickupIntent()) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(secondaryInk)
                            .frame(width: 34, height: 30)
                            .background(Capsule().fill(.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                }
                // 翻页按钮整体垂直居中（2026-11-08 主人：别贴在卡顶）
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        // HIG：锁屏卡 84–160pt，取上限 160；减去上下 14pt 内边距 = 内容区 132pt。
        // 用**定高**（不是 Spacer）：外层舞台是整屏提案，Spacer 会把卡撑成整屏。
        .frame(height: PickupActivityAttributes.LockScreenMetrics.contentHeight(for: page.count),
               alignment: .topLeading)
    }

    /// 一行：品牌图标 + 取件码（主角）+ 地址
    private func row(_ item: PickupActivityAttributes.Item) -> some View {
        HStack(spacing: 10) {
            CourierLogo(company: item.displayName, size: 22, showsShadow: false, usesStaticAsset: true)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    PickupCodeEmphasis.text(item.code,
                                            tint: islandInk(item.tint))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospaced()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .allowsTightening(true)
                        .layoutPriority(1)
                        .shadow(color: inkShadow, radius: 2, x: 0, y: 0.5)

                    // 多条时柜位一律做成**标签跟在码尾**（2026-11-08 主人定）：
                    // 列表行空间紧，塞进码右侧会挤掉码本身；标签只占 8pt 高。
                    if let locker = item.locker, !locker.isEmpty {
                        Text(locker.L)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.white.opacity(0.20)))
                            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
                    }
                }

                if !item.address.isEmpty {
                    Text(item.address.L)
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
    }
}

// MARK: - 灵动岛 · 紧凑与最小形态
//
// 口径（2026-09-22 主人定调）：两个形态都以 **App 图标**作唯一锚点，
// 不再跟随当前那条待办的快递品牌 ——
//   · 紧凑态 = 左 App 图标 + 右**待取数量**（2026-11-01 起去掉「待取」二字，>99 显示 99+）。原来右侧放取件码尾段，但紧凑态
//     右侧可画宽度只有约 44pt（系统在挖孔两侧各留了硬边距），4 个等宽字形就是上限，
//     多一位就截断成半个数字；数量是**一至两位**的短内容，永远不截断，
//     而且「有几件要取」正是扫一眼岛时最该知道的量。
//     🔴 「待取」二字不能省（2026-09-22 主人补）：单给一个数字，旁边没有任何
//     上下文，读不出这个数是干什么的。
//   · 最小态 = 只有约 20×20pt，仅放 App 图标，任何数字/文字都读不出来。
//
// 🔴 App 图标（`AppIcon01`…`AppIcon16`，编号与设置里的网格顺序一致）**只放在
//    `AlludeShared/Assets.xcassets`**（2026-11-15 从 App 的 catalog 迁过来）。
//    这份共享 catalog 被 **App 与小组件扩展两个 target 各编译一次**
//    （`Allude.xcodeproj` 里两个 Resources build phase 各引一份），
//    所以两个进程的 `Assets.car` 里都查得到同名 imageset。
//    ⚠️ 只放在 App 的 catalog = 扩展进程查不到 → `Image("AppIcon07")` 静默渲染成
//    灰块。1.0.0(312) 灵动岛不显示 App 图标就是这个原因，别再把图挪回 App 目录。
//
// 🔴 **灵动岛的可画尺寸（Apple HIG 官方值，必须按它约束内容）**：
// ```
//                         Compact leading / trailing      Minimal            Expanded
//   430x932 (17 Pro Max)      62.33 x 36.67 pt          36.67–45 x 36.67      408 x 84–160
//   393x852 (17 Pro)          52.33 x 36.67 pt          36.67–45 x 36.67      371 x 84–160
// ```
//    两项硬结论：**① 紧凑态单侧宽度只有 52.33~62.33pt、高度统一 36.67pt；
//    ② 抽屉式排版（把 leading/trailing 当成一个连续横条）是错的** —— 中间
//    那块是 TrueDepth 挖孔，系统按两个**独立**的元素分别给宽度。
//    预览外壳 `IslandShell` 必须复现这个几何，否则"预览好看、真机显示不全"。

/// App 图标：灵动岛紧凑 / 最小态的唯一锚点。
struct AppMarkIcon: View {
    var size: CGFloat = 22

    /// 显式指定用哪一套图标；`nil` = 按本进程读到的 `AppIconStore.current`。
    ///
    /// 🔴 灵动岛/锁屏的调用点**必须**把 `state.appIcon` 传进来（2026-11-15）：
    ///    扩展进程自己读偏好域可能读不到（详见 `ContentState.appIconRaw` 的注释），
    ///    读不到就会画成默认的 C 标，和桌面图标对不上。
    ///    App 内预览（分享卡等）跑在 App 进程，`nil` 就够了。
    var choice: AppIconChoice? = nil

    private var resolved: AppIconChoice { choice ?? AppIconStore.current }

    /// iOS App 图标的圆角比例 = 边长 × 0.2237（连续曲率的方圆形）——
    /// 用普通圆角会显得比桌面上的系统图标更「方」，两处放一起能看出不是同一种形状。
    private var corner: CGFloat { size * 0.2237 }

    var body: some View {
        // 🔴🔴 **真机岛内图标发灰的修复**（2026-09-23 主人反馈"真机是灰的，
        //      模拟器正常"）—— 两个修饰符都**必须**保留：
        //
        //   · `.renderingMode(.original)` —— 显式声明"这是彩色图，别当模板用"。
        //     Asset catalog 默认虽也是 original，但显式写出来才不会在将来
        //     有人往 Contents.json 里加 rendering-intent 时被静默改掉。
        //
        //   · `.widgetAccentedRenderingMode(.fullColor)` —— **关键那行**。
        //     灵动岛/锁屏属于 WidgetKit 渲染管线，系统可以在 **accented
        //     （着色）模式**下渲染：该模式里**图片资源默认被当作蒙版**，
        //     用系统 accent 色单色填充。22pt 的小图标一旦被填成单色，
        //     真机上看到的就是"一枚灰白色块"。
        //     App 内预览页（`ActivityPreviewGallery`）跑在 App 进程、
        //     环境是 fullColor，所以**预览永远看不出这个问题** ——
        //     这正是"模拟器正常、真机灰"的成因，也是这个修饰符存在的意义。
        //
        // 🔴 三个都是 **Image 的方法**、不是 View 修饰符，且顺序有讲究：
        //    `renderingMode` / `resizable` 返回 `Image`，可以继续接 Image 方法；
        //    `widgetAccentedRenderingMode` 返回 `some View` —— **必须放在
        //    resizable 之后、其余 View 修饰符之前**。顺序错了就是
        //    "value of type 'some View' has no member 'xxx'"（2026-09-23 实测）。
        // 2026-11-01 主人：灵动岛也要跟着 App 图标的选择走。
        // 🔴 2026-11-15 改为**由调用方把选择传进来**（`choice: state.appIcon`）：
        //    早先这里直接读 `AppIconStore.current`（App Group 偏好），扩展进程
        //    在 App Group 不可用时读到 nil → 回落到默认 C 标 → 与桌面图标对不上。
        //    现在选择跟着 ContentState 走，渲染端不再依赖任何跨进程存储。
        Image(resolved.assetName)
            .renderingMode(.original)
            .resizable()
            .widgetAccentedFullColor()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .accessibilityLabel("Allude")
    }
}

/// 保留 `state` 入参：与 `IslandExpandedContent` 同一套调用签名，
/// 装配层（`PickupLiveActivity`）不必为不同形态换参数写法。
struct IslandCompactLeading: View {
    let state: PickupActivityAttributes.ContentState

    var body: some View {
        // 🔴 **20pt + 前置 2pt 内边距**（2026-09-23 主人反馈"图标左边没显示全"）：
        //
        //   真机 8 倍放大取证（主人截图逐像素）：系统把紧凑态内容**贴着可画区前缘**
        //   排布，图标左缘距岛左缘仅 **7.3pt**，而岛帽形圆角（半径 ≈ 18.3pt）在
        //   图标上/下缘处距图标左角只有 **约 3.6pt** —— 图标 22pt 时占岛高 60%，
        //   角上的这点缝隙在深色壁纸前读起来就是"左边被切掉一角"。
        //
        //   两条对策：① 22 → 20pt（占岛高降到 54.5%，角上缝隙加宽）；
        //   ② 自带 2pt 前边距把图标整体推离前缘（不管系统的边距模型是
        //   "前缘对齐 + 固定边距" 还是 "可画区起点内缩"，这 2pt 都会原样生效）。
        //   宽度代价 22pt（20+2），远小于单侧可画 52.33pt，无截断风险。
        AppMarkIcon(size: 20, choice: state.appIcon)
            .padding(.leading, 2)
    }
}

/// 当前是不是「iPhone Duo 外屏」——紧凑态只在那种屏上改成纯数字。
///
/// 🔴 为什么要把这个判断放进 App Group：灵动岛由**小组件进程**渲染，
///    它看不到主 App 的窗口尺寸；主 App 启动时把结论写进共享容器，
///    两边读到的是同一个答案（与 `AppIconStore` 同一套路）。
enum DuoOuterDisplay {
    private static let key = "allude.duoOuter"

    static var isActive: Bool {
        // 截图脚手架：`DUO_OUTER=1|0` 强制覆盖，方便在任何一台模拟器上拍两种形态
        if let raw = ProcessInfo.processInfo.environment["DUO_OUTER"] { return raw == "1" }
        let defaults = UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
        return defaults.bool(forKey: key)
    }

    /// 主 App 启动时调用：窗口高度 < 720pt 即判定为 Duo 折叠态外屏
    /// （直板机最矮也有 852pt，永远不满足）。
    ///
    /// 🔴 2026-11-12 主人：「iPad 的 UI 不要和 iPhone Duo 混在一起」——
    ///    iPad 在台前调度 / 分屏时窗口高度也可能 < 720，几何判断会把 iPad
    ///    误当成 Duo 外屏（灵动岛改成纯数字）。所以这里先按 **idiom** 闸掉 iPad。
    static func refresh(windowHeight: CGFloat) {
        let defaults = UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
        #if canImport(UIKit)
        if UIDevice.current.userInterfaceIdiom != .phone {
            if defaults.bool(forKey: key) { defaults.set(false, forKey: key) }
            return
        }
        #endif
        let duo = windowHeight < 720
        if defaults.bool(forKey: key) != duo {
            defaults.set(duo, forKey: key)
        }
    }
}

struct IslandCompactTrailing: View {
    let state: PickupActivityAttributes.ContentState

    /// 超过 99 写成「99+」，避免三位数触发缩放
    private var cappedCount: String {
        state.pendingCount > 99 ? "99+" : "\(state.pendingCount)"
    }

    var body: some View {
        if DuoOuterDisplay.isActive {
            // 🔴 **只在 iPhone Duo 外屏**（2026-11-01 主人）：
            //   那里灵动岛很窄，「待取」二字占掉近一半可画宽 —— 只留数字、居中。
            // 🔴 真灵动岛里 trailing 区域的宽度由系统决定，
            //    `.frame(maxWidth: .infinity)` 撑的是**内容**宽度、不是区域宽度，
            //    所以数字会贴着图标一侧。用 GeometryReader 拿到区域真实尺寸再居中。
            GeometryReader { proxy in
                Text(cappedCount.L)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(islandPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            }
        } else {
            // 直板机保持原样：光一个数字没有上下文，必须带「待取」二字（2026-09-22 定调）
            //
            // 宽度账（按 Apple HIG 的**真实**单侧可画宽）：
            //   紧凑态单侧 = 52.33pt（393x852）/ 62.33pt（430x932）
            //   「待取」10pt × 2 字 = 20pt + 间距 3pt + 数字 15pt
            //   → 合计 32.2pt（一位）/ 41.4pt（两位），仍有余量。
            HStack(spacing: 3) {
                Text("待取")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(islandSecondary)

                Text("\(state.pendingCount)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(islandPrimary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            // 🔴 **不要加 `.fixedSize()`**（2026-09-23 撤掉）：真机上单侧只有 52.33pt，
            //    内容溢出会被系统直接裁掉右半截，`minimumScaleFactor` 来不及生效。
        }
    }
}

struct IslandMinimal: View {
    let state: PickupActivityAttributes.ContentState

    var body: some View {
        AppMarkIcon(size: 20, choice: state.appIcon)
    }
}

// MARK: - 灵动岛 · 展开形态
//
// 版式（2026-09-22 三改定稿 · 按主人给的同类产品参考图重排）：
//   · **纯展示，岛内不放按钮**：灵动岛面积以十几个点计、且贴着屏幕顶端，
//     误触代价高；标记已取的动作留给锁屏卡片与小组件勾选框；
//   · 全部内容收进 `.bottom` 区：leading / trailing 被挖孔夹在两侧、各只占约
//     1/3 岛宽，品牌图标会被压到看不全（真机实测）；bottom 是全岛最宽的区域；
//   · 字段只留「取件码 + 地址」，类别（kindLabel）在锁屏卡片上已有胶囊，岛内删；
//   · 层级借参考图的口径 —— 站点（图标 + 名）在左上、**待取数量**在右上
//     （数字大、标签小），取件码在底部作为视觉落点、字号最大；
//   · 🔴 取件码与地址**不同字号并列**时，只有 `lastTextBaseline` 对齐才不会
//     一高一低：标签/值各自成行、值行按**最后一行基线**对齐（原版按 top 对齐，
//     19pt 的码与 13pt 的地址底边差出半个字高，真机上就是「不在一条线」）。
//
// 🔴 不再按待办条数分档（2026-09-22 · 三改定稿）：
//   曾经做过「恰好 2 条 → 底部并排两个取件码、左右居中」的分支，本版删除。
//   根因是那个版式与顶部**站点名**各说各话 —— 左上角只画得了最新一条的
//   快递/驿站名，底部却并排画两条不同站点的码，谁属于哪个站点只能靠猜，
//   真机上就是主人说的「名称和取件码对不上」。现在**无论几条待办都只画最近一条**
//   的完整信息（站点名与码同源，必然对得上），条数交给右上角计数。
//
//   · 内容左右内缩 `hInset`：真机上岛的两侧边缘离机身很近，贴边看着像被遮挡。

struct IslandExpandedContent: View {
    let state: PickupActivityAttributes.ContentState

    /// 真机展开态的三个可画区，预览按同一结构复现：
    ///
    /// ```
    /// ┌────────────────────────────────┐
    /// │ [leading]      (挖孔)   [trailing] │  ← 挖孔高度 37pt
    /// ├────────────────────────────────┤
    /// │ bottom：取件码（+柜位）           │
    /// │ bottom：取件地址                  │
    /// └────────────────────────────────┘
    /// ```
    var body: some View {
        // 🔴 预览版式 = 真机版式 + 系统 region 内边距。
        //    每个数都是「内容距岛缘的最终距离」，从 3x 原始截图反推出来的，
        //    所以这里画出来的东西与真机是**同一套结构**，不是另画一张示意图。
        VStack(alignment: .leading, spacing: 0) {
            // 顶部行：内容落在挖孔**左右两侧**（真机的 leading / trailing 区）。
            // 中间那段不能画东西（TrueDepth 挖孔），所以左右各靠边、中间整段空着。
            HStack(spacing: 0) {
                IslandExpandedLeading(state: state)
                Spacer(minLength: IslandExpandedMetrics.punchHoleWidth)
                IslandExpandedTrailing(state: state)
            }
            .padding(.leading, IslandExpandedMetrics.previewLeading
                     - IslandExpandedMetrics.hInset)
            .padding(.trailing, IslandExpandedMetrics.previewTrailing
                     - IslandExpandedMetrics.hInset)
            // 挖孔占掉的那段高度用**顶部留白**表达
            .padding(.top, IslandExpandedMetrics.previewTop)

            VStack(alignment: .leading, spacing: IslandExpandedMetrics.previewLineSpacing) {
                IslandExpandedBottom(state: state)
            }
            // 底部内容距岛缘 33pt（= 外层 12 + 这里 21）
            .padding(.leading, IslandExpandedMetrics.previewHInset
                     - IslandExpandedMetrics.hInset)
            .padding(.top, IslandExpandedMetrics.previewRowGap)
        }
        .padding(.horizontal, IslandExpandedMetrics.hInset)
        .padding(.bottom, IslandExpandedMetrics.previewBottom)
        // 高度定死：外层壳按这个值摆岛，底部留白才不会被裁
        .frame(height: IslandExpandedMetrics.previewTotalHeight)
    }
}

/// 展开态共用的尺寸口径 —— 预览壳与真机三个 region 都读这一份，避免两边各写一套。
///
/// 🔴 数值全部来自**同一张真机截图内的标定**（手机本体宽 430px = 402pt → 1.027 px/pt）：
/// ```
/// 岛 357×100px = 348×97pt
/// 站名行文字顶  距岛顶 24pt
/// 取件码顶      距岛顶 52pt
/// 地址底        距岛顶 88pt   →  地址底距岛底 9pt
/// 内容左缘 12pt /「N 待取」右缘 15pt
/// ```
enum IslandExpandedMetrics {
    /// 底部内容左右内缩。
    ///
    /// 🔴 2026-10-28 第二版：上一轮把它从 12 降到 9.5（想把码的字形左缘提到地址的位置），
    /// 结果**码反而比图标和地址都靠左**，主人一眼看出「取件码有点偏左」。
    /// 回到 12 —— 三行里码是主角，应以它为基准，其余两个向它看齐。
    static let hInset: CGFloat = 12
    /// 地址行的视觉补偿：汉字字形贴字符框，取件码是数字（有 side bearing），
    /// 给地址 1pt 让两者观感齐平（上一版给 2.5 反而把地址推得比码靠右）。
    static let addressOpticalInset: CGFloat = 1
    /// 顶部行左侧内缩：让**图标（圆角方块）的视觉左缘**与取件码字形左缘对齐。
    /// 方块是按外框排的、圆角还会往里收一点，所以比纯像素对齐再左提 2pt。
    static let leadingInset: CGFloat = 13
    /// 顶部行右侧内缩：待取计数从贴边往左收一点（真机距右缘仅 11pt，偏挤）
    static let trailingInset: CGFloat = 8
    /// 地址行下方的留白。真机上地址底距岛底约 12pt。
    /// 给 10 是因为 `Text` 的行框比字号高约 3pt（15pt 行高 vs 12pt 字），
    /// 再加 14 就会看到明显多出来的空带。
    static let bottomInset: CGFloat = 19
    /// 顶部留白 = 挖孔区（不可画）。
    /// 真机实测：站名行占整岛 16%~42%（顶留白 16%），给 11pt。
    static let punchHoleTopInset: CGFloat = 11
    /// 站名行 → 取件码的空隙（真机约 13pt）
    static let rowGap: CGFloat = 13
    /// 码 → 地址的行距（真机约 2–3pt，几乎贴着）
    static let lineSpacing: CGFloat = 3
    // MARK: 预览专用：内容「距岛缘」的最终距离
    //
    // 🔴 2026-10-28 主人点破的关键：展开态版式是我们自己设计的 ——
    //    哪个元素进哪个 region、挖孔多宽、岛多大，全都已知；
    //    唯一要反推的只是**系统给每个 region 的内边距**。
    //    把它算出来写死，预览就按"距岛缘"摆放，与真机同一套结构，而不是各画各的。
    //
    //    数据来自 3x 原始截图（岛 x 42…1163 = 374pt）：
    //      图标左缘 139px → (139−42)/3 = 32.3pt → 系统 leading 边距 ≈ 19
    //      码左缘   141px → 33pt                 → 系统 bottom  边距 ≈ 21
    //      计数右缘 1120px → (1163−1120)/3 = 14.3pt → 系统 trailing 边距 ≈ 6
    /// 预览：内容距岛左右缘的统一值 = **16pt**。
    ///
    /// 🔴 2026-10-28 主人：「图标、取件码、取件地址有点偏右了，待取数量偏左了」。
    /// 根因是这套值不对称 —— 左 32/33、右 14，三块内容各按各的猜出来的。
    /// 真机上 `DynamicIslandExpandedRegion` 给 leading / trailing / bottom 的
    /// 左右内边距是**同一档**（对称），所以预览也必须三处同值。
    /// 取值依据（都是「内容距岛缘 ÷ 岛宽」的比例，主人截图与服务截图同口径实测）：
    /// ```
    /// 16pt → 4.6%   主人：「图标、取件码、地址太偏左，待取数量偏右」
    /// 32pt → 8.8%   主人：「偏右了」
    /// 24pt → 6.9%   ← 取两者中间，两边反馈的中点
    /// ```
    static let previewLeading: CGFloat = 24
    /// 预览：顶部行右缘距岛缘（与左缘同值，保持对称）
    static let previewTrailing: CGFloat = 24
    /// 预览：底部内容左缘距岛缘（与顶部行同值，三行左缘对齐）
    static let previewHInset: CGFloat = 24
    /// 预览：挖孔区留白（真机站名行距岛顶 16%，111pt × 16% ≈ 18）
    static let previewTop: CGFloat = 12
    /// 预览：地址底距岛底（真机 19%，111pt × 19% ≈ 21）
    static let previewBottom: CGFloat = 21
    /// 预览：站名行 → 码的空隙（按真机 111pt 总高反推）
    static let previewRowGap: CGFloat = 9
    /// 预览：码 → 地址的行距
    static let previewLineSpacing: CGFloat = 5
    /// 预览：整岛高度。
    /// 等于 `previewTop 18 + 图标 20 + previewRowGap 7 + 码行 25 + 5 + 地址 15 + previewBottom 21`。
    /// **必须给死** —— 不给的话外层用别的数字去卡高度，底部留白会被裁掉
    /// （地址贴上岛底，观感立刻变差）。
    static let previewTotalHeight: CGFloat = 92

    /// TrueDepth 挖孔宽度（官方 125.34pt，各机型一致）——
    /// 顶部行左右两块内容就是被它隔开的。
    static let punchHoleWidth: CGFloat = 125.34
}

/// 展开态 · 顶部左：品牌图标 + 快递公司／驿站
struct IslandExpandedLeading: View {
    let state: PickupActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 5) {
            // 图标不允许被压缩：HStack 宽度竞争时 Image 会被压扁，
            // 真机上就表现成「图标被挡住、看不全」。
            // 图标源与 App 内一致：快递公司 > 短信平台（2026-10-25 修）
            CourierLogo(company: state.item.displayName, size: 18, usesStaticAsset: true)
                .fixedSize()

            Text(state.item.displayName.L)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                // 挖孔左侧只有约 120pt，4–5 个字刚好；再长就该缩一点而不是直接切
                .minimumScaleFactor(0.75)
                .foregroundStyle(islandPrimary)
        }
    }
}

/// 展开态 · 顶部右：待取数量（数字大、标签小）
struct IslandExpandedTrailing: View {
    let state: PickupActivityAttributes.ContentState

    private var tint: Color { islandTint(state.item.tint) }

    var body: some View {
        // 数字 + 标签：数字是第二视觉重心，标签只做释义。
        // 「待取」原本 9pt —— 低于系统可读下限（11pt），小字会糊成一团；
        // 放大到 11 之后与数字之间留 1pt，避免两行黏连。
        VStack(alignment: .trailing, spacing: 1) {
            Text("\(state.pendingCount)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)

            Text("待取")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(islandSecondary)
        }
        .fixedSize()
    }
}

/// 展开态 · 底部：取件码（+ 柜位）与取件地址，各占一整行
struct IslandExpandedBottom: View {
    let state: PickupActivityAttributes.ContentState

    private var tint: Color { islandTint(state.item.tint) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // ① 取件码 —— 全岛唯一的视觉主角，任何情况下都不许截断
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                PickupCodeEmphasis.text(state.item.code, tint: tint)
                    // 19 → 21（2026-10-28 主人）：地址下方还有余量，把主角放大一点，
                    // 整岛高度同时用掉那块空，视觉重心更稳。
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .monospaced()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                // 柜位跟在码后面（与小组件同一口径）：到柜那一刻要用的信息。
                if let locker = state.item.locker, !locker.isEmpty {
                    Text(locker.L)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(islandSecondary)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 0)
            }

            // ② 取件地址 —— 单独一行拿满宽度，长地址才不至于只露七八个字。
            //    左侧补 `addressOpticalInset`：汉字字形几乎贴着字符框，
            //    而上面的取件码是数字（字形左侧有 side bearing）——
            //    不补这 2.5pt，地址会比码凸出来一点，三行看着不齐。
            if !state.item.address.isEmpty {
                Text(state.item.address.L)
                    // 12pt 用 semibold 会显得比 21pt 的码还"重"，
                    // 系统在这么小的字号上一律用 regular/medium。
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(islandSecondary)
                    .padding(.leading, IslandExpandedMetrics.addressOpticalInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 亮色液态玻璃（锁屏卡底）

// MARK: ============================================================================
// 亮色液态玻璃背景（2026-10-28，锁屏卡专用）
//
// 为什么必须用 UIKit：
//   SwiftUI 的 `.ultraThinMaterial` 会**跟随环境外观**渲染 —— 锁屏是 dark 环境，
//   于是它画出来的是深灰磨砂，`activityBackgroundTint` 怎么染、`.environment(\.colorScheme, .light)`
//   怎么压，真机上都是一片灰黑（连续实测三次）。材质这条路在锁屏卡上走不通。
//
//   UIKit 的 `UIBlurEffect.Style` 里有**显式亮色变体**：
//   `.systemUltraThinMaterialLight` / `.systemThinMaterialLight` —— 与外观无关，
//   永远是白色的模糊。这才是「液态玻璃」该有的通透感：壁纸透过来、被磨砂、但整体是亮的。
//
// 用法：贴在内容背后，自己 clip 成卡片圆角。
// ============================================================================

struct LightGlassBackground: UIViewRepresentable {

    /// 模糊强度（默认极薄 —— 透得出来又能压住壁纸纹理的锐利感）。
    /// 更实一点用 `.systemThinMaterialLight`。
    var style: UIBlurEffect.Style = .systemUltraThinMaterialLight

    /// 提白量：纯模糊在深色壁纸上仍偏灰，靠这层把整体拉到「乳白」。
    /// 0.10~0.18 之间是微信通知卡的手感；加大到 0.3+ 会开始像塑料片。
    var whiten: CGFloat = 0.14

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: style))
        configure(view)
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        view.effect = UIBlurEffect(style: style)
        configure(view)
    }

    /// 🔴 `tintColor` 必须显式钉成白色。
    ///
    /// 材质（material）会用 tintColor 做 vibrancy 着色，而 Live Activity 的环境 tint
    /// 是**这张卡的品牌色** —— 不钉住的话，整块玻璃会被染成韵达黄 / 圆通紫
    /// （真机实证：卡片直接变成一整块亮黄，字全糊）。
    private func configure(_ view: UIVisualEffectView) {
        view.tintColor = .white
        view.backgroundColor = UIColor.white.withAlphaComponent(whiten)
        view.contentView.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }
}
