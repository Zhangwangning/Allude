import SwiftUI
import StoreKit

// MARK: ============================================================================
// 设置页二级页（2026-11-12 主人改版）
//
// 主人给的首页结构：
//   ① 通用：快捷指令 / 通知 / 桌面小组件 / 实时活动 / iCloud 同步 / Apple 智能
//   ② 外观与个性化（二级页收拢：App 图标 / 外观 / 字体大小 / 语言）
//   ③ 存储空间
//   ④ 帮助与反馈
//   ⑤ 更多：快递公司 / 驿站管理 / 关于 Allude
//
// 这一版把「界面自定义」和「关于」各自收成**一个入口**，首页不再一行行铺开。
// 宽屏（Duo 展开 / iPad）的分栏里，这些页是常驻详情列，`NavigationLink` 不落地，
// 所以都接受一个 `openPane` 回调，由外层把右栏切过去（与 HelpCenterView 同口径）。
// ============================================================================

// MARK: - 外观与个性化

struct AppearancePersonalizationView: View {
    /// 宽屏分栏下由外层注入「切换右栏」的能力；窄屏为 nil，走普通 push。
    var openPane: ((SettingsPane) -> Void)? = nil

    /// 底部菜单栏是否显示「统计」。放 App Group，主界面和本页读写同一份。
    @AppStorage(TabBarPrefs.showsStatsKey,
                store: UserDefaults(suiteName: PickupStorage.appGroupID))
    private var showsStats = true

    /// 液态玻璃开关（2026-11-14 从「外观」页移过来）：仅 iOS 26+ 展示；
    /// 关闭后走系统毛玻璃材质，与 iOS 18 的观感一致。
    @State private var usesLiquidGlass = GlassSettings.isEnabled

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    ForEach(Array(SettingsPane.appearanceDetailGroup.enumerated()),
                            id: \.element) { index, item in
                        if index > 0 { SettingsDivider() }
                        row(item)
                    }
                }
                .settingsCard()

                if GlassSettings.isSupported {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Toggle(isOn: Binding(
                                get: { usesLiquidGlass },
                                set: { newValue in
                                    usesLiquidGlass = newValue
                                    GlassSettings.setEnabled(newValue)
                                    DiagnosticsLog.record("appearance", "liquidGlass=\(newValue)")
                                }
                            )) {
                                Text("液态玻璃")
                                    .font(AppTheme.TypeScale.rowTitle)
                            }
                            .tint(AppTheme.accent)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .settingsCard()

                    Text("关闭后改用系统毛玻璃材质，与 iOS 18 的观感一致。需重启 App 生效。")
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 底部菜单栏：统计页可以关掉（2026-11-13 主人要求）。
                // 关掉后底栏只剩 待取 / 已取 / 设置，统计页也就没有入口。
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Toggle(isOn: $showsStats) {
                            Text("显示「统计」")
                                .font(AppTheme.TypeScale.rowTitle)
                        }
                        .tint(AppTheme.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .settingsCard()

            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("外观与个性化")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(_ item: SettingsPane) -> some View {
        if let openPane {
            Button { openPane(item) } label: { label(item) }
                .buttonStyle(.plain)
        } else {
            NavigationLink { destination(item) } label: { label(item) }
                .buttonStyle(.plain)
        }
    }

    private func label(_ item: SettingsPane) -> some View {
        SettingsRow(symbol: item.symbol,
                    title: item.title,
                    detail: detail(item),
                    tint: item.tint)
    }

    private func detail(_ item: SettingsPane) -> String? {
        switch item {
        case .appIcon:    return AppIconStore.current.title
        case .appearance: return AppearanceSettings.shared.mode.title
        case .fontSize:
            return AppearanceSettings.shared.followSystem
                ? "跟随系统" : AppearanceSettings.shared.step.title
        case .language:   return AppLanguageSettings.summary
        default:          return nil
        }
    }

    @ViewBuilder
    private func destination(_ item: SettingsPane) -> some View {
        switch item {
        case .appIcon:    AppIconSettingsView()
        case .appearance: AppearanceSettingsView()
        case .fontSize:   FontSizeView()
        default:          AppLanguageView()
        }
    }
}

// MARK: - 存储空间

struct StorageSpaceView: View {
    @EnvironmentObject private var store: PickupStore

    private var quotaText: String {
        store.isPro
            ? "不限量"
            : "最多 \(PickupStore.freeStorageLimit) 条（超出后按最早入库淘汰）"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    SettingsRow(symbol: "internaldrive.fill", title: "已存记录",
                                detail: "\(store.records.count) 条",
                                showsChevron: false,
                                tint: AppTheme.todayTint)

                    SettingsDivider()

                    SettingsRow(symbol: "shippingbox.fill", title: "待取",
                                detail: "\(store.pending.count) 条",
                                showsChevron: false,
                                tint: AppTheme.sky)

                    SettingsDivider()

                    SettingsRow(symbol: "checkmark.circle.fill", title: "已取",
                                detail: "\(store.pickedUpRecords.count) 条",
                                showsChevron: false,
                                tint: AppTheme.doneTint)

                    SettingsDivider()

                    SettingsRow(symbol: "doc.text.fill", title: "数据文件",
                                detail: PickupStorage.fileSizeDescription,
                                showsChevron: false,
                                tint: AppTheme.indigo)
                }
                .settingsCard()

                VStack(spacing: 0) {
                    SettingsRow(symbol: "square.stack.3d.up.fill", title: "当前额度",
                                subtitle: quotaText,
                                showsChevron: false,
                                tint: AppTheme.amber)

                    SettingsDivider()

                    SettingsRow(symbol: "rectangle.stack.fill", title: "同屏展示",
                                detail: store.isPro ? "全部" : "\(PickupLimits.freeVisible) 条",
                                showsChevron: false,
                                tint: AppTheme.violet)
                }
                .settingsCard()

                Text("默认只保存在这台设备上；开启 iCloud 同步后只存进你自己的 iCloud，不经过开发者服务器。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                PageFooter()
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("存储空间")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 关于 Allude

struct AboutAlludeView: View {
    var openPane: ((SettingsPane) -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                VStack(spacing: 0) {
                    ForEach(Array(SettingsPane.aboutDetailGroup.enumerated()),
                            id: \.element) { index, item in
                        if index > 0 { SettingsDivider() }
                        row(item)
                    }
                }
                .settingsCard()

                PageFooter()
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("关于 Allude")
        .navigationBarTitleDisplayMode(.inline)
    }

    // 顶部：图标 + 名字 + 版本号（照 iOS「关于本机」的排版）
    private var header: some View {
        VStack(spacing: 8) {
            Image(AppIconStore.current.assetName)
                .resizable()
                .interpolation(.high)
                .frame(width: 78, height: 78)
                .clipShape(.rect(cornerRadius: 78 * 0.2237, style: .continuous))

            Text("Allude")
                .font(AppTheme.TypeScale.rowTitle.weight(.semibold))

            Text(AppVersion.display.L)
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func row(_ item: SettingsPane) -> some View {
        if let openPane {
            Button { openPane(item) } label: { label(item) }
                .buttonStyle(.plain)
        } else {
            NavigationLink { destination(item) } label: { label(item) }
                .buttonStyle(.plain)
        }
    }

    private func label(_ item: SettingsPane) -> some View {
        SettingsRow(symbol: item.symbol,
                    title: title(item),
                    subtitle: subtitle(item),
                    detail: item == .version ? AppVersion.display : nil,
                    tint: item.tint)
    }

    private func title(_ item: SettingsPane) -> String {
        switch item {
        case .privacyDoc: return "隐私政策（完整版）"
        default:          return item.title
        }
    }

    private func subtitle(_ item: SettingsPane) -> String? {
        switch item {
        case .termsDoc: return "使用条款与声明和免责"
        default:        return nil
        }
    }

    @ViewBuilder
    private func destination(_ item: SettingsPane) -> some View {
        switch item {
        case .encourage:     EncourageView()
        case .termsDoc:      LegalDocumentView(document: .terms, extraHTML: StatementHTML.appended)
        case .privacyDoc:    LegalDocumentView(document: .privacy)
        case .privacySimple: PrivacySimpleView()
        default:             VersionHistoryView()
        }
    }
}

// MARK: - 鼓励一下

/// 「鼓励一下」= 评分 + 分享，不做任何打赏/付费引导。
/// 用系统的 `requestReview`：什么时候弹由 iOS 决定，我们不诱导、也不追踪。
struct EncourageView: View {
    @Environment(\.requestReview) private var requestReview

    private let shareText = "推荐 Allude：一个只在本机整理快递取件码的 App，不联网、不上传、不用注册。"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(AppTheme.pendingTint)
                        .padding(.top, 8)

                    Text("如果 Allude 帮你少翻了几次短信、少漏了几件快递，就是它最想要的了。")
                        .font(AppTheme.TypeScale.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)

                    Text("如果愿意，可以在 App Store 给个评分，或者推荐给身边的人。")
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                VStack(spacing: 0) {
                    Button {
                        requestReview()
                    } label: {
                        SettingsRow(symbol: "star.fill", title: "在 App Store 上评分",
                                    showsChevron: false,
                                    tint: AppTheme.amber)
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    ShareLink(item: shareText) {
                        SettingsRow(symbol: "square.and.arrow.up.fill", title: "推荐给朋友",
                                    showsChevron: false,
                                    tint: AppTheme.sky)
                    }
                    .buttonStyle(.plain)
                }
                .settingsCard()

                Text("评分与否都不会影响任何功能，Allude 也不会因此收集任何数据。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("鼓励一下")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 隐私政策（简明版）

/// 完整版是随包的 HTML（法律文本）；这一页是给人看的大白话摘要。
struct PrivacySimpleView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    SettingsRow(symbol: "wifi.slash", title: "不联网",
                                subtitle: "App 本体不发任何请求；内购由 Apple 处理。",
                                showsChevron: false, tint: AppTheme.doneTint)

                    SettingsDivider()

                    SettingsRow(symbol: "hand.raised.fill", title: "不收集数据",
                                subtitle: "没有账号、没有统计 SDK、没有广告。",
                                showsChevron: false, tint: AppTheme.sky)

                    SettingsDivider()

                    SettingsRow(symbol: "internaldrive.fill", title: "取件记录默认只在本机",
                                subtitle: "存在这台设备的 App Group 里，主 App 与小组件共用；开启 iCloud 同步后才另存一份到你自己的 iCloud。",
                                showsChevron: false, tint: AppTheme.todayTint)

                    SettingsDivider()

                    SettingsRow(symbol: "camera.fill", title: "权限只在本机用",
                                subtitle: "通知提醒、相册选图、相机扫码，处理全在设备上。",
                                showsChevron: false, tint: AppTheme.violet)

                    SettingsDivider()

                    SettingsRow(symbol: "trash.fill", title: "卸载或删除即消失",
                                subtitle: "没有回收站。开了 iCloud 同步时，记录会留在你自己的 iCloud 里，重装后可同步回来。",
                                showsChevron: false, tint: AppTheme.pendingTint)

                    SettingsDivider()

                    SettingsRow(symbol: "creditcard.fill", title: "内购由 Apple 处理",
                                subtitle: "我们看不到你的支付信息。",
                                showsChevron: false, tint: AppTheme.indigo)
                }
                .settingsCard()

                NavigationLink {
                    LegalDocumentView(document: .privacy)
                } label: {
                    SettingsRow(symbol: "doc.text.fill", title: "查看完整隐私政策",
                                tint: AppTheme.doneTint)
                }
                .buttonStyle(.plain)
                .settingsCard()

                Text("最后更新：2026-11-12")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("隐私政策（简明版）")
        .navigationBarTitleDisplayMode(.inline)
    }
}
// MARK: - iCloud 同步

/// 2026-11-12 实现真正同步；布局参考常见 App 的「同步状态面板」：
/// 开关 → 状态（网络 / iCloud / 同步状态 / 最近同步）→ 立即同步 → 异常通知 → 说明。
/// 借的是信息层级，不是样式——每行仍用 App 自己的 SettingsRow。
struct ICloudSyncView: View {
    @StateObject private var sync = ICloudSyncController.shared
    @State private var showHelp = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                syncToggleCard
                helpLink
                statusCard
                actionCard
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("iCloud 同步")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showHelp) {
            NavigationStack { ICloudSyncHelpView() }
                .presentationDetents([.medium, .large])
        }
    }

    private var syncToggleCard: some View {
        Toggle(isOn: Binding(get: { sync.isEnabled },
                             set: { sync.setEnabled($0) })) {
            Text("开启同步")
                .font(AppTheme.TypeScale.rowTitle)
        }
        .tint(AppTheme.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .settingsCard()
    }

    private var helpLink: some View {
        Button {
            showHelp = true
        } label: {
            HStack(spacing: 4) {
                Text("点此查看 iCloud 同步说明")
                Image(systemName: "arrow.right")
            }
            .font(AppTheme.TypeScale.rowSubtitle)
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    private var statusCard: some View {
        VStack(spacing: 0) {
            SettingsRow(symbol: "wifi",
                        title: "网络",
                        detail: sync.networkAvailable ? "正常" : "无网络",
                        showsChevron: false,
                        tint: AppTheme.sky)
            SettingsDivider()
            SettingsRow(symbol: "icloud.fill",
                        title: "iCloud",
                        detail: sync.isAvailable ? "已连接" : "未启用",
                        showsChevron: false,
                        tint: AppTheme.accent)
            SettingsDivider()
            SettingsRow(symbol: "arrow.triangle.2.circlepath",
                        title: "同步状态",
                        detail: sync.isSyncing ? "正在同步…" : sync.statusSummary,
                        showsChevron: false,
                        tint: AppTheme.doneTint,
                        trailing: sync.isSyncing
                            ? AnyView(ProgressView().controlSize(.small))
                            : nil)
            SettingsDivider()
            SettingsRow(symbol: "clock",
                        title: "最近同步",
                        detail: sync.lastSyncedDescription,
                        showsChevron: false,
                        tint: AppTheme.indigo)
        }
        .settingsCard()
    }

    private var actionCard: some View {
        Button {
            sync.syncNow()
        } label: {
            SettingsRow(symbol: "arrow.clockwise",
                        title: sync.isSyncing ? "正在同步…" : "立即同步",
                        detail: sync.isEnabled ? "" : "先打开上面的开关",
                        showsChevron: false,
                        tint: AppTheme.accent,
                        trailing: sync.isSyncing
                            ? AnyView(ProgressView().controlSize(.small))
                            : nil)
        }
        .buttonStyle(.plain)
        .disabled(!sync.isEnabled || sync.isSyncing)
        .opacity(sync.isEnabled ? 1 : 0.5)
        .settingsCard()
        .animation(.easeInOut(duration: 0.2), value: sync.isSyncing)
    }

}

/// iCloud 同步说明：先讲前提，再讲开关与效果（参考同类 App 的同步教程结构）。
struct ICloudSyncHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(String, String)] = [
        ("1", "两台设备登录同一个 Apple ID"),
        ("2", "设置 › Apple ID › iCloud › iCloud 云盘 打开"),
        ("3", "同一页的「使用 iCloud 的 App」里确认有 Allude"),
        ("4", "回到本页打开「开启同步」，两台设备各打开一次 Allude"),
        ("5", "之后任意一台改动，另一台启动或回到前台时自动合并")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("同步怎么工作")
                    .font(AppTheme.TypeScale.section)
                    .foregroundStyle(.secondary)

                ForEach(steps, id: \.0) { number, text in
                    HStack(alignment: .top, spacing: 12) {
                        Text(number)
                            .font(AppTheme.TypeScale.badge.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 20, height: 20)
                            .background(AppTheme.accent.opacity(0.12), in: Circle())
                        Text(text)
                            .font(AppTheme.TypeScale.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text("冲突怎么处理")
                    .font(AppTheme.TypeScale.section)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                Text("同一件包裹在两台设备上都改过时，保留最后改动的那一份；删掉的记录不会从另一台设备「复活」。关掉开关后本机记录一条不少，iCloud 里那份会留着。")
                    .font(AppTheme.TypeScale.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("iCloud 同步说明")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
    }
}
