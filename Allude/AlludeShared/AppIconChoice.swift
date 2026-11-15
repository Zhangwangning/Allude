import Foundation

// MARK: ============================================================================
// App 图标切换（2026-11-01 主人）
//
// 十六套内置图标，**第 7 套（C 标）为默认主图标**（2026-11-11 主人定；
// 2026-11-12 主人又补了第 9–12 套；2026-11-15 补第 13 套「快递箱」，
// 同日晚再补第 14–21 套「快递盒 / ALLUDE 招牌」八个变体）。
//
// 🔴 2026-11-15 主人圈掉六套（1 号码牌 / 4 扫码件 / 6 手提袋 / 8 卡包 / 11 牛皮纸 /
//    13 快递箱），要求删掉；同晚又给了两张「白色 ALLUDE 立方体」补成 22、23，
//    随即又删掉 23（「最后一个图标」），最终 16 套。**编号故意留空、不重排**：rawValue 与 `number` 都是持久化过的
//    （App Group 偏好里的 `allude.appIcon`、资源名 `AppIconNN`、Info.plist 的
//    `IconNN`），一重排就会让老用户选的图变成另一张。删掉的号从此不复用。
//
// 🔴 图标的 imageset 统一放 `AlludeShared/Assets.xcassets`（2026-11-15 从 App 的
//    catalog 迁过来）：App 与小组件两个 target **都**编译这份共享 catalog，
//    灵动岛/锁屏才取得到图。之前只放在 App 的 catalog 里，小组件进程找不到
//    `AppIconNN` 这名字，`Image(…)` 直接渲染成灰块 —— 那是 1.0.0(312) 灵动岛
//    不显示 App 图标的根因。
// 图都是 512 满幅方图，不再裁切；主图标 art 与 alternate 的对应关系见下。
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
    /// ⚠️ 编号 1、4、6、8、11、13 已于 2026-11-15 删除，不再存在。
    case icon02, icon03, icon05, icon07, icon09, icon10
    /// 2026-11-15 主人补的第二批：8 张「快递盒 / ALLUDE 招牌」变体（立体、平涂、光泽各配色）。
    /// 其中第 13 套「快递箱」同晚被删。
    /// 🔴 都是 1536 满幅方图，**不裁切**、直接等比缩放到 60/120/180 与 120/180。
    case icon12, icon14, icon15, icon16, icon17, icon18, icon19, icon20, icon21
    /// 2026-11-15 深夜第三笔：主人给的两张「白色 ALLUDE 立方体」，其中 3D 玻璃那套
    /// （原 23）当晚又被主人点名删掉，只留下 22「白盒平涂」。
    case icon22

    /// 默认图标 = 第 7 套（C 标）。
    ///
    /// 🔴 2026-11-11 主人：默认图标换成「C 标」。主图标（`AppIcon.appiconset`）
    ///    art 已同步换成 C 标；原来的「取件袋」改为 alternate icon `Icon03`。
    static let fallback: AppIconChoice = .icon07

    var id: String { rawValue }

    /// 序号（= 历史编号，**有空洞**：1/4/6/8/11/13/23 已删）。用于文案与文件名。
    var number: Int {
        switch self {
        case .icon02: 2
        case .icon03: 3
        case .icon05: 5
        case .icon07: 7
        case .icon09: 9
        case .icon10: 10
        case .icon12: 12
        case .icon14: 14
        case .icon15: 15
        case .icon16: 16
        case .icon17: 17
        case .icon18: 18
        case .icon19: 19
        case .icon20: 20
        case .icon21: 21
        case .icon22: 22
        }
    }

    /// 格子里的名字。主人没点名，这里按图形起的描述名，随时可改。
    var title: String {
        switch self {
        case .icon02: "信封"
        case .icon03: "取件袋"
        case .icon05: "文件夹"
        case .icon07: "C 标"
        case .icon09: "霓虹 A"
        case .icon10: "折纸 A"
        case .icon12: "包裹"
        case .icon14: "黑盒立体"
        case .icon15: "蓝盒立体"
        case .icon16: "蓝牌"
        case .icon17: "黑盒平涂"
        case .icon18: "蓝盒平涂"
        case .icon19: "黑牌"
        case .icon20: "暗牌"
        case .icon21: "光泽黑标"
        case .icon22: "白盒平涂"
        }
    }

    /// 资源目录里的图（App 内预览、灵动岛、关于页都用这个名字）
    var assetName: String { String(format: "AppIcon%02d", number) }

    /// `UIApplication.setAlternateIconName` 用的名字；默认图标返回 nil
    ///
    /// 注意：`Icon03`（原主图标「取件袋」）现在是 alternate，必须由
    /// `Allude/Info.plist` 的 `CFBundleAlternateIcons` 声明 + bundle 根目录的
    /// `Icon03@2x.png`(120) / `Icon03@3x.png`(180) 两份文件，缺一不可。
    var alternateName: String? {
        self == Self.fallback ? nil : String(format: "Icon%02d", number)
    }
}

enum AppIconStore {
    private static let key = "allude.appIcon"

    /// 同一容器内的镜像文件。
    ///
    /// 🔴 为什么需要它（2026-11-15 实测）：App Group **不可用**时
    ///    （典型是命令行 `CODE_SIGNING_ALLOWED=NO` 构建的无签名调试包），
    ///    `UserDefaults(suiteName:)` 返回 nil，App 写进自己的 `.standard`、
    ///    扩展写进扩展自己的 `.standard` —— 两个进程互相看不见。
    ///    结果就是「桌面图标换了、灵动岛还是第 7 套 C 标」，主人一眼看出对不上。
    ///    文件走 `PickupStorage.directory`：App Group 在就用共享目录，
    ///    不在就回落到 App 容器（扩展与 App 共用同一个容器），两边都能读。
    private static var mirrorURL: URL {
        PickupStorage.directory.appendingPathComponent("appicon.txt")
    }

    /// 当前选中的图标。未选过 → `fallback`（第 7 套 C 标）。
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

    /// 🔴 2026-11-15 删掉 5 套图标（1 号码牌 / 4 扫码件 / 6 手提袋 / 8 卡包 / 11 牛皮纸）
    ///    之后必须处理的一种存量状态：老用户当时选的正好是被删的那几套，
    ///    偏好里存着 `icon01` 这类现在解不出 case 的名字。
    ///    App 内读到 true 就 `store(.fallback)` 并 `setAlternateIconName(nil)` ——
    ///    后者会把系统的备用图标引用归零，否则桌面还挂着已经不存在的图。
    static var hasDanglingSelection: Bool {
        guard let raw = storedRawValue, !raw.isEmpty else { return false }
        return AppIconChoice(rawValue: raw) == nil
    }

    /// 写选择：三处都写（App Group 偏好、镜像文件、本进程偏好），
    /// 保证「有 App Group」与「没有 App Group」两种情况下扩展都读得到。
    /// 真正切换系统图标由 App 侧调用 `UIApplication.setAlternateIconName` 完成。
    static func store(_ choice: AppIconChoice) {
        UserDefaults(suiteName: PickupStorage.appGroupID)?.set(choice.rawValue, forKey: key)
        UserDefaults.standard.set(choice.rawValue, forKey: key)
        try? FileManager.default.createDirectory(at: PickupStorage.directory,
                                                 withIntermediateDirectories: true)
        try? choice.rawValue.write(to: mirrorURL, atomically: true, encoding: .utf8)
    }
}
