import Foundation

// MARK: ============================================================================
// App 图标切换（2026-11-01 主人）
//
// 八套内置图标，**第 3 套（取件袋）为默认主图标**。图都是 512 满幅方图，不再裁切。
//
// 主图标放 `AppIcon.appiconset`；其余七套是 **alternate icon** —— 由 Info.plist 的
// `CFBundleAlternateIcons` 声明（`Icon01` / `Icon02` / `Icon04`…`Icon08`），
// 文件是 bundle 根目录的 `IconNN@2x.png` / `@3x.png`。
//
// 🔴 选择状态存 **App Group**：灵动岛/锁屏由小组件进程渲染，它读不到 App 的偏好，
//    只有共享容器里的这份能两边都看到。
// 🔴 给灵动岛用的图必须带 `template-rendering-intent: original` 与 1x/2x/3x 三档，
//    否则 WidgetKit 会把它当模板涂成单色 —— 详见 AGENTS.md。
// ============================================================================

enum AppIconChoice: String, CaseIterable, Identifiable {
    case icon01, icon02, icon03, icon04, icon05, icon06, icon07, icon08

    /// 默认图标 = 第 3 套（取件袋）
    static let fallback: AppIconChoice = .icon03

    var id: String { rawValue }

    /// 序号（1–8），用于文案与文件名
    var number: Int {
        switch self {
        case .icon01: 1
        case .icon02: 2
        case .icon03: 3
        case .icon04: 4
        case .icon05: 5
        case .icon06: 6
        case .icon07: 7
        case .icon08: 8
        }
    }

    /// 格子里的名字。主人没点名，这里按图形起的描述名，随时可改。
    var title: String {
        switch self {
        case .icon01: "号码牌"
        case .icon02: "信封"
        case .icon03: "取件袋"
        case .icon04: "扫码件"
        case .icon05: "文件夹"
        case .icon06: "手提袋"
        case .icon07: "C 标"
        case .icon08: "卡包"
        }
    }

    /// 资源目录里的图（App 内预览、灵动岛、关于页都用这个名字）
    var assetName: String { String(format: "AppIcon%02d", number) }

    /// `UIApplication.setAlternateIconName` 用的名字；默认图标返回 nil
    var alternateName: String? {
        self == Self.fallback ? nil : String(format: "Icon%02d", number)
    }
}

enum AppIconStore {
    private static let key = "allude.appIcon"

    /// 当前选中的图标。未选过 → 第 3 套。
    static var current: AppIconChoice {
        let defaults = UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
        guard let raw = defaults.string(forKey: key),
              let choice = AppIconChoice(rawValue: raw) else { return .fallback }
        return choice
    }

    /// 只写共享状态（真正切换系统图标由 App 侧调用 UIApplication 完成）
    static func store(_ choice: AppIconChoice) {
        let defaults = UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
        defaults.set(choice.rawValue, forKey: key)
    }
}
