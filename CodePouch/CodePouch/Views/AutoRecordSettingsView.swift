import SwiftUI
import SafariServices
import UIKit

// MARK: ============================================================================
// 设置 › 快捷指令自动化（2026-11-04）
//
// 两种导入方式（主人定的口径）：
//   · **iCloud 链接**（推荐）：点一下在 App 内用 Safari 打开，系统会问是否添加；
//   · **用文件导入**：走系统分享面板把打包好的 .shortcut 交给快捷指令。
//
// 导入后的自动化**默认关闭**，必须让用户自己去「快捷指令 › 自动化」打开开关 ——
// App 改不了这个开关，所以文案必须把这一步单独说清。
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
    @State private var imported: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                steps
                ForEach(ShortcutAutomation.presets) { preset in
                    presetCard(preset)
                }
                limitation
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("快捷指令自动化")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { imported = Set(ShortcutAutomation.importedKeywords) }
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

    // MARK: 步骤说明

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepRow(1, "选一个关键词，导入自动化",
                    "关键词决定哪些短信会被收进来")
            Divider().opacity(0.5)
            stepRow(2, "到「快捷指令 › 自动化」打开开关",
                    "系统导入的自动化默认是关闭的，不打开不会触发")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func stepRow(_ index: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(AppTheme.TypeScale.badge)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 18, height: 18)
                .background(Circle().fill(AppTheme.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.TypeScale.bodyMedium)
                Text(detail)
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 单个关键词

    private func presetCard(_ preset: ShortcutAutomation.Preset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("包含「\(preset.keyword)」")
                    .font(AppTheme.TypeScale.rowTitle)
                if imported.contains(preset.keyword) {
                    Text("已导入")
                        .font(AppTheme.TypeScale.badge)
                        .foregroundStyle(AppTheme.accent)
                }
                Spacer(minLength: 0)
            }

            Text(preset.hint)
                .font(AppTheme.TypeScale.rowSubtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if let link = ShortcutAutomation.icloudURL(for: preset.keyword) {
                    Button { linkURL = link } label: {
                        pill("iCloud 链接", symbol: "link", primary: true)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    guard let url = ShortcutAutomation.importFile(for: preset) else { return }
                    shareURL = url
                    showShare = true
                    ShortcutAutomation.markImported(preset.keyword)
                    imported.insert(preset.keyword)
                } label: {
                    pill("用文件导入", symbol: "square.and.arrow.down", primary: ShortcutAutomation.icloudURL(for: preset.keyword) == nil)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .cardSurface()
    }

    private func pill(_ title: String, symbol: String, primary: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            Text(title).font(AppTheme.TypeScale.bodyMedium)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(primary ? AppTheme.accent.opacity(0.13) : Color(.secondarySystemFill))
        )
        .foregroundStyle(primary ? AppTheme.accent : Color.primary)
    }

    // MARK: 限制说明

    private var limitation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("为什么只有这几个关键词")
                .font(AppTheme.TypeScale.rowTitleMedium)
            Text("自动化文件必须由开发者签名后才能导入，App 里无法当场生成，所以只提供预制的几个关键词。想覆盖更多短信，可以导入多个关键词的自动化，它们互不冲突。")
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
