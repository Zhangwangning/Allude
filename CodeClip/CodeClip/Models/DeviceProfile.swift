import UIKit

// MARK: ============================================================================
// 设备能力档案
//
// 灵动岛没有公开的「支持与否」查询 API —— ActivityKit 在任何设备上都可用，
// 系统会自动把灵动岛形态降级成锁屏卡片。但产品口径需要区分（#主人 2026-09-21）：
// **没有灵动岛的机型（iPhone 13 Pro Max 及更早 / 全系非 Pro 刘海屏），
// 不该在 UI 里展示「灵动岛」这个功能** —— 说了用户也用不上，只会困惑。
// 锁屏实时活动在这些设备上照常有效（系统自动降级），所以功能本身不关，
// 只是把「灵动岛」字样与岛形态的展示收起来。
//
// 机型判定：utsname 读 machine；**模拟器不返回机型名**（返回 arm64/x86_64），
// 用 `SIMULATOR_MODEL_IDENTIFIER` 环境变量拿真实机型 —— 模拟器选「iPhone 16 Pro」
// 就该按有岛处理、选「iPhone 13 Pro Max」就按无岛处理。
// ============================================================================

enum DeviceProfile {

    private static let machine: String = {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown"
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        #endif
    }()

    /// iPhone 14 Pro 起才有灵动岛；白名单 + 「iPhone17/18/19 及以后全系」规则。
    /// iPhone 15 全系、16 全系（含 16e）、17 全系都有岛；14 / 13 及更早全系没有。
    static var hasDynamicIsland: Bool {
        switch machine {
        case "iPhone15,2", "iPhone15,3":          // 14 Pro / 14 Pro Max
            return true
        case "iPhone15,4", "iPhone15,5",          // 15 / 15 Plus
             "iPhone16,1", "iPhone16,2":          // 15 Pro / 15 Pro Max
            return true
        default:
            // iPhone 16 / 17 及以后全系标配灵动岛（identifier 前缀 iPhone17+）
            return machine.hasPrefix("iPhone17")
                || machine.hasPrefix("iPhone18")
                || machine.hasPrefix("iPhone19")
        }
    }
}
