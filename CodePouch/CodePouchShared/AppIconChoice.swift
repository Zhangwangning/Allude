import Foundation

// MARK: ============================================================================
// App 图标切换（2026-11-01 主人）
//
// 三套内置图标：经典（手取快递）、信封、卡券。
// 主图标放 `AppIcon.appiconset`；另外两套是 **alternate icon** —— 由 Info.plist 的
// `CFBundleAlternateIcons` 声明（`IconEnvelope` / `IconCards`），文件是 bundle 根目录的
// `IconEnvelope@2x.png` / `@3x.png`。
//
// 🔴 选择状态存 **App Group**：灵动岛/锁屏由小组件进程渲染，它读不到 App 的偏好，
//    只有共享容器里的这份能两边都看到。
// ============================================================================

enum AppIconChoice: String, CaseIterable, Identifiable {
    case hand
    case envelope
    case cards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hand: "经典"
        case .envelope: "信封"
        case .cards: "卡券"
        }
    }

    /// 资源目录里的图（App 内预览、灵动岛、关于页都用这个名字）
    var assetName: String {
        switch self {
        case .hand: "AppIconHand"
        case .envelope: "AppIconEnvelope"
        case .cards: "AppIconCards"
        }
    }

    /// `UIApplication.setAlternateIconName` 用的名字；nil = 回到主图标
    var alternateName: String? {
        switch self {
        case .hand: nil
        case .envelope: "IconEnvelope"
        case .cards: "IconCards"
        }
    }
}

enum AppIconStore {
    private static let key = "codeclip.appIcon"

    /// 当前选中的图标。未选过 → 经典。
    static var current: AppIconChoice {
        let defaults = UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
        guard let raw = defaults.string(forKey: key),
              let choice = AppIconChoice(rawValue: raw) else { return .hand }
        return choice
    }

    /// 只写共享状态（真正切换系统图标由 App 侧调用 UIApplication 完成）
    static func store(_ choice: AppIconChoice) {
        let defaults = UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
        defaults.set(choice.rawValue, forKey: key)
    }
}
