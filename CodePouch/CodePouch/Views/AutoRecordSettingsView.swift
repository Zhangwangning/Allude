import SwiftUI
import UIKit

// MARK: ============================================================================
// 设置 › 自动收录（2026-11-04）
//
// 用户点「导入」→ 系统弹出快捷指令的导入确认 → 自动化进入「快捷指令 › 自动化」，
// **默认关闭**，需要用户自己打开开关。App 无法代改，只能把话说明白。
// ============================================================================

struct AutoRecordSettingsView: View {
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var imported: Set<String> = []
    @State private var manualCopied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                intro
                ForEach(ShortcutAutomation.presets) { preset in
                    presetRow(preset)
                }
                note
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("自动收录")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { imported = Set(ShortcutAutomation.importedKeywords) }
        .sheet(isPresented: $showShare) {
            if let shareURL {
                ActivitySheet(items: [shareURL])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("导入自动化后，收到快递短信会自动入库。")
                .font(AppTheme.TypeScale.body)
            Text("导入完成后，请到「快捷指令 › 自动化」把它打开——系统导入的自动化默认是关闭的。")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardSurface()
    }

    private func presetRow(_ preset: ShortcutAutomation.Preset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("包含「\(preset.keyword)」")
                    .font(AppTheme.TypeScale.rowTitleMedium)
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

            Button {
                guard let url = ShortcutAutomation.importFile(for: preset) else { return }
                shareURL = url
                showShare = true
                ShortcutAutomation.markImported(preset.keyword)
                imported.insert(preset.keyword)
            } label: {
                Text("导入这个自动化")
                    .font(AppTheme.TypeScale.bodyMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.accent.opacity(0.12))
                    )
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .cardSurface()
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("自定义关键词")
                .font(AppTheme.TypeScale.rowTitleMedium)
            Text("目前提供的是预设关键词。自定义关键词需要事先签名，App 里无法当场生成——这条限制来自 iOS 的快捷指令签名机制。")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardSurface()
    }
}
