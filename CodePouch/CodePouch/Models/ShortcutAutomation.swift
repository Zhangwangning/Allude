import SwiftUI
import UIKit

// MARK: ============================================================================
// 自动收录：把「收到短信 → 添加到拾码」的自动化直接导入系统（2026-11-04）
//
// 事实基础（实测拆包）：
//   .shortcut 文件由 AA01 归档里的 `Shortcut.wflow` 组成，里面**带触发器**：
//   `WFWorkflowTriggers` = WFMessageTrigger +「信息 包含 关键词」。
//   导入后系统会把它放进「快捷指令 › 自动化」，状态**默认关闭**，
//   需要用户自己打开开关 —— 这是 iOS 的行为，App 无法代劳。
//
// 🔴 为什么只能给预设关键词：签名（`shortcuts sign`）只能在电脑上做，
//    App 里没有签名私钥，运行时生成的文件无法签名，iOS 会拒绝导入。
//    所以这里只打包了几个预签好的文件（【 / 快递 / 取件）。
// ============================================================================

enum ShortcutAutomation {

    struct Preset: Identifiable, Hashable {
        let keyword: String
        let file: String
        /// 是否推荐（界面打「推荐」标签）
        var recommended: Bool = false
        var id: String { keyword }

        /// 导入后显示的名称：快递取件码拾码解析「关键词」
        var displayName: String { "快递取件码拾码解析「\(keyword)」" }
        /// 一句话说明适用场景
        var hint: String {
            switch keyword {
            case "【": return "大多数快递短信的取件码都包在全角方括号里，先加这一个就够"
            case "取": return "只匹配一个「取」字，用于没有【的短信"
            case "快递": return "短信里写了「快递」两个字就触发"
            case "包裹": return "短信里写了「包裹」就触发"
            default: return ""
            }
        }
    }

    /// 预设关键词（顺序即界面顺序）
    static let presets: [Preset] = [
        Preset(keyword: "【", file: "auto-【", recommended: true),
        Preset(keyword: "取", file: "auto-取"),
        Preset(keyword: "快递", file: "auto-快递"),
        Preset(keyword: "包裹", file: "auto-包裹"),
    ]

    /// iCloud 链接（推荐方式）。在 Shortcuts 里「共享 › 拷贝 iCloud 链接」拿到后填这里；
    /// 为空时界面只给「用文件导入」。
    /// iCloud 链接（推荐方式）。
    /// 🔴 每一条都**下载回来验过**：名称与触发关键词都对得上。
    /// 2026-11-05 第一版曾有三条链接的触发器仍是「【」，现已全部修正。
    static let icloudLinks: [String: String] = [
        "【": "https://www.icloud.com/shortcuts/d784aa0874414c289977f4b7ee4efc0b",
        "取": "https://www.icloud.com/shortcuts/43de0243d32347789c1c8730f4148154",
        "快递": "https://www.icloud.com/shortcuts/1df8675b3c8e4ca68a787b83fb71da65",
        "包裹": "https://www.icloud.com/shortcuts/d6d646342e5340798d05966f94a3fb76",
    ]

    static func icloudURL(for keyword: String) -> URL? {
        guard let raw = icloudLinks[keyword], !raw.isEmpty,
              let url = URL(string: raw) else { return nil }
        return url
    }

    /// 已导入过哪些关键词（本地记录，仅用于界面显示"已导入"）
    private static let key = "codeclip.automation.imported"

    static var importedKeywords: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func hasImported(_ keyword: String) -> Bool {
        importedKeywords.contains(keyword)
    }

    static func markImported(_ keyword: String) {
        var list = importedKeywords
        guard !list.contains(keyword) else { return }
        list.append(keyword)
        importedKeywords = list
    }

    /// 把预签好的文件写一份到临时目录（带好读的名字），返回可分享的 URL。
    static func importFile(for preset: Preset) -> URL? {
        guard let url = Bundle.main.url(forResource: preset.file, withExtension: "shortcut") else {
            return nil
        }
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("拾码·自动收录（\\(preset.keyword)）.shortcut")
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.copyItem(at: url, to: target)
            return target
        } catch {
            return nil
        }
    }
}

// MARK: - 分享面板（把 .shortcut 交给系统的「快捷指令」）

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
