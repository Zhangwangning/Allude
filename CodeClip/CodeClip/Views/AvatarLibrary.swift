import SwiftUI

// MARK: ============================================================================
// 内置头像库（2026-09-23 深夜二版 · 主人要求"太幼稚化，更新一版"）
//
// 一版卡通（熊/猫/兔…）整体退役，改为 **抽象几何**：
//   每款 = 一组**深色系渐变底** + **白色极简几何**（月牙、山脊、轨道…）。
// 成熟感的来源是三件事：深色底、渐变、克制的线条 —— 不画脸、不画眼睛。
//
// 🔴 **全部 SwiftUI 绘制，零图片资源**（沿用一版的三条理由）：
//   ① 任何尺寸都不糊（30pt 导航栏 → 88pt 预览同一份代码）；
//   ② 与全 App 几何语言一致，没有"贴图感"；
//   ③ 调一个数字就改比例。
//
// ⚠️ 坐标系：全部按 `size` 归一化（`s * 比例`），换尺寸零改动。
// ============================================================================

// MARK: - 头像款式

enum AccountAvatarStyle: String, CaseIterable, Identifiable {
    /// 用户自己上传的照片（相册选一张）。
    ///
    /// 🔴 **排在第一位**：自定义是唯一"属于我"的选项，其余都是备选。
    case custom
    /// 月相 — 午夜蓝 + 白月牙（出厂默认，最中性）
    case moon
    /// 山峦 — 黛青 + 双峰折线
    case peaks
    /// 波纹 — 海蓝 + 三道浪线
    case waves
    /// 星轨 — 墨黑 + 轨道环与卫星
    case orbit
    /// 日环 — 暗紫 + 偏心圆环
    case eclipse
    /// 沙丘 — 暖沙 + 层叠沙弧
    case dune
    /// 极光 — 深绿 + 光带
    case aurora
    /// 晶面 — 石墨 + 切面线
    case facet
    /// 潮汐 — 靛蓝 + 月与海面
    case tide
    /// 晨昏 — 暮色 + 地平线半日
    case horizon
    /// 曜石 — 近黑 + 尖峰轮廓
    case obsidian

    var id: String { rawValue }

    var title: String {
        switch self {
        case .custom:   return "自定义"
        case .moon:     return "月相"
        case .peaks:    return "山峦"
        case .waves:    return "波纹"
        case .orbit:    return "星轨"
        case .eclipse:  return "日环"
        case .dune:     return "沙丘"
        case .aurora:   return "极光"
        case .facet:    return "晶面"
        case .tide:     return "潮汐"
        case .horizon:  return "晨昏"
        case .obsidian: return "曜石"
        }
    }

    /// 出厂默认：月相 —— 深色底上白月牙，最中性也最耐看。
    /// 🔴 老用户存的旧款式名（bear/cat…首字）解不出来时也落到这里，
    ///    `LocalAccount.avatar` 的 `?? .fallback` 兜底保证不出现空白头像。
    static let fallback: AccountAvatarStyle = .moon

    /// 内置（非上传）款式。
    static var builtIns: [AccountAvatarStyle] { allCases.filter { $0 != .custom } }
}

// MARK: - 几何头像

/// 一款抽象头像。`size` 是外接圆直径。
struct CartoonAvatar: View {
    let style: AccountAvatarStyle
    let size: CGFloat

    private var s: CGFloat { size }

    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: backdrop,
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
            )

            switch style {
            case .custom:   AvatarUploadPlaceholder(size: s)
            case .moon:     moon
            case .peaks:    peaks
            case .waves:    waves
            case .orbit:    orbit
            case .eclipse:  eclipse
            case .dune:     dune
            case .aurora:   aurora
            case .facet:    facet
            case .tide:     tide
            case .horizon:  horizon
            case .obsidian: obsidian
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
    }

    // MARK: 调色

    /// 每款底色的渐变两端（对角向）。全深色系，这是"成熟感"的底子。
    private var backdrop: [Color] {
        switch style {
        case .custom:   return [.clear, .clear]
        case .moon:     return [rgb(0x27, 0x35, 0x58), rgb(0x0F, 0x18, 0x30)]
        case .peaks:    return [rgb(0x33, 0x52, 0x5B), rgb(0x14, 0x28, 0x2E)]
        case .waves:    return [rgb(0x24, 0x55, 0x66), rgb(0x0D, 0x28, 0x33)]
        case .orbit:    return [rgb(0x2A, 0x2A, 0x33), rgb(0x10, 0x10, 0x15)]
        case .eclipse:  return [rgb(0x43, 0x32, 0x5E), rgb(0x1B, 0x14, 0x28)]
        case .dune:     return [rgb(0x77, 0x52, 0x38), rgb(0x39, 0x28, 0x1B)]
        case .aurora:   return [rgb(0x16, 0x44, 0x3A), rgb(0x08, 0x1C, 0x18)]
        case .facet:    return [rgb(0x40, 0x46, 0x4F), rgb(0x1D, 0x20, 0x24)]
        case .tide:     return [rgb(0x28, 0x3E, 0x78), rgb(0x11, 0x1A, 0x38)]
        case .horizon:  return [rgb(0x93, 0x51, 0x3E), rgb(0x2E, 0x1A, 0x28)]
        case .obsidian: return [rgb(0x27, 0x27, 0x2B), rgb(0x0C, 0x0C, 0x0E)]
        }
    }

    /// 几何元素统一用米白（不是纯白 —— 纯白在深底上太"闪"）。
    private var ivory: Color { rgb(0xF2, 0xEE, 0xE4) }

    private func rgb(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    // MARK: 零件

    /// 描边圆/环。
    private func ring(_ color: Color, diameter: CGFloat,
                      lineWidth: CGFloat, dx: CGFloat = 0, dy: CGFloat = 0) -> some View {
        Circle()
            .stroke(color, lineWidth: max(0.8, s * lineWidth))
            .frame(width: s * diameter, height: s * diameter)
            .offset(x: s * dx, y: s * dy)
    }

    private func dot(_ color: Color, _ d: CGFloat, dx: CGFloat = 0, dy: CGFloat = 0) -> some View {
        Circle()
            .fill(color)
            .frame(width: s * d, height: s * d)
            .offset(x: s * dx, y: s * dy)
    }

    /// 折线/曲线描边。`points`/`curve` 都按中心归一化坐标给（0 = 中心）。
    private func stroke(_ color: Color, lineWidth: CGFloat,
                        points: [(CGFloat, CGFloat)]) -> some View {
        Path { p in
            guard let first = points.first else { return }
            p.move(to: CGPoint(x: s / 2 + s * first.0, y: s / 2 + s * first.1))
            for pt in points.dropFirst() {
                p.addLine(to: CGPoint(x: s / 2 + s * pt.0, y: s / 2 + s * pt.1))
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: max(0.9, s * lineWidth),
                                          lineCap: .round, lineJoin: .round))
        .frame(width: s, height: s)
    }

    /// 二次曲线。
    private func quad(_ color: Color, lineWidth: CGFloat,
                      from: (CGFloat, CGFloat), to: (CGFloat, CGFloat),
                      control: (CGFloat, CGFloat)) -> some View {
        Path { p in
            p.move(to: CGPoint(x: s / 2 + s * from.0, y: s / 2 + s * from.1))
            p.addQuadCurve(to: CGPoint(x: s / 2 + s * to.0, y: s / 2 + s * to.1),
                           control: CGPoint(x: s / 2 + s * control.0, y: s / 2 + s * control.1))
        }
        .stroke(color, style: StrokeStyle(lineWidth: max(0.9, s * lineWidth), lineCap: .round))
        .frame(width: s, height: s)
    }

    /// 填充多边形。
    private func poly(_ color: Color, _ points: [(CGFloat, CGFloat)]) -> some View {
        Path { p in
            guard let first = points.first else { return }
            p.move(to: CGPoint(x: s / 2 + s * first.0, y: s / 2 + s * first.1))
            for pt in points.dropFirst() {
                p.addLine(to: CGPoint(x: s / 2 + s * pt.0, y: s / 2 + s * pt.1))
            }
            p.closeSubpath()
        }
        .fill(color)
        .frame(width: s, height: s)
    }

    // MARK: 各款

    /// 月相：白月牙 = 大白圆 + 底色圆偏移盖掉一角。
    private var moon: some View {
        let bg = backdrop[1]
        return ZStack {
            dot(ivory, 0.46, dx: 0.02, dy: -0.02)
            dot(bg, 0.44, dx: 0.16, dy: -0.10)
            // 一颗伴星，压住"表情包"感
            dot(ivory.opacity(0.85), 0.045, dx: -0.26, dy: 0.24)
        }
    }

    /// 山峦：双峰折线 + 一线月。
    private var peaks: some View {
        ZStack {
            stroke(ivory.opacity(0.92), lineWidth: 0.045,
                   points: [(-0.36, 0.24), (-0.12, -0.16), (0.04, 0.08), (0.20, -0.22), (0.38, 0.24)])
            dot(ivory, 0.075, dx: 0.24, dy: -0.30)
        }
    }

    /// 波纹：三道渐短的浪。
    private var waves: some View {
        ZStack {
            quad(ivory.opacity(0.95), lineWidth: 0.045,
                 from: (-0.30, -0.10), to: (0.30, -0.10), control: (0, -0.24))
            quad(ivory.opacity(0.70), lineWidth: 0.045,
                 from: (-0.30, 0.08), to: (0.30, 0.08), control: (0, -0.06))
            quad(ivory.opacity(0.42), lineWidth: 0.045,
                 from: (-0.30, 0.26), to: (0.30, 0.26), control: (0, 0.12))
        }
    }

    /// 星轨：斜置轨道环 + 卫星 + 中心星。
    private var orbit: some View {
        ZStack {
            ring(ivory.opacity(0.85), diameter: 0.62, lineWidth: 0.035)
                .rotationEffect(.degrees(-24))
            dot(ivory, 0.10, dx: 0.20, dy: -0.16)
            dot(ivory, 0.055)
        }
    }

    /// 日环：偏心圆环，环心叠一枚实心点。
    private var eclipse: some View {
        ZStack {
            ring(ivory.opacity(0.92), diameter: 0.52, lineWidth: 0.05, dx: 0.05, dy: -0.04)
            dot(ivory, 0.075, dx: 0.05, dy: -0.04)
            dot(ivory.opacity(0.5), 0.045, dx: -0.26, dy: 0.28)
        }
    }

    /// 沙丘：两道交叠弧，前弧压后弧。
    private var dune: some View {
        ZStack {
            quad(ivory.opacity(0.34), lineWidth: 0.05,
                 from: (-0.40, 0.02), to: (0.40, -0.10), control: (-0.02, -0.22))
            quad(ivory.opacity(0.75), lineWidth: 0.05,
                 from: (-0.40, 0.24), to: (0.40, 0.14), control: (0.02, -0.02))
        }
    }

    /// 极光：一道由浓到淡的光带（渐变遮罩曲线）。
    private var aurora: some View {
        let auroraGreen = rgb(0x7F, 0xE3, 0xB0)
        return ZStack {
            quad(auroraGreen, lineWidth: 0.09,
                 from: (-0.34, -0.06), to: (0.34, -0.20), control: (0, -0.30))
                .opacity(0.85)
            quad(auroraGreen.opacity(0.45), lineWidth: 0.07,
                 from: (-0.30, 0.10), to: (0.30, -0.02), control: (0, -0.08))
            dot(ivory.opacity(0.9), 0.05, dx: -0.24, dy: -0.28)
        }
    }

    /// 晶面：三线交于一点的切面。
    private var facet: some View {
        ZStack {
            stroke(ivory.opacity(0.9), lineWidth: 0.04,
                   points: [(-0.32, -0.20), (0.06, 0.06), (-0.10, 0.34)])
            stroke(ivory.opacity(0.55), lineWidth: 0.04,
                   points: [(0.34, -0.24), (0.06, 0.06)])
            stroke(ivory.opacity(0.35), lineWidth: 0.04,
                   points: [(-0.34, 0.16), (0.06, 0.06)])
        }
    }

    /// 潮汐：小满月悬在海面上，两道静水线。
    private var tide: some View {
        ZStack {
            dot(ivory, 0.24, dx: 0.0, dy: -0.16)
            stroke(ivory.opacity(0.75), lineWidth: 0.04,
                   points: [(-0.28, 0.16), (0.28, 0.16)])
            stroke(ivory.opacity(0.4), lineWidth: 0.04,
                   points: [(-0.16, 0.32), (0.16, 0.32)])
        }
    }

    /// 晨昏：地平线 + 半轮落日。
    private var horizon: some View {
        ZStack {
            // 半日：圆的上半在线上，下半被底色横带盖掉
            dot(ivory, 0.30, dy: -0.10)
            Rectangle()
                .fill(LinearGradient(colors: backdrop,
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: s, height: s * 0.30)
                .offset(y: s * 0.28)
            stroke(ivory.opacity(0.85), lineWidth: 0.04,
                   points: [(-0.36, 0.13), (0.36, 0.13)])
        }
    }

    /// 曜石：实心尖峰 + 白描轮廓。
    private var obsidian: some View {
        ZStack {
            poly(ivory.opacity(0.9),
                 [(-0.06, -0.30), (0.16, 0.10), (-0.28, 0.10)])
            stroke(ivory.opacity(0.45), lineWidth: 0.035,
                   points: [(-0.36, 0.30), (0.36, 0.30)])
            dot(ivory, 0.05, dx: 0.22, dy: -0.22)
        }
    }
}

// MARK: - 「自定义」占位

/// 还没上传照片时的占位圆：灰底 + 相机。
///
/// 用相机而不是"+"：这一格的动作是**从相册挑一张**，不是"新建"。
struct AvatarUploadPlaceholder: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(.tertiarySystemFill))
            Image(systemName: "camera.fill")
                .font(.system(size: size * 0.30, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
    }
}
