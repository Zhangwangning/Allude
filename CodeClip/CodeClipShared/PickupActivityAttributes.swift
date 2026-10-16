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
        var code: String
        var kindLabel: String
        var address: String
        var tint: UInt32
    }

    /// 动态部分：每次待办变动整体替换。
    struct ContentState: Codable, Hashable {
        /// 当前展示的那一条（取最新待办）
        var item: Item
        /// 待办总数 —— 卡面只画一条，其余用计数交代
        var pendingCount: Int
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

/// 岛内正文（平台名）：纯白，与系统给岛内文字的口径一致
private let islandPrimary = Color.white
/// 岛内次级文字（地址、"共 N 件"）：白色降不透明度，而不是 `.secondary`
private let islandSecondary = Color.white.opacity(0.72)

// MARK: - 锁屏卡片

/// 锁屏 / 通知中心里的实时活动卡面。
///
/// 背景与着色交给宿主：`.activityBackgroundTint(...)` 由
/// `ActivityConfiguration` 施在外层，这里只画内容，不要自己铺背景
/// （自己铺会和系统给活动卡片的圆角与材质打架）。
struct ActivityLockScreenCard: View {
    let state: PickupActivityAttributes.ContentState

    /// 常亮显示（Always-On）下系统会把卡面**按深色渲染并整体压暗**，
    /// 品牌色里偏暗的那批（顺丰 / 抖音的主色就是纯黑）会糊进底色。
    /// 此时退回语义色，交给系统按对比度自己选 —— Apple 对 Always-On 的明确建议。
    ///
    /// 🔴 正常态也**不能直接用品牌色**（2026-09-24 主人真机指认"黑色取件码"）：
    ///    暗色锁屏上卡底是深色材质 + 品牌色叠层，顺丰的纯黑主色码就是黑上黑。
    ///    统一走 `islandTint` 亮度插值（≥0.55），色相保留、对比度兜底。
    @Environment(\.isLuminanceReduced) private var dimmed

    private var tint: Color { dimmed ? .primary : islandTint(state.item.tint) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 取件码是整张卡唯一要「一眼读出」的内容，与 App 列表卡片同一口径：
            // 上方一行放来源，中间大字放码，底部一行放地址。
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(state.item.company)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    Text(state.item.kindLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(tint.opacity(0.18), in: .capsule)
                        .foregroundStyle(tint)

                    Spacer(minLength: 6)

                    if state.pendingCount > 1 {
                        Text("还有 \(state.pendingCount - 1) 条")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                PickupCodeEmphasis.text(state.item.code, tint: tint)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .monospaced()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.top, 6)

                if !state.item.address.isEmpty {
                    Text(state.item.address)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, 3)
                }
            }

            CourierLogo(company: state.item.company, size: 30)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 灵动岛 · 紧凑与最小形态
//
// 口径（2026-09-22 主人定调）：两个形态都以 **App 图标**作唯一锚点，
// 不再跟随当前那条待办的快递品牌 ——
//   · 紧凑态 = 左 App 图标 + 右**「待取 N」横排**。原来右侧放取件码尾段，但紧凑态
//     右侧可画宽度只有约 44pt（系统在挖孔两侧各留了硬边距），4 个等宽字形就是上限，
//     多一位就截断成半个数字；数量是**一至两位**的短内容，永远不截断，
//     而且「有几件要取」正是扫一眼岛时最该知道的量。
//     🔴 「待取」二字不能省（2026-09-22 主人补）：单给一个数字，旁边没有任何
//     上下文，读不出这个数是干什么的。
//   · 最小态 = 只有约 20×20pt，仅放 App 图标，任何数字/文字都读不出来。
//
// 🔴 App 图标的**唯一存放处 = `CodeClipShared/Assets.xcassets/AppMark.imageset`**
//    （2026-09-23 核实）：这份共享资源在 pbxproj 里被 **App 与小组件扩展两个 target
//    各自编译一次**（`CodeClip.xcodeproj` 有两个 Resources build phase 各引一份），
//    所以 `Image("AppMark")` 在**两个进程的 main bundle** 里都查得到。
//    已用 `xcrun assetutil --info <appex>/Assets.car` 确认过 `Name: AppMark`
//    确实在扩展产物里 —— 真机岛内显示异常**不是**"扩展缺图"造成的。
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
        Image("AppMark")
            .renderingMode(.original)
            .resizable()
            .widgetAccentedRenderingMode(.fullColor)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .accessibilityLabel("码夹")
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
        AppMarkIcon(size: 20)
            .padding(.leading, 2)
    }
}

struct IslandCompactTrailing: View {
    let state: PickupActivityAttributes.ContentState

    var body: some View {
        // 横排「待取 4」：光一个数字没有语义 —— 紧凑态旁边没有别的上下文，
        // 主人看到「3」无法判断是还有 3 件待取还是别的什么。
        //
        // 宽度账（按 Apple HIG 的**真实**单侧可画宽重算）：
        //   紧凑态单侧 = **52.33pt（393x852 · 17 Pro）/ 62.33pt（430x932 · Pro Max）**
        //   「待取」10pt × 2 字 = 20pt + 间距 3pt + 数字 15pt（一位 ≈ 9.2 / 两位 ≈ 18.4）
        //   → 合计 **32.2pt（一位）/ 41.4pt（两位）**，在 52.33pt 内仍有余量。
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
        // 🔴 **不要加 `.fixedSize()`**（2026-09-23 撤掉，主人反馈真机"显示不全"）：
        //    它的语义是"按理想尺寸布局、宁可溢出也不收缩"。真机上单侧只有
        //    52.33pt，内容一旦超出就被系统**直接裁掉**（右半截消失），
        //    `minimumScaleFactor` 根本没机会生效。
        //    撤掉后宽度竞争会先走缩放，不足时才截断 —— 这才是"显示不全"的正解。
    }
}

struct IslandMinimal: View {
    let state: PickupActivityAttributes.ContentState

    var body: some View {
        AppMarkIcon(size: 20)
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

    private var tint: Color { islandTint(state.item.tint) }

    /// 内容左右内缩 —— 灵动岛两侧离机身极近，贴边会被读成「被切掉」。
    private let hInset: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            codeRow
        }
        .padding(.horizontal, hInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 顶部行：品牌图标 + 平台名（左）｜待取数量（右）
    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 6) {
                // 图标不允许被压缩：HStack 宽度竞争时 Image 会被压扁，
                // 真机上就表现成「图标被挡住、看不全」。
                // 尺寸给到 22：岛内品牌图标要能看清图案细节，更小会糊成一块色块。
                CourierLogo(company: state.item.company, size: 22)
                    .fixedSize()

                Text(state.item.company)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(islandPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 待取数量：数字大、标签小 —— 参考图里数量是右上的第二视觉重心。
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(state.pendingCount)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)

                Text("待取")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(islandSecondary)
            }
            .fixedSize()
        }
    }

    // 底部行：最近一条的完整信息 —— 码（主角）+ 地址，按**最后一行基线**对齐。
    //
    // 为什么不把两列各自包成「标签在上、值在下」再按 `.top` 对齐：19pt 的码与
    // 13pt 的地址顶部齐了，底边却差了半个字高，真机上就是「取件码和取件地址
    // 不在一条线上」。9pt 小标签也去掉（参考图没有这类标签，数字串与中文地址
    // 本身就自明），省下的高度给了码：19pt → 21pt。
    private var codeRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 14) {
            PickupCodeEmphasis.text(state.item.code, tint: tint)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .monospaced()
                .lineLimit(1)
                // 取件码是唯一主角，不允许为了给地址让路而被截断
                .fixedSize(horizontal: true, vertical: false)

            if !state.item.address.isEmpty {
                Text(state.item.address)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(islandPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
