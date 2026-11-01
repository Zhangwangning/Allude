import SwiftUI

// MARK: ============================================================================
// 联系方式（2026-11-01 主人要求重做）
//
// 交互口径：
//   · **能跳转的直接跳**——小红书点一下就用系统打开主页链接；邮箱点一下复制。
//   · **二维码直接展示**，不再"点进去看大图"（原来那个二级页要两次点击才看到码）。
//
// 🔴 账号与二维码来自主人提供的截图/链接，改之前先核对：
//    小红书 https://xhslink.cn/o/7EXKCLCJzB0（号 zwn1652503532）、
//    抖音 ZWN1652503532（显示名 John Wayne，暂无主页链接，只能复制号 + 扫码）、
//    公众号「极客 ZHANG」。
// ============================================================================

private enum ContactLink {
    /// 小红书主页（主人给的口令链接，会跳到 App 或网页）
    static let xiaohongshu = URL(string: "https://xhslink.cn/o/7EXKCLCJzB0")!
}

struct ContactView: View {
    @State private var copied: String?
    @State private var openFailed = false

    private let mail = FeedbackModel.mail
    private let xhsID = "zwn1652503532"
    private let douyinID = "ZWN1652503532"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                linksCard
                qrSection
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
        .alert("打不开链接", isPresented: $openFailed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("系统没有能打开这个链接的 App，你可以先复制账号再手动搜索。")
        }
    }

    // MARK: 直接联系

    private var linksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "直接联系")

            VStack(spacing: 0) {
                // 邮箱：只复制（点开邮件 App 再填收件人反而多一步）
                Button {
                    copy(mail, id: "mail")
                } label: {
                    SettingsRow(symbol: "envelope.fill", title: "邮箱",
                                subtitle: mail, subtitleOneLine: true,
                                detail: copied == "mail" ? "已复制" : "复制",
                                showsChevron: false,
                                tint: AppTheme.doneTint)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                // 小红书：点一下直接打开主页
                Button {
                    open(ContactLink.xiaohongshu, fallbackID: xhsID, id: "xhs")
                } label: {
                    SettingsRow(symbol: "heart.fill", title: "小红书",
                                subtitle: xhsID,
                                detail: "打开主页",
                                tint: AppTheme.pendingTint)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                // 抖音：没有主页链接，只能复制号（抖音号拼不主页地址，需要 sec_uid）
                Button {
                    copy(douyinID, id: "douyin")
                } label: {
                    SettingsRow(symbol: "music.note", title: "抖音",
                                subtitle: douyinID,
                                detail: copied == "douyin" ? "已复制" : "复制号",
                                showsChevron: false,
                                tint: AppTheme.indigo)
                }
                .buttonStyle(.plain)
            }
            .cardSurface()
        }
    }

    // MARK: 二维码（直接展示）

    private var qrSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "扫码找到我")

            HStack(spacing: 12) {
                qrTile(asset: "QRXiaohongshu", caption: "小红书", tint: AppTheme.pendingTint)
                qrTile(asset: "QRWeChat", caption: "微信公众号", tint: AppTheme.doneTint)
                qrTile(asset: "QRDouyin", caption: "抖音", tint: AppTheme.indigo)
            }
        }
    }

    private func qrTile(asset: String, caption: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(asset)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .padding(6)
                .frame(maxWidth: .infinity)
                .background(.white, in: .rect(cornerRadius: 12, style: .continuous))

            Text(caption)
                .font(AppTheme.TypeScale.note.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
    }

    // MARK: 动作

    private func copy(_ text: String, id: String) {
        UIPasteboard.general.string = text
        DiagnosticsLog.record("contact", "copy \(id)")
        withAnimation(.snappy(duration: 0.2)) { copied = id }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.snappy(duration: 0.2)) {
                if copied == id { copied = nil }
            }
        }
    }

    private func open(_ url: URL, fallbackID: String, id: String) {
        DiagnosticsLog.record("contact", "open \(id)")
        UIApplication.shared.open(url, options: [:]) { success in
            guard !success else { return }
            DispatchQueue.main.async {
                // 打不开就复制账号，至少让人能自己搜到
                UIPasteboard.general.string = fallbackID
                copied = id
                openFailed = true
            }
        }
    }
}
