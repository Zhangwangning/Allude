import SwiftUI
import MessageUI

// MARK: ============================================================================
// 设置的两个二级页：帮助与反馈 / 关于（2026-10-31 重构）
//
// 参考了几款成熟 App 的设置页（VidHub、APTV、iCost、Scripting），共同点是：
//   · 根页面只放入口，**细节全部下沉到二级页**；
//   · 「帮助与反馈」「关于」各占一页，不在根页面铺开；
//   · 二级页底部固定一行小字：版本号 + 备案号。
// 我们原来把版本历史、反馈、两份法律文档全排在根页面，越加越长，
// 这一版按上面的结构拆开。
// ============================================================================

// MARK: - 帮助与反馈

struct HelpCenterView: View {
    /// 宽屏分栏下由外层传入「切换详情列」的能力（`pane = …`）。
    /// push 在常驻详情列里不落地，切 pane 是唯一可靠的做法。
    var openPane: ((SettingsPane) -> Void)? = nil

    @StateObject private var feedback = FeedbackModel()
    @State private var showClearConfirm = false
    @State private var showCleared = false
    // 🔴 2026-11-07：分栏布局（Duo 展开 / iPad）里，这个页是 NavigationSplitView 的
    //    详情列，直接放 `NavigationLink` 有时点不动（push 不落地）。
    //    改成显式状态 + `navigationDestination(isPresented:)`，两种布局都能进。
    @State private var showTraining = false
    @State private var showContact = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    Button {
                        DiagnosticsLog.record("feedback", "open")
                        feedback.startMail(includeLog: feedback.includeLog)
                    } label: {
                        SettingsRow(symbol: "envelope.fill", title: "咨询或反馈",
                                    showsChevron: false,
                                    tint: AppTheme.doneTint)
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    // 诊断日志导出：直接走系统分享（可存文件、发给任何人）
                    ShareLink(item: DiagnosticsLog.exportText()) {
                        SettingsRow(symbol: "doc.badge.arrow.up.fill",
                                    title: "导出诊断日志",
                                    showsChevron: false,
                                    tint: AppTheme.sky)
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    // 帮助改进Allude（2026-11-05 主人 A+B 方案：手动提供样本 → 本地存 → 用户主动导出）
                    Button {
                        DiagnosticsLog.record("help", "tap-training")
                        if let openPane { openPane(.trainingSamples) } else { showTraining = true }
                    } label: {
                        SettingsRow(symbol: "sparkles.rectangle.stack.fill",
                                    title: "帮助改进Allude",
                                    tint: AppTheme.violet)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())

                    SettingsDivider()

                    // 联系方式（2026-11-01 从「关于」移到这里：它属于"找我们"，不是"关于产品"）
                    Button {
                        DiagnosticsLog.record("help", "tap-contact")
                        if let openPane { openPane(.contactInfo) } else { showContact = true }
                    } label: {
                        SettingsRow(symbol: "at", title: "联系方式",
                                    tint: AppTheme.indigo)
                    }
                    .buttonStyle(.plain)
                }
                .settingsCard()

                VStack(spacing: 0) {
                    // 🔴 2026-11-08 主人：设置行只留标题，说明统一放页面底部
                    Toggle(isOn: $feedback.includeLog) {
                        Text("反馈时附带诊断日志")
                            .font(AppTheme.TypeScale.rowTitle)
                    }
                    .tint(AppTheme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .settingsCard()

                VStack(spacing: 0) {
                    Button {
                        showClearConfirm = true
                    } label: {
                        SettingsRow(symbol: "trash.fill", title: "清除诊断日志",
                
                                    showsChevron: false,
                                    tint: AppTheme.pendingTint)
                    }
                    .buttonStyle(.plain)
                }
                .settingsCard()
                Text("诊断日志只在本机保存，只有你点发送并确认后才会随邮件发出。")
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
        .navigationTitle("帮助与反馈")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $feedback.showComposer) {
            MailComposeView(subject: feedback.composerSubject,
                            body: feedback.composerBody,
                            attachment: feedback.composerAttachment) {
                feedback.showComposer = false
            }
        }
        .overlay(alignment: .bottom) { feedbackToast }
        // 🔴 2026-11-07：push 在宽屏详情列里两种写法都点不动（NavigationLink、navigationDestination），
        //    改成 sheet —— 与导航栈无关，两种布局都一定能打开。
        .sheet(isPresented: $showTraining) {
            NavigationStack { TrainingDataView() }
        }
        .sheet(isPresented: $showContact) {
            NavigationStack { ContactView() }
        }
        .alert("清除诊断日志？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                DiagnosticsLog.clear()
                DiagnosticsLog.record("diagnostics", "cleared")
                withAnimation { showCleared = true }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation { showCleared = false }
                }
            }
        } message: {
            Text("只删除本机日志，取件记录不受影响。")
        }
    }

    @ViewBuilder private var feedbackToast: some View {
        if showCleared {
            Text("诊断日志已清除")
                .font(AppTheme.TypeScale.rowSubtitle.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: .capsule)
                .padding(.bottom, 24)
                .transition(.opacity)
        } else if feedback.showFallback {
            Text("邮件 App 不可用，邮箱已复制到剪贴板")
                .font(AppTheme.TypeScale.rowSubtitle.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: .capsule)
                .padding(.bottom, 24)
                .transition(.opacity)
        }
    }
}

// MARK: - 关于

struct AboutView: View {
    @EnvironmentObject private var store: PickupStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                offlineCard

                VStack(spacing: 0) {
                    legalRow(title: "隐私政策",
                             document: .privacy,
                             symbol: "hand.raised.fill",
                             tint: AppTheme.doneTint)

                    SettingsDivider()

                    legalRow(title: "使用条款",
                             document: .terms,
                             symbol: "doc.text.fill",
                             tint: AppTheme.sky)
                }
                .settingsCard()

                // 🔴 2026-11-08 主人：数据只留一个入口 —— 设置 › 本机数据 › 存储。
                //    关于页不再重复「已存记录 / 数据文件」（同一份数据两个入口）。

                VStack(spacing: 0) {
                    NavigationLink {
                        VersionHistoryView()
                    } label: {
                        SettingsRow(symbol: "clock.arrow.circlepath", title: "版本历史",
                                    tint: AppTheme.amber)
                    }
                    .buttonStyle(.plain)
                }
                .settingsCard()

                VStack(spacing: 0) {
                    NavigationLink {
                        StatementView()
                    } label: {
                        SettingsRow(symbol: "text.document.fill", title: "声明与免责",
                                    tint: AppTheme.amber)
                    }
                    .buttonStyle(.plain)
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
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 顶部标识：名称 + 版本号。参考图里这一块都是居中的图标 + 名字 + 版本。
    // MARK: 软件说明（2026-11-07 主人要求写清楚）

    /// 四条事实直接摆在页面上（不再有独立的「软件说明」二级页）。
    /// 🔴 2026-11-07 主人：不要把同样几句话在两处各写一遍（之前四行与二级页完全重复）。
    private var offlineCard: some View {
        VStack(spacing: 0) {
            // 🔴 2026-11-08 主人：软件说明不必再单独一页 —— 这几条就是「关于」
            //    最该第一眼看到的事实，直接摆在页面上，少一层点击。
            SettingsRow(symbol: "wifi.slash", title: "纯离线运行，不联网",
                        showsChevron: false, tint: AppTheme.doneTint)
            SettingsDivider()
            SettingsRow(symbol: "hand.raised.fill", title: "不获取任何用户数据",
                        showsChevron: false, tint: AppTheme.sky)
            SettingsDivider()
            SettingsRow(symbol: "internaldrive.fill", title: "数据只存在本机",
                        showsChevron: false, tint: AppTheme.todayTint)
            SettingsDivider()
            SettingsRow(symbol: "iphone", title: "最低系统版本",
                        detail: Self.minimumOS,
                        showsChevron: false, tint: AppTheme.violet)
        }
        .settingsCard()
    }

    /// 与工程 `IPHONEOS_DEPLOYMENT_TARGET` 保持一致（改部署目标时同步这里）
    static let minimumOS = "iOS 18.0"

    private var header: some View {
        VStack(spacing: 8) {
            // 2026-10-31 主人：关于页顶部用 App 自己的 logo（已去掉白底）。
            // 图标本身带圆角，这里不再叠圆角遮罩，免得边缘出现双重圆角。
            // 图标资源是 1024 的满幅方图（App Store 要求无透明、无自带圆角），
            // App 内要模仿系统图标的样子，这里按 iOS 的比例裁连续圆角：22.37%。
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

    private func legalRow(title: String, document: LegalDocument,
                          symbol: String, tint: Color) -> some View {
        NavigationLink {
            LegalDocumentView(document: document)
        } label: {
            SettingsRow(symbol: symbol, title: title, tint: tint)
        }
        .buttonStyle(.plain)
    }

}

// MARK: - 二级页共用页脚

/// 版本号页脚。参考里这几个 App 都把它固定在二级页底部。
///
/// 🔴 App 备案（2026-11-07 判断）：Allude是无服务器、不联网的单机 App，
/// 唯一网络行为是 StoreKit（仅连 Apple），按官方口径「单机不联网的 App 无需备案」，
/// 走苹果豁免即可 —— 因此**App 内不展示备案号**（网站备案号只用于开发者网站）。
/// 若将来加了任何自建网络服务（如上传训练数据到自建服务器），就必须备案并在页脚补号。
struct PageFooter: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Allude \(AppVersion.display)")
        }
        .font(AppTheme.TypeScale.note)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

