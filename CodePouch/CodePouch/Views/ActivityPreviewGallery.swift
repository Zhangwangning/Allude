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

    // 真实尺寸（pt）。机模图 1350×2760 px，**屏幕实测 1206px 宽 = 402pt** → **3.0 px/pt**，
    // 于是整图 = 450 × 920pt。这组数字不是估的，是 2026-10-30 主人给的四张
    // 16 Pro 真实尺寸机模逐像素量出来的（四张几何完全一致）：
    // ```
    // 屏幕     x 72…1277（1206px = 402pt），顶边 y 69px = 23pt
    // 挖孔     x 490…859（370px = 123.3pt），y 113…217（105px = 35pt）→ 顶边 37.7pt，水平居中
    // 机身外沿 x 17…1334，y 25…2734
    // ```
    private let designWidth: CGFloat = 450       // 1350 ÷ 3
    private let designHeight: CGFloat = 920      // 2760 ÷ 3
    /// 灵动岛顶边（相对整图顶边）—— 直接取实测的挖孔顶：岛是从这个 y 往下长的。
    private let islandTopInImage: CGFloat = 37.7
    private var holeTop: CGFloat { islandTopInImage }

    /// 岛宽 / 岛高。默认 = 展开态（Apple HIG：16 Pro 展开态岛宽 **371**，屏 402）；
    /// 紧凑态传 `230 × 43`，并把 `islandTop` 上提半个高度差，让两种形态竖直居中对齐。
    var islandWidth: CGFloat = 371
    var islandHeight: CGFloat = IslandExpandedMetrics.previewTotalHeight
    /// 岛顶边的额外上提量（pt）。紧凑态比展开态矮，需要上提才与挖孔居中对齐。
    var islandTopLift: CGFloat = 0

    /// ⚠️ 必须声明在最后：`content` 排第一时 memberwise init 也把它排第一，
    ///    `PhoneTopShell(islandWidth: 230) { ... }` 这种尾随闭包写法就编译不过。
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width, 1) / designWidth

            ZStack(alignment: .topLeading) {
                // 机模（屏幕里自带壁纸，不需要额外铺屏幕内容）
                // 浅色 / 深色各一张：有专用图就用专用图，没有退回旧单张。
                Image(MockupArt.name(.home, scheme: colorScheme))
                    .resizable()
                    .frame(width: designWidth, height: designHeight)

                // 灵动岛：顶部与挖孔顶边等高
                content()
                    .frame(width: islandWidth, height: islandHeight, alignment: .top)
                    .offset(x: (designWidth - islandWidth) / 2, y: holeTop - islandTopLift)
            }
            .frame(width: designWidth, height: designHeight, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: designWidth * scale, height: designHeight * scale,
                   alignment: .topLeading)
        }
        .aspectRatio(designWidth / designHeight, contentMode: .fit)
    }
}

// MARK: - 机模底图（浅色 / 深色）

/// 机模底图选择。
///
/// 实时活动的内容是**软件真实渲染**的（与扩展同一份 View），机模只提供机身与壁纸。
/// 深色外观必须配深色壁纸 —— 否则黑色岛屿叠在浅色壁纸上、卡片的液态玻璃按深色渲染，
/// 拼出来是一个真机上不存在的组合。
///
/// 2026-10-30 主人给的四张 16 Pro 真实尺寸机模（1350×2760，白底已抠成透明）：
/// ```
/// 主屏幕   PhoneFrameLight  / PhoneFrameDark
/// 锁屏     LockFrameLight   / LockFrameDark
/// ```
enum MockupArt {
    enum Kind {
        case home, lock

        var light: String {
            switch self {
            case .home: "PhoneFrameLight"
            case .lock: "LockFrameLight"
            }
        }

        var dark: String {
            switch self {
            case .home: "PhoneFrameDark"
            case .lock: "LockFrameDark"
            }
        }
    }

    static func name(_ kind: Kind, scheme: ColorScheme) -> String {
        scheme == .dark ? kind.dark : kind.light
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

    /// ⚠️ 必须最后声明，尾随闭包才成立（同 `PhoneTopShell`）。
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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width, 1) / designWidth

            // 底部对齐：图片底 = 屏幕底，卡片按「距底 148pt」摆，高度交给内容
            ZStack(alignment: .bottom) {
                Image(MockupArt.name(.lock, scheme: colorScheme))
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

    /// 灵动岛外圈描边 = **取件码的颜色**（2026-10-30 主人口径）。
    ///
    /// 它不是装饰：真机的 `keylineTint` 就是让"这个岛和下面那个码是同一件事"的视觉线索，
    /// 所以取色必须与岛内码走同一条路（`islandTint` 亮度插值），不能另取品牌原色 ——
    /// 顺丰那种纯黑在暗壁纸上描边会直接隐形。
    ///
    /// 强度：1pt / 0.85 → **0.8pt / 0.6**。原值在浅色壁纸上是一圈很硬的金边，
    /// 抢过了取件码本身；压到 0.6 后只在边缘留一层色晕，编码颜色仍然读得出来。
    private var islandKeyline: Color { islandTint(islandState.item.tint).opacity(0.6) }
    private let islandKeylineWidth: CGFloat = 0.8

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
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    // 🔴 每页必须撑满容器宽 —— 不给 `maxWidth: .infinity` 时页宽 = 内容宽，
                    //    一页只有 205pt，滑动时相邻两页会同时露出来（截图里左右各半个手机）。
                    page.content
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
            ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                let on = index == previewPage
                Button {
                    withAnimation(.snappy(duration: 0.28)) { previewPage = index }
                } label: {
                    Text(page.title)
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
                .accessibilityLabel(page.title)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
    }

    // MARK: 三页预览（全部由 App 真实渲染）

    /// 每一页 = **机模 + 真实 View**。
    ///
    /// 🔴 2026-10-30 改口径：此前三页贴的是主人从真机截的整图（`RealExpanded` 等），
    ///    真机效果虽权威，但那是**一张死图** —— 换一条待办不会变、深色下还是浅色壁纸、
    ///    而且截图里的卡片是系统渲染的，与我们改过的版式会渐行渐远。
    ///    现在反过来：**内容用与扩展同一份 View 实时渲染**，机模只负责机身与壁纸
    ///    （浅色 / 深色各一张，见 `MockupArt`）。
    private var pages: [(title: String, note: String, content: AnyView)] {
        var list: [(String, String, AnyView)] = []
        if DeviceProfile.hasDynamicIsland {
            list.append(("灵动岛 · 展开",
                         "长按或同时有两个活动时展开，可画面积最大；只画最近一条待办，条数看右上角",
                         AnyView(islandExpandedPage)))
            list.append(("灵动岛 · 紧凑",
                         "同时有两个活动时收成紧凑态：左 App 图标、右「待取 N」，三个以上只剩图标",
                         AnyView(islandCompactPage)))
        }
        list.append(("锁屏卡片",
                     "锁屏上多条待办时取最新一条，其余用「还有 N 条」交代",
                     AnyView(lockScreenPage)))
        return list
    }

    /// 灵动岛 · 展开：黑色岛体 + `IslandExpandedContent`（与 `PickupLiveActivity` 同源）。
    private var islandExpandedPage: some View {
        PhoneTopShell {
            IslandExpandedContent(state: islandState)
                .frame(width: 371, height: IslandExpandedMetrics.previewTotalHeight)
                .background(Color.black, in: .rect(cornerRadius: 46, style: .continuous))
                .overlay {
                    // 真机岛外圈有一道 `keylineTint`（= 取件码颜色），暗壁纸上是唯一的轮廓线索
                    RoundedRectangle(cornerRadius: 46, style: .continuous)
                        .strokeBorder(islandKeyline, lineWidth: islandKeylineWidth)
                }
                // 岛内恒为深色底，品牌色与文字取深色档（与真机一致）
                .environment(\.colorScheme, .dark)
        }
    }

    /// 灵动岛 · 紧凑：左 App 图标 + 右「待取 N」，中间是挖孔。
    ///
    /// 真机上紧凑态是**两块独立画布**（被挖孔隔开），但整岛仍是一块黑色胶囊 ——
    /// 这里按整块黑胶囊画，内容两端对齐，中间本来就是黑的，看不出拼缝。
    private var islandCompactPage: some View {
        PhoneTopShell(islandWidth: 230, islandHeight: 43, islandTopLift: 4) {
            HStack(spacing: 0) {
                IslandCompactLeading(state: islandState)
                Spacer(minLength: 0)
                IslandCompactTrailing(state: islandState)
            }
            .padding(.horizontal, 7)
            .frame(width: 230, height: 43)
            .background(Color.black, in: .capsule)
            .overlay { Capsule().strokeBorder(islandKeyline, lineWidth: islandKeylineWidth) }
            .environment(\.colorScheme, .dark)
        }
    }

    /// 锁屏卡片：`ActivityLockScreenCard` 摆在锁屏机模的实时活动位置。
    private var lockScreenPage: some View {
        LockScreenShell {
            ActivityCardShell(tint: accent) {
                ActivityLockScreenCard(state: multiState)
            }
        }
    }

    private var currentPageTitle: String {
        pages[min(previewPage, pages.count - 1)].title
    }

    private var currentPageNote: String {
        pages[min(previewPage, pages.count - 1)].note
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
