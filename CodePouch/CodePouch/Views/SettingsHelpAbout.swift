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
    @StateObject private var feedback = FeedbackModel()
    @State private var showClearConfirm = false
    @State private var showCleared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    NavigationLink {
                        UsageGuideView()
                    } label: {
                        SettingsRow(symbol: "book.fill", title: "使用教程",
                                    subtitle: "入门 · 短信自动化 · 截屏收件",
                                    tint: AppTheme.violet)
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    Button {
                        DiagnosticsLog.record("feedback", "open")
                        feedback.startMail(includeLog: feedback.includeLog)
                    } label: {
                        SettingsRow(symbol: "envelope.fill", title: "咨询或反馈",
                                    subtitle: FeedbackModel.mail,
                                    showsChevron: false,
                                    tint: AppTheme.doneTint)
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    // 诊断日志导出：直接走系统分享（可存文件、发给任何人）
                    ShareLink(item: DiagnosticsLog.exportText()) {
                        SettingsRow(symbol: "doc.badge.arrow.up.fill",
                                    title: "导出诊断日志",
                                    subtitle: "版本、系统与最近操作记录，不含短信内容",
                                    showsChevron: false,
                                    tint: AppTheme.sky)
                    }
                    .buttonStyle(.plain)
                }
                .cardSurface()

                VStack(spacing: 0) {
                    Toggle(isOn: $feedback.includeLog) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("反馈时附带诊断日志")
                                .font(AppTheme.TypeScale.body)
                            Text("只在本机保存，点了发送才会随邮件发出")
                                .font(AppTheme.TypeScale.note)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(AppTheme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .cardSurface()

                VStack(spacing: 0) {
                    Button {
                        showClearConfirm = true
                    } label: {
                        SettingsRow(symbol: "trash.fill", title: "清除诊断日志",
                                    subtitle: "删掉本机记录的诊断信息，不影响取件数据",
                                    showsChevron: false,
                                    tint: AppTheme.pendingTint)
                    }
                    .buttonStyle(.plain)
                }
                .cardSurface()

                PageFooter()
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
    @State private var copiedMail = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                VStack(spacing: 0) {
                    legalRow(title: "隐私政策",
                             note: "无账号、无联网；取件数据只在本机",
                             document: .privacy,
                             symbol: "hand.raised.fill",
                             tint: AppTheme.doneTint)

                    SettingsDivider()

                    legalRow(title: "使用条款",
                             note: "订阅、自动续期与退款规则",
                             document: .terms,
                             symbol: "doc.text.fill",
                             tint: AppTheme.sky)
                }
                .cardSurface()

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

                VStack(spacing: 0) {
                    NavigationLink {
                        VersionHistoryView()
                    } label: {
                        SettingsRow(symbol: "clock.arrow.circlepath", title: "版本历史",
                                    detail: AppVersion.display,
                                    tint: AppTheme.amber)
                    }
                    .buttonStyle(.plain)
                }
                .cardSurface()

                VStack(spacing: 0) {
                    NavigationLink {
                        StatementView()
                    } label: {
                        SettingsRow(symbol: "text.document.fill", title: "声明与免责",
                                    subtitle: "来源 · 技术栈 · 第三方标识 · 侵权联系",
                                    tint: AppTheme.amber)
                    }
                    .buttonStyle(.plain)
                }
                .cardSurface()

                VStack(spacing: 0) {
                    Button {
                        UIPasteboard.general.string = FeedbackModel.mail
                        withAnimation(.snappy(duration: 0.2)) { copiedMail = true }
                        DiagnosticsLog.record("about", "copy-mail")
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_600_000_000)
                            withAnimation(.snappy(duration: 0.2)) { copiedMail = false }
                        }
                    } label: {
                        SettingsRow(symbol: "at", title: "联系方式",
                                    subtitle: copiedMail ? "邮箱已复制" : FeedbackModel.mail,
                                    subtitleOneLine: true,
                                    showsChevron: false,
                                    tint: AppTheme.indigo)
                    }
                    .buttonStyle(.plain)
                }
                .cardSurface()

                PageFooter()
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

            Text("拾码 CodePouch")
                .font(AppTheme.TypeScale.rowTitle.weight(.semibold))

            Text(AppVersion.display)
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func legalRow(title: String, note: String, document: LegalDocument,
                          symbol: String, tint: Color) -> some View {
        NavigationLink {
            LegalDocumentView(document: document)
        } label: {
            SettingsRow(symbol: symbol, title: title, subtitle: note, tint: tint)
        }
        .buttonStyle(.plain)
    }

}

// MARK: - 二级页共用页脚

/// 版本号 + 备案号。参考里这几个 App 都把它固定在二级页底部。
/// 备案号还没下来，先写「备案中」——上架前换成真实号。
struct PageFooter: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("拾码 CodePouch \(AppVersion.display)")
            Text("ICP 备案号：备案中")
        }
        .font(AppTheme.TypeScale.note)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}
