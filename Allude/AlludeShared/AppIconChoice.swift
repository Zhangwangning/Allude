import Foundation

// MARK: ============================================================================
// App 图标切换（2026-11-01 主人）
//
// 十七套内置图标，**第 7 套（黑盒立体）为默认主图标**（2026-11-20 主人定）。
//
// 🔴 2026-11-15 大整理（主人连着几轮删改之后定的最终形态）：
//    · 先删掉 1 号码牌 / 4 扫码件 / 6 手提袋 / 8 卡包 / 11 牛皮纸 / 13 快递箱 / 23 玻璃白盒；
//    · 再要求「从上到下、从左至右，依次编号」，于是现存 15 套**重排为 01–15**，
//      当晚新给的一张「蓝线稿白盒」补成 **16**。
//    编号从此连续无空洞。⚠️ 重排会让老用户存的 `rawValue` 指向另一张图，
//    所以 `AppIconStore` 里带了一次性的旧编号→新编号迁移（见 `legacyMap`）。
//
// 🔴 图标的 imageset 统一放 `AlludeShared/Assets.xcassets`（2026-11-15 从 App 的
//    catalog 迁过来）：App 与小组件两个 target **都**编译这份共享 catalog，
//    灵动岛/锁屏才取得到图。之前只放在 App 的 catalog 里，小组件进程找不到
//    `AppIconNN` 这名字，`Image(…)` 直接渲染成灰块 —— 那是 1.0.0(312) 灵动岛
//    不显示 App 图标的根因。
// 图都是 512 / 1536 满幅方图，不再裁切；主图标 art 与 alternate 的对应关系见下。
//
// 主图标放 `AppIcon.appiconset`；其余是 **alternate icon** —— 由 Info.plist 的
// `CFBundleAlternateIcons` 声明，图是包根目录的 `IconNN@2x/@3x`（iPad 另加
// `IconNN~ipad` / `IconNN@2x~ipad`），**不能只放资产目录**：App Store 校验
// ITMS-90032 会认不出资产目录里的备用图标，直接用错误退包（2026-11-12 踩过）。
// 每套都带 Any / Dark / Tinted 三张 1024（iOS 18 起系统按外观自动选）。
// 需要 `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`，否则 actool 会跳过这些图标集。
//
// 🔴 选择状态存 **App Group**：灵动岛/锁屏由小组件进程渲染，它读不到 App 的偏好，
//    只有共享容器里的这份能两边都看到。
// 🔴 给灵动岛用的图必须带 `template-rendering-intent: original` 与 1x/2x/3x 三档，
//    否则 WidgetKit 会把它当模板涂成单色 —— 详见 AGENTS.md。
// ============================================================================

enum AppIconChoice: String, CaseIterable, Identifiable {
    /// 编号与界面网格**严格一致**：从上到下、从左到右 = 01…17。
    case icon01, icon02, icon03, icon04, icon05, icon06, icon07, icon08
    case icon09, icon10, icon11, icon12, icon13, icon14, icon15, icon16, icon17

    /// 默认图标 = 第 7 套（黑盒立体）。
    ///
    /// 🔴 2026-11-20 主人：默认图标从第 4 套「C 标」换成第 7 套「黑盒立体」。
    ///    主图标（`AppIcon.appiconset` 的三张 1024）art 同步换成第 7 套；
    ///    反过来 **C 标（Icon04）改登记成 alternate** —— `Info.plist` 的
    ///    `CFBundleAlternateIcons` 去掉 `Icon07`、补上 `Icon04`。
    ///    `alternateName` 对 fallback 恒返回 nil（即「用回主图标」），所以
    ///    第 7 套走主图标、第 4 套走 alternate，两者都能被选。
    static let fallback: AppIconChoice = .icon07

    var id: String { rawValue }

    /// 序号（1–17），与网格顺序一致。用于文案与文件名。
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
        case .icon09: 9
        case .icon10: 10
        case .icon11: 11
        case .icon12: 12
        case .icon13: 13
        case .icon14: 14
        case .icon15: 15
        case .icon16: 16
        case .icon17: 17
        }
    }

    /// 格子里的无障碍名。主人没点名，按图形起的描述名，随时可改。
    var title: String {
        switch self {
        case .icon01: "信封"
        case .icon02: "取件袋"
        case .icon03: "文件夹"
        case .icon04: "C 标"
        case .icon05: "霓虹 A"
        case .icon06: "包裹"
        case .icon07: "黑盒立体"
        case .icon08: "蓝盒立体"
        case .icon09: "蓝牌"
        case .icon10: "黑盒平涂"
        case .icon11: "蓝盒平涂"
        case .icon12: "黑牌"
        case .icon13: "暗牌"
        case .icon14: "光泽黑标"
        case .icon15: "白盒平涂"
        case .icon16: "线框白盒"
        case .icon17: "皮革卡包"
        }
    }

    /// 资源目录里的图（App 内预览、灵动岛、关于页都用这个名字）
    var assetName: String { String(format: "AppIcon%02d", number) }

    /// `UIApplication.setAlternateIconName` 用的名字；默认图标返回 nil
    ///
    /// 注意：`Icon02`（原主图标「取件袋」）现在是 alternate，必须由
    /// `Allude/Info.plist` 的 `CFBundleAlternateIcons` 声明 + bundle 根目录的
    /// `Icon02@2x.png`(120) / `Icon02@3x.png`(180) 两份文件，缺一不可。
    var alternateName: String? {
        self == Self.fallback ? nil : String(format: "Icon%02d", number)
    }
}

enum AppIconStore {
    private static let key = "allude.appIcon"
    /// 编号方案版本。`"2"` = 2026-11-15 重排后的连续编号 01…16。
    private static let schemeKey = "allude.appIcon.scheme"
    private static let currentScheme = "2"

    /// 🔴 2026-11-15 重排编号前的老 `rawValue` → 新图标。
    ///
    /// 老编号带空洞（2,3,5,7,9,12,14…22），新编号连续（1…16），两者**同名不同图**
    /// （老的 `icon09` 是「霓虹 A」，新的 `icon09` 是「蓝牌」）。所以不能靠
    /// 「能不能解出 case」判断新旧，必须靠 `schemeKey` 这个版本标记走一次性迁移。
    /// 已被主人删掉的那几套（icon01/04/06/08/10/11/13/23）不在表里 → 落到 `fallback`。
    private static let legacyMap: [String: AppIconChoice] = [
        "icon02": .icon01,   // 信封
        "icon03": .icon02,   // 取件袋
        "icon05": .icon03,   // 文件夹
        "icon07": .icon04,   // C 标（默认）
        "icon09": .icon05,   // 霓虹 A
        "icon12": .icon06,   // 包裹
        "icon14": .icon07,   // 黑盒立体
        "icon15": .icon08,   // 蓝盒立体
        "icon16": .icon09,   // 蓝牌
        "icon17": .icon10,   // 黑盒平涂
        "icon18": .icon11,   // 蓝盒平涂
        "icon19": .icon12,   // 黑牌
        "icon20": .icon13,   // 暗牌
        "icon21": .icon14,   // 光泽黑标
        "icon22": .icon15,   // 白盒平涂
    ]

    /// 同一容器内的镜像文件。
    ///
    /// 🔴 为什么需要它（2026-11-15 实测）：App Group **不可用**时
    ///    （典型是命令行 `CODE_SIGNING_ALLOWED=NO` 构建的无签名调试包），
    ///    `UserDefaults(suiteName:)` 返回 nil，App 写进自己的 `.standard`、
    ///    扩展写进扩展自己的 `.standard` —— 两个进程互相看不见。
    ///    结果就是「桌面图标换了、灵动岛还是 C 标」，主人一眼看出对不上。
    ///    文件走 `PickupStorage.directory`：App Group 在就用共享目录，
    ///    不在就回落到 App 容器（扩展与 App 共用同一个容器），两边都能读。
    private static var mirrorURL: URL {
        PickupStorage.directory.appendingPathComponent("appicon.txt")
    }

    /// 当前选中的图标。未选过 → `fallback`（C 标）。
    ///
    /// 读取顺序：App Group 偏好 → 同容器镜像文件 → 本进程 `.standard`。
    static var current: AppIconChoice {
        if let raw = UserDefaults(suiteName: PickupStorage.appGroupID)?.string(forKey: key),
           let choice = AppIconChoice(rawValue: raw) {
            return choice
        }
        if let raw = try? String(contentsOf: mirrorURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let choice = AppIconChoice(rawValue: raw) {
            return choice
        }
        if let raw = UserDefaults.standard.string(forKey: key),
           let choice = AppIconChoice(rawValue: raw) {
            return choice
        }
        return .fallback
    }

    /// 存下来的原始值，**不做合法性校验**；三处按与 `current` 相同的优先级，
    /// 取第一个非空。没存过 → nil。
    private static var storedRawValue: String? {
        if let raw = UserDefaults(suiteName: PickupStorage.appGroupID)?.string(forKey: key) {
            return raw
        }
        if let raw = try? String(contentsOf: mirrorURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) {
            return raw
        }
        return UserDefaults.standard.string(forKey: key)
    }

    /// 一次性迁移：把老编号方案下的选择换算到新编号。
    ///
    /// 只在 `schemeKey != "2"` 时执行，跑完打标记，之后永久 no-op。
    /// 返回**迁移后应当生效的图标**；调用方负责把它同步给系统
    /// （`UIApplication.shared.setAlternateIconName(choice.alternateName)`）。
    /// 没有迁移发生（已是新方案）时返回 nil。
    @discardableResult
    static func migrateLegacyNumberingIfNeeded() -> AppIconChoice? {
        if UserDefaults.standard.string(forKey: schemeKey) == currentScheme { return nil }

        // 迁移只认「旧方案存下来的名字」：命中 legacyMap 就换算，
        // 其余（没存过 = 全新安装，或存的是已删除图标）一律回落到当前默认图标。
        // ⚠️ 不能写成「能解出 case 就沿用」—— 新旧方案的 iconNN 同名不同图。
        let target = storedRawValue.flatMap { legacyMap[$0] } ?? .fallback

        // `store` 会顺手把方案标记写进去，这里再补一遍确保三处一致
        store(target)
        return target
    }

    /// 写选择：三处都写（App Group 偏好、镜像文件、本进程偏好），
    /// 保证「有 App Group」与「没有 App Group」两种情况下扩展都读得到。
    /// 真正切换系统图标由 App 侧调用 `UIApplication.setAlternateIconName` 完成。
    ///
    /// 🔴 顺手打上 `schemeKey` 标记：新版本写下的值一律是「新编号方案」，
    ///    否则下次冷启动的一次性迁移会把它当成旧编号再换一遍（会换错）。
    static func store(_ choice: AppIconChoice) {
        UserDefaults(suiteName: PickupStorage.appGroupID)?.set(choice.rawValue, forKey: key)
        UserDefaults(suiteName: PickupStorage.appGroupID)?.set(currentScheme, forKey: schemeKey)
        UserDefaults.standard.set(choice.rawValue, forKey: key)
        UserDefaults.standard.set(currentScheme, forKey: schemeKey)
        try? FileManager.default.createDirectory(at: PickupStorage.directory,
                                                 withIntermediateDirectories: true)
        try? choice.rawValue.write(to: mirrorURL, atomically: true, encoding: .utf8)
    }
}
