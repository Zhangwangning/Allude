import SwiftUI

// MARK: ============================================================================
// 联系方式（2026-11-01 主人要求独立成页）
//
// 两组：
//   · 账号 —— 整行点按复制（邮箱 / 小红书 / 抖音）
//   · 二维码 —— 点开看大图（微信公众号 / 抖音）；同一台手机上扫自己的码没意义，
//     这里是给「把手机递过去」或截图分享的场景用的。
//
// 🔴 账号与二维码都来自主人提供的截图，改文案前先核对：小红书 zwn1652503532、
//    抖音 ZWN1652503532（显示名 John Wayne）、公众号「极客 ZHANG」。
// ============================================================================

struct ContactAccount: Identifiable {
    let id: String
    var title: String
    var handle: String
    var symbol: String
    var tint: Color
}

struct ContactQR: Identifiable {
    let id: String
    var title: String
    var asset: String
    var note: String
}

struct ContactView: View {
    @State private var copied: String?
    @State private var previewQR: ContactQR?

    private let accounts: [ContactAccount] = [
        ContactAccount(id: "mail", title: "邮箱",
                       handle: FeedbackModel.mail,
                       symbol: "envelope.fill", tint: AppTheme.doneTint),
        ContactAccount(id: "xhs", title: "小红书",
                       handle: "zwn1652503532",
                       symbol: "heart.fill", tint: AppTheme.pendingTint),
        ContactAccount(id: "douyin", title: "抖音",
                       handle: "ZWN1652503532",
                       symbol: "music.note", tint: AppTheme.indigo),
    ]

    private let qrs: [ContactQR] = [
        ContactQR(id: "wechat", title: "微信公众号",
                  asset: "QRWeChat", note: "微信扫一扫 · 极客 ZHANG"),
        ContactQR(id: "douyin", title: "抖音二维码",
                  asset: "QRDouyin", note: "抖音扫一扫 · @John Wayne"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "账号")

                    VStack(spacing: 0) {
                        ForEach(Array(accounts.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { SettingsDivider() }
                            accountRow(item)
                        }
                    }
                    .cardSurface()

                    Text("点一下整行即可复制。")
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "二维码")

                    VStack(spacing: 0) {
                        ForEach(Array(qrs.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { SettingsDivider() }
                            Button {
                                previewQR = item
                            } label: {
                                SettingsRow(symbol: "qrcode", title: item.title,
                                            detail: "查看",
                                            tint: AppTheme.sky)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .cardSurface()

                    Text("公众号与抖音的码来自主人截图；递给别人扫或截图分享时用。")
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("联系方式")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $previewQR) { item in
            QRPreviewSheet(item: item)
        }
    }

    private func accountRow(_ item: ContactAccount) -> some View {
        let copiedThis = copied == item.id

        return Button {
            UIPasteboard.general.string = item.handle
            DiagnosticsLog.record("contact", "copy \(item.id)")
            withAnimation(.snappy(duration: 0.2)) { copied = item.id }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                withAnimation(.snappy(duration: 0.2)) {
                    if copied == item.id { copied = nil }
                }
            }
        } label: {
            SettingsRow(symbol: item.symbol, title: item.title,
                        subtitle: item.handle, subtitleOneLine: true,
                        detail: copiedThis ? "已复制" : "复制",
                        showsChevron: false,
                        tint: item.tint)
        }
        .buttonStyle(.plain)
    }
}

/// 二维码大图。白底 + 居中，方便别人扫或直接截图。
private struct QRPreviewSheet: View {
    let item: ContactQR
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(item.asset)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: 300)
                    .padding(14)
                    .background(.white, in: .rect(cornerRadius: 16))

                Text(item.note)
                    .font(AppTheme.TypeScale.body)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .frame(maxWidth: .infinity)
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
