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
//
// 🔴 2026-11-11 主人：**一键添加（iCloud 链接 / 文件导入）只在 iOS 27+ 可用**；
//    iOS 26 及更早的系统不支持导入带触发器的自动化，只能照下面「手动配置」
//    的步骤在「快捷指令」里自己新建一条。本页按系统版本分流，不给无用的按钮。
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
    @State private var linkURL: URL?

    /// 一键添加快捷指令（分享 .shortcut / 打开 iCloud 链接）只在 iOS 27+ 可用；
    /// iOS 26 及更早只能手动新建自动化（2026-11-11 主人定）。
    private var quickImportAvailable: Bool {
        // 截图/验收脚手架：本机只有 iOS 27 运行时，用 FORCE_MANUAL_SHORTCUT=1
        // 模拟 iOS 26 及更早（Release 不含脚手架）。
        #if DEBUG
        if ProcessInfo.processInfo.environment["FORCE_MANUAL_SHORTCUT"] != nil { return false }
        #endif
        if #available(iOS 27.0, *) { return true } else { return false }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // 🔴 2026-11-08 主人：用户看不懂上面四个「添加」是干嘛的。
                //    第一句就直接说清楚目的，再给卡片。
                Text("装一条「自动化」：收到快递短信，Allude自动收码，不用手动粘贴。")
                    .font(AppTheme.TypeScale.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)

                keywordsCard
                note

                // 🔴 2026-11-08 主人：必须讲清楚"上面的能导入，就不用看下面的"。
                // 2026-11-11：iOS 26 及更早没有一键导入，下面这段是**必看**。
                SectionHeader(title: quickImportAvailable
                              ? "手动配置（仅在上面导入不了时）"
                              : "手动配置（当前系统需要手动新建）")

                Text(quickImportAvailable
                     ? "点「添加」后，「快捷指令」里没出现这条自动化（没能直接保存），才需要照下面的步骤手动建一条。".richText
                     : "iOS 26 及更早版本不支持一键导入自动化，请照下面的步骤在「快捷指令 › 自动化」里手动新建一条。".richText)
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
            if quickImportAvailable {
                addMenu(preset)
            }
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
                // 与首启引导同一个修法：分享面板直接挂最上层控制器
                guard let url = ShortcutAutomation.preparedImportURL(for: preset) else { return }
                ShareSheetPresenter.present([url])
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
        // 只留最要紧的两件事：加完要去开开关；一条自动化 = 一条系统通知。
        Text("加完请到「快捷指令 › 自动化」把开关打开（默认是关的）。默认加「【」就够；每多一条自动化，就多一条系统「自动化已运行」通知。")
            .font(AppTheme.TypeScale.note)
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

/// 让 URL 能作为 sheet(item:) 的标识
private struct WebLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
