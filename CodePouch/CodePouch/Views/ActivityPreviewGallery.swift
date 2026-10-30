import SwiftUI

// MARK: ============================================================================
// 实时活动预览（App 内 · 真实渲染）
//
// 背景：锁屏卡片与灵动岛**都无法脚本化截图** —— 锁屏要真的把设备锁上，
// 灵动岛只在带灵动岛的机型上由系统绘制。唯一能拿到「真实渲染证据」的办法，
// 与桌面小组件（`WidgetPreviewGallery.swift`）同一套：在 App 内用**同一份视图代码**
// （`CodeClipShared/PickupActivityAttributes.swift`）按各形态的约束渲染一次。
//
// 因此这里不是手工复刻：锁屏卡片与灵动岛四块区域引用的都是共享层那几个
// `ActivityLockScreenCard` / `IslandExpandedContent` / `IslandCompact*` / `IslandMinimal`
// 结构体本身，改版式两处一起变，预览不会与真机漂移。
//
// ⚠️ 唯一「模拟」的成分是外框：锁屏的卡片材质与灵动岛的黑洞形状由系统绘制，
//    这里用等尺寸的外壳近似，只为观察内容的排布与截断。
//
// 入口：`SCREEN=activity`（命令行验收截图）。
// ⚠️ 本文件不得使用 SwiftUI 宏（#Preview / @State），原因见 DesignSystem.swift 顶部。
// ============================================================================

// MARK: - 外框

/// 锁屏 / 通知中心里的活动卡片外壳。
///
/// 真实卡片 = 系统给的圆角 + 半透明材质，再由活动自己的
/// `.activityBackgroundTint(...)` 叠一层品牌色。这里把同一套叠加顺序复现一次：
/// 材质在下、品牌色（opacity 0.10）在上 —— 顺序反了颜色会脏。
struct ActivityCardShell: View {
    let tint: Color
    let content: AnyView

    init(tint: Color, @ViewBuilder content: () -> some View) {
        self.tint = tint
        self.content = AnyView(content())
    }

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 🔴 2026-10-28 主人：真机锁屏卡是 iOS 26 的**液态玻璃**，
            //    原来那层 `.ultraThinMaterial` 只是磨砂玻璃，发灰、没有折射和高光。
            //    `.glassEffect` 是系统 Liquid Glass 的原生实现：折射下层内容、
            //    边缘镜面高光、可带品牌色 tint —— 与真机同一个渲染器。
            .glassEffect(
                .regular.tint(tint.opacity(0.16)),
                in: .rect(cornerRadius: 24, style: .continuous)
            )
            .allowsHitTesting(false)
    }
}

/// 灵动岛外壳。
///
/// 🔴 **几何按 Apple HIG 官方尺寸**（2026-09-23 修正）：
/// ```
///                        Compact leading / trailing      Minimal          Expanded
///   393x852 (17 Pro)         52.33 x 36.67 pt         36.67–45 x 36.67     371 x 84–160
///   430x932 (17 Pro Max)     62.33 x 36.67 pt         36.67–45 x 36.67     408 x 84–160
///
///   紧凑态整岛宽：17 Pro **230** / 17 Pro Max **250**
///   （= 单侧 × 2 + 挖孔 125.34，两档机型的挖孔宽度相同）
/// ```
/// 旧版预览把紧凑态画成「148pt 的一个连续黑框、里面 leading 与 trailing 并排」——
/// 两处都错：**总宽差了一倍**，而且真机上 leading / trailing 是被 TrueDepth 挖孔
/// **隔开的两块独立画布**，不是一条横条里的左右两端。于是"预览宽松、真机发挤"，
/// 这就是主人说的"真机截图与模拟器对比相差很大"。
///
/// 预览一律取 **393x852（17 Pro）** 这一档，不按机型分流：它的单侧更窄（52.33 < 62.33），
/// 预览偏保守 —— 与"预览别比真机更好看"的既定口径一致。
struct IslandShell: View {

    enum Style {
        /// 展开态：整岛宽度（Pro Max 档 408）
        case expanded(width: CGFloat)
        /// 紧凑态：两翼 + 挖孔（官方 230 = 52.33 × 2 + 125.34）
        case compact
        /// 最小态：只有约 45×36.67pt 可画
        case minimal

        /// 紧凑态单侧可画宽度（393x852 档）
        static let compactSide: CGFloat = 52.33
        /// 单侧可画高度（两个形态共用）
        static let contentHeight: CGFloat = 36.67
        /// TrueDepth 挖孔的宽度
        static let punchHole: CGFloat = 125.34

        var cornerRadius: CGFloat {
            switch self {
            // 🔴 2026-10-28 主人：「灵动岛卡片的圆角再做大一点点」→ 43 → **46**。
            //    46 × 缩放 0.817 ≈ 37.6pt 渲染（机模屏幕圆角 42.9 × 0.817 ≈ 35），
            //    视觉上岛角比屏幕角略圆一档，是「再大一点点」的合适幅度。
            case .expanded: 46
            // 紧凑/最小态是**居中的胶囊**（两端半圆），半径 = 高/2。
            // 之前写的 22 是猜的；按 36.67 的内容高 + 上下各 3.17 的岛体余量 = 43，
            // 半径取 21.5。
            case .compact, .minimal: 21.5
            }
        }

        /// 外壳总宽（= 真机整岛宽，黑框包含在内）。
        var width: CGFloat {
            switch self {
            case .expanded(let w): w
            case .compact: Self.compactSide * 2 + Self.punchHole
            case .minimal: 44
            }
        }

        /// 外壳总高。展开态由内容撑开，另两种形态高度固定。
        var height: CGFloat? {
            switch self {
            case .expanded: nil
            case .compact, .minimal: 43
            }
        }
    }

    let style: Style
    let content: AnyView
    /// 真机岛外圈有一圈 `keylineTint`（品牌色细线）。预览壳复现它：
    /// 🔴 必须用 `islandTint` 亮化后的品牌色 —— 顺丰的纯黑主色描边
    /// 贴着黑色壳 + 暗黑页面就是隐形的（2026-09-24 主人真机指认）。
    var keyline: Color?

    init(_ style: Style, keyline: Color? = nil, @ViewBuilder content: () -> some View) {
        self.style = style
        self.keyline = keyline
        self.content = AnyView(content())
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            // 外框宽度 = 真机整岛宽度。顺序不能反：frame 在 padding 之前会让总宽超出。
            // 紧凑/最小态**连高度一起定死**，宽度才是有意义的对照 ——
            // 否则外壳会跟着内容缩，量出来的"余量"全是假的。
            .frame(width: style.width, height: style.height, alignment: .center)
            // 灵动岛恒为黑色挖孔：不跟随 App 外观，深色下也是这块黑，
            // 所以这里写死 .black 而不是语义色。
            .background(Color.black, in: .rect(cornerRadius: style.cornerRadius, style: .continuous))
            // 暗黑页面底也是黑的，黑壳直接融进去 —— 画一圈真机同款的
            // keyline 描边把岛的轮廓勾出来（浅色下多这一圈也自然）。
            .overlay {
                if let keyline {
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .strokeBorder(keyline, lineWidth: 1)
                }
            }
            // 同时把外观锁成深色 —— 岛内是黑底，品牌图标要取它在深色下的那一档。
            .environment(\.colorScheme, .dark)
            .allowsHitTesting(false)
    }

    private var horizontalPadding: CGFloat {
        switch style {
        // 🔴 展开态 **不给** 外壳内边距（2026-10-28）。
        //    `IslandExpandedContent` 已经按 `previewLeading / previewHInset /
        //    previewTrailing` 精确模拟了系统 region 的 inset，这里再补 16
        //    就是**双重内缩** —— 实测内容距岛缘变成 32pt，
        //    主人一眼看出「图标、取件码、地址偏右，待取数量偏左」。
        //    展开态的左右边距统一由 preview* 常量负责，外壳只管画黑底和圆角。
        case .expanded: 0
        // 🔴 紧凑态左右各留 **7pt**（2026-09-23 从主人真机截图逐像素量得：
        //    系统给紧凑态内容的前边距 ≈ 7.3pt，不是 0）。之前写 0 的理由
        //    （"官方可画宽从岛边缘算起"）导致预览里图标**整个贴在胶囊左缘**、
        //    左角被帽形圆角压住 —— 主人："超出灵动岛紧凑显示区域了"。
        //    预览要复现的是"系统边距之后的内容区"，所以这 7pt 必须给。
        case .compact: 7
        case .minimal: 12
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .expanded: 14
        case .compact: 3.17
        case .minimal: 3.17
        }
    }
}

// MARK: - 机身上半截

/// 机身 —— 用官网导出的 **iPhone 16 Pro** 机模当底，全部按真实 pt 尺寸绘制后整体缩放。
///
/// 🔴 2026-10-28 主人：「机模是真实的尺寸啊，你完全可以按照机模来做，做完做缩放的合适大小」。
/// 这张机模图的**屏幕里已经带壁纸**（日期、天气、图标、Dock 全在），
/// 所以不再需要单独铺一层屏幕截图，只叠灵动岛即可。
///
/// 实测（图 939×1920 px，屏幕 839px = 402pt → 2.087 px/pt）：
/// ```
/// 整机   450 × 920 pt
/// 屏幕   402 × 857 pt，左上角 (24, 23)
/// 挖孔   顶边 y = 62.3 pt，宽 121 pt（官方 125.34）
/// 灵动岛 374 × 111 pt（16 Pro 官方展开宽），水平居中 → x = (450−374)/2 = 38
/// ```
/// 岛顶 62.3 与挖孔顶同值 → 天然等高。
struct PhoneTopShell<Content: View>: View {

    @ViewBuilder let content: () -> Content

    // 真实尺寸（pt）。机模图 1350×2760 px，机身外沿 1292px = 419.5pt
    // （iPhone 16 Pro 机身宽 71.5mm ≈ 420pt）→ **3.08 px/pt**。
    // 校验：机身高度 2710px ÷ 3.08 = 880pt ≈ 官方 874pt。
    private let designWidth: CGFloat = 438.3     // 1350 ÷ 3.08
    private let designHeight: CGFloat = 896.1    // 2760 ÷ 3.08
    /// 屏幕顶边（相对 PNG 图片顶边）。
    ///
    /// 🔴 2026-10-28 主人：「是和机模的屏幕的顶部，不是 png 图片的顶部啊」。
    /// PNG 顶边往下一段才是屏幕：x=300 列实测 y 26…40 是机身边框（银色），
    /// **y 42 起是屏幕黑边**（42 ÷ 3.08 = 13.6pt），y 69 起才是壁纸。
    /// 所有边距一律从「屏幕顶边」算，不是从图片顶边算。
    private let screenTopInImage: CGFloat = 13.6
    /// 岛到屏幕三边（上 / 左 / 右）的统一留白。
    ///
    /// 🔴 机模 PNG 里屏幕的**可见内容宽只有 394pt**（x 29…1320 是整机外沿 1292px，
    /// 其中两侧各约 40px 被机身边框/屏幕黑边压掉），不是标称的 402pt。
    /// 所以左右边距 = (394 − 372) / 2 = **11**，上边距也取 11 才视觉一致。
    /// 上一版按 402 算成 15，结果左右 28px、上边 38px，岛看着往上顶。
    private let islandEdgeInset: CGFloat = 11
    /// 整体下移量（pt）。
    /// 🔴 2026-10-28 主人的连续微调：下移 20 → 上移 8 → 上移 2 → 上移 2 → 下移 2，
    /// **净下移 10**。相对「三边 11pt 一致」基准的额外偏移。
    private let islandTopShift: CGFloat = 10
    /// 灵动岛顶部 = 屏幕顶边 + 三边留白 + 额外下移。**派生，不写死绝对值**。
    private var holeTop: CGFloat { screenTopInImage + islandEdgeInset + islandTopShift }
    /// 岛宽 = **Apple 官方口径**。
    ///
    /// 🔴 2026-10-28 查证 HIG「Live Activities」：iPhone 16 Pro 屏 402×874pt，
    /// **展开态岛宽 371pt**、圆角 44pt、高度 84–160pt、紧凑态 230pt。
    /// → 左右边距 = (402 − 371) / 2 = **15.5pt**（占屏宽 3.86%）。
    ///
    /// 本预览的机模屏幕可见宽是 394pt（不是 402 —— 两侧各被机身压掉约 4pt），
    /// 按同一比例换算边距 = 394 × 3.86% ≈ **15.2pt**，岛宽 = 394 − 2×15.2 = **363.6**。
    /// （上一版 370.4 对应边距 11.9pt = 3.0%，比真机窄 3.6pt）
    private let islandW: CGFloat = 363.6
    private let islandH: CGFloat = IslandExpandedMetrics.previewTotalHeight

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width, 1) / designWidth

            ZStack(alignment: .topLeading) {
                // 机模（屏幕里自带壁纸，不需要额外铺屏幕内容）
                Image("PhoneFrame16Pro")
                    .resizable()
                    .frame(width: designWidth, height: designHeight)

                // 灵动岛：顶部与挖孔顶边等高
                content()
                    .frame(width: islandW, height: islandH, alignment: .top)
                    .offset(x: (designWidth - islandW) / 2, y: holeTop)
            }
            .frame(width: designWidth, height: designHeight, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: designWidth * scale, height: designHeight * scale,
                   alignment: .topLeading)
        }
        .aspectRatio(designWidth / designHeight, contentMode: .fit)
    }
}


// MARK: - 锁屏机模

/// 锁屏机模 —— 官网导出的 iPhone 16 Pro 锁屏图，锁屏卡片摆进它的实时活动位置。
///
/// 🔴 底图必须是 **`Photoshop/iPhone 16 Pro.png`**（1350×2760、**hasAlpha=yes**）。
/// 用剪贴板里的 jpg 会出白色底（没有 alpha 通道），主人已指认过一次。
///
/// 实测（图 1350×2760，屏幕宽 1206px = 402pt → **3.0 px/pt**，正好 3x）：
/// ```
/// 整图   450 × 920 pt
/// 屏幕   x 72…1277（宽 402pt）= 24…426pt，机身框各约 24pt
/// 状态栏文字 y 33…53px
/// 日期       y 149…188px  → 50…63pt
/// 时间 12:58 y 422…683px  → 141…228pt
/// 手电筒/相机 y 2421…2486px → 807…829pt
/// ```
/// 🔴 2026-10-28 主人给了**真机拾码锁屏截图**，位置与"时间下方"完全不同：
/// 卡片贴在**屏幕底部**、手电筒按钮上方（无通知时 iOS 把实时活动排在最下一位）。
/// 真机图实测（883×1920，883px = 402pt → 2.196 px/pt）：
/// ```
/// 卡片 x 30…855（宽 825px = 376pt），左右各留 30px ≈ 14pt
/// 卡片底 y≈1610px，距屏幕底 310px ≈ 141pt
/// 卡片顶 y≈1405px → 高 205px ≈ 93pt
/// ```
/// 所以这里用**底部定位**：卡片底距屏幕底 148pt，左右各 14pt。
/// 用底部定位而不是顶部，是因为卡片高度由内容决定，顶部定位一旦内容换行就会整体错位。
struct LockScreenShell<Content: View>: View {

    @ViewBuilder let content: () -> Content

    private let designWidth: CGFloat = 450      // 939 ÷ 2.087
    private let designHeight: CGFloat = 920     // 1920 ÷ 2.087
    /// 屏幕内容左缘（图内 50px ÷ 2.087）
    private let screenLeft: CGFloat = 24
    /// 屏幕宽 402pt（16 Pro 标称值）
    private let screenWidth: CGFloat = 402
    /// 卡片底距屏幕底（图内 310px ÷ 2.196 ≈ 141，取 148 与真机观感对齐）
    private let cardBottomGap: CGFloat = 148
    /// 卡片左右留白：真机 30px ÷ 2.196 ≈ 14pt
    private let cardSideInset: CGFloat = 14

    private var cardWidth: CGFloat { screenWidth - cardSideInset * 2 }

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width, 1) / designWidth

            // 底部对齐：图片底 = 屏幕底，卡片按「距底 148pt」摆，高度交给内容
            ZStack(alignment: .bottom) {
                Image("LockScreenFrame16Pro")
                    .resizable()
                    .frame(width: designWidth, height: designHeight)

                content()
                    .frame(width: cardWidth)
                    .padding(.bottom, cardBottomGap)
            }
            .frame(width: designWidth, height: designHeight, alignment: .bottom)
            // 整体等比缩放到可用宽度：内部所有相对关系都不变
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: designWidth * scale, height: designHeight * scale,
                   alignment: .topLeading)
        }
        .aspectRatio(designWidth / designHeight, contentMode: .fit)
    }
}


// MARK: - 真机截图机模

/// 真机截图预览 —— **直接用真机上截下来的整机图**当预览。
///
/// 🔴 2026-10-28 主人：「我直接从真机上截图的，咱俩还在这手搓，直接截图就可以啊」。
/// 这是对的：任何自绘的机模 + 叠加卡片，都只是对真机效果的近似；
/// 而真机截图本身就是**唯一权威**的效果 —— 尺寸、材质、圆角、字号全对。
///
/// 三张图都来自 `Photoshop/` 下、1350×2760 带 alpha、450:920：
/// ```
/// RealCompact      灵动岛 · 紧凑态
/// RealExpanded     灵动岛 · 展开态
/// RealLockScreen   锁屏卡片
/// ```
/// 统一 `maxHeight 520`（宽 254pt），与页面内其它预览同尺寸。
struct RealDeviceShot: View {
    let name: String

    var body: some View {
        Image(name)
            .resizable()
            .aspectRatio(450.0 / 920.0, contentMode: .fit)
            .frame(maxHeight: 520)
            .accessibilityHidden(true)
    }
}

// MARK: - 预览页

struct ActivityPreviewGallery: View {
    @EnvironmentObject private var store: PickupStore

    /// 预览分页：0 展开 / 1 紧凑 / 2 锁屏。
    /// 🔴 2026-10-28 主人：三个机模做成**滑动切换**，底部一排按钮指示当前页
    /// （参考 Apple 官网那种轮播选择器的意思，不是照抄）。
    /// 截图脚手架：`SIMCTL_CHILD_ACTIVITY_PAGE=1` 可直接落到指定页（默认 0）。
    @State private var previewPage = Int(ProcessInfo.processInfo.environment["ACTIVITY_PAGE"] ?? "") ?? 0

    /// 真实待办里的前三条。
    private var realItems: [PickupActivityAttributes.Item] {
        store.pending.prefix(3).map { record -> PickupActivityAttributes.Item in
            let station = StationDirectory.shared.matchedName(in: [record.rawMessage])
            // 取色与主名同源 —— 走统一命名规则（`PickupNaming`），
            // 与真机卡面 / 列表卡取的是同一个字符串。
            let nameSource = record.naming(station: station).iconSource
            return PickupActivityAttributes.Item(
                id: record.id.uuidString,
                company: record.company,
                courier: record.courier,
                station: station,
                code: record.code,
                address: record.address,
                tint: CourierBrand.info(for: nameSource).resolvedFrom,
                locker: record.widgetLockerLabel(WidgetDisplayOptions.load())
            )
        }
    }

    /// 兜底样本：库里一条待办都没有时（刚装、刚清空）预览不至于空着。
    /// 第一条带柜位，好让「码 + 柜位」这一段在预览里也能被看到。
    private static let sampleItems: [PickupActivityAttributes.Item] = [
        .init(id: "preview-1", company: "顺丰速运", code: "8-2-4031",
              address: "丰巢智能柜 · 望京SOHO T1 大堂", tint: 0x000000,
              locker: "2号柜"),
        .init(id: "preview-2", company: "蜜雪冰城", code: "A128",
              address: "望京SOHO T2 1层", tint: 0xE4002B),
    ]

    /// 预览数据：**优先用你库里的真实待办**，一条都没有时才退回样本。
    ///
    /// 🔴 2026-10-28 主人：「再加一条模拟数据，不就是真机的实际效果一模一样了吗」。
    /// 以前的门槛是「≥2 条才用真实数据」，手里只有 1 条待办时预览仍然画样本
    /// （拼多多 / D-1-3516），于是预览和真机上的岛永远是两套内容 ——
    /// 看着就像"预览在骗人"。现在只要有一条真实待办就用它，条数就用真实条数。
    private var items: [PickupActivityAttributes.Item] {
        realItems.isEmpty ? Self.sampleItems : realItems
    }

    private var usingSample: Bool { realItems.isEmpty }

    /// 带「还有 N 条」的状态：卡面只画一条，其余用计数交代
    private var multiState: PickupActivityAttributes.ContentState {
        .init(item: items[0], pendingCount: items.count)
    }

    /// 单条状态：不出现计数文案，用来对照两种排布
    private var singleState: PickupActivityAttributes.ContentState {
        .init(item: items.count > 1 ? items[1] : items[0], pendingCount: 1)
    }

    /// 灵动岛展开用的状态：只画**最近一条**的完整信息，条数交给右上角计数。
    ///
    /// 计数用 `max(items.count, 3)`：多条时的计数样式（一位数）与单条一致，
    /// 预览取 3 是为了让右上角的两位数以内的排布也能被看到。
    private var islandState: PickupActivityAttributes.ContentState {
        .init(item: items[0], pendingCount: max(items.count, 3))
    }

    // 🔴 预览壳上所有品牌色一律走 `islandTint` 亮度插值 —— 与真机锁屏卡
    //    / 岛的亮化口径一致；原始品牌色（顺丰纯黑）在暗色页面上全部隐形。
    private var accent: Color { islandTint(multiState.item.tint) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                activityToggleSection
                previewPagerSection
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("实时活动")
        .cloaksTabBar()
        .navigationBarTitleDisplayMode(.inline)
    }


    // MARK: 滑动分页预览

    /// 三个形态共用一个机模位，左右滑动切换，底部一排按钮同时指示 + 可点。
    ///
    /// 为什么不再各占一块：三张真机截图纵向铺开要滚两屏半，
    /// 而它们本来就是同一件事（实时活动在不同位置的样子）——
    /// 分页看更接近用户真实的心理模型，也让一屏装得下。
    private var previewPagerSection: some View {
        // 🔴 2026-10-28 主人：说明文字挪到**按钮下方**，上方只留标题。
        //    原因是说明长度随页面变化（一行 / 两行），若把说明放在机模上方，
        //    切换页面时机模会被推着上下跳 —— 位置不固定，看着晃。
        //    现在「标题 → 机模 → 按钮」三段的顺序和尺寸都恒定，只有最下面的说明会变。
        VStack(alignment: .leading, spacing: 12) {
            Text(currentPageTitle)
                .font(.headline)

            TabView(selection: $previewPage) {
                ForEach(Array(pageShots.enumerated()), id: \.offset) { index, shot in
                    // 🔴 每页必须撑满容器宽 —— 不给 `maxWidth: .infinity` 时页宽 = 图片宽，
                    //    一页只有 205pt，滑动时相邻两页会同时露出来（截图里左右各半个手机）。
                    RealDeviceShot(name: shot.image)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(index)
                }
            }
            // 分页样式、隐藏系统圆点（底部自绘一排按钮）
            .tabViewStyle(.page(indexDisplayMode: .never))
            // 440：机模宽约 215pt（原来 400 → 195pt，放大一档）。
            // 上方的提示行已删除，省下的高度让给了机模。
            .frame(height: 440)
            .frame(maxWidth: .infinity)

            pagePicker
                .frame(maxWidth: .infinity)

            // 说明放在按钮下方：高度可变，但它在机模下面，不会推动机模位置。
            Text(currentPageNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
        }
    }

    /// 底部切换按钮：选中的拉成胶囊并填主色，未选中的是浅灰胶囊。
    private var pagePicker: some View {
        HStack(spacing: 10) {
            ForEach(Array(pageShots.enumerated()), id: \.offset) { index, shot in
                let on = index == previewPage
                Button {
                    withAnimation(.snappy(duration: 0.28)) { previewPage = index }
                } label: {
                    Text(shot.title)
                        .font(.system(size: 13, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .lineLimit(1)
                        .padding(.horizontal, on ? 16 : 13)
                        .padding(.vertical, 7)
                        .background {
                            Capsule(style: .continuous)
                                .fill(on ? AnyShapeStyle(AppTheme.accent)
                                          : AnyShapeStyle(Color(.secondarySystemFill)))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shot.title)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
    }

    /// 三页的图与文案。无灵动岛的机型只保留锁屏一页。
    private var pageShots: [(title: String, note: String, image: String)] {
        var pages: [(String, String, String)] = []
        if DeviceProfile.hasDynamicIsland {
            pages.append(("灵动岛 · 展开",
                          "长按或同时有两个活动时展开，可画面积最大；只画最近一条待办，条数看右上角",
                          "RealExpanded"))
            pages.append(("灵动岛 · 紧凑",
                          "同时有两个活动时收成紧凑态：左 App 图标、右「待取 N」，三个以上只剩图标",
                          "RealCompact"))
        }
        pages.append(("锁屏卡片",
                      "锁屏上多条待办时取最新一条，其余用「还有 N 条」交代",
                      "RealLockScreen"))
        return pages
    }

    private var currentPageTitle: String {
        pageShots[min(previewPage, pageShots.count - 1)].title
    }

    private var currentPageNote: String {
        pageShots[min(previewPage, pageShots.count - 1)].note
    }

    // MARK: 锁屏

    private var lockScreenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("锁屏卡片", note: "多条待办时取最新一条，其余用计数交代")

            // 🔴 2026-10-28 主人：把锁屏卡片放进机模的锁屏里，而不是浮在页面上。
            //    机模自带壁纸、状态栏、时间、手电筒，卡片就摆在时间下方 —— 真机上的位置。
            // 真机截图直出（2026-10-28）：这张就是拾码在真机锁屏上的实际样子，
            // 卡片位置、液态玻璃材质、字号全部是系统渲染的结果，不再自绘叠加。
            RealDeviceShot(name: "RealLockScreen")
        }
    }

    // MARK: 灵动岛 · 展开

    private var expandedSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            label("灵动岛 · 展开", note: "长按 / 有第二个活动时展开，可画面积最大；只画最近一条待办，条数看右上角")

            // 与 `PickupLiveActivity` 的 dynamicIsland 分支同一份内容：只挂 bottom 区。
            //
            // 只有一种版式了：无论几条待办都画**最近一条**（站点名与取件码同源），
            // 「恰好 2 条并排两个码」的分支已删 —— 那样顶部的站点名只能对上其中一条。
            expandedCase("多条待办 · 站点名与取件码同源，条数看右上角", state: islandState)        }
    }

    private func expandedCase(_ caption: String,
                              state: PickupActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)

            // 真机截图直出：岛的位置、形状、字号、边缘高光都是系统画的。
            RealDeviceShot(name: "RealExpanded")
        }
    }

    // MARK: 灵动岛 · 紧凑与最小

    private var compactSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("灵动岛 · 紧凑与最小",
                  note: "左 App 图标 + 右「待取 N」（同时有两个活动时退化为紧凑态）；三个以上只剩最小态，只画 App 图标")

            // 真机截图直出：紧凑态两翼 + 挖孔的实际观感（左 App 图标 + 右「待取 5」）。
            RealDeviceShot(name: "RealCompact")
        }
    }

    // MARK: 总开关

    /// 🔴 总开关（2026-09-23 主人要求）。
    ///
    /// 存储在 **App Group**（`LiveActivitySetting`），理由见该类型注释：
    /// 桌面小组件的勾选意图在**扩展进程**里直接调 `PickupActivityController.sync`，
    /// 那条路径不经本页，开关只存 App 的 standard defaults 就会被勾选"复活"。
    ///
    /// 切换后立即 `sync` 一次：
    ///   · 关 → 控制器第 0 道门当场收掉正在跑的活动；
    ///   · 开 → 按当前待办立刻补起一张卡，不用等下一次数据变动。
    private var activityToggleSection: some View {
        // 🔴 2026-10-28 主人：「总开关」三个字删掉 —— 卡片里那行「显示实时活动」已说明一切。
        SettingsGroup(title: "",
                      note: "在锁屏与灵动岛上显示最新待取的取件码。关闭后立刻收掉卡片，重新打开后自动恢复。") {
            SettingsPlainRow(title: "显示实时活动") {
                Toggle("", isOn: Binding(
                    get: { LiveActivitySetting.isEnabled },
                    set: { on in
                        LiveActivitySetting.isEnabled = on
                        PickupActivityController.sync(pending: store.pending)
                    }))
                    .labelsHidden()
                    .tint(AppTheme.accent)
            }
        }
    }

    // MARK: 小节标题

    private func label(_ title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
