import SwiftUI
import UIKit
import PhotosUI

// MARK: ============================================================================
// 设置（2026-10-14 由「我的」面板重构而来，主人定稿：底部标签栏直达）
//
// 结构调整：
//   · 原「我的」由右上角头像 push 进入，现改为**底部第 4 个标签页**；
//     顶部头像入口整体退役（三个列表页的工具栏不再放头像）。
//   · 🔴 **VIP/会员体系整体退役** —— 软件全功能、无任何限制：
//     无会员分区、无档位徽章、无行尾锁、无 TestFlight 档位说明。
//   · 新增「反馈」（mailto:zhang_wangning@126.com）与「使用教程」
//     （合并原「自动化设置」+「引导教程」，2026-10-14 主人定稿）。
//
// 版式沿用 iOS 分组面板：账户卡 + 若干分组卡，组标题在卡外。
// 账户仍为**本机档案**（无登录、无联网，2026-09-23 定稿口径不变）。
// ============================================================================

// MARK: - 分栏设置页的面板清单（宽屏用）
//
// 2026-10-25：Duo 展开态（regular）改成 macOS / iPad 设置式「左列表 + 右内容」，
// 这里把原来散落在 ScrollView 里的条目收成一个枚举，供侧栏与内容面板共用。
// 窄屏仍走原来的长页布局，与本枚举无关。

enum SettingsPane: String, CaseIterable, Identifiable {
    case notification
    case widget
    case activity
    case courier
    case station
    case guide
    case license
    case storage
    case feedback
    case version
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notification: return "通知提醒"
        case .widget:       return "桌面小组件"
        case .activity:     return "实时活动"
        case .courier:      return "快递公司"
        case .station:      return "驿站管理"
        case .guide:        return "使用教程"
        case .license:      return "凭证"
        case .storage:      return "本机数据"
        case .feedback:     return "反馈"
        case .version:      return "版本"
        case .privacy:      return "隐私"
        }
    }

    var symbol: String {
        switch self {
        case .notification: return "bell.badge.fill"
        case .widget:       return "square.text.square.fill"
        case .activity:     return "platter.filled.top.iphone"
        case .courier:      return "shippingbox.fill"
        case .station:      return "storefront.fill"
        case .guide:        return "book.fill"
        case .license:      return "key.fill"
        case .storage:      return "internaldrive.fill"
        case .feedback:     return "envelope.fill"
        case .version:      return "info.circle.fill"
        case .privacy:      return "hand.raised.fill"
        }
    }

    var tint: Color {
        switch self {
        case .notification: return AppTheme.pendingTint
        case .widget:       return AppTheme.sky
        case .activity:     return AppTheme.accent
        case .courier:      return AppTheme.indigo
        case .station:      return AppTheme.violet
        case .guide:        return AppTheme.sky
        case .license:      return AppTheme.amber
        case .storage:      return AppTheme.todayTint
        case .feedback:     return AppTheme.doneTint
        case .version:      return AppTheme.todayTint
        case .privacy:      return AppTheme.doneTint
        }
    }

    /// 侧栏分组（顺序即显示顺序，与原来长页的分组一一对应）
    static let generalGroup: [SettingsPane] = [.notification, .widget, .activity, .courier, .station, .guide, .license]
    static let dataGroup: [SettingsPane] = [.storage]
    static let aboutGroup: [SettingsPane] = [.feedback, .version, .privacy]
}

struct SettingsView: View {
    @EnvironmentObject private var store: PickupStore

    /// 反馈结果的轻提示（邮件打不开时引导复制邮箱）。
    @StateObject private var feedback = FeedbackModel()

    /// 宽屏（iPhone Duo 展开态）判定 —— 与列表页同一口径。
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// 分栏设置页当前选中的面板（2026-10-25，参照 macOS / iPad 设置）。
    @State private var pane: SettingsPane? = SettingsView.scaffoldPane

    /// 侧栏搜索词（2026-10-25 照 iPad 设置：侧栏顶部有搜索框）
    @State private var query = ""

    /// 截图脚手架：`SIMCTL_CHILD_SETTINGS_PANE=courier|widget|…` 启动即选中该面板，
    /// 命令行点不到侧栏行，逐页验收底色/图标只能用这个入口。
    static var scaffoldPane: SettingsPane? {
        guard let raw = ProcessInfo.processInfo.environment["SETTINGS_PANE"] else {
            return .notification
        }
        return SettingsPane(rawValue: raw) ?? .notification
    }

    /// 按搜索词过滤某一组（空词 = 原样返回）
    private func filtered(_ items: [SettingsPane]) -> [SettingsPane] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                splitSettings
            } else {
                stackedSettings
            }
        }
        .overlay { feedbackToast }
    }

    /// 窄屏：原「一张长页」布局，保持不变。
    private var stackedSettings: some View {
        ScrollView {
            VStack(spacing: 16) {
                settingsSection
                licenseSection
                dataSection
                aboutSection
                footer
            }
            .padding(.horizontal, AppTheme.hInset)
            // 📱 宽屏限宽居中（iPhone Duo 展开态）：设置项与账户卡按阅读列排布，
            //    窄屏触不到 700 上限，视觉零变化。
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        // 截图脚手架（2026-10-30）：`SETTINGS_ANCHOR=about` 时整页从底部起滚，
        // 直接露出「关于」组末行的「设备标识」。
        // 起因：命令行既不能滚动（simctl 无手势），又不能驱动模拟器点击
        // （AppleScript 被辅助功能权限拒绝，报 -10004），而这行在长页最底部。
        // 默认 `.top`，不注入变量时与改动前完全一致。
        .defaultScrollAnchor(
            ProcessInfo.processInfo.environment["SETTINGS_ANCHOR"] == "about" ? .bottom : .top
        )
        // 页面底 = 浅灰，卡片才是白（2026-09-23 修正口径，与全 App 一致）
        .background(Color(.systemGroupedBackground))
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // 设置是标签根页：兜底露出标签栏（其它标签返回同口径，见 RootView）
            TabBarCloak.shared.reveal()
        }
    }

    /// 宽屏：macOS / iPad 设置式「左侧分组列表 + 右侧内容面板」。
    ///
    /// 2026-10-25 主人：「设置页面参考 Apple 的 mac、iPad 这种设置页面布局」，
    /// 并当场指正配色 —— **左侧栏浅灰底、选中行白色**（我第一版做反了）。
    /// 所以这里不用 `List(selection:)` 的系统高亮（iOS 会给灰色/蓝色选中块），
    /// 改成 plain List + 自绘行背景：底色浅灰、选中行白色圆角块。
    private var splitSettings: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // 侧栏顶部搜索框（照 iPad 设置：胶囊输入框 + 放大镜）
                settingsSearchField

                List {
                    settingsGroup("通用", items: filtered(SettingsPane.generalGroup))
                    settingsGroup("本机数据", items: filtered(SettingsPane.dataGroup))
                    settingsGroup("关于", items: filtered(SettingsPane.aboutGroup))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                .toolbarBackground(.hidden, for: .navigationBar)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            // 侧栏宽度**按屏幕宽比例**（2026-10-25 主人：Duo 展开竖屏也要照 iPad 竖屏布局）：
            // 横屏 951pt → ~380pt；竖屏 669pt → ~280pt（下限）。
            // 写死 434 会让竖屏侧栏占到 65%，右侧内容被挤扁。
            .navigationSplitViewColumnWidth(min: 280,
                                            ideal: settingsSidebarWidth,
                                            max: 420)
        } detail: {
            // 右栏与左栏**同一底色**（2026-10-25 主人两次强调：Duo 展开时左侧浅灰、
            // 右侧白色，「先全部是一个底色」）。
            // 三层兜底，任何一层漏掉都不会露出白：
            //   ① ZStack 铺满浅灰（含安全区）；
            //   ② NavigationStack 自身再垫一层浅灰；
            //   ③ 导航栏 toolbar 背景也显式设为浅灰（默认是 systemBackground 白）。
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                NavigationStack {
                    // 照 iPad 设置的内容列：左右留白更大、内容限宽居中
                    paneContent(pane ?? .notification)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: 600)
                        .frame(maxWidth: .infinity)
                        // 🔴 分栏里的这些页面是**常驻 pane**，不是 push 进来的二级页，
                        // 不能再让 `cloaksTabBar()` 把底部标签栏收走
                        // （2026-10-25 审查修：否则一进宽屏设置标签栏就没了）。
                        .environment(\.suppressTabBarCloak, true)
                }
                .background(Color(.systemGroupedBackground))
                // 导航栏透明 → 露出下面的浅灰，避免顶部一条白
                .toolbarBackground(.hidden, for: .navigationBar)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { TabBarCloak.shared.reveal() }
    }

    /// 侧栏目标宽：按屏幕宽的 40% 取，夹在 280…400 之间。
    /// Duo 横屏（951）→ 380；竖屏（669）→ 280。
    private var settingsSidebarWidth: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let width = scene?.screen.bounds.width ?? 844
        return min(400, max(280, width * 0.40))
    }

    /// 侧栏搜索框（照 iPad 设置）
    private var settingsSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("搜索", text: $query)
                .font(.system(size: 15))
                .textFieldStyle(.plain)
                .submitLabel(.search)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(.tertiarySystemFill), in: .capsule)
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    /// 侧栏的一个分组（标题 + 若干行）
    @ViewBuilder
    private func settingsGroup(_ title: String, items: [SettingsPane]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    settingsSidebarRow(item)
                        .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } header: {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .padding(.leading, 10)
            }
        }
    }

    /// 侧栏一行（照 iPad 设置：小图标 + 15pt 文字 + 灰色选中块，行高紧凑）
    private func settingsSidebarRow(_ item: SettingsPane) -> some View {
        HStack(spacing: 10) {
            SettingsGlyph(symbol: item.symbol, tint: item.tint, size: 26)

            Text(item.title)
                .font(.system(size: 15))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            // iPad 设置的选中块是**灰色**（不是白色），圆角 9
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(pane == item ? Color(.systemGray5) : Color.clear)
        }
        .contentShape(.rect)
        .onTapGesture { pane = item }
        .tag(item)
    }

    /// 右侧内容：选中项展开的页面 / 卡片
    @ViewBuilder
    private func paneContent(_ item: SettingsPane) -> some View {
        switch item {
        case .notification: NotificationSettingsView()
        case .widget:     WidgetSettingsView()
        case .activity:   ActivityPreviewGallery()
        case .courier:    CourierGalleryView(scope: .courier)
        case .station:    CourierGalleryView(scope: .station)
        case .guide:      UsageGuideView()
        case .license:    LicenseActivationView()
        case .version:    VersionHistoryView()
        case .storage:    dataDetailPane
        case .feedback:   feedbackPane
        case .privacy:    privacyPane
        }
    }

    /// 「已存记录 / 数据文件」面板（原 dataSection 的数据部分）
    private var dataDetailPane: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    SettingsRow(symbol: "internaldrive.fill", title: "已存记录",
                                detail: "\(store.records.count) 条",
                                showsChevron: false,
                                tint: AppTheme.todayTint)

                    SettingsDivider()

                    SettingsRow(symbol: "doc.text.fill", title: "数据文件",
                                detail: PickupStorage.fileSizeDescription,
                                showsChevron: false,
                                tint: AppTheme.doneTint)
                }
                .cardSurface()

                Text("全部功能开放，记录数量不限；数据只保存在这台设备上。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding(AppTheme.hInset)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("本机数据")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 「反馈」面板：邮件直达 + 邮箱展示
    private var feedbackPane: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    Button {
                        feedback.openMail()
                    } label: {
                        SettingsRow(symbol: "envelope.fill", title: "发送邮件反馈",
                                    subtitle: FeedbackModel.mail,
                                    showsChevron: false,
                                    tint: AppTheme.doneTint)
                    }
                    .buttonStyle(.plain)
                }
                .cardSurface()

                Text("邮件会自动带上版本号，方便定位问题。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding(AppTheme.hInset)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("反馈")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 「隐私」面板：把原关于组里的隐私口径单独成页
    private var privacyPane: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    SettingsRow(symbol: "hand.raised.fill", title: "隐私",
                                subtitle: "无账号、无联网；取件数据全程只在本机",
                                showsChevron: false,
                                tint: AppTheme.doneTint)
                }
                .cardSurface()

                footer
            }
            .padding(AppTheme.hInset)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("隐私")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 设置

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "通用")

            VStack(spacing: 0) {
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    SettingsRow(symbol: "bell.badge.fill", title: "通知提醒",
                                subtitle: "入库通知 · 定期与不定期取件提醒",
                                tint: AppTheme.pendingTint)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                NavigationLink {
                    WidgetSettingsView()
                } label: {
                    SettingsRow(symbol: "square.text.square.fill", title: "桌面小组件",
                                subtitle: "显示内容 · 效果预览 · 添加指引",
                                tint: AppTheme.sky)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                NavigationLink {
                    ActivityPreviewGallery()
                } label: {
                    SettingsRow(symbol: "platter.filled.top.iphone",
                                title: "实时活动",
                                subtitle: DeviceProfile.hasDynamicIsland
                                    ? "灵动岛常驻最新取件码，锁屏同显"
                                    : "锁屏实时活动卡，取件前抬手即见",
                                tint: AppTheme.accent)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                // 快递公司 / 驿站管理 两个模块（2026-10-27 拆开）。
                // 原来是一行「快递管理」把两件事混在一起：用户既不知道里面有什么，
                // 也不知道「驿站名称可自定义」其实藏在那个页面的第二/三个分类里。
                NavigationLink {
                    CourierGalleryView(scope: .courier)
                } label: {
                    SettingsRow(symbol: "shippingbox.fill", title: "快递公司",
                                subtitle: "承运方品牌图标 · 未收录的按名称自绘",
                                tint: AppTheme.indigo)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                NavigationLink {
                    CourierGalleryView(scope: .station)
                } label: {
                    SettingsRow(symbol: "storefront.fill", title: "驿站管理",
                                subtitle: "驿站 / 快递柜名称可自定义",
                                tint: AppTheme.violet)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                // 使用教程：合并原「自动化设置」+「引导教程」（2026-10-14 主人定稿）
                NavigationLink {
                    UsageGuideView()
                } label: {
                    SettingsRow(symbol: "book.fill", title: "使用教程",
                                subtitle: "入门 · 短信自动化 · 截屏收件",
                                tint: AppTheme.violet)
                }
                .buttonStyle(.plain)
            }
            .cardSurface()
        }
    }

    // MARK: 签名凭证（买断解锁）

    /// 窄屏的「解锁」分组（宽屏走 `SettingsPane.license` 面板）。
    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "凭证")

            VStack(spacing: 0) {
                NavigationLink {
                    LicenseActivationView()
                } label: {
                    SettingsRow(symbol: "key.fill",
                                title: "本机凭证",
                                subtitle: store.isPro
                                    ? "完整版 · \(store.plan.title)"
                                    : "免费版 · 只显示 \(PickupStore.freeVisibleLimit) 条",
                                tint: AppTheme.amber)
                }
                .buttonStyle(.plain)
            }
            .cardSurface()
        }
    }

    // MARK: 本机数据

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "本机数据")

            VStack(spacing: 0) {
                SettingsRow(symbol: "internaldrive.fill", title: "已存记录",
                            detail: "\(store.records.count) 条",
                            showsChevron: false,
                            tint: AppTheme.todayTint)

                SettingsDivider()

                SettingsRow(symbol: "doc.text.fill", title: "数据文件",
                            detail: PickupStorage.fileSizeDescription,
                            showsChevron: false,
                            tint: AppTheme.doneTint)
            }
            .cardSurface()

            Text("全部功能开放，记录数量不限；数据只保存在这台设备上。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 关于（版本 / 反馈 / 隐私）

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "关于")

            VStack(spacing: 0) {
                NavigationLink {
                    VersionHistoryView()
                } label: {
                    SettingsRow(symbol: "info.circle.fill", title: "版本",
                                detail: AppVersion.display,
                                tint: AppTheme.todayTint)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                // 反馈：邮件直达（2026-10-14 主人指定邮箱）
                Button {
                    feedback.openMail()
                } label: {
                    SettingsRow(symbol: "envelope.fill", title: "反馈",
                                subtitle: feedback.subtitle,
                                showsChevron: false,
                                tint: AppTheme.doneTint)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                SettingsRow(symbol: "hand.raised.fill", title: "隐私",
                            subtitle: "无账号、无联网；取件数据全程只在本机",
                            showsChevron: false,
                            tint: AppTheme.doneTint)
            }
            .cardSurface()
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("拾码 CodePouch")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
            Text("取件码只在本机流转，不上传任何服务器")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    /// 邮件打不开时的提示条（复制邮箱兜底）。
    @ViewBuilder private var feedbackToast: some View {
        if feedback.showFallback {
            VStack(spacing: 10) {
                Text("邮件 App 不可用，已复制邮箱到剪贴板：")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(FeedbackModel.mail)
                    .font(.footnote.weight(.semibold).monospaced())
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .glassEffect(.regular, in: .capsule)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.85),
                       value: feedback.showFallback)
        }
    }
}

// MARK: - 反馈

/// 打开邮件反馈；邮件 App 不可用时自动复制邮箱兜底并提示。
final class FeedbackModel: ObservableObject {
    static let mail = "zhang_wangning@126.com"

    @Published var showFallback = false
    private var hideTask: Task<Void, Never>?

    var subtitle: String { Self.mail }

    func openMail() {
        // 主题带上版本号，定位问题更快
        let subject = "拾码反馈（\(AppVersion.display)）"
        let url = URL(string: "mailto:\(Self.mail)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!

        // 2026-10-20：iOS 27 起 `canOpenURL` 已弃用（官方建议「直接尝试打开、按失败分支处理」）。
        // 改为用 open 的 completion 判断结果：成功即正常，失败走复制邮箱兜底。
        UIApplication.shared.open(url, options: [:]) { success in
            DispatchQueue.main.async {
                if success {
                    self.showFallback = false
                } else {
                    self.copyMailFallback()
                }
            }
        }
    }

    /// 邮件 App 不可用时的兜底：复制邮箱到剪贴板并浮出提示（3.2s 自动收起）
    private func copyMailFallback() {
        UIPasteboard.general.string = Self.mail
        showFallback = true
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if !Task.isCancelled { showFallback = false }
        }
    }
}

// MARK: - 版本号显示（单一真值）
//
// 以 Info.plist 的 MARKETING_VERSION 为准（工程已改 0.2.3），
// 版本历史页与设置页共用，避免「两处各写一个号」漂移。
enum AppVersion {
    static var display: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return (short?.isEmpty == false) ? short! : "0.2.8"
    }
}

// MARK: - 签名凭证（买断解锁）

/// 输入凭证 → 本地验签 → 写入权益。全程离线，不联网、不涉及账号。
///
/// 凭证格式见 `OfflineLicense.swift`：`CLIP1.<base64载荷>.<ECDSA-P256 签名>`。
/// 本页只做三件事：把本机设备码摆出来让人复制、收一串凭证、把结果说清楚。
///
/// 🔴 **App 内不出现任何价格**（见 `MembershipPlan` 里的历史注释）：
///    档位归属由卖家在店外说明，这里只说「已解锁 / 未解锁」。
struct LicenseActivationView: View {
    @EnvironmentObject private var store: PickupStore

    @State private var text = ""
    @State private var outcome: Outcome?
    @State private var copiedDevice = false
    /// 本机标识默认打码，点「显示」才展开
    @State private var revealed = false
    @State private var copyResetTask: Task<Void, Never>?

    private enum Outcome: Equatable {
        /// 激活成功，关联值是档位说明（如「永久」）
        case unlocked(String)
        /// 激活失败：标题 + 下一步该怎么做
        case rejected(String, String)

        /// 弹窗标题 / 正文。**结果必须由用户确认后才消失** ——
        /// 原先是在列表下方长出一张结果卡：验签失败时那行字很容易被
        /// 键盘或屏幕边缘挡掉，用户只看到"点了没反应"。
        var alertTitle: String {
            switch self {
            case .unlocked: return "凭证有效"
            case .rejected(let title, _): return title
            }
        }

        var alertMessage: String {
            switch self {
            case .unlocked(let label):
                return "校验通过，已切换为完整版（\(label)）。"
            case .rejected(_, let message):
                return message
            }
        }
    }

    private var deviceCode: String { LicenseDevice.current }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            // 版式对齐「通知提醒」「小组件」这些二级设置页：
            // 分组标题（卡外）→ 白卡 → 卡外说明，组间距 24。
            //
            // 🔴 2026-10-30 改版：原先是三张**品牌色卡**（天蓝 / 琥珀 / 绿）各自带
            //    彩色图标标题，放进一排白卡的设置模块里像另一个 App 的页面。
            //    设置语言里颜色只用来标"值的状态"，不用来给整张卡上色。
            VStack(spacing: 24) {
                statusSection
                deviceSection
                activateSection
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 14)
            .padding(.bottom, 60)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("凭证")
        .cloaksTabBar()
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: runLicenseScaffold)
        // 验签结果走系统弹窗：必须点「确认」才消失，不给"没看清就滑走"的机会。
        // 关闭（无论点确认还是点外部）就把 outcome 清掉，避免下次进页面又弹一次。
        .alert(outcome?.alertTitle ?? "",
               isPresented: Binding(get: { outcome != nil },
                                    set: { if !$0 { outcome = nil } }),
               presenting: outcome) { _ in
            Button("确认", role: .cancel) { outcome = nil }
        } message: { outcome in
            Text(outcome.alertMessage)
        }
    }

    // MARK: 当前状态

    /// 行尾的档位文字。买断制口径 —— **不出现「会员 / 年费 / 月付」任何订阅词**。
    /// 临时凭证按到期时间算剩余天数（凭证里签的是绝对时间，这里只是显示）。
    private var planValue: String {
        guard store.isPro else { return "免费版" }
        if store.plan == .lifetime { return "完整版 · 永久" }
        if let expiry = EntitlementSnapshot.load().expiresAt {
            let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0)
            return "临时 · 剩 \(days) 天"
        }
        return "临时"
    }

    private var statusSection: some View {
        // 🔴 2026-10-31 主人：**不出现「授权 / 解锁 / 激活」**这类词。
        //    App 内越像"卖东西"，审核越容易按 3.1.1（内购）挑刺；
        //    这里的口径改成描述「本机是什么版本」，而不是「你买了没」。
        SettingsGroup(title: "当前状态",
                      note: store.isPro
                        ? "功能全部可用。凭证只在本机校验，不联网、不上传。"
                        : "同屏显示 \(PickupStore.freeVisibleLimit) 条，最多存 \(PickupStore.freeStorageLimit) 条；超出后自动移除最旧的。") {
            SettingsPlainRow(title: "版本") {
                Text(planValue)
                    .font(.system(size: 17))
                    .foregroundStyle(store.isPro ? AppTheme.doneTint : Color.secondary)
                    .fixedSize()
            }
        }
    }

    // MARK: 本机标识

    private var deviceSection: some View {
        SettingsGroup(title: "本机标识",
                      note: "凭证与本机绑定，这一串就是绑定依据。更换设备后需按新设备重新签发。") {
            SettingsPlainRow(title: "标识") {
                HStack(spacing: 14) {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { revealed = !revealed }
                    } label: {
                        Text(revealed ? "隐藏" : "显示")
                            .font(.system(size: 17))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)

                    Button { copyDevice() } label: {
                        Text(copiedDevice ? "已复制" : "复制")
                            .font(.system(size: 17))
                            .foregroundStyle(copiedDevice ? AppTheme.doneTint : AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            SettingsDivider(style: .plain)

            // 35 个字符（32 位十六进制分四组）放不进行尾：17pt 标题已占去半行，
            // 挤在右边只剩 ~250pt，必然折行。整串单独占一行，15pt 等宽。
            // 默认打码（首尾各 8 位），点「显示」才展开 —— 复制永远复制完整值。
            Text(revealed ? LicenseDevice.display(deviceCode)
                          : LicenseDevice.masked(deviceCode))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }

    // MARK: 输入凭证

    private var activateSection: some View {
        VStack(spacing: 12) {
            SettingsGroup(title: "凭证",
                          note: "校验只在本机进行，不联网。凭证与本机标识一一对应，换机需重新签发。") {
                editor
                SettingsDivider(style: .plain)
                actionRow(title: "从剪贴板粘贴", systemImage: "doc.on.clipboard") { pasteCredential() }

                if !text.isEmpty {
                    SettingsDivider(style: .plain)
                    actionRow(title: "清空", systemImage: "xmark.circle", tint: .secondary) {
                        text = ""
                        outcome = nil
                    }
                }
            }

            activateButton
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)

            if text.isEmpty {
                Text("CLIP1 开头的一整串，中间没有空格。")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
        .padding(16)
    }

    /// 设置页形态的动作行：整行可点，标题用强调色，右侧配一个弱化的符号。
    ///
    /// 原先这里是一排胶囊小按钮（粘贴 / 清空 / 激活），那是工具条的语汇；
    /// 放进「授权状态 + 设备码」这排设置卡里，只有它长得不像设置页。
    private func actionRow(title: String, systemImage: String,
                           tint: Color = AppTheme.accent,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(tint)

                Spacer(minLength: 8)

                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(tint.opacity(0.75))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// 主操作：与「添加」页的提交键同一口径（胶囊实心主色）。
    private var activateButton: some View {
        Button { activate() } label: {
            Text("验证")
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(trimmed.isEmpty ? Color(.tertiarySystemFill) : AppTheme.accent,
                            in: .capsule)
                .foregroundStyle(trimmed.isEmpty ? Color.secondary : Color.white)
        }
        .buttonStyle(.plain)
        .disabled(trimmed.isEmpty)
    }

    // MARK: 截图脚手架

    /// `LICENSE_VOUCHER=<凭证>` 注入一串凭证并自动点一次「激活」。
    ///
    /// 命令行点不到屏幕上的按钮（本机没有 idb / applesimutils，AppleScript 会被
    /// 辅助功能权限拒绝），没有这个入口就拍不到结果弹窗 —— 而弹窗正是要验的东西。
    /// 走真实 `activate()`，不是伪造 outcome，验签与写盘都会被真的执行。
    private func runLicenseScaffold() {
        guard let voucher = ProcessInfo.processInfo.environment["LICENSE_VOUCHER"],
              !voucher.isEmpty else { return }
        Task { @MainActor in
            // 等导航转场落定再弹，否则 alert 会被转场动画吃掉。
            try? await Task.sleep(nanoseconds: 800_000_000)
            text = voucher
            activate()
        }
    }

    // MARK: 动作

    private func activate() {
        guard !trimmed.isEmpty else { return }
        switch LicenseActivation.activate(trimmed) {
        case .success(let payload):
            // 关键一步：不改这一步，界面会停在免费档（权益快照已经写盘，但 store 不知道）
            store.refreshEntitlement()
            outcome = .unlocked(planWord(payload.service.plan))
            text = ""
        case .failure(let error):
            outcome = .rejected(error.title, error.message)
        }
    }

    private func pasteCredential() {
        guard let value = UIPasteboard.general.string, !value.isEmpty else { return }
        text = value
        outcome = nil
    }

    private func copyDevice() {
        UIPasteboard.general.string = deviceCode
        withAnimation(.easeOut(duration: 0.15)) { copiedDevice = true }
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.2)) { copiedDevice = false }
            }
        }
    }

    /// 档位的中文短名。**买断制：只说「临时 7 天 / 永久」，不出现会员、年费这类订阅词。**
    private func planWord(_ plan: MembershipPlan) -> String {
        switch plan {
        case .none:     return "未开通"
        case .trial:    return "临时 7 天"
        case .lifetime: return "永久"
        }
    }
}
