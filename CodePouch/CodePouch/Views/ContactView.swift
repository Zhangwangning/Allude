import SwiftUI

// MARK: ============================================================================
// 联系方式（2026-11-01 主人第二版要求）
//
// 交互口径：
//   · 每行显示**平台名 + 账号名**（不是那串 ID——ID 对用户没有意义）；
//   · 行尾动作写明做什么：「复制邮箱」「去小红书」「去抖音」；
//   · **不再展示二维码**；
//   · 微信公众号没有可用的跳转方式（`weixin://` 只能打开微信本体，定位不到某个公众号），
//     按要求改成直接展示主人给的那张「微信搜一搜 极客ZHANG」横幅。
//
// 🔴 账号口径（改前核对）：
//    邮箱 zhang_wangning@126.com、小红书「极客 ZHANG」、
//    抖音「John Wayne」、公众号「极客 ZHANG」。
// ============================================================================

private enum ContactLink {
    /// 小红书主页（主人给的口令链接，会跳到 App 或网页）
    static let xiaohongshu = URL(string: "https://xhslink.cn/o/7EXKCLCJzB0")!
    /// 抖音主页（分享短链；不装抖音会落到网页版）
    static let douyin = URL(string: "https://v.douyin.com/jUUUICs4WuY/")!
}

struct ContactView: View {
    @State private var copiedMail = false
    @State private var openFailed = false

    private let mail = FeedbackModel.mail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                rowsCard
                wechatCard
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
            Text("系统没有能打开这个链接的 App，请稍后再试。")
        }
    }

    // MARK: 三个渠道

    private var rowsCard: some View {
        VStack(spacing: 0) {
            // 邮箱：只能复制（点开邮件 App 还得自己填收件人，反而多一步）
            Button {
                UIPasteboard.general.string = mail
                DiagnosticsLog.record("contact", "copy mail")
                withAnimation(.snappy(duration: 0.2)) { copiedMail = true }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    withAnimation(.snappy(duration: 0.2)) { copiedMail = false }
                }
            } label: {
                SettingsRow(symbol: "envelope.fill", imageAsset: "IconMail",
                            title: "邮箱", subtitle: mail, subtitleOneLine: true,
                            detail: copiedMail ? "已复制" : "复制邮箱",
                            showsChevron: false)
            }
            .buttonStyle(.plain)

            SettingsDivider()

            Button {
                open(ContactLink.xiaohongshu, id: "xhs")
            } label: {
                SettingsRow(symbol: "heart.fill", imageAsset: "IconXiaohongshu",
                            title: "小红书", subtitle: "极客 ZHANG",
                            detail: "去小红书")
            }
            .buttonStyle(.plain)

            SettingsDivider()

            Button {
                open(ContactLink.douyin, id: "douyin")
            } label: {
                SettingsRow(symbol: "music.note", imageAsset: "IconDouyin",
                            title: "抖音", subtitle: "John Wayne",
                            detail: "去抖音")
            }
            .buttonStyle(.plain)
        }
        .cardSurface()
    }

    // MARK: 微信公众号（只能展示，无法跳转）

    private var wechatCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image("IconWeChat")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                    .clipShape(.rect(cornerRadius: 22 * 0.29, style: .continuous))

                Text("微信公众号")
                    .font(AppTheme.TypeScale.rowTitle.weight(.medium))

                Text("极客 ZHANG")
                    .font(AppTheme.TypeScale.rowSubtitle)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // 公众号没有可用的跳转 scheme，这里直接展示主人给的「搜一搜」横幅。
            Image("QRWeChatBanner")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)

            Text("微信里搜一搜「极客ZHANG」即可关注")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: 动作

    private func open(_ url: URL, id: String) {
        DiagnosticsLog.record("contact", "open \(id)")
        UIApplication.shared.open(url, options: [:]) { success in
            guard !success else { return }
            DispatchQueue.main.async { openFailed = true }
        }
    }
}
