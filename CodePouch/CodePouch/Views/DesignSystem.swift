import SwiftUI
import Combine
import PhotosUI

// MARK: ============================================================================
// 拾码 CodePouch 设计系统（App 专属组件）
//
// 依据 iOS 27 Liquid Glass 官方规则落地，三条硬约束：
//
//  1) 玻璃只用于「浮在内容之上的导航层」——系统标签栏、浮动提示条、独立浮起的主操作。
//     原文：「Liquid Glass is best reserved for the navigation layer that floats above
//     the content of your app.」把玻璃用在内容卡片上会与导航层争夺层级、
//     且在「降低透明度 / 增强对比度」下退化。
//
//  2) 内容层（卡片 / 列表行 / 数据）一律实体填充，且「第二层不再叠玻璃」。
//
//  3) 颜色要注入内容层——原文：「When every element is tinted, nothing stands out…
//     imbue color into your app… in the content layer instead.」
//     所以快递公司品牌色、状态色、关键数字着色全部落在卡片内部，而不是给导航铬上色。
//
// ── 已知例外（都是主人明确要求，不是漏网） ────────────────────────────────
//  `RecordDetailView` 的顶部主卡与主操作按钮**确实用了玻璃**，与本文件第 1/2 条相悖：
//    · 卡底 = 品牌色磨砂玻璃（`BrandPalette` 渐变 + `.ultraThinMaterial`）
//      —— 这里是「以材质表达品牌身份」，不是与导航层争层级。
//    · 主按钮 = 液态玻璃（`glassEffect(.regular.tint(...).interactive())`）
//      —— 等价于系统 `.glassProminent`；已取件态退成 `.regular` 中性玻璃，因为它不是主动作。
//  两处都只出现在详情页的**唯一一张主卡**上，不构成「层层叠玻璃」。逐条理由写在
//  `RecordDetailView.swift` 文件头与 `actionGlass` 注释里。
//
// ── 与共享层的分工 ────────────────────────────────────────────────────────
//  本文件只放 **App 专属** 组件。以下几项已移至 `CodeClipShared/`，与小组件扩展共用：
//    · AppTheme / Color(hex:) / PickupKind.tint  → CodeClipShared/AppTheme.swift
//    · CourierBrand / CourierLogo                → CodeClipShared/CourierBrand.swift
// ============================================================================

// MARK: - 内容层卡片（实体填充 + 发丝描边 + 极轻投影，不使用玻璃）

struct CardSurface: ViewModifier {
    var radius: CGFloat = AppTheme.cardRadius
    var tint: Color? = nil

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    // 🔴 卡片 = **白**（浅色）/ #1C1C1E（深色），页面底 = 浅灰。
                    //
                    // 2026-09-23 修正：这里原先填 `.background.secondary`，
                    // 而各列表页都开了 `.scrollContentBackground(.hidden)`，
                    // 于是渲染成「白底 + 灰卡」，与 iOS 分组列表规范正好相反。
                    // 改用 `secondarySystemGroupedBackground` —— 它就是
                    // 「分组列表里的卡片色」这条语义，浅色下为纯白，
                    // 深色下与 `.background.secondary` 同值，深色观感不变。
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay {
                        if let tint {
                            // 品牌色以对角线渐变铺在卡面上：左上角颜色最足、右下角褪去。
                            // 强度受 AppTheme.cardTintOpacity 统一约束，避免退化成「整卡染色」。
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [tint.opacity(AppTheme.cardTintOpacity * 1.7),
                                                 tint.opacity(AppTheme.cardTintOpacity * 0.5)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    // v2：描边压轻一档（0.55 → 0.4）—— 大圆角卡靠「底色差 + 柔投影」
                    // 分层已经足够，重描边会让卡片看起来「被框住」。
                    .stroke(.separator.opacity(0.4), lineWidth: 0.5)
            }
            // v2：投影更柔更大（r7→r11, y2→y3, α0.05→0.06）——
            // 大圆角卡片配大半径软投影，是 iOS 27 系统 App 的卡片质感。
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06),
                    radius: colorScheme == .dark ? 0 : 11, x: 0, y: 3)
    }
}

// MARK: - 彩色圆底图标
//
// iOS 系统 App（健康 / 健身 / 设置）里最常见的一种「着色单位」：圆形浅色底 + 同色相图标。
// 比起裸图标，它让每一块信息有自己的颜色身份，一眼可分辨，且不喧宾夺主。

struct IconBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.15))
            Image(systemName: symbol)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

extension View {
    func cardSurface(radius: CGFloat = AppTheme.cardRadius,
                     tint: Color? = nil) -> some View {
        modifier(CardSurface(radius: radius, tint: tint))
    }
}

// MARK: - 卡片内直接完成取件（核心交互，无需进入详情页）

/// 圆形勾选控件：轻点即在卡片内完成 / 取消取件状态。
/// 命中区固定 44×44pt 以满足 HIG 最小可点尺寸。
struct CompleteButton: View {
    let isDone: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isDone ? tint : Color.secondary.opacity(0.5),
                                  lineWidth: 1.8)
                    .frame(width: 27, height: 27)

                Circle()
                    .fill(tint)
                    .frame(width: 27, height: 27)
                    .scaleEffect(isDone ? 1 : 0.2)
                    .opacity(isDone ? 1 : 0)

                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(isDone ? 1 : 0.3)
                    .opacity(isDone ? 1 : 0)
            }
            .frame(width: 44, height: 44)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDone ? "已取件，轻点可恢复为待取件" : "标记为已取件")
    }
}

// MARK: - 类别标签（已于 2026-10-28 删除）
//
// 原来这里有个 `KindTag`：按凭证类型（取件码 / 运单号 / 尾号 / 特殊码）画彩色胶囊。
// 主人 2026-10-28 定：「拾码内再不区分取件码信息的类型」——
// 所有卡片、预览、编辑、通知、锁屏一律只认「取件码」，分类退化成纯后台字段，
// 于是这个组件没有任何调用点，整体删除。要恢复分类展示时别急着照抄旧样式：
// 先想清楚「用户拿到这条信息时真的需要知道它是哪类凭证吗」。

// MARK: - 虚线分隔（信息层 / 数据层的分界）

/// 一条虚线把「平台 + 地址」（信息层）与「取件码」（数据层）分开。
///
/// 取件码是整张卡片唯一需要「一眼读出」的内容。与其不断加大字号去争视觉权重，
/// 不如先用一条虚线把它单独分区 —— 分区之后即便字号只比正文大一档，
/// 眼睛也能立刻锁定它。这是成熟取件码 App 通行的信息分层手法。
struct DashedDivider: View {
    var body: some View {
        HorizontalRule()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3.5, 3.5]))
            .foregroundStyle(Color.secondary.opacity(0.3))
            .frame(height: 1)
    }
}

/// 水平直线 —— 虚线的可描边载体（SwiftUI 没有内置虚线分隔视图）
private struct HorizontalRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return path
    }
}

// MARK: - 票券撕票线（虚线 + 两侧打孔）
//
// 设计语言 v2（2026-10-14，借鉴车票票的票面质感）：把普通卡片变成「票」的关键
// 就是这条撕票线 —— 虚线两侧各嵌一枚「打孔」半圆（填页面底色、外溢出卡边），
// 上下两层信息像被撕开的票根。纸质票 / 钱包 Pass / 车票票都用这一视觉母语。
struct TicketPunchLine: View {
    /// 打孔直径（外溢一半，露出半圆缺口）
    private let punch: CGFloat = 13

    var body: some View {
        DashedDivider()
            .overlay {
                HStack(spacing: 0) {
                    Circle()
                        .fill(Color(.systemGroupedBackground))
                        .frame(width: punch, height: punch)
                        .offset(x: -punch / 2)
                    Spacer(minLength: 0)
                    Circle()
                        .fill(Color(.systemGroupedBackground))
                        .frame(width: punch, height: punch)
                        .offset(x: punch / 2)
                }
            }
            .frame(height: punch)
    }
}

// MARK: - 支持的快递图标总览
//
// 把共享层的品牌清单可视化，既方便自查，也是「30+ 家快递覆盖」这一卖点的直观呈现。

struct CourierGalleryView: View {
    /// 这一页管哪种东西（2026-10-27 主人：拆成「快递公司」与「驿站管理」两个模块）。
    /// 原先是**一页全包**（快递公司 / 驿站·代收平台 / 智能快递柜 / 商家 / 国际快递），
    /// 设置里只有一行「快递管理」，用户既不知道里面有什么、也不知道驿站自定义在哪。
    /// 拆开之后：承运方归 `.courier`，取件地点归 `.station`，各自只显示自己那几类和自己的说明。
    enum Scope {
        /// 承运方：快递公司 / 国际快递 / 商家·电商
        case courier
        /// 取件地点：驿站·代收平台 / 智能快递柜（含自定义驿站增删）
        case station

        var categories: [CourierBrand.Category] {
            switch self {
            case .courier: [.company, .international, .merchant]
            case .station: [.station, .locker]
            }
        }

        var title: String {
            switch self {
            case .courier: "快递公司"
            case .station: "驿站管理"
            }
        }
    }

    var scope: Scope = .courier

    /// 截图脚手架用：指定则进入后直接滚到该分类（分类越来越多，一屏放不下）
    var anchor: String? = nil

    private let columns = [GridItem(.adaptive(minimum: 68), spacing: 10)]

    /// 驿站名称库（2026-10-14 集成进本页）：自定义增删后页面即时刷新
    @ObservedObject private var station = StationDirectory.shared

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
            }
            .onAppear {
                guard let anchor else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    proxy.scrollTo(anchor, anchor: .top)
                }
            }
        }
        .navigationTitle(scope.title)
        .cloaksTabBar()
        .navigationBarTitleDisplayMode(.inline)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            summary

            ForEach(scope.categories) { category in
                let items = CourierBrand.items(in: category)
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: category.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                            Text(category.rawValue.L)
                                .font(.footnote.weight(.semibold))
                            // 驿站分类把自定义格子数并进去（网格里实际有多少格就显示多少）
                            Text(category == .station
                                 ? "\(items.count + station.customNames.count)"
                                 : "\(items.count)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 4)

                        LazyVGrid(columns: columns, spacing: 14) {
                            // 驿站分类第一格 = 添加入口（驿站图标 + 加号）；
                            // 其后跟用户自定义的驿站，最后才是内置品牌。
                            // （2026-10-14 主人定稿：驿站管理融进网格，不要顶部列表）
                            if category == .station {
                                addStationCell
                                ForEach(station.customNames, id: \.self) { name in
                                    customStationCell(name)
                                }
                            }
                            ForEach(items) { item in
                                brandCell(item)
                            }
                        }
                        .padding(14)
                        .cardSurface()
                    }
                    .id(category.rawValue)
                }
            }

            // 版权说明只对「品牌图标」有意义；驿站页那句换成自定义入口的提示
            Text(scope == .courier
                 ? "品牌图标版权归各公司所有，此处仅用于标识取件来源；未收录的品牌按名称自绘色块兜底，不会出现空白。"
                 : "点网格里的「添加驿站」可新增自定义名称与图标，匹配时按名称最长命中。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AppTheme.hInset)
        .padding(.top, 8)
        .padding(.bottom, 110)
    }

    private var summary: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((scope == .courier ? AppTheme.accent : AppTheme.indigo).opacity(0.13))
                    .frame(width: 52, height: 52)
                Image(systemName: scope == .courier ? "shippingbox.fill" : "storefront.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(scope == .courier ? AppTheme.accent : AppTheme.indigo)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(scope == .courier
                     ? "内置 \(courierCount) 个承运方图标"
                     : "内置 \(stationCount) 个取件地点图标")
                    .font(.subheadline.weight(.semibold))
                Text(scope == .courier
                     ? "未收录的快递按名称自动生成图标"
                     : "驿站名称可自定义，添加后按名字自动匹配短信里的取件地点")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .cardSurface()
    }

    /// 承运方品牌数（三个分类合计）
    private var courierCount: Int {
        Scope.courier.categories.reduce(0) { $0 + CourierBrand.items(in: $1).count }
    }

    /// 取件地点品牌数（驿站 + 快递柜）
    private var stationCount: Int {
        Scope.station.categories.reduce(0) { $0 + CourierBrand.items(in: $1).count }
    }

    // MARK: 品牌网格格子

    /// 内置品牌格子（全分类通用）
    ///
    /// 🔴 网格里 **53+ 个图标全部关掉投影**（`showsShadow: false`）：
    /// 投影是离屏渲染，滚动时每帧要为每个可见图标重算一遍，
    /// 主人反馈「快递公司 / 驿站管理一点开就掉帧严重」——根因就在这里。
    /// 54pt 图标压在白色卡面上，投影本来就几乎看不见，关掉无观感损失。
    private func brandCell(_ item: CourierBrand.Info) -> some View {
        VStack(spacing: 7) {
            CourierLogo(info: item, size: 54, showsShadow: false)
            Text(item.name.L)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 26, alignment: .top)
        }
    }

    /// 驿站分类第一格：**添加入口** —— 圆角矩形（与内置图标同圆角同尺寸）+ 中心十字。
    /// 刻意与 brandCell 完全同构（VStack：54pt 方块 + 双行文字位）—— LazyVGrid 里
    /// 结构差异过大的格子会算错 ideal size，曾有复杂版式被整格跳过不渲染。
    /// 点按 → 独立编辑页（名称 + 图标同页填，2026-10-15 主人定稿）。
    private var addStationCell: some View {
        NavigationLink {
            StationEditView(mode: .add)
        } label: {
            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 54 * 0.29, style: .continuous)
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: 54, height: 54)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }

                Text("添加驿站")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.accent)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 26, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("添加自定义驿站")
    }

    /// 自定义驿站格子：有自定义图标显示图片（统一圆角矩形），没有则按名兜底图标；
    /// 点按 → 独立编辑页（改名 / 换图 / 删除同页）
    private func customStationCell(_ name: String) -> some View {
        NavigationLink {
            StationEditView(mode: .edit(name))
        } label: {
            VStack(spacing: 7) {
                StationLogo(name: name, size: 54, showsShadow: false)
                Text(name.L)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 26, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name)，轻点编辑")
    }
}

// MARK: - 自定义驿站图标（有图用图、无图兜底，统一圆角矩形）

/// 自定义驿站格子 / 卡片上的驿站图标。
/// 2026-10-15 主人定稿：自定义驿站支持上传图标，「无论上传什么图片，
/// 都以圆角矩形显示」—— 图片分支与兜底分支走同一套圆角（0.29×size）与描边，
/// 保证网格里任何来源的图标观感一致。
struct StationLogo: View {

    let name: String
    var size: CGFloat = 54
    /// 是否画投影（2026-10-28 加，同 `CourierLogo`）：网格里关掉，单处展示保留
    var showsShadow: Bool = true

    /// 订阅图标增删（相册选完即时刷新）
    @ObservedObject private var station = StationDirectory.shared

    private var corner: CGFloat { size * 0.29 }

    @ViewBuilder
    var body: some View {
        if let image = station.iconImage(for: name) {
            let base = Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(.primary.opacity(0.10), lineWidth: 0.5)
                }
            // 与 CourierLogo 的投影同规格，有图无图观感一致；
            // 网格里传 false —— 几十个离屏阴影就是滚动掉帧的元凶。
            if showsShadow {
                base.shadow(color: .black.opacity(0.28),
                            radius: size * 0.14, x: 0, y: size * 0.06)
                    .accessibilityLabel("\(name) 的自定义图标")
            } else {
                base.accessibilityLabel("\(name) 的自定义图标")
            }
        } else {
            CourierLogo(company: name, size: size, showsShadow: showsShadow)
        }
    }
}

// MARK: - 复制取件码按钮（内容层实体着色，不叠玻璃）

struct CopyCodeButton: View {
    let isCopied: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isCopied ? .white : tint)
                .frame(width: 34, height: 34)
                .background {
                    Circle().fill(isCopied ? tint : tint.opacity(0.15))
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCopied ? "已复制取件码" : "复制取件码")
    }
}

// MARK: - 分组标题

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    /// 可选彩色前置图标：给分区一个颜色身份（标题本身仍保持次级灰，避免整屏都在喊）
    var symbol: String? = nil
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let symbol, let tint {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(title.L)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            if let trailing {
                Text(trailing.L)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
    }
}

// MARK: - 时间分组的颜色身份（首页分区标题使用）

extension DayGroup {
    var tint: Color {
        switch self {
        case .today: AppTheme.accent
        case .yesterday: AppTheme.todayTint
        case .earlier: AppTheme.violet
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .yesterday: "clock.fill"
        case .earlier: "calendar"
        }
    }
}

// MARK: - 浮动操作提示条（浮在内容之上 → 这里用玻璃是符合规则的）

struct UndoToast: View {
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.doneTint)

            Text(message.L)
                .font(.subheadline)

            Spacer(minLength: 8)

            Button(actionTitle, action: action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .appGlass(.capsule)
    }
}

// MARK: - 顶栏矢量图标（添加 / 扫描）
//
// 两个图标都按设计稿给定的 48×48 网格逐点还原，而不是拿相近的 SF Symbol 顶上 ——
// 「三条等长文本行」「圆圈加号」这些细节正是它们与其他同类别图标的区别所在。
//
// 颜色一律不写死：Shape 只负责描边，颜色由 `foregroundStyle` 决定。
// 放进顶栏后与相邻的「筛选」一样走系统默认前景色，因此深浅色模式自动切换，
// 也与系统图标尺寸口径一致。
//
// 尺寸统一走同一个 `size`：内容占位按各自设计稿的比例换算（扫描框 36/48、
// 圆 40/48），线宽同样按 4/48 换算 —— 所以两个图标并排时粗细与重量是一致的。

/// 设计稿统一的 48×48 网格 → 实际尺寸换算
private struct GlyphGrid {
    private let origin: CGPoint
    private let scale: CGFloat

    init(rect: CGRect) {
        scale = min(rect.width, rect.height) / 48
        origin = rect.origin
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }

    func box(x: CGFloat, y: CGFloat, side: CGFloat) -> CGRect {
        CGRect(x: origin.x + x * scale, y: origin.y + y * scale,
               width: side * scale, height: side * scale)
    }
}

// MARK: 添加（圆圈 + 十字）

struct AddGlyph: View {
    var size: CGFloat = 21
    var lineWidth: CGFloat { size * 4 / 48 }

    var body: some View {
        AddGlyphShape()
            .stroke(style: StrokeStyle(lineWidth: lineWidth,
                                       lineCap: .round,
                                       lineJoin: .round))
            .frame(width: size, height: size)
    }
}

private struct AddGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let grid = GlyphGrid(rect: rect)
        var path = Path()

        // 外圆：设计稿圆心 (24,24)、直径 40
        path.addEllipse(in: grid.box(x: 4, y: 4, side: 40))

        // 十字
        path.move(to: grid.point(24, 16))
        path.addLine(to: grid.point(24, 32))
        path.move(to: grid.point(16, 24))
        path.addLine(to: grid.point(32, 24))

        return path
    }
}

// MARK: - 带强调的文案
extension String {
    /// 把文案里的 `**重点**` 渲染成真正加粗的富文本。
    ///
    /// ⚠️ 直接用 `Text(某个 String 变量)` **不会**解析 Markdown ——
    /// 那条路径只对编译期字面量生效，从变量传进来的字符串会把 `**` 原样显示给用户
    /// （已在自动化引导页真实复现）。所以凡是含强调标记的文案，一律走这里。
    var richText: AttributedString {
        (try? AttributedString(
            markdown: self,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(self)
    }
}

// MARK: - 视图模型（局部状态统一放在 ObservableObject 里）
//
// 说明：这样写是为了让工程在「Xcode GUI」与「命令行 xcodebuild」两条链路下
// 都能编译——本机 Xcode 27 beta 的 swift-plugin-server 在命令行下对 SwiftUI 宏
// （#Preview / @State）返回 malformed response。避开宏之后，单一代码库即可双跑，
// 不必再维护一份改写副本。

final class CopyFeedbackModel: ObservableObject {
    @Published var copied = false
    private var resetTask: Task<Void, Never>?

    func flash() {
        copied = true
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if !Task.isCancelled { copied = false }
        }
    }
}

// MARK: - 分栏占位（宽屏 · iPhone Duo 展开态）

/// 分栏布局下详情列的空态：还没点选任何记录时显示。
///
/// 只在 `horizontalSizeClass == .regular`（Duo 展开态 / iPad）出现；
/// 常规 iPhone 走单栈，永远不会渲染到这个视图。
struct SplitDetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView {
            Label("未选择取件码", systemImage: "rectangle.split.2x1")
        } description: {
            Text("从左侧列表点选一条，详情会显示在这一栏。")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
