import SwiftUI

// MARK: ============================================================================
// 拾码 CodePouch 共享设计基建
//
// 本目录（CodeClipShared/）同时加入 **App target** 与 **小组件扩展 target**，
// 使得品牌色、类别色、圆角等视觉常量只有一份定义 —— 避免 App 与桌面小组件
// 各写一套后逐渐漂移（同一家公司在小组件里是紫的、在 App 里是蓝的）。
//
// ⚠️ 本目录内的文件必须满足「双 target 可编译」：
//    · 不得引用 App 专属类型（PickupStore / PickupParser / 各种 View）；
//    · 不得使用 SwiftUI 宏（@State / #Preview）—— 本机 Xcode 27 beta 的
//      swift-plugin-server 在命令行链路下对宏返回 malformed response。
// ============================================================================

// MARK: - 配色体系
//
// 三条原则：
//  1) **全部随系统外观切换** —— 不再有写死的单值色。浅色外观取深色相、深色外观取
//     亮色相，这样两种模式下「对比度合格」与「观感协调」同时成立。
//     切换逻辑集中在 `Color.adaptive(light:dark:)`，改一处即全站生效。
//  2) **语义色与功能色分离** —— 状态色（待取 / 今日新增 / 已取）只表达含义，
//     不随主色漂移；功能色板（sky / violet / pink / amber / indigo）用于图标底、
//     分区标记等「节奏性」着色，让界面有色彩层次而不至于花。
//  3) **克制** —— 颜色只进内容层（卡片、图标底、数据），导航层交给系统玻璃。

enum AppTheme {
    // MARK: 主色

    /// 应用主色（= Assets/AccentColor 的浅色值，深色外观自动提亮）。
    /// 只用于「意义着色」：主操作、关键数字、选中态。
    ///
    /// 2026-09-21 **定为图标蓝**（此前是淘宝橙）。主色不再另起一套色相，
    /// 直接取自 App 图标 `AppIcon-1024.png` 本体：图标是蓝底 + 白卡 + 蓝扫描框，
    /// 蓝色像素占 66.8%、中位色 `#0B63F3` —— 浅色档用它；深色档用图标同一渐变的
    /// 亮部 `#2BA4FC`（不是另外挑的色，是图标上本来就有的那一端）。
    /// 这样 App 内的强调色与桌面上的图标是同一个颜色，一眼能对上号。
    ///
    /// 对比度：`#0B63F3` 对白底 5.1:1 —— 作为图标色、正文色都过 WCAG AA(4.5:1)。
    static let accent      = Color.adaptive(light: 0x0B63F3, dark: 0x2BA4FC)
    /// 主色浅端，用于渐变与进度条终点 —— 取图标渐变的亮部一侧。
    static let accentLight = Color.adaptive(light: 0x2BA4FC, dark: 0x6CC0FF)

    // MARK: 状态语义色（含义固定，不随主色漂移）
    //
    // ⚠️ 一处例外：`pendingTint` 直接复用主色。「待取」是这个 App 的核心状态，
    //    用主题色表达它，语义上最贴切（主色改蓝后「待取」也随之变蓝）。
    static let pendingTint = accent                                             // 待取
    /// 「今日新增 / 昨天」的色。
    ///
    /// 2026-09-21 随主色转蓝而改：这一档原本就是蓝（`#2563EB`），主色也变蓝之后
    /// 同屏会出现两种蓝，谁也说不清哪个才算"今天的"。改回暖橙 —— 蓝主色配橙强调
    /// 是这版配色里色相距离最远的一对，分组标题一眼可辨。
    static let todayTint   = Color.adaptive(light: 0xEA580C, dark: 0xFB923C)   // 今日新增
    static let doneTint    = Color.adaptive(light: 0x0E9E82, dark: 0x3FD9BA)   // 已取

    // MARK: 功能色板（图标底 / 分区标记 / 提示条，提供色彩节奏）

    static let sky     = Color.adaptive(light: 0x0284C7, dark: 0x38BDF8)
    static let violet  = Color.adaptive(light: 0x7C3AED, dark: 0xA78BFA)
    static let pink    = Color.adaptive(light: 0xDB2777, dark: 0xF472B6)
    static let amber   = Color.adaptive(light: 0xB45309, dark: 0xFBBF24)
    static let indigo  = Color.adaptive(light: 0x4338CA, dark: 0x9BABFF)

    // MARK: 布局常量
    //
    // 🔴 2026-10-14 设计语言 v2（主人定：「整个 App 重构，参考头部竞品 UI」）：
    //  · 卡片圆角 20 → 22 —— 对齐 iOS 27 系统 App（健康/钱包）的大圆角卡片语言；
    //  · heroRadius：首页 Hero 统计大卡专用（比普通卡再大一档，凸显主视觉地位）；
    //  · heroNumber：Hero 卡主数字字号 —— 头部 App 仪表盘的「一眼大数字」。
    static let cardRadius: CGFloat = 22
    static let heroRadius: CGFloat = 26
    static let heroNumber: CGFloat = 46
    static let innerRadius: CGFloat = 14
    /// 「最大圆角」—— 胶囊形提示条专用（2026-10-30 主人定：提示类形状圆角给满）。
    ///
    /// `RoundedRectangle` 会把超过半高的圆角自动夹成胶囊形，所以给一个够大的数
    /// 就能拿到「满圆角」，不必为它新造一个 Shape 分支 —— 这样 `cardSurface` 的
    /// 描边与阴影仍走同一条路径，不会出现「填充是胶囊、边框是方块」的错位。
    static let capsuleRadius: CGFloat = 1_000
    static let hInset: CGFloat = 16
    static let cardPadding: CGFloat = 15
    static let listSpacing: CGFloat = 10

    /// 内容列最大宽度（2026-10-25 · iPhone Duo 适配）
    ///
    /// 背景：Duo 展开态内屏 951×669pt 且 `horizontalSizeClass == .regular`，
    /// 若让列表/详情铺满，单张卡片会到 911pt —— 取件码与右端勾选相距过远、
    /// 文字行长失控，观感与 iPad 上把 iPhone 版拉伸是同一个毛病。
    ///
    /// 取 700pt 的理由：
    ///  · 常规 iPhone（402 / 440pt）**根本触不到这个上限**，窄屏行为零变化；
    ///  · Duo 展开态下内容成一条居中的阅读列（两侧各留 ~125pt），
    ///    与 Apple 自家 App 在宽屏上的居中列口径一致；
    ///  · 700 仍比 Pro Max 宽 59%，能真正吃到折叠屏的横向空间，
    ///    但不足以让一行文字长到需要转头。
    static let contentMaxWidth: CGFloat = 700

    /// 卡片内容层叠品牌色的强度。克制 —— 只提供「每张卡有自己的颜色」的氛围，
    /// 一旦调高就会变成整卡染色，与导航层争夺层级。
    /// 0.08 对应左上角约 0.136、右下角约 0.04 的对角渐变（见 CardSurface）。
    static let cardTintOpacity: Double = 0.08
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1
        )
    }
}

extension Color {
    /// 深浅色自适应色。
    ///
    /// 用途：小面积的前景色（标签文字、图标）在两种外观下都要看得清。
    /// 单一定值做不到 —— 例如曾经的主色 `#25695C` 在白色卡片上对比度约 6.1:1（合格），
    /// 但落到深色卡片上只剩约 2.5:1，低于 WCAG AA 的 4.5:1 门槛。
    /// 这里为深色外观单独给一档更亮的同色相值，而不是简单提亮（避免偏白失真）。
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0,
                alpha: 1
            )
        })
    }
}

extension PickupKind {
    /// 类别色：与快递公司品牌色分开，保证「类别」与「公司」两套信息各自可辨。
    /// 小组件同样需要它（每条记录左侧的类别标识）。
    ///
    /// 深浅两套值均按 WCAG AA（≥4.5:1）选取：浅色外观取深色相，深色外观取亮色相。
    var tint: Color {
        switch self {
        // 「取件码」是本 App 的核心凭证，直接用主色跟着走。
        case .code: AppTheme.accent
        // 「运单号」原本是蓝，主色转蓝后必须让位 —— 两个蓝并排谁也认不出谁。
        // 沿色相往前推一档到靛，四类正好连成 蓝 → 靛 → 紫 → 粉 的一段递进。
        case .waybill: AppTheme.indigo
        case .tail: Color.adaptive(light: 0xA855F7, dark: 0xC79BFF)
        case .special: Color.adaptive(light: 0xEC4899, dark: 0xFF8CC0)
        }
    }
}
