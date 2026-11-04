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
        VStack(spacing: 0) {
            ForEach(Array(ShortcutAutomation.presets.enumerated()), id: \.element.id) { index, preset in
                HStack(spacing: 12) {
                    Text("信息 包含「\(preset.keyword)」")
                        .font(AppTheme.TypeScale.rowTitle)
                    Spacer(minLength: 8)
                    addMenu(preset)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if index < ShortcutAutomation.presets.count - 1 {
                    SettingsDivider()
                }
            }
        }
        .cardSurface()
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
            // 独立按钮：描边胶囊，与左侧文案分开，点它才出菜单
            Text("添加")
                .font(AppTheme.TypeScale.bodyMedium)
                .foregroundStyle(AppTheme.accent)
                .padding(.vertical, 5)
                .padding(.horizontal, 14)
                .overlay(
                    Capsule().stroke(AppTheme.accent.opacity(0.45), lineWidth: 1)
                )
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

            Text("关键词可以多加几个，互不冲突。四个都加上最稳，能覆盖没有【的短信。")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardSurface()
    }
}

/// 让 URL 能作为 sheet(item:) 的标识
private struct WebLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
