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
        case .license:      return "完整版"
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
        case .license:      return "sparkles"
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

    /// 关于页「设备 UUID」的复制反馈（1.6s 后自动复原）
    @State private var copiedUUID = false

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
                proBanner
                settingsSection
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
        case .license:    FullVersionView()
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

                Text("数据只保存在这台设备上，不上传任何服务器。")
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

    // MARK: 顶部订阅横幅

    /// 设置页顶部那条 PRO 横幅（2026-10-31 主人参照 Infuse 定）。
    ///
    /// 为什么放到最顶上：App 免费下载、靠订阅解锁，**入口必须显眼**；
    /// 藏起来既不厚道，也会被审核按「付费功能没有明显入口」挑刺。
    /// 已购时同一块横幅改口径为「完整版已开通」，不摆第二次购买。
    private var proBanner: some View {
        NavigationLink {
            FullVersionView()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("拾码")
                            .font(.system(size: 23, weight: .bold))
                        Text("PRO")
                            .font(.system(size: 12, weight: .heavy))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.24), in: .rect(cornerRadius: 6))
                    }
                    .foregroundStyle(.white)

                    Text(store.isPro ? "完整版已开通" : "查看订阅")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // 橙色渐变：整页唯一的彩色块。
                // 🔴 这里**故意不用**主题色（主题是蓝的）：横幅是营销面，
                //    参照 Infuse 的高饱和橙来看更像"付费墙"，也更容易被注意到。
                //    原来的 amber(#B45309) 起手偏褐，压到白底上像脏了。
                LinearGradient(colors: [AppTheme.proOrangeLight, AppTheme.proOrange],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
            }
            .clipShape(.rect(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .shadow(color: AppTheme.todayTint.opacity(0.25), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
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

            Text("数据只保存在这台设备上，不上传任何服务器。")
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

                SettingsDivider()

                // 法律文档（2026-10-31）：订阅类 App 必须能点到隐私政策与使用条款。
                // 用系统浏览器打开 —— App 内嵌网页会在审核时被问"为什么不用 SF Safari"。
                legalRow(symbol: "hand.raised.fill", title: "隐私政策",
                         note: "无账号、无联网；取件数据只在本机", url: LegalLinks.privacy,
                         tint: AppTheme.doneTint)

                SettingsDivider()

                legalRow(symbol: "doc.text.fill", title: "使用条款",
                         note: "订阅、自动续期与退款规则", url: LegalLinks.terms,
                         tint: AppTheme.sky)
            }
            .cardSurface()
        }
    }

    /// 复制本机 UUID：**复制完整值**（界面上是打码的）
    private func copyDeviceUUID() {
        UIPasteboard.general.string = LicenseDevice.current
        withAnimation(.easeOut(duration: 0.15)) { copiedUUID = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.easeOut(duration: 0.2)) { copiedUUID = false }
        }
    }

    /// 打开外部法律文档的整行（点哪都跳，右侧带外链箭头提示「会离开 App」）
    private func legalRow(symbol: String, title: String, note: String,
                          url: URL, tint: Color) -> some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            SettingsRow(symbol: symbol, title: title, subtitle: note,
                        showsChevron: false, tint: tint,
                        trailing: AnyView(
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.quaternary)
                        ))
        }
        .buttonStyle(.plain)
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
        return (short?.isEmpty == false) ? short! : "0.3.0"
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
// MARK: - 完整版（订阅）

/// 免费下载 + 三档解锁（2026-10-31 主人定：月 ¥1 / 年 ¥9 / 终身 ¥28）。
///
/// 版式：**大标题 → 竖排方案（单选）→ 功能清单 → 主行动键 → 恢复购买**。
/// 刻意与 Infuse 的订阅页不同构（那边是三张并排卡 + 橙色线稿图标 + 直接点卡即买）：
/// 信息结构可以参考，视觉签名不能照搬 —— 并排卡＋线稿图标是它最显眼的识别点。
/// 这里用一个可选方案列表 + 一枚主按钮，买之前先明确"我要买哪一档"。
struct FullVersionView: View {
    @EnvironmentObject private var store: PickupStore
    @ObservedObject private var purchase = PurchaseStore.shared

    /// 默认落在主推档（买断）
    @State private var selected: PurchaseStore.Plan = .lifetime

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header

                if purchase.isOwned {
                    ownedSection
                } else {
                    planList
                    featureList
                    primaryButton
                    restoreButton
                    finePrint
                }

                if let message = purchase.message, !purchase.isOwned {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 10)
            .padding(.bottom, 60)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        // 截图脚手架：命令行点不了、也滚不动屏幕，`PAYWALL_ANCHOR=bottom`
        // 时直接落到页底，用来验「恢复购买 + 条款链接」这两行确实在。
        .onAppear {
            guard ProcessInfo.processInfo.environment["PAYWALL_ANCHOR"] == "bottom" else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .navigationTitle("完整版")
        .navigationBarTitleDisplayMode(.inline)
        .cloaksTabBar()
        .onAppear {
            if purchase.canPurchase == false { Task { await purchase.loadProducts() } }
        }
        }
    }

    // MARK: 页首

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("拾码")
                    .font(.system(size: 34, weight: .heavy))
                Text("PRO")
                    .font(.system(size: 15, weight: .heavy))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.proOrange, in: .rect(cornerRadius: 7))
                    .foregroundStyle(.white)
            }

            Text("免费下载。解锁后不限条数，桌面小组件与实时活动一并完整。")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 方案（竖排单选）

    private var planList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "选择方案")

            VStack(spacing: 10) {
                ForEach(PurchaseStore.Plan.allCases) { plan in
                    planCard(plan)
                }
            }

            Text("推荐买断：一次付清、永久有效，不用记着取消订阅。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func planCard(_ plan: PurchaseStore.Plan) -> some View {
        let on = selected == plan
        let price = purchase.price(for: plan)

        return Button {
            withAnimation(.snappy(duration: 0.2)) { selected = plan }
        } label: {
            HStack(spacing: 12) {
                // 单选圈：选中填橙，未选空心
                ZStack {
                    Circle()
                        .strokeBorder(on ? AppTheme.proOrange : Color(.separator), lineWidth: on ? 2 : 1.5)
                        .frame(width: 22, height: 22)
                    if on {
                        Circle()
                            .fill(AppTheme.proOrange)
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(plan.title)
                            .font(.system(size: 17, weight: .semibold))
                        if plan.isRecommended {
                            Text("推荐")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.proOrange.opacity(0.14), in: .rect(cornerRadius: 4))
                                .foregroundStyle(AppTheme.proOrange)
                        }
                    }
                    Text(plan.period)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                Text(price ?? "—")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(on ? AppTheme.proOrange : Color.primary)
                    .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground),
                        in: .rect(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(on ? AppTheme.proOrange : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: 功能清单

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "解锁什么")

            VStack(spacing: 0) {
                featureRow(symbol: "tray.full.fill", title: "不限条数",
                           note: "免费版同屏 \(PickupStore.freeVisibleLimit) 条、最多存 \(PickupStore.freeStorageLimit) 条；解锁后全部放开")
                SettingsDivider()
                featureRow(symbol: "square.grid.2x2.fill", title: "桌面小组件全尺寸",
                           note: "免费版只有小、中两种尺寸；解锁后大尺寸与 iPad 尺寸一并可用")
                SettingsDivider()
                featureRow(symbol: "iphone.gen3.radiowaves.left.and.right", title: "实时活动",
                           note: "灵动岛与锁屏常驻最新取件码")
                SettingsDivider()
                featureRow(symbol: "arrow.triangle.2.circlepath", title: "后续更新",
                           note: "订阅期内或买断后，新版本的新功能都包含")
            }
            .cardSurface()
        }
    }

    private func featureRow(symbol: String, title: String, note: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsGlyph(symbol: symbol, tint: AppTheme.proOrange, size: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: 主行动

    private var primaryButton: some View {
        Button {
            Task { await purchase.purchase(selected) }
        } label: {
            Text(primaryTitle)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(canBuy ? AppTheme.proOrange : Color(.tertiarySystemFill), in: .capsule)
                .foregroundStyle(canBuy ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(!canBuy)
    }

    private var canBuy: Bool { purchase.canPurchase && purchase.purchasingPlan == nil }

    private var primaryTitle: String {
        if purchase.purchasingPlan != nil { return "处理中…" }
        guard let price = purchase.price(for: selected) else { return "暂时无法购买" }
        switch selected {
        case .monthly:  return "\(price) / 月 订阅"
        case .yearly:   return "\(price) / 年 订阅"
        case .lifetime: return "\(price) 买断"
        }
    }

    private var restoreButton: some View {
        Button {
            Task { await purchase.restore() }
        } label: {
            Text("恢复购买")
                .font(.system(size: 16, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay {
                    Capsule().strokeBorder(AppTheme.proOrange.opacity(0.55), lineWidth: 1.5)
                }
                .foregroundStyle(AppTheme.proOrange)
        }
        .buttonStyle(.plain)
    }

    /// 自动续期说明 + 隐私政策 / 使用条款（App Review 3.1.2 要求在订阅页能点到）
    private var finePrint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("订阅会自动续期：确认购买后从 Apple ID 扣款，当前周期结束前 24 小时内自动续费；随时可在「设置 › Apple ID › 订阅」中取消。买断档不自动续期。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Link("隐私政策", destination: LegalLinks.privacy)
                Text("·").foregroundStyle(.tertiary)
                Link("使用条款", destination: LegalLinks.terms)
            }
            .font(.caption)
            // 付费面上统一用橙，别让两条蓝色链接在整页里跳出来
            .tint(AppTheme.proOrange)
            .foregroundStyle(AppTheme.proOrange)
        }
        .padding(.horizontal, 4)
        .id("bottom")
    }

    // MARK: 已开通

    private var ownedSection: some View {
        VStack(spacing: 10) {
            SettingsGroup(title: "当前状态", note: "感谢支持。换机或重装后在原 Apple ID 下「恢复购买」即可找回。") {
                SettingsPlainRow(title: "版本") {
                    Text(store.plan == .lifetime ? "已买断" : "已订阅")
                        .font(.system(size: 17))
                        .foregroundStyle(AppTheme.doneTint)
                        .fixedSize()
                }
            }

            Button {
                Task { await purchase.restore() }
            } label: {
                Text("恢复购买")
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay { Capsule().strokeBorder(Color(.separator), lineWidth: 1.5) }
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            finePrint
        }
    }
}
