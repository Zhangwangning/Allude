import SwiftUI

// MARK: ============================================================================
// Allude 共享设计基建
//
// 本目录（AlludeShared/）同时加入 **App target** 与 **小组件扩展 target**，
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
    /// 付费面专用橙（2026-10-31 · 订阅页与设置页 PRO 横幅共用）。
    ///
    /// 与主题蓝分开是刻意的：付费面要"热"、要跟内容区拉开距离；
    /// 而 App 内容区的主色仍是图标蓝，不能因为卖东西改成橙的。
    // MARK: 字号（2026-11-01 统一）
    //
    // 🔴 全 App 的**设置类界面**只用这几档，别再随手写 `.system(size: 11.5)`。
    //    起因：主人指出"教程字号太小、设置里大大小小随意来"，盘了一遍发现
    //    9–24 之间散着 18 种字号（还有 10.5 / 11.5 / 12.5 这种没道理的值）。
    //
    // 档位口径（对齐 iOS 设置页的比例）：
    //   行标题 17 · 行副标题 13 · 行尾值 17 · 正文/说明 15 · 分区标题 13 · 注解 12
    // 需要强调时**只加 weight，不加字号**。
    enum TypeScale {
        /// 🔴 2026-11-04 改为**文本样式**（.body / .subheadline …），不再写死点数。
        ///
        /// 原因：设置里的「字体大小」要跟着系统字号体系走。
        /// 写死 `.system(size: 17)` 的字体**不会随 Dynamic Type 缩放**，
        /// 之前只能靠根视图 `.id(...)` 强制重建整棵树 —— 一拖滑块就整页重建，
        /// 导航栈被清空、直接弹回首页（主人当场骂有病，确实是 bug）。
        /// 换成样式后，字号由 `dynamicTypeSize` 环境驱动，改它不会重建视图树。
        ///
        /// 默认档位与原来的点数一一对应：body 17 / subheadline 15 / footnote 13 /
        /// caption 12 / caption2 11。
        static var rowTitle: Font { .system(.body) }
        static var rowTitleMedium: Font { .system(.body, weight: .medium) }
        static var rowSubtitle: Font { .system(.footnote) }
        static var body: Font { .system(.subheadline) }
        static var bodyMedium: Font { .system(.subheadline, weight: .medium) }
        static var section: Font { .system(.footnote) }
        static var note: Font { .system(.caption) }
        static var noteStrong: Font { .system(.caption, weight: .semibold) }
        static var badge: Font { .system(.caption2, weight: .semibold) }
    }

    // MARK: 付费面 · 香槟金（2026-10-31 主人定）
    //
    // 🔴 金色必须**成对用**：浅金只做底，文字一律用深金墨。
    //    白字压在香槟金上对比度只有 2.3:1（远低于 4.5:1 的可读线），
    //    看着像蒙了层雾。所以这里给三个档位，谁也不能单独拿去当文字色。
    /// 香槟金浅档 —— 卡片底、横幅渐变起点
    static let champagneLight = Color(red: 0.98, green: 0.92, blue: 0.79)   // #FAEBC9
    /// 香槟金中档 —— 横幅渐变终点、选中描边、按钮底
    static let champagne      = Color(red: 0.85, green: 0.72, blue: 0.45)   // #D9B873
    /// 深金墨 —— 落在白底或浅金底上的**文字与图标**
    static let champagneInk   = Color(red: 0.44, green: 0.33, blue: 0.11)   // #70541C
    /// 图标底色 —— 比 `champagneInk` 浅一档（2026-10-31 主人：图标太深了）。
    ///
    /// 图标是"实心金色方块 + 白色符号"，所以底色深浅由**白符号的对比度**决定：
    /// ```
    /// #70541C  7.06:1   ← 原值，偏深偏重
    /// #8F6C2E  4.82:1   ← 现在这档，明显轻一档且仍清晰
    /// #A8873F  3.39:1   ← 再浅就开始发虚，别越过这条
    /// #D9B873  1.90:1   ← 白符号几乎看不见，不能用
    /// ```
    static let champagneIcon  = Color(red: 0.56, green: 0.42, blue: 0.18)   // #8F6C2E

    /// 付费面专用：**Apple 系统蓝**（保留，`champagne*` 是当前方案）
    static let appleBlue = Color(.systemBlue)

    static let proOrange      = Color(red: 0.94, green: 0.33, blue: 0.04)   // #F0540A
    static let proOrangeLight = Color(red: 1.00, green: 0.63, blue: 0.16)   // #FFA029

    static let innerRadius: CGFloat = 14
    /// 「最大圆角」—— 胶囊形提示条专用（2026-10-30 主人定：提示类形状圆角给满）。
    ///
    /// `RoundedRectangle` 会把超过半高的圆角自动夹成胶囊形，所以给一个够大的数
    /// 就能拿到「满圆角」，不必为它新造一个 Shape 分支 —— 这样 `cardSurface` 的
    /// 描边与阴影仍走同一条路径，不会出现「填充是胶囊、边框是方块」的错位。
    static let capsuleRadius: CGFloat = 1_000
    static let hInset: CGFloat = 16
    static let cardPadding: CGFloat = 15
    static let listSpacing: CGFloat = 2

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
    /// 卡片品牌色淡染强度。
    /// 2026-11-08 主人：「还是品牌色淡染好看，深了就再淡一些」→ 0.08 → 0.06
    /// （渲染时再 ×1.7 / ×0.5 做对角线渐变）。
    static let cardTintOpacity: Double = 0.06
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
