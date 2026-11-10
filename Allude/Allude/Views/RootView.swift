import SwiftUI
import UIKit

/// 应用根视图：**系统原生 `TabView` + 原生 Liquid Glass 标签栏**。
///
/// 🔴 **2026-10-14 信息架构定稿（主人）**：删除票夹功能，四个标签 =
///   **待取**（待取件列表）/ **已取**（取件回执库）/ **统计**（取件数据分析）/ **设置**。
/// 原「我的」面板重构进「设置」（见 ProfileView.swift 的 `SettingsView`），
/// 顶栏头像入口退役；VIP/会员体系整体退役，全功能开放。
///
/// 标签栏显隐沿用 `TabBarCloak`（原生 tabBar 视图本体 + 自驱动弹簧动画）：
/// 设置分支的二级页出现收起、转场开始即滑回，计数制保证嵌套 push/pop 不闪。
struct RootView: View {
    @StateObject private var model = RootTabModel()

    /// 分享面板的全局呈现状态（2026-10-25）：面板放在 TabView **外层**的 ZStack 里，
    /// 而不是页面级 cover —— 否则 Duo 右侧 84pt 标签栏、底部 34pt 安全区会被重新引入，
    /// 面板宽度和按钮位置都控不住（详见 `SharePresenter` 的注释）。
    @StateObject private var share = SharePresenter.shared

    /// 通知点击带来的记录 id（2026-10-25）：只负责**切到正确的标签**，
    /// 具体 push 详情由列表页自己消费（见 `NotificationRouter`）。
    @StateObject private var notificationRouter = NotificationRouter.shared

    var body: some View {
        ZStack {
            TabView(selection: $model.selection) {
                PickupListView()
                    .tabItem { Label("待取", systemImage: "tray.fill") }
                    .tag(RootTab.pending)

                PickedUpView()
                    .tabItem { Label("已取", systemImage: "checkmark.circle.fill") }
                    .tag(RootTab.picked)

                StatsTabView()
                    .tabItem { Label("统计", systemImage: "chart.bar.xaxis") }
                    .tag(RootTab.stats)

                SettingsTabRoot()
                    .tabItem { Label("设置", systemImage: "gearshape.fill") }
                    .tag(RootTab.settings)
            }
            // 标签栏**固定显示**，不随滚动收缩（2026-10-27 主人定）。
            // iOS 26 默认行为是 `onScrollDown` —— 列表往下滚时标签栏会缩成
            // 一小条胶囊、上滑再展开。主人要求常驻，所以显式设为 `.never`。
            // ⚠️ 别改回 `.automatic`：那等同于跟系统默认走，又会收起。
            // 注意这与下方 `TabBarCloak`（进设置二级页时**故意**收起）是两件事：
            // 那条是有意的导航语义，不受这里影响。
            // `.tabBarMinimizeBehavior` 是 iOS 26 新增；低版本没有这个行为，直接跳过。
            .modifier(TabBarMinimizeNever())
            .tint(AppTheme.accent)
            // 装配后接管系统 tabBar 引用（见 `TabBarCloak`），供显隐动画驱动。
            .background(NativeTabBarBridge())

            // ── 分享面板（全屏浮动，盖住标签栏） ──
            if let records = share.records {
                SharePreviewSheet(records: records)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: share.records?.first?.id)
        // 通知点击 → 切到这条记录所在的标签（待取 / 已取），
        // 具体打开详情由列表页消费同一个 `pendingRecordID`（2026-10-25）
        // 没有具体记录的通知（每日提醒等）被点击 → 至少切回待取
        .onChange(of: notificationRouter.shouldShowPendingTab) { _, show in
            guard show else { return }
            model.selection = .pending
        }
        .onChange(of: notificationRouter.pendingRecordID) { _, id in
            guard let id,
                  let record = PickupStore.shared.records.first(where: { $0.id == id })
            else { return }
            model.selection = record.isPickedUp ? .picked : .pending
        }
        .onAppear {
            // 记录"当前是不是 Duo 折叠态外屏"给小组件进程用（灵动岛由它渲染）
            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).first(where: \.isKeyWindow) {
                DuoOuterDisplay.refresh(windowHeight: window.bounds.height)
            }

            // 冷启动场景：delegate 在视图起来之前就写好了 id，这里补切一次
            if let id = notificationRouter.pendingRecordID,
               let record = PickupStore.shared.records.first(where: { $0.id == id }) {
                model.selection = record.isPickedUp ? .picked : .pending
            }
        }
        // 首次启动：**先合法同意，再引导**。两个都是全屏，互不叠加。
        .fullScreenCover(isPresented: $model.showConsent) {
            LegalConsentView {
                model.acceptConsent()
            }
        }
        // 首次安装引导（写完标记后不再出现；设置页可重看）
        .fullScreenCover(isPresented: $model.showOnboarding) {
            OnboardingView {
                model.completeOnboarding()
            }
        }
    }
}

// MARK: - 当前标签

enum RootTab: String, Hashable {
    case pending    // 待取
    case picked     // 已取
    case stats      // 统计
    case settings   // 设置
}

final class RootTabModel: ObservableObject {
    @Published var selection: RootTab

    /// 首次启动的**法律同意页**（2026-11-01）：必须先同意条款才能进 App。
    @Published var showConsent: Bool
    /// 首次安装引导的呈现态（UserDefaults 手写持久化，工程不用 @AppStorage）。
    @Published var showOnboarding: Bool

    private static let onboardingKey = "onboarding.completed.v1"
    private static let consentKey = "legal.consent.v1"

    init() {
        // 截图脚手架统一跳过首启流程（SKIP_ONBOARDING=1）
        let skipping = ProcessInfo.processInfo.environment["SKIP_ONBOARDING"] != nil

        // 顺序很重要：**先同意条款，再看引导**。同意过就直接看引导。
        showConsent = !skipping && !UserDefaults.standard.bool(forKey: Self.consentKey)
        showOnboarding = !skipping
            && UserDefaults.standard.bool(forKey: Self.consentKey)
            && !UserDefaults.standard.bool(forKey: Self.onboardingKey)

        // 截图脚手架：`SIMCTL_CHILD_TAB=pending|picked|stats|settings` 直接落到目标页
        // （simctl 没有触摸注入通道，点不了底部标签栏）。旧值兼容映射：
        // ticket→picked（票夹已删，2026-10-14）、browse→stats。
        let raw = ProcessInfo.processInfo.environment["TAB"] ?? ""
        switch raw {
        case "picked", "ticket": selection = .picked
        case "stats", "browse":  selection = .stats
        case "settings":         selection = .settings
        default:                 selection = .pending
        }
    }

    /// 同意条款：写标记 + 收起同意页、接着进入引导页。
    func acceptConsent() {
        UserDefaults.standard.set(true, forKey: Self.consentKey)
        showConsent = false
        if !UserDefaults.standard.bool(forKey: Self.onboardingKey) {
            showOnboarding = true
        }
    }

    /// 引导完成：写标记 + 收起引导页。
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        showOnboarding = false
    }
}

// MARK: - 首次安装引导（三页，放本文件避免增删工程文件引用）
//
/// 三页横滑引导：① 欢迎（这是什么）② 自动化（怎么自动收码）③ 完成。
/// 「设置 › 使用教程」是合并后的完整教程页（见 UsageGuideView.swift），
/// 本引导只做首启三页速览，不再提供回放入口。
struct OnboardingView: View {
    /// 完成回调（首启模式必传）。
    var onFinish: (() -> Void)? = nil

    // 宏规避：页码收进 ObservableObject（与全工程口径一致）
    @StateObject private var state = OnboardingPageState()

    // 首启页里的「导入自动化」用的分享面板
    @State private var automationURL: URL?
    @State private var showAutomationShare = false

    var body: some View {
        // 🔴 必须自带 NavigationStack：引导住在 fullScreenCover 里，
        // 那是一层独立的表现上下文，没有栈的话第 2 页「查看完整使用教程」
        // 的 NavigationLink 点了不会有任何反应。
        NavigationStack {
            TabView(selection: $state.page) {
                welcomePage.tag(0)
                automationPage.tag(1)
                finishPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            // 截图脚手架：ONBOARDING_PAGE=0/1/2 直接落到某一页
            if let raw = ProcessInfo.processInfo.environment["ONBOARDING_PAGE"],
               let page = Int(raw), (0...2).contains(page) {
                state.page = page
            }
        }
        .sheet(isPresented: $showAutomationShare) {
            if let automationURL {
                ActivitySheet(items: [automationURL])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: ① 欢迎

    private var welcomePage: some View {
        OnboardingPage(
            symbol: "tray.full.fill",
            tint: AppTheme.accent,
            title: "欢迎使用Allude",
            subtitle: "快递取件码自动收集，到驿站打开就能报码")
        {
            OnboardingPoint(symbol: "bubble.left.and.text.bubble.right.fill",
                            tint: AppTheme.accent,
                            title: "自动收码",
                            detail: "配合快捷指令，快递短信一到取件码自动入库")
            // 🔴 2026-11-08 主人：重点是**小组件实时更新**，以及灵动岛/锁屏的实时活动，
            //    不要只写「灵动岛常显」——那只是其中一个入口。
            OnboardingPoint(symbol: "rectangle.grid.2x2.fill",
                            tint: AppTheme.violet,
                            title: "小组件与实时活动",
                            detail: "待取码在桌面小组件实时更新，也常驻灵动岛与锁屏卡片")
            OnboardingPoint(symbol: "hand.raised.fill",
                            tint: AppTheme.doneTint,
                            title: "只在本机",
                            detail: "无账号、无联网，取件数据不出这台手机")
        }
    }

    // MARK: ② 自动化

    private var automationPage: some View {
        OnboardingPage(
            symbol: "bolt.badge.automatic.fill",
            tint: AppTheme.amber,
            title: "开启快捷指令自动化",
            subtitle: "一次配置，之后每一单都自动进来")
        {
            VStack(spacing: 0) {
                OnboardingStep(index: 1, tint: AppTheme.amber,
                               title: "导入自动化",
                               detail: "点下面的按钮，把「收到短信 → 添加到Allude」导进系统")
                SettingsDivider()
                OnboardingStep(index: 2, tint: AppTheme.amber,
                               title: "打开开关",
                               detail: "快捷指令 › 自动化 里找到它，把开关打开（导入后默认关）")
                SettingsDivider()
                OnboardingStep(index: 3, tint: AppTheme.amber,
                               title: "完成",
                               detail: "之后收到取件短信，列表自动出现新记录")
            }
            .settingsCard()

        }
    }

    // MARK: ③ 完成

    private var finishPage: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)

            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(spacing: 8) {
                Text("一切就绪")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("所有功能已开放，数据只在本机。\n到驿站时打开Allude，报码就走。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 底栏

    private var bottomBar: some View {
        VStack(spacing: 14) {
            // 自动化页：一键导入 + 完整教程（都放底栏，页面圆点不会压到它们）
            if state.page == 1 {
                Button {
                    guard let preset = ShortcutAutomation.presets.first,
                          let url = ShortcutAutomation.importFile(for: preset) else { return }
                    automationURL = url
                    showAutomationShare = true
                    ShortcutAutomation.markImported(preset.keyword)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text("一键导入自动化（关键词：【）")
                    }
                    .font(AppTheme.TypeScale.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .appGlass(.capsule, tint: AppTheme.amber, interactive: true)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
            }

            if state.page == 1 {
                NavigationLink {
                    UsageGuideView()
                } label: {
                    Label("查看完整使用教程", systemImage: "book.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(AppTheme.accent.opacity(0.12), in: .capsule)
                        .foregroundStyle(AppTheme.accent)
                }
                .padding(.horizontal, 32)
            }

            Button {
                if state.page < 2 {
                    withAnimation(.snappy) { state.page += 1 }
                } else {
                    onFinish?()
                }
            } label: {
                Text(state.page < 2 ? "下一步" : "开始使用")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(AppTheme.accent, in: .capsule)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 32)

            if state.page == 0 {
                Button("跳过") {
                    onFinish?()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 24)
    }
}

/// 引导页骨架：图标 + 标题 + 副标题 + 要点列表。
private struct OnboardingPage<Points: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    @ViewBuilder let points: Points

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 30)

            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 104, height: 104)
                Image(systemName: symbol)
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(tint)
            }

            VStack(spacing: 8) {
                Text(title.L)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(subtitle.L)
                    .font(AppTheme.TypeScale.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)

            VStack(spacing: 14) {
                points
            }
            .padding(.top, 30)

            Spacer(minLength: 30)
        }
        .padding(.horizontal, 28)
        // 页面圆点由 TabView 画在底部，内容要给它让位，否则会压住「一键导入」按钮
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 引导步骤行：数字徽标 + 标题 + 说明（放在同一张卡里，用分隔线分开）。
private struct OnboardingStep: View {
    let index: Int
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "\(index).circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.L)
                    .font(AppTheme.TypeScale.rowTitleMedium)
                Text(detail.L)
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

/// 引导要点行：彩色图标 + 标题 + 说明。
private struct OnboardingPoint: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.L)
                    .font(AppTheme.TypeScale.rowTitleMedium)
                Text(detail.L)
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// 引导页码状态（宏规避口径，与全工程一致）。
final class OnboardingPageState: ObservableObject {
    @Published var page = 0
}

// MARK: - 原生标签栏显隐（TabBarCloak）

/// 「设置」分支二级页显隐的**唯一真值 + 动画驱动器**，作用对象是系统 tabBar 视图本体。
///
/// 为什么显隐还是我们自己驱动：三条系统路线全部实测被否 ——
///   ① `.toolbar(.hidden, for: .tabBar)`：pop 恢复由 UIKit 托管在转场之外，
///      转场结束才蹦出来（僵硬，否）；
///   ② `hidesBottomBarWhenPushed` 桥接：SwiftUI NavigationStack 不理会（无效，否）；
///   ③ 不收起（"原生语义"）：主人明确要求二级页必须收起（否）。
/// 剩下的自由度只有"对原生 tabBar 视图自己做动画" —— 组件原生、动画顺滑。
///
/// 计数制（嵌套 push 安全）：
///   · **cover()** = 二级页 onAppear（设置分支），计数 +1；
///   · **popSecondary()** = 二级页 onDisappear（async 下一跳），计数 −1 ——
///     pop 转场一开始就触发滑回动画，与转场并行，不再等转场结束；
///   · **reveal()** = 标签根页 onAppear，计数归零（兜底防泄漏）。
final class TabBarCloak: ObservableObject {
    static let shared = TabBarCloak()

    private var coverCount = 0
    private var isHidden = false

    /// 系统 tabBar 视图本体（原生 Liquid Glass 组件，只动 transform/alpha）。
    private(set) weak var tabBar: UITabBar?

    /// 二级页出现：收起（计数 +1，嵌套安全）。
    func cover() {
        coverCount += 1
        sync()
    }

    /// 二级页消失：解除一层（计数 −1，下限 0）。
    /// 🔴 调用方必须 `DispatchQueue.main.async` 包一层：push 更深页时
    ///    新页 onAppear 与旧页 onDisappear 顺序不定，下一跳执行让
    ///    cover 先落账，计数才不会瞬间归零造成闪烁。
    func popSecondary() {
        coverCount = max(0, coverCount - 1)
        sync()
    }

    /// 回到标签根页：露出（计数归零，兜底防泄漏）。
    func reveal() {
        coverCount = 0
        sync()
    }

    /// 从装配好的视图层级里接管 tabBar 引用（幂等，可重复调用）。
    func locate(from vc: UIViewController) {
        guard tabBar == nil else { return }
        guard let root = vc.view.window?.rootViewController else { return }
        // 先沿 VC 树找 UITabBarController（SwiftUI 内部 addChild 托管），
        // 找不到再暴力遍历视图树找 UITabBar 实例兜底。
        tabBar = Self.findTabBarController(root)?.tabBar ?? Self.findBar(in: root.view)
    }

    private static func findTabBarController(_ root: UIViewController) -> UITabBarController? {
        if let tab = root as? UITabBarController { return tab }
        for child in root.children {
            if let found = findTabBarController(child) { return found }
        }
        return nil
    }

    private static func findBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar { return bar }
        for sub in view.subviews {
            if let found = findBar(in: sub) { return found }
        }
        return nil
    }

    private func sync() {
        let hidden = coverCount > 0
        guard hidden != isHidden else { return }
        isHidden = hidden
        apply(hidden)
    }

    /// 滑出 / 滑回动画。弹簧参数对齐主人认可的顺滑手感：
    /// response 0.38 / damping 0.86 ≈ UIKit spring(duration:damping:0.38/0.86)。
    private func apply(_ hide: Bool) {
        guard let bar = tabBar else { return }
        // 出屏位移：从当前位置滑到屏幕下缘之外（含 home indicator 区）再余 40pt。
        let distance = bar.superview.map { $0.bounds.height - bar.frame.minY } ?? 220

        UIView.animate(withDuration: 0.38,
                       delay: 0,
                       usingSpringWithDamping: 0.86,
                       initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            bar.transform = hide
                ? CGAffineTransform(translationX: 0, y: distance + 40)
                : .identity
            bar.alpha = hide ? 0 : 1
        }
    }
}

/// 嵌在 `RootView` 里的装配钩子：TabView 建好系统层级后把 tabBar 引用
/// 交给 `TabBarCloak`。只做接管，不做任何显示干预。
private struct NativeTabBarBridge: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Bridge { Bridge() }
    func updateUIViewController(_ vc: Bridge, context: Context) {}

    final class Bridge: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            // SwiftUI 装配可能晚一拍：本帧没拿到就下一帧再找。
            if TabBarCloak.shared.tabBar == nil {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    TabBarCloak.shared.locate(from: self)
                    // 深层兜底：再不行等 0.5s 补一次（App 冷启动慢机型）。
                    if TabBarCloak.shared.tabBar == nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            TabBarCloak.shared.locate(from: self)
                        }
                    }
                }
            }
        }
    }
}

extension View {
    /// 设置分支内**任意层级**的二级页都挂这一个修饰符：
    /// 出现时收起标签栏、离开时恢复（转场一开始就滑回，不蹦出）。
    ///
    /// 🔴 **设置分支的每个二级页（含深层）都必须挂** ——
    ///    深层页不挂的话，push 进去时上一页的 `onDisappear` 会把计数
    ///    扣回零，标签栏就滑回来了（2026-09-23 主人实测抓到）。
    ///    计数制保证「设置 → 小组件 → …」这类嵌套 push/pop 不闪。
    ///
    /// ⚠️ 宽屏分栏例外（2026-10-25 审查修）：iPad 式设置页把这些页面当成
    /// **常驻 pane** 渲染，不再是「push 进来的二级页」。那时若照常 cover，
    /// 一进设置标签栏就被滑走、用户换不了标签。分栏侧通过环境值
    /// `suppressTabBarCloak` 关掉这套显隐。
    func cloaksTabBar() -> some View {
        modifier(TabBarCloakModifier())
    }
}

/// 环境值：true 时 `cloaksTabBar()` 只挂空修饰（用于宽屏设置分栏的常驻 pane）
private struct SuppressTabBarCloakKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var suppressTabBarCloak: Bool {
        get { self[SuppressTabBarCloakKey.self] }
        set { self[SuppressTabBarCloakKey.self] = newValue }
    }
}

private struct TabBarCloakModifier: ViewModifier {
    @Environment(\.suppressTabBarCloak) private var suppressed
    /// 必须在**出现那一刻**记下当时是否被抑制，否则中途环境值变化会让
    /// onDisappear 少扣一次计数，把标签栏永久卡在收起态。
    @State private var engaged = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !suppressed else { engaged = false; return }
                engaged = true
                TabBarCloak.shared.cover()
            }
            .onDisappear {
                guard engaged else { return }
                engaged = false
                DispatchQueue.main.async { TabBarCloak.shared.popSecondary() }
            }
    }
}

// MARK: - 设置 Tab 根容器

/// 「设置」Tab 的导航栈容器（SettingsView 本体在 ProfileView.swift）。
/// 单独包一层 NavigationStack：四个标签各自持有独立栈，push/pop 互不干扰。
struct SettingsTabRoot: View {
    var body: some View {
        NavigationStack {
            SettingsView()
        }
    }
}

/// TabView 的「常驻标签栏」行为只有 iOS 26 才有，用 modifier 收起来。
private struct TabBarMinimizeNever: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.never)
        } else {
            content
        }
    }
}
