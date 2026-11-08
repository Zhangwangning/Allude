import SwiftUI
import UIKit
import WidgetKit

// MARK: ============================================================================
// 小组件预览（App 内 · 真实渲染）
//
// 背景：桌面小组件在模拟器 / CI 里**无法脚本化添加**，唯一能拿到「真实渲染证据」的
// 办法，是在 App 内用**同一份视图代码**（`CodeClipShared/WidgetVisuals.swift`）
// 按小组件尺寸渲染一次。因此这里不是手工复刻，是同一份实现。
//
// 两处使用：
//   1) 「设置 › 桌面小组件」二级页 —— 开关下方直接铺开全部尺寸（2026-09-22 起，
//      不再套「查看全部尺寸」的第二跳）；
//   2) `SCREEN=widgets` 命令行入口 —— 深/浅两套外观的验收截图都从这里出。
//
// 尺寸按设备过滤：iPhone 上没有 iPad 超大（690pt 宽）那一档，装在哪就渲染哪套；
// 截图定位：`WIDGET_SIZE` 只渲染指定的那一块 —— 五个尺寸全铺出来是好几屏，
// 一张截图只能拍到最上面一屏，靠滚动取证等于没取证。
//
// ⚠️ 本文件不得使用 SwiftUI 宏（#Preview / @State），原因见 DesignSystem.swift 顶部。
// ============================================================================

// MARK: - 仿真小组件容器

/// 把共享视图装进一个「长得像小组件」的框里。
///
/// 尺寸取 iOS 常见取值 —— 真实值随机型与主屏缩放略有出入，这里只求版式比例正确。
/// 内边距 16pt 对应 WidgetKit 默认给内容的 margin。
///
/// 预览**不响应点击**：勾选框与翻页控件在真实小组件里由 AppIntent 直接写数据，
/// 而在 App 内预览时点击既不会更新界面、又会让内存副本与文件不一致，
/// 因此整块 `allowsHitTesting(false)`，只作视觉对照。
struct WidgetCanvas: View {
    enum Style: String, CaseIterable {
        case small
        case medium
        case large
        case extraLarge
        case extraLargePortrait

        /// 🔴 2026-11-08 主人：预览必须和桌面上真实大小一致。
        ///
        /// 原来写死 158 / 338 / 354 —— 那是 **390pt 屏**（iPhone 12/13/14 标准版）的数值。
        /// 系统小组件是按屏宽等比缩放的，402pt（16 Pro）、430pt（Pro Max）上会更大，
        /// 于是预览永远比真机小一圈。
        ///
        /// 基准值 158 / 338 / 354 是 iPhone 15·16 Pro（**393pt**）实测，按屏宽等比缩放。
        /// 预览尺寸（2026-11-08 回滚到「之前看着合适」的那组固定值）。
        ///
        /// 教训：我按屏宽比例缩放 + 读实测值，把这一页改坏了两版。
        /// 固定 158 / 338 / 354 是当年在真机上对过、主人认可的观感，
        /// 在没拿到可靠真机数据之前不要动它。
        var size: CGSize {
            switch self {
            case .small:  CGSize(width: 158, height: 158)
            case .medium: CGSize(width: 338, height: 158)
            case .large:  CGSize(width: 338, height: 354)
            case .extraLarge: CGSize(width: 690, height: 354)
            case .extraLargePortrait: CGSize(width: 338, height: 690)
            }
        }

        var title: String {
            switch self {
            case .small: "小尺寸 · 最多 4 条"
            case .medium: "中尺寸 · 3 条/页"
            case .large: "大尺寸 · 8 条/页"
            case .extraLarge: "iPad 超大 · 6 条/页"
            case .extraLargePortrait: "iPhone 竖版超大 · 14 条/页"
            }
        }

        /// 与 `WidgetPageSize.key(_:)` 同一口径 —— 预览里的翻页控件要读到真的那一页
        var pageKey: String {
            switch self {
            case .small: "s"
            case .medium: "m"
            case .large: "l"
            case .extraLarge: "xl"
            case .extraLargePortrait: "xlp"
            }
        }

        /// 宽于手机屏的尺寸（iPad 超大）需要横向滚动才看得到右半部分
        var overflowsPhoneWidth: Bool { size.width > 360 }

        /// 对应的系统尺寸 —— 用来和 `WidgetPageSize.supportedFamilies` 对档位过滤
        var family: WidgetFamily {
            switch self {
            case .small: .systemSmall
            case .medium: .systemMedium
            case .large: .systemLarge
            case .extraLarge: .systemExtraLarge
            case .extraLargePortrait:
                // 竖版超大是 iOS 27 新增；低版本回落到同尺寸的横版枚举只为比对档位，
                // 实际展示由 `supportedFamilies` 过滤掉，不会出现在系统小组件库里。
                if #available(iOS 27.0, *) {
                    .systemExtraLargePortrait
                } else {
                    .systemExtraLarge
                }
            }
        }
    }

    let style: Style
    let content: AnyView

    /// `expandsToFill`：宽度吃满父视图（高度仍按 `style.size.height`）。
    /// 设置页的「效果预览」只有一块、上面没有并排的兄弟视图，按固定 338pt 摆会
    /// 左右各空 16pt 显得又瘦又小（2026-10-27 主人：「左右再加长一点点」）；
    /// 图库里是多尺寸纵向排列，必须保持真实尺寸，所以默认仍是固定宽。
    var expandsToFill: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    init<Content: View>(_ style: Style,
                        padding: CGFloat = 16,
                        expandsToFill: Bool = false,
                        @ViewBuilder content: () -> Content) {
        self.style = style
        self.expandsToFill = expandsToFill
        self.content = AnyView(content().padding(padding))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    var body: some View {
        content
            .frame(maxWidth: expandsToFill ? .infinity : nil, alignment: .topLeading)
            .frame(width: expandsToFill ? nil : style.size.width,
                   height: style.size.height,
                   alignment: .topLeading)
            // 与真实 WidgetKit 小组件同一套外观：实体底色 + 顶部主色氛围渐变，
            // 不给小组件叠玻璃（玻璃只用于 App 的导航层）。
            .background {
                Color(.secondarySystemBackground)
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [AppTheme.accent.opacity(0.10), .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 88)
                    }
            }
            .clipShape(shape)
            // 🔴 2026-11-08 主人：预览和页面背景分不清 —— 给一张**软阴影 + 发丝描边**，
            //    这是 iOS 系统里「浮起卡片」的标准做法（比加深底色更像真机）。
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.10),
                    radius: 12, y: 6)
            .overlay {
                shape.stroke(.primary.opacity(colorScheme == .dark ? 0.10 : 0.06),
                             lineWidth: 0.5)
            }
            // 🔴 描边 + 阴影（2026-10-27 主人：「下面都融在一起看不见底了」）：
            // `secondarySystemBackground` 与设置页的 `systemGroupedBackground`
            // 在浅色下几乎是同一个浅灰白，没有分离手段时小组件下边缘直接消失。
            // 做法是两道都很轻：0.5pt 极淡描边负责"边界"，柔阴影负责"浮起"。
            .overlay {
                shape.strokeBorder(Color(.separator).opacity(colorScheme == .dark ? 0.55 : 0.35),
                                   lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.50 : 0.12),
                    radius: 12, y: 5)
            .allowsHitTesting(false)
    }
}

// MARK: - 全部尺寸目录（预览页与设置二级页共用）

/// 「所有尺寸的小组件效果」这一块内容。
///
/// 从设置二级页与 `SCREEN=widgets` 入口两处抽出来的公共体 ——
/// 渲染口径（同一份代码、同设备尺寸）只有这一份，铺开处各自包壳。
///
/// 🔴 **2026-09-23 改口径：一律用示例数据，不再读用户的待取件。**
///
/// 起因是主人报的问题：这一页原先是「用你自己的数据渲染真实观感」，
/// 但用户把件取完之后，设置页里整页预览全变成空态 ——
/// 「小组件长什么样」这个页面在**最需要看它的时候**（想确认版式/想挑模板）
/// 恰好什么都没有，等于把预览做废了。
/// 现在这里永远铺 8 条示例记录：它展示的是**版式**，不是**你的数据**。
struct WidgetGalleryContent: View {
    /// 显示内容配置。设置页传用户当前选择，使预览与桌面所见一致；
    /// 不传时按当前档位取生效配置（免费版恒为完整形态）。
    var options: WidgetDisplayOptions? = nil

    private var effectiveOptions: WidgetDisplayOptions {
        options ?? WidgetDisplayOptions.full
    }

    /// 示例快照：8 条，跨两页 —— 只有超过一页才看得出翻页控件对不对。
    private var snapshot: WidgetSnapshot { .preview() }

    /// **只按设备过滤，不按档位裁剪**（2026-11-01 主人）。
    ///
    /// 原来免费版会把大尺寸整块藏掉，理由是不想让人到系统图库里找不到；
    /// 但主人的口径是：**这里就应该把所有尺寸都摆出来**，
    /// 免费版/拾码 Pro 的差别是"能不能用"，不是"看不看得到"。
    /// 所以现在全部渲染，付费档才有的尺寸挂一个「拾码 Pro」标记并说明。
    ///
    /// 仍保留设备过滤：iPad 超大只存在于 iPad 桌面，iPhone 上渲染它等于展示一个加不出来的尺寸。
    private var styles: [WidgetCanvas.Style] {
        UIDevice.current.userInterfaceIdiom == .pad
            ? WidgetCanvas.Style.allCases
            : WidgetCanvas.Style.allCases.filter { $0 != .extraLarge }
    }

    /// 该尺寸在当前档位能不能用。免费版只有小 / 中（`WidgetPageSize.supportedFamilies`）。
    private func isLocked(_ style: WidgetCanvas.Style) -> Bool {
        !WidgetPageSize.supportedFamilies.contains(style.family)
    }

    /// 内容区实测宽度（用来把小尺寸的左缘对齐到中尺寸卡片的左缘）
    @State private var contentWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("待取件")
                .font(.headline)
                .padding(.top, 2)

            // 档位说明（2026-11-01 主人）：这里展示**全部尺寸**，
            // 免费版与拾码 Pro 的差别只是"能不能加到桌面"，不是"看不看得到"。

            ForEach(styles, id: \.rawValue) { style in
                block(title: style.title) {
                    // 🔴 2026-11-08 主人：除小尺寸外一律**水平居中**；
                    //    小尺寸保持左对齐（与上方的分区标题同一条左边缘）。
                    HStack(spacing: 0) {
                        // 🔴 2026-11-08 主人：小尺寸要和中尺寸的**左缘**对齐。
                        //    中尺寸是居中的，左缘 = (内容宽 − 中宽) / 2，小尺寸补同样的左缩进。
                        if style == .small {
                            let inset = max(0, (contentWidth - WidgetCanvas.Style.medium.size.width) / 2)
                            Spacer().frame(width: inset)
                        } else {
                            Spacer(minLength: 0)
                        }

                        ZStack(alignment: .topTrailing) {
                            canvas(style: style, snapshot: snapshot)
                                .opacity(isLocked(style) ? 0.55 : 1)
                                // 🔴 2026-11-08：尺寸从「估值」切到「实测」时会发生一次
                                //    隐式过渡，动画中间帧看起来像两层文字叠在一起（乱套）。
                                //    预览尺寸变化不需要动画，直接关掉。
                                .transaction { $0.animation = nil }

                            if isLocked(style) {
                                proBadge
                                    .padding(8)
                            }
                        }

                        if style != .small { Spacer(minLength: 0) }
                    }
                }
            }

            block(title: "空态：一件待取都没有时") {
                HStack(spacing: 16) {
                    WidgetCanvas(.small) {
                        WidgetEmptyContent(pickedTodayCount: 0, compact: true)
                    }
                    Spacer(minLength: 0)
                }
            }

            if !EntitlementSnapshot.licensedPro {
                Text("小、中两种尺寸可直接添加，桌面最多显示 \(PickupLimits.freeVisible) 条待取。")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("以上为示例数据；桌面上的小组件显示你的真实记录。")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            contentWidth = width
        }
    }

    @ViewBuilder
    private func canvas(style: WidgetCanvas.Style,
                        snapshot: WidgetSnapshot) -> some View {
        let content = WidgetCanvas(style) { widgetBody(style: style, snapshot: snapshot) }
        if style.overflowsPhoneWidth {
            // iPad 超大比手机屏还宽，不套横向滚动就只能看到左半截
            ScrollView(.horizontal, showsIndicators: false) { content }
        } else {
            content
        }
    }

    @ViewBuilder
    private func widgetBody(style: WidgetCanvas.Style, snapshot: WidgetSnapshot) -> some View {
        let compact = style == .small
        if snapshot.isEmpty {
            WidgetEmptyContent(pickedTodayCount: snapshot.pickedTodayCount,
                               compact: compact)
        } else if compact {
            WidgetSmallContent(snapshot: snapshot, options: effectiveOptions)
        } else {
            WidgetPagedContent(snapshot: snapshot,
                               pageSize: WidgetPageSize.rowCount(family: style.pageKey),
                               familyKey: style.pageKey,
                               options: effectiveOptions)
        }
    }

    /// 档位说明。命名按主人定的：免费版 = 拾码 CodePouch，付费版 = 拾码 Pro。
    private var proBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .bold))
            Text("拾码 Pro")
                .font(AppTheme.TypeScale.badge)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppTheme.amber, in: .capsule)
    }

    private func block<Content: View>(title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.L)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

// MARK: - 预览页（SCREEN=widgets 截图入口）

struct WidgetPreviewGallery: View {
    /// 截图定位：只渲染指定尺寸
    private var onlyStyle: WidgetCanvas.Style? {
        WidgetCanvas.Style(rawValue: ProcessInfo.processInfo.environment["WIDGET_SIZE"] ?? "")
    }

    /// 是否处于 `SIMCTL_CHILD_SCREEN` 截图模式
    private var screenshotMode: Bool { ProcessInfo.processInfo.environment["SCREEN"] != nil }

    /// 截图脚手架 `DISPLAY=full|codeOnly|companyOnly|stationOnly` 由
    /// `CodeClipApp.init()` 直接写进 App Group（走的是正式链路，
    /// 所以设置页与这里看到的是同一份配置，不是两个特例）。

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let style = onlyStyle {
                    // 单块模式：截图验收用（示例数据，与目录页同一口径）
                    VStack(alignment: .leading, spacing: 10) {
                        Text("待取件 · \(style.title)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)

                        WidgetCanvas(style) {
                            galleryBody(style: style, snapshot: .preview())
                        }
                    }
                } else {
                    WidgetGalleryContent()

                    // 命令行验证专用：真实数据往往缺少「极端组合」，这里用示例数据压测一次 ——
                    // 最长凭证（15 位运单号）与最长标签（「特殊取件码」）同页出现时不折行、不溢出。
                    if screenshotMode {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("压测：最长凭证 + 最长标签同页")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)

                            WidgetCanvas(.medium) {
                                WidgetPagedContent(snapshot: .preview(),
                                                   pageSize: WidgetPageSize.rowCount(family: "m"),
                                                   familyKey: "m")
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("桌面小组件")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 单块模式的渲染体：与目录页同一份分发逻辑。
    @ViewBuilder
    private func galleryBody(style: WidgetCanvas.Style, snapshot: WidgetSnapshot) -> some View {
        let options = WidgetDisplayOptions.full
        let compact = style == .small
        if snapshot.isEmpty {
            WidgetEmptyContent(pickedTodayCount: snapshot.pickedTodayCount,
                               compact: compact)
        } else if compact {
            WidgetSmallContent(snapshot: snapshot, options: options)
        } else {
            WidgetPagedContent(snapshot: snapshot,
                               pageSize: WidgetPageSize.rowCount(family: style.pageKey),
                               familyKey: style.pageKey,
                               options: options)
        }
    }
}
