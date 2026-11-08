import SwiftUI
import SafariServices
import UIKit

// MARK: ============================================================================
// 设置 › 快捷指令自动化（2026-11-05 重构）
//
// 版式按主人给的清单做：一行一个关键词，右侧「添加」，点开是弹出菜单：
//   · iCloud 链接（推荐，填了才有）
//   · 用文件导入（App 内自带已签名的文件）
//
// 🔴 **不显示「已导入」状态**：用户可能在快捷指令里删掉，App 无从得知，
//    显示状态只会制造"明明显示已导入却没生效"的误会。
//
// 🔴 自定义关键词仍不可行：未签名文件导入失败（已实测），
//    导入时询问（WFWorkflowImportQuestions）对触发器不生效（B1/B2 实测无弹窗），
//    所以只能提供预设关键词。
// ============================================================================

/// App 内打开网页（SFSafariViewController），不跳出 App
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.dismissButtonStyle = .close
        return vc
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

struct AutoRecordSettingsView: View {
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var linkURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                keywordsCard
                note

                // 🔴 2026-11-08 主人：必须讲清楚"上面的能导入，就不用看下面的"。
                SectionHeader(title: "手动配置（仅在上面导入不了时）")

                Text("""
上面的「添加」会把整条自动化直接存进「快捷指令」App。**导入成功、并去\
「快捷指令 › 自动化」把开关打开之后，下面的步骤全都不用做。**

只有一种情况需要往下看：点「添加」后系统没有把文件存进「快捷指令」App\
（没法从拾码直接保存），那时才照下面的步骤自己建一条。
""".richText)
                    .font(AppTheme.TypeScale.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingsCard()

                // 🔴 2026-11-08 主人：和使用教程合成**一页**，不要再套下级页面。
                UsageGuideView.UsageGuideContent()
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("快捷指令自动化")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) {
            if let shareURL {
                ActivitySheet(items: [shareURL]).presentationDetents([.medium, .large])
            }
        }
        .sheet(item: Binding(
            get: { linkURL.map(WebLink.init) },
            set: { linkURL = $0?.url }
        )) { link in
            SafariSheet(url: link.url).ignoresSafeArea()
        }
    }

    // MARK: 关键词列表

    private var keywordsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                keywordRow(ShortcutAutomation.presets[0], showsDivider: false)
            }
            .settingsCard()

            Text("可选关键词")
                .font(AppTheme.TypeScale.section)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(ShortcutAutomation.presets.dropFirst().enumerated()), id: \.element.id) { index, preset in
                    keywordRow(preset, showsDivider: index < ShortcutAutomation.presets.count - 2)
                }
            }
            .settingsCard()
        }
    }

    @ViewBuilder
    private func keywordRow(_ preset: ShortcutAutomation.Preset, showsDivider: Bool) -> some View {
        HStack(spacing: 12) {
            Text("信息 包含「\(preset.keyword)」")
                .font(AppTheme.TypeScale.rowTitle)
            if preset.recommended {
                Text("推荐")
                    .font(AppTheme.TypeScale.badge)
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(AppTheme.accent.opacity(0.12)))
            }
            Spacer(minLength: 8)
            addMenu(preset)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        if showsDivider { SettingsDivider() }
    }

    /// 右侧「添加」：点开是弹出菜单（iCloud 链接 / 文件）
    private func addMenu(_ preset: ShortcutAutomation.Preset) -> some View {
        Menu {
            if let link = ShortcutAutomation.icloudURL(for: preset.keyword) {
                Button {
                    linkURL = link
                } label: {
                    Label("iCloud 链接（推荐）", systemImage: "link")
                }
            }
            Button {
                guard let url = ShortcutAutomation.importFile(for: preset) else { return }
                shareURL = url
                showShare = true
            } label: {
                Label("用文件导入", systemImage: "square.and.arrow.down")
            }
        } label: {
            // 🔴 2026-11-08 主人：改成**蓝色填充的液态玻璃**按钮，文字白色。
            //    iOS 26+ 走系统玻璃（靠 tint 染成品牌蓝）；iOS 18 没有液态玻璃，
            //    由 appGlass 的回落实现铺两层同色，看起来同样是实心蓝。
            Text("添加")
                .font(AppTheme.TypeScale.bodyMedium)
                .foregroundStyle(.white)
                .padding(.vertical, 6)
                .padding(.horizontal, 16)
                .appGlass(.capsule, tint: AppTheme.accent, interactive: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    // MARK: 说明

    private var note: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("添加后，请到「快捷指令 › 自动化」把它打开——系统导入的自动化默认是关闭的。")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Text("默认加「【」就够了。只有当你的快递短信里确实没有【时，再加下面的可选关键词。")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Text("每多一条自动化，iOS 就会多一条「自动化已运行」的系统通知。iOS 27.2 起这条通知已经无法关闭（旧系统还能去「设置 › 屏幕时间」关掉），所以关键词加得越多、通知越频繁——只加「【」通常就够。")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .settingsCard()
    }
}

/// 让 URL 能作为 sheet(item:) 的标识
private struct WebLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
