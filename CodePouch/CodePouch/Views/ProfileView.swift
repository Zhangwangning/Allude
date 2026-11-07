import SwiftUI
import MessageUI
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
    case appearance
    case fontSize
    case language
    case automation
    case notification
    case widget
    case activity
    case courier
    case station
    case guide
    case license
    case activation
    case storage
    case feedback
    case version
    case privacy
    case aiCapability

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance:   return "外观"
        case .fontSize:     return "字体大小"
        case .language:     return "语言"
        case .automation:   return "快捷指令自动化"
        case .notification: return "通知提醒"
        case .widget:       return "桌面小组件"
        case .activity:     return "实时活动与灵动岛"
        case .courier:      return "快递公司"
        case .station:      return "驿站管理"
        case .guide:        return "使用教程"
        case .license:      return "拾码 Pro"
        case .activation:   return "激活"
        case .storage:      return "本机数据"
        case .feedback:     return "反馈"
        case .version:      return "版本"
        case .privacy:      return "隐私"
        case .aiCapability: return "Apple 智能"
        }
    }

    var symbol: String {
        switch self {
        case .appearance:   return "circle.lefthalf.filled"
        case .fontSize:     return "textformat.size"
        case .language:     return "globe"
        case .automation:   return "bolt.badge.automatic.fill"
        case .notification: return "bell.badge.fill"
        case .widget:       return "square.text.square.fill"
        case .activity:     return "platter.filled.top.iphone"
        case .courier:      return "shippingbox.fill"
        case .station:      return "storefront.fill"
        case .guide:        return "book.fill"
        case .license:      return "sparkles"
        case .activation:   return "key.horizontal.fill"
        case .storage:      return "internaldrive.fill"
        case .feedback:     return "envelope.fill"
        case .version:      return "info.circle.fill"
        case .privacy:      return "hand.raised.fill"
        case .aiCapability: return "brain.head.profile"
        }
    }

    var tint: Color {
        switch self {
        case .appearance:   return AppTheme.accent
        case .fontSize:     return AppTheme.sky
        case .language:     return AppTheme.indigo
        case .automation:   return AppTheme.amber
        case .notification: return AppTheme.pendingTint
        case .widget:       return AppTheme.sky
        case .activity:     return AppTheme.accent
        case .courier:      return AppTheme.indigo
        case .station:      return AppTheme.violet
        case .guide:        return AppTheme.sky
        case .license:      return AppTheme.amber
        case .activation:   return AppTheme.indigo
        case .storage:      return AppTheme.todayTint
        case .feedback:     return AppTheme.doneTint
        case .version:      return AppTheme.todayTint
        case .privacy:      return AppTheme.doneTint
        case .aiCapability: return AppTheme.violet
        }
    }

    /// 侧栏分组（顺序即显示顺序，与原来长页的分组一一对应）
    static let generalGroup: [SettingsPane] = [.automation, .notification, .widget, .activity, .courier, .station, .guide, .license, .appearance, .fontSize, .language]
    static let dataGroup: [SettingsPane] = [.storage]
    static let aboutGroup: [SettingsPane] = [.version, .aiCapability]
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

    /// 订阅入口的「暂不支持」提示（2026-10-31 主人：不让进二级页）

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
            // 🔴 2026-11-07 主人：iPhone Duo（折叠/展开）也用直板机这套单列布局，
            //    不再走 iPad 那种"左侧分组 + 右侧面板"的分栏。
            //    分栏只留给 iPad（暂不维护）。
            if UIDevice.current.userInterfaceIdiom == .pad {
                splitSettings
            } else {
                stackedSettings
            }
        }
        .overlay { feedbackToast }
        // 订阅暂未开放：点了只弹提示，不进入二级页
        .sheet(isPresented: $feedback.showComposer) {
            MailComposeView(subject: feedback.composerSubject,
                            body: feedback.composerBody,
                            attachment: feedback.composerAttachment) {
                feedback.showComposer = false
            }
        }
    }

    /// 窄屏：原「一张长页」布局，保持不变。
    private var stackedSettings: some View {
        ScrollView {
            VStack(spacing: 16) {
                proBanner
                settingsSection
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
                Text(title.L)
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

            Text(item.title.L)
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
        .onTapGesture {
            // 语言没有 App 内页面：按主人要求直接跳到 设置 › App › 拾码
            if item == .language { openAppLanguageSettings() } else { pane = item }
        }
        .tag(item)
    }

    /// 右侧内容：选中项展开的页面 / 卡片
    @ViewBuilder
    private func paneContent(_ item: SettingsPane) -> some View {
        switch item {
        case .appearance: AppearanceSettingsView()
        case .fontSize:   FontSizeView()
        case .language:   languageDetailPane
        case .automation: AutoRecordSettingsView()
        case .notification: NotificationSettingsView()
        case .widget:     WidgetSettingsView()
        case .activity:   ActivityPreviewGallery()
        case .courier:    CourierGalleryView(scope: .courier)
        case .station:    CourierGalleryView(scope: .station)
        case .guide:      UsageGuideView()
        case .license:    FullVersionView()
        case .activation: ActivationView()
        case .version:    VersionHistoryView()
        case .storage:    dataDetailPane
        case .feedback:   feedbackPane
        case .privacy:    privacyPane
        case .aiCapability: AICapabilityView()
        }
    }

    /// 语言：不在 App 内做切换，交给系统（跳 设置 › App › 拾码）
    @ViewBuilder
    private var languageDetailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "语言")

                VStack(spacing: 0) {
                    SettingsRow(symbol: "globe", title: "当前语言", detail: "简体中文",
                                showsChevron: false, tint: AppTheme.indigo)
                    SettingsDivider()
                    Button { openAppLanguageSettings() } label: {
                        SettingsRow(symbol: "arrow.up.forward.app.fill", title: "在系统设置中更改",
                                    detail: nil, tint: AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .cardSurface()

                Text("语言由 iOS 统一管理：设置 › App › 拾码 › 语言。\n首次安装时默认是简体中文。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground))
    }

    /// 当前界面语言名（跟着系统走，不在 App 内切换）
    private var currentLanguageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
        return code.hasPrefix("zh-Hant") ? "繁體中文" : "简体中文"
    }

    /// 跳到 iOS 设置里本 App 的页面（语言项在那里）
    private func openAppLanguageSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
                        DiagnosticsLog.record("feedback", "open")
                        feedback.startMail(includeLog: feedback.includeLog)
                    } label: {
                        SettingsRow(symbol: "envelope.fill", title: "发送邮件反馈",
                                    subtitle: FeedbackModel.mail,
                                    showsChevron: false,
                                    tint: AppTheme.doneTint)
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    Toggle(isOn: $feedback.includeLog) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("附带诊断日志")
                                .font(.system(size: 15))
                            Text("版本、系统、最近的操作记录，不含短信内容")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(AppTheme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .cardSurface()

                Text("日志只在本机滚动保存，只有你点发送并确认后才会随邮件发出。")
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
                                showsChevron: false,
                                tint: AppTheme.doneTint)
                }
                .cardSurface()

                Text("无账号、无联网；取件数据全程只在本机。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

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
                    AutoRecordSettingsView()
                } label: {
                    SettingsRow(symbol: "bolt.badge.automatic.fill", title: "快捷指令自动化",
                                tint: AppTheme.amber)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    SettingsRow(symbol: "bell.badge.fill", title: "通知提醒",
                                tint: AppTheme.pendingTint)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                NavigationLink {
                    WidgetSettingsView()
                } label: {
                    SettingsRow(symbol: "square.text.square.fill", title: "桌面小组件",
                                tint: AppTheme.sky)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                NavigationLink {
                    ActivityPreviewGallery()
                } label: {
                    // 🔴 2026-11-01 主人：设置首页这一行的名字与二级页导航栏对齐
                    SettingsRow(symbol: "platter.filled.top.iphone",
                                title: "实时活动与灵动岛",
                                tint: AppTheme.accent,
                                locked: !store.isPro)
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
                                tint: AppTheme.indigo)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                NavigationLink {
                    CourierGalleryView(scope: .station)
                } label: {
                    SettingsRow(symbol: "storefront.fill", title: "驿站管理",
                                tint: AppTheme.violet)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                // 使用教程（2026-10-31 主人：放回「通用」最后一个）
                NavigationLink {
                    UsageGuideView()
                } label: {
                    SettingsRow(symbol: "book.fill", title: "使用教程",
                                tint: AppTheme.violet)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                // App 图标（2026-11-01 主人：三套内置图标可切换）
                NavigationLink {
                    AppIconSettingsView()
                } label: {
                    SettingsRow(symbol: "app.badge.fill", title: "App 图标",
                                detail: AppIconStore.current.title,
                                tint: AppTheme.doneTint)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                // 外观 / 字体大小 / 语言（2026-11-07 主人：不常用，挪到「通用」最下面）
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    SettingsRow(symbol: "circle.lefthalf.filled", title: "外观",
                                detail: AppearanceSettings.shared.mode.title,
                                tint: AppTheme.accent)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                NavigationLink {
                    FontSizeView()
                } label: {
                    SettingsRow(symbol: "textformat.size", title: "字体大小",
                                detail: AppearanceSettings.shared.followSystem
                                    ? "跟随系统" : AppearanceSettings.shared.step.title,
                                tint: AppTheme.sky)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                Button { openAppLanguageSettings() } label: {
                    SettingsRow(symbol: "globe", title: "语言",
                                detail: currentLanguageName, tint: AppTheme.indigo)
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
        // 🔴 2026-11-07 主人：恢复订阅页 —— 横幅直接进 FullVersionView，
        //    不再弹「暂不支持订阅」。
        //    （2026-10-31 之所以拦住，是商品还没在 App Store Connect 建好；
        //      现在准备上架，入口必须能进，否则审核按「付费功能无入口」挑刺。）
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
                            .background(.white.opacity(0.55), in: .rect(cornerRadius: 6))
                    }
                    .foregroundStyle(AppTheme.champagneInk)

                    Text(store.isPro ? "拾码 Pro 已开通" : "了解拾码 Pro")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.champagneInk.opacity(0.8))
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.champagneInk.opacity(0.75))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 23)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // 橙色渐变：整页唯一的彩色块。
                // 🔴 这里**故意不用**主题色（主题是蓝的）：横幅是营销面，
                //    参照 Infuse 的高饱和橙来看更像"付费墙"，也更容易被注意到。
                //    原来的 amber(#B45309) 起手偏褐，压到白底上像脏了。
                LinearGradient(colors: [AppTheme.champagneLight, AppTheme.champagne],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
            }
            .clipShape(.rect(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .shadow(color: AppTheme.champagneInk.opacity(0.16), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }

    // 2026-11-07 主人：上架前移除「激活」入口（App Review 3.1.1），
    // 对应分组已从两种布局里删除，激活页代码保留但不再有入口。

    // MARK: 关于（版本 / 反馈 / 隐私）

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "更多")

            VStack(spacing: 0) {
                NavigationLink {
                    HelpCenterView()
                } label: {
                    SettingsRow(symbol: "questionmark.bubble.fill", title: "帮助与反馈",
                                tint: AppTheme.sky)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                NavigationLink {
                    AboutView()
                } label: {
                    SettingsRow(symbol: "info.circle.fill", title: "关于",
                                detail: AppVersion.display,
                                tint: AppTheme.todayTint)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                // 🔴 iPhone 用的是这一份**手写**的「更多」组，不走 SettingsPane.aboutGroup
                //    （那是 iPad / Duo 宽屏分栏用的）。2026-11-05 加了 AI 能力检测却漏了这处，
                //    真机上完全看不到 —— 两套布局都要各加一次。
                NavigationLink {
                    AICapabilityView()
                } label: {
                    SettingsRow(symbol: "brain.head.profile", title: "Apple 智能",
                                tint: AppTheme.violet)
                }
                .buttonStyle(.plain)
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

    /// 法律文档整行：**推入 App 内页面**（2026-10-31 主人：不要跳浏览器）。
    /// 文档 HTML 随包发布，离线可读；Store 表单里的地址另填 `LegalLinks`。
    private func legalRow(symbol: String, title: String, note: String,
                          document: LegalDocument, tint: Color) -> some View {
        NavigationLink {
            LegalDocumentView(document: document)
        } label: {
            SettingsRow(symbol: symbol, title: title, subtitle: note, tint: tint)
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
                Text(FeedbackModel.mail.L)
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
    /// 是否附带诊断日志（默认开：出问题的人一般不知道该带什么）
    @Published var includeLog = true
    /// 系统邮件编辑器
    @Published var showComposer = false
    @Published var composerSubject = ""
    @Published var composerBody = ""
    @Published var composerAttachment: (name: String, data: Data)?

    private var hideTask: Task<Void, Never>?

    var subtitle: String { Self.mail }

    /// 组织一封带诊断日志的反馈邮件（2026-10-31 主人：日志随反馈一起发过来）。
    ///
    /// 优先用系统邮件编辑器（能带附件）；设备没配邮件时退回复制邮箱的兜底，
    /// 那种情况下把日志正文贴进剪贴板不合适（太长），所以只提示用户去配置邮件。
    func startMail(includeLog: Bool) {
        let version = AppVersion.display
        composerSubject = "拾码反馈（\(version)）"
        composerBody = """
        请描述你遇到的问题（什么时候、做了什么、预期是什么）：



        —— 以下由 App 自动填写 ——
        版本：\(version)
        系统：iOS \(UIDevice.current.systemVersion)
        """

        if includeLog {
            let text = DiagnosticsLog.exportText()
            composerAttachment = (name: "codepouch-log.txt", data: Data(text.utf8))
        } else {
            composerAttachment = nil
        }

        if MFMailComposeViewController.canSendMail() {
            showComposer = true
        } else {
            // 没有邮件账号：不硬弹，复制邮箱兜底（日志留在本机，下次配好再发）
            copyMailFallback()
        }
    }

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
        return (short?.isEmpty == false) ? short! : "0.3.2"
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

/// 免费下载 + 三档解锁（2026-11-07 主人定：月 ¥1 / 年 ¥9 / 终身 ¥18）。
///
/// 版式：**大标题 → 竖排方案（单选）→ 功能清单 → 主行动键 → 恢复购买**。
/// 刻意与 Infuse 的订阅页不同构（那边是三张并排卡 + 橙色线稿图标 + 直接点卡即买）：
/// 信息结构可以参考，视觉签名不能照搬 —— 并排卡＋线稿图标是它最显眼的识别点。
/// 这里用一个可选方案列表 + 一枚主按钮，买之前先明确"我要买哪一档"。
/// 订阅面板占位（宽屏分栏用）。
///
/// 2026-10-31 主人：订阅未开放，不允许进入二级页 —— 分栏布局里点侧栏
/// 「完整版」不该出现定价页，这里给一张说明卡。
struct SubscriptionUnavailablePane: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text("暂不支持订阅")
                .font(.system(size: 17, weight: .semibold))
            Text("敬请期待……")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("拾码 Pro")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FullVersionView: View {
    @EnvironmentObject private var store: PickupStore
    @ObservedObject private var purchase = PurchaseStore.shared

    /// 默认落在主推档（买断）
    @State private var selected: PurchaseStore.Plan = .lifetime
    /// 条款 / 隐私以 App 内页面弹出，不跳浏览器
    @State private var legalSheet: LegalDocument?

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            // 2026-10-31 主人：**一屏放得下，不要翻页**。
            // 所以去掉了页首的大标题块，版式与其它设置页同口径：
            // 分组标题 13pt、行标题 17pt、说明 11–12pt，靠紧凑间距压进一屏。
            VStack(alignment: .leading, spacing: 18) {
                // 页内标题（2026-10-31 主人要求补上）。导航栏那个「完整版」太小，
                // 进页面第一眼得知道这一页在卖什么；字号取 24pt，介于正文 17 与
                // 系统大标题 34 之间，不与导航栏抢层级。
                titleBlock

                // 2026-10-31 主人：**已购后页面结构不变**，只把三张方案卡换成一张「谢谢您」，
                // 解锁清单、恢复购买、条款链接都还在。不要另做一个"订阅成功页"。
                if purchase.isOwned {
                    thanksCard
                } else {
                    planList
                }

                featureList

                if !purchase.isOwned {
                    primaryButton
                }

                restoreButton
                finePrint

                if let message = purchase.message, !purchase.isOwned {
                    Text(message.L)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 6)
            .padding(.bottom, 20)
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
        .navigationTitle("拾码 Pro")
        .navigationBarTitleDisplayMode(.inline)
        .cloaksTabBar()
        .onAppear {
            if purchase.canPurchase == false { Task { await purchase.loadProducts() } }
        }
        .sheet(item: $legalSheet) { document in
            LegalDocumentView(document: document)
        }
        }
    }

    // MARK: 页内标题

    private var titleBlock: some View {
        // 两行标题（2026-10-31 主人指定文案）。断行位置按语义切：
        // 「感谢」单独一行，「订阅 拾码 CodePouch Pro」整行 —— 与参考页同样的
        // 大标题节奏，但不复制它的字句。
        VStack(alignment: .leading, spacing: 2) {
            Text("感谢订阅")
            Text("拾码 CodePouch Pro")
        }
        .font(.system(size: 26, weight: .bold))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 方案（横排）

    private var planList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "选择方案")

            // 三档**横排**（2026-10-31 主人：参照 Infuse 的横向分布）。
            // 402pt 屏上内容宽 370pt，卡片间距 8 → 每张约 118pt，
            // 价格 20pt 字刚好放得下「¥18.00」。
            HStack(spacing: 8) {
                ForEach(PurchaseStore.Plan.allCases) { plan in
                    planCard(plan)
                }
            }
            .padding(.top, 9)     // 给「推荐」徽章留出上探的空间

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
            VStack(spacing: 6) {
                Text(plan.title.L)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                // 价格是这个卡片的主角：三档之间要比的是这个数
                Text(price ?? "—")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(on ? AppTheme.champagneInk : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                Text(plan.shortPeriod.L)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(on ? AppTheme.champagneLight.opacity(0.55)
                              : Color(.secondarySystemGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(on ? AppTheme.champagne : Color.clear, lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                // 只靠描边颜色不够：截图、色弱、或渲染晚一帧都可能看错档位。
                // 加一个勾，选中与否有形状上的差别。
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.champagne)
                        .padding(7)
                }
            }
            .overlay(alignment: .top) {
                if plan.isRecommended {
                    Text("推荐")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.champagneInk, in: .capsule)
                        .foregroundStyle(AppTheme.champagneLight)
                        .offset(y: -9)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: 功能清单

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            SettingsGlyph(symbol: symbol, tint: AppTheme.champagneIcon, size: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.L)
                    .font(.system(size: 15, weight: .semibold))
                Text(note.L)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: 主行动

    private var primaryButton: some View {
        Button {
            Task { await purchase.purchase(selected) }
        } label: {
            Text(primaryTitle.L)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(canBuy ? AppTheme.champagne : Color(.tertiarySystemFill), in: .capsule)
                .foregroundStyle(canBuy ? AppTheme.champagneInk : Color.secondary)
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
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .overlay {
                    Capsule().strokeBorder(AppTheme.champagneInk.opacity(0.55), lineWidth: 1.5)
                }
                .foregroundStyle(AppTheme.champagneInk)
        }
        .buttonStyle(.plain)
    }

    /// 自动续期说明 + 隐私政策 / 使用条款（App Review 3.1.2 要求在订阅页能点到）
    private var finePrint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("订阅会自动续期：确认购买后从 Apple ID 扣款，当前周期结束前 24 小时内自动续费；随时可在「设置 › Apple ID › 订阅」中取消。买断档不自动续期。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("隐私政策") { legalSheet = .privacy }
                Text("·").foregroundStyle(.tertiary)
                Button("使用条款") { legalSheet = .terms }
            }
            .font(.system(size: 12))
            // 付费面上统一用橙，别让两条蓝色链接在整页里跳出来
            .tint(AppTheme.champagneInk)
            .foregroundStyle(AppTheme.champagneInk)
        }
        .padding(.horizontal, 4)
        .id("bottom")
    }

    // MARK: 已开通

    /// 已购状态的那张卡：与三张方案卡**同一位置、同一视觉语言**
    /// （同样的圆角、浅金底、金色描边），只是内容换成一句道谢。
    /// 这样买完之后页面不会"换一张脸"，只是卡片本身变了。
    private var thanksCard: some View {
        VStack(spacing: 6) {
            Text("谢谢您")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.champagneInk)

            Text(store.plan == .lifetime ? "已买断 · 永久有效" : "拾码 Pro 已开通")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.champagneInk.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.champagneLight.opacity(0.55))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.champagne, lineWidth: 2)
        }
    }

}
