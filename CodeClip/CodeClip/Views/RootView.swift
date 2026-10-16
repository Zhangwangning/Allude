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

    var body: some View {
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
        // iOS 26 原生：向下滚动收起、上滑恢复，系统弹簧动画。
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(AppTheme.accent)
        // 装配后接管系统 tabBar 引用（见 `TabBarCloak`），供显隐动画驱动。
        .background(NativeTabBarBridge())
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

    /// 首次安装引导的呈现态（UserDefaults 手写持久化，工程不用 @AppStorage）。
    @Published var showOnboarding: Bool

    private static let onboardingKey = "onboarding.completed.v1"

    init() {
        // 首启引导：没写过完成标记就是第一次装（截图脚手架可用 SKIP_ONBOARDING=1 跳过）
        showOnboarding = ProcessInfo.processInfo.environment["SKIP_ONBOARDING"] == nil
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
    }

    // MARK: ① 欢迎

    private var welcomePage: some View {
        OnboardingPage(
            symbol: "tray.full.fill",
            tint: AppTheme.accent,
            title: "欢迎使用码夹",
            subtitle: "快递取件码自动收集，到驿站打开就能报码")
        {
            OnboardingPoint(symbol: "bubble.left.and.text.bubble.right.fill",
                            tint: AppTheme.accent,
                            title: "自动收码",
                            detail: "配合快捷指令，快递短信一到取件码自动入库")
            OnboardingPoint(symbol: "platter.filled.top.iphone",
                            tint: AppTheme.violet,
                            title: "灵动岛常显",
                            detail: "最新取件码挂在灵动岛与锁屏，抬手即见")
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
            title: "开启短信自动化",
            subtitle: "一次配置，之后每一单都自动进来")
        {
            OnboardingPoint(symbol: "1.circle.fill",
                            tint: AppTheme.amber,
                            title: "获取快捷指令",
                            detail: "设置 › 使用教程，按指引获取「快递取件码」")
            OnboardingPoint(symbol: "2.circle.fill",
                            tint: AppTheme.amber,
                            title: "开启信息自动化",
                            detail: "快捷指令 App › 自动化 › 信息：收到含关键词的短信时运行")
            OnboardingPoint(symbol: "3.circle.fill",
                            tint: AppTheme.amber,
                            title: "完成",
                            detail: "之后收到取件短信，待取列表自动出现新记录并提醒")
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
                Text("所有功能已开放，数据只在本机。\n到驿站时打开码夹，报码就走。")
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
            // 自动化页内嵌完整教程入口
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
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.subheadline)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(detail)
                    .font(.system(size: 13))
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
    func cloaksTabBar() -> some View {
        onAppear { TabBarCloak.shared.cover() }
            .onDisappear {
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
