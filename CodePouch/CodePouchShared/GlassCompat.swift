import SwiftUI

// MARK: ============================================================================
// 液态玻璃兼容层（2026-11-07）
//
// 背景：`.glassEffect`（Liquid Glass）是 iOS 26 新增 API。
// 拾码要同时兼容 iOS 18 / 26 / 27，所以统一走这一层：
//
//   · 系统 < 26           → 一律用系统毛玻璃 `.ultraThinMaterial` + 细描边
//   · 系统 >= 26 且开关开 → 真·液态玻璃
//   · 系统 >= 26 但关开关 → 也用毛玻璃（用户在「外观」里关掉了）
//
// 🔴 毛玻璃（`ultraThinMaterial`）本身就是 Apple 的系统材质，不是自绘 ——
//    在 iOS 18 上它就是系统设置/控制中心那种观感，符合规范。
// ============================================================================

enum GlassSettings {
    /// App Group 键：是否使用液态玻璃（外观设置项）
    static let key = "codeclip.usesLiquidGlass"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
    }

    /// 当前系统是否支持液态玻璃（iOS 26+）
    static var isSupported: Bool {
        if #available(iOS 26.0, *) { return true } else { return false }
    }

    /// 用户偏好（默认开）
    static var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    static func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: key)
    }

    /// 实际是否走液态玻璃
    static var isActive: Bool { isSupported && isEnabled }
}

extension View {
    /// 统一玻璃外壳：支持则液态玻璃，否则系统毛玻璃。
    /// - Parameters:
    ///   - shape: 玻璃形状（`.rect(cornerRadius:)` / `.capsule` / `.circle`）
    ///   - tint: 可选染色（液态玻璃下生效；毛玻璃下用同色极淡叠层近似）
    ///   - interactive: 是否要按下形变（仅液态玻璃支持）
    @ViewBuilder
    func appGlass<S: Shape>(_ shape: S,
                            tint: Color? = nil,
                            interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *), GlassSettings.isActive {
            let base = Glass.regular
            let tinted = tint.map { base.tint($0) } ?? base
            let final = interactive ? tinted.interactive() : tinted
            self.glassEffect(final, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    // 毛玻璃没有液态玻璃的镜面高光，用一圈极淡描边找边界
                    shape.stroke(.white.opacity(0.16), lineWidth: 0.5)
                }
                .overlay {
                    if let tint {
                        shape.fill(tint.opacity(0.35))
                    }
                }
        }
    }
}
