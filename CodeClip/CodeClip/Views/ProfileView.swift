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

struct SettingsView: View {
    @EnvironmentObject private var store: PickupStore

    /// 直接订阅账户仓库：改名 / 换头像后账户卡自己重画。
    @ObservedObject private var accountStore = LocalAccountStore.shared

    /// 反馈结果的轻提示（邮件打不开时引导复制邮箱）。
    @StateObject private var feedback = FeedbackModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                accountCard
                settingsSection
                dataSection
                aboutSection
                footer
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        // 页面底 = 浅灰，卡片才是白（2026-09-23 修正口径，与全 App 一致）
        .background(Color(.systemGroupedBackground))
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // 设置是标签根页：兜底露出标签栏（其它标签返回同口径，见 RootView）
            TabBarCloak.shared.reveal()
        }
        .overlay { feedbackToast }
    }

    // MARK: 账户卡

    /// 账户卡。本机档案恒存在，没有"未登录"这回事；档位徽章随 VIP 体系退役。
    private var accountCard: some View {
        NavigationLink {
            AccountDetailView()
        } label: {
            HStack(spacing: 14) {
                AccountAvatar(size: 58)

                VStack(alignment: .leading, spacing: 5) {
                    Text(accountStore.current.name)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("本机档案 · 不联网")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(16)
            .cardSurface()
        }
        .buttonStyle(.plain)
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

                NavigationLink {
                    CourierGalleryView()
                } label: {
                    SettingsRow(symbol: "shippingbox.fill", title: "快递管理",
                                subtitle: "\(CourierBrand.table.count) 个品牌图标 · 驿站名称可自定义",
                                tint: AppTheme.indigo)
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
            Text("码夹 CodeClip")
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
        let subject = "码夹反馈（\(AppVersion.display)）"
        let url = URL(string: "mailto:\(Self.mail)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!

        if UIApplication.shared.canOpenURL(url) {
            showFallback = false
            UIApplication.shared.open(url)
        } else {
            UIPasteboard.general.string = Self.mail
            showFallback = true
            hideTask?.cancel()
            hideTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_200_000_000)
                if !Task.isCancelled { showFallback = false }
            }
        }
    }
}

// MARK: - 版本号显示（单一真值）
//
// 以 Info.plist 的 MARKETING_VERSION 为准（工程已改 0.2.1），
// 版本历史页与设置页共用，避免「两处各写一个号」漂移。
enum AppVersion {
    static var display: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return (short?.isEmpty == false) ? short! : "0.2.1"
    }
}

// MARK: - 账户
//
// 二级页：改头像、改名字（单账户内置，无登录语义 —— 2026-09-23 定稿口径不变）。
// 头像选完即生效，名字走右上角「保存」。

struct AccountDetailView: View {
    @EnvironmentObject private var store: PickupStore

    @ObservedObject private var accountStore = LocalAccountStore.shared
    @StateObject private var model = AccountDetailModel()

    /// ⚠️ 必须是 `@FocusState` 且**直接挂在 `TextField` 上** ——
    ///    `.focused()` 施加给容器（比如一个自定义输入行组件）不会生效，
    ///    焦点只认它直接修饰的那个可聚焦视图。
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 顶部身份区：头像 + 名字直接落在页面底色上，**不再包白卡**。
                hero
                nameSection
                avatarEntrySection
                summarySection
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        // 页面底 = 浅灰，卡片才是白（2026-09-23 修正，理由同设置主页）
        .background(Color(.systemGroupedBackground))
        .navigationTitle("账户")
        .navigationBarTitleDisplayMode(.inline)
        // 🔴 设置分支二级页必须挂：之前漏挂导致（1）进入账户页标签栏不收起、
        // （2）从「更换头像」返回时计数被扣回零、标签栏在账户页上蹦出来。
        .cloaksTabBar()
        .onAppear { model.load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.hasChanges {
                    Button("保存") { model.save() }
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    /// 顶部身份区：不包白卡 —— 头像与名字直接落在页面浅灰底上。
    private var hero: some View {
        VStack(spacing: 12) {
            AccountAvatar(size: 96, style: model.avatar)

            Text(model.draft.isEmpty ? LocalAccountStore.defaultName : model.draft)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    /// 「头像」区 = 一行**更换头像**入口，宫格选择器收进下级页。
    private var avatarEntrySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "头像")

            NavigationLink {
                AvatarPickerView(model: model)
            } label: {
                HStack(spacing: 12) {
                    AccountAvatar(size: 40, style: model.avatar)

                    Text("更换头像")
                        .font(.system(size: 17))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .cardSurface()
        }
    }

    // MARK: 名称

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "名称")

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("名称")
                        .font(.system(size: 17))
                        .fixedSize(horizontal: true, vertical: false)

                    Spacer(minLength: 8)

                    TextField(LocalAccountStore.defaultName, text: $model.draft)
                        .font(.system(size: 17))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($nameFieldFocused)
                        .onSubmit { model.save() }

                    // 一键清空：改名时"全删重打"是常态，长按退格太慢。
                    if !model.draft.isEmpty {
                        Button {
                            model.draft = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.quaternary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
            }
            .cardSurface()

            Text("只在这台设备上使用，不上传、不联网，也不会出现在任何分享内容里。最多 \(LocalAccountStore.nameLimit) 个字。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 取件记录

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "取件记录")

            VStack(spacing: 0) {
                SettingsRow(symbol: "shippingbox.fill", title: "累计入库",
                            detail: "\(store.records.count) 条", showsChevron: false,
                            tint: AppTheme.pendingTint)

                SettingsDivider()

                SettingsRow(symbol: "checkmark.circle.fill", title: "累计取走",
                            detail: "\(store.pickedUpRecords.count) 条", showsChevron: false,
                            tint: AppTheme.doneTint)

                SettingsDivider()

                SettingsRow(symbol: "clock.fill", title: "当前待取",
                            detail: "\(store.pending.count) 条", showsChevron: false,
                            tint: AppTheme.todayTint)
            }
            .cardSurface()

            Text("记录保存在本机，不上传任何服务器。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 账户页局部状态

/// 单账户化（2026-09-23 定稿）：本 model 只剩名字草稿（「保存」）与头像草稿
/// （宫格页即时生效）。@Published 收进 ObservableObject 是命令行编译链路的
/// 宏规避口径（与全工程一致），不是风格偏好。
final class AccountDetailModel: ObservableObject {
    /// 名称草稿（未提交）。改它，顶部身份区的名字实时跟着走。
    @Published var draft = ""
    /// 选中的头像款式（未提交）。改了它，顶部大头像实时跟着走。
    @Published var avatar: AccountAvatarStyle = .fallback

    /// 系统选图器的选中项（`AvatarPickerView` 用）。**处理完立刻置回 nil**。
    @Published var pickedPhoto: PhotosPickerItem?

    /// 选中的图读不出来（格式怪、iCloud 图还没下载完…）→ 弹一次提示。
    @Published var photoFailed = false

    private var original = ""
    private var originalAvatar: AccountAvatarStyle = .fallback
    private var loaded = false

    private var store: LocalAccountStore { .shared }

    /// 名称或头像任一有改动，右上角才出现「保存」。
    var hasChanges: Bool { draft != original || avatar != originalAvatar }

    /// 加载当前账户的资料（幂等：只装一次，改动期间不回读覆盖草稿）。
    func load() {
        guard !loaded else { return }
        draft = store.current.name
        avatar = store.current.avatar
        original = draft
        originalAvatar = avatar
        loaded = true
    }

    func save() {
        store.renameCurrent(to: draft)
        store.setAvatar(avatar)
        draft = store.current.name
        original = draft
        originalAvatar = avatar
    }

    /// 「自定义」上传是**选完即落盘**的 —— 落盘后把草稿基线同步成自定义款。
    func commitCustomAvatar() {
        avatar = .custom
        originalAvatar = .custom
    }

    /// 处理「自定义」格选回来的照片：落盘 → 切到自定义款。
    func handlePickedPhoto(_ item: PhotosPickerItem) {
        Task { @MainActor in
            defer { pickedPhoto = nil }

            guard let data = try? await item.loadTransferable(type: Data.self),
                  store.saveCustomAvatar(data) else {
                photoFailed = true
                return
            }

            commitCustomAvatar()
        }
    }
}
