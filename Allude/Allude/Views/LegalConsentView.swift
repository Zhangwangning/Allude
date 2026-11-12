import SwiftUI

// MARK: ============================================================================
// 首次启动的法律同意页（2026-11-01 主人要求）
//
// 首启顺序：**先读并同意《使用条款》《隐私政策》** → 再看使用教程 → 进 App。
//
// 除了同意，这一页还要把最容易被误解的一件事说清：
// **数据只在这台手机上**，卸载 App / 清除数据后 App 内**无法恢复**——
// 这是我们"不联网、不上传"承诺的直接代价，必须在用户第一次打开时讲明白，
// 而不是等他删完记录才在后知后觉。
// ============================================================================

struct LegalConsentView: View {
    /// 同意后回调（首启模式必传）
    var onAccept: () -> Void

    @State private var agreed = false
    @State private var showDeclineAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    dataNotice
                    agreement
                }
                .padding(.horizontal, AppTheme.hInset)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: AppTheme.contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
        .alert("需要同意后才能使用", isPresented: $showDeclineAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("《使用条款》与《隐私政策》说明了数据处理方式与使用规则。不同意的话，暂时无法使用Allude。")
        }
    }

    // MARK: 顶部

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("开始使用Allude")
                .font(.system(size: 26, weight: .bold))

            Text("请先阅读并同意《使用条款》与《隐私政策》")
                .font(AppTheme.TypeScale.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 数据说明（最容易被误解的一条）

    private var dataNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive.fill")
                    .font(AppTheme.TypeScale.note.weight(.semibold))
                    .foregroundStyle(AppTheme.todayTint)
                Text("数据只在这台手机上")
                    .font(AppTheme.TypeScale.rowTitle.weight(.semibold))
            }

            Text("""
            Allude**不联网、不上传、没有账号**，你的取件记录默认只保存在本机；你也可以在设置里选择用你自己的 iCloud 在设备间同步。

            因此：**卸载 App、或在 App 内删除记录之后，App 里没有任何办法找回旧数据**——没有云端备份，也没有"回收站"。
            """)
            .font(AppTheme.TypeScale.body)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)

            Text("删除请谨慎。")
                .font(AppTheme.TypeScale.body.weight(.semibold))
                .foregroundStyle(AppTheme.todayTint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.todayTint.opacity(0.10), in: .rect(cornerRadius: 14, style: .continuous))
    }

    // MARK: 条款链接 + 勾选

    private var agreement: some View {
        VStack(spacing: 0) {
            NavigationLink {
                LegalDocumentView(document: .terms)
            } label: {
                SettingsRow(symbol: "doc.text.fill", title: "使用条款",
                            tint: AppTheme.sky)
            }
            .buttonStyle(.plain)

            SettingsDivider()

            NavigationLink {
                LegalDocumentView(document: .privacy)
            } label: {
                SettingsRow(symbol: "hand.raised.fill", title: "隐私政策",
                            tint: AppTheme.doneTint)
            }
            .buttonStyle(.plain)

            SettingsDivider()

            Button {
                withAnimation(.snappy(duration: 0.2)) { agreed.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: agreed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(agreed ? AppTheme.accent : Color.secondary)

                    Text("我已阅读并同意以上条款")
                        .font(AppTheme.TypeScale.body)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .cardSurface()
    }

    // MARK: 底部按钮

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button {
                guard agreed else { return }
                DiagnosticsLog.record("consent", "accepted")
                onAccept()
            } label: {
                Text("同意并继续")
                    .font(AppTheme.TypeScale.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(agreed ? AppTheme.accent : Color(.tertiarySystemFill), in: .capsule)
                    .foregroundStyle(agreed ? .white : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!agreed)

            Button {
                showDeclineAlert = true
            } label: {
                Text("不同意")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.hInset)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }
}
