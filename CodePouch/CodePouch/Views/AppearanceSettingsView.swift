import SwiftUI
import UIKit

// MARK: ============================================================================
// 设置 › 外观 / 字体大小（2026-11-04 主人定）
//
// 外观：三档（自动 / 浅色 / 深色），存 App Group，根视图用 preferredColorScheme 生效。
// 字体大小：二级页 —— 预览区（照主人给的参考图）+「跟随系统」开关 + 底部字号滑块。
//
// 🔴 字号不是逐页改，而是**全局倍率**（`FontScale`），`AppTheme.TypeScale` 里每档都乘它。
// ============================================================================

// MARK: - 根视图外观宿主

/// 把外观与字号接到整棵视图树上的宿主。
///
/// 为什么要包一层：
///   · `preferredColorScheme` 必须在**根**上设，散在页面里会被系统覆盖；
///   · 字号是 static 倍率，SwiftUI 不会自动重算 body，只能靠 `.id` 重建一次整棵树。
struct AppearanceHost<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var settings = AppearanceSettings.shared

    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            // DARK=1 是截图脚手架，优先级高于「自动」，方便拍暗色取证
            .preferredColorScheme(
                ProcessInfo.processInfo.environment["DARK"] == "1"
                ? .dark : settings.mode.colorScheme
            )
            // 字号通过 Dynamic Type 生效：只改环境值，**不会重建视图树**，
            // 所以拖滑块时不会把导航栈清掉、弹回首页。
            .environment(\.dynamicTypeSize,
                         settings.followSystem ? dynamicTypeSize : settings.step.dynamicTypeSize)
    }
}

// MARK: - 外观

struct AppearanceSettingsView: View {
    @State private var settings = AppearanceSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(Array(AppearanceMode.allCases.enumerated()), id: \.element) { index, mode in
                        Button {
                            withAnimation(.snappy(duration: 0.22)) { settings.mode = mode }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.title.L)
                                        .font(AppTheme.TypeScale.rowTitle)
                                        .foregroundStyle(.primary)
                                    Text(mode.detail.L)
                                        .font(AppTheme.TypeScale.rowSubtitle)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if settings.mode == mode {
                                    Image(systemName: "checkmark")
                                        .font(AppTheme.TypeScale.body.weight(.semibold))
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)

                        if index < AppearanceMode.allCases.count - 1 {
                            SettingsDivider()
                        }
                    }
                }
                .cardSurface()

                Text("「自动」跟随系统的深浅色设置；选「浅色」或「深色」后，本 App 不再随系统切换。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 字体大小

struct FontSizeView: View {
    @State private var settings = AppearanceSettings.shared

    /// 预览用的示例文本（照主人参考图的两行说明）
    private let sampleTitle = "预览文字大小"
    private let sampleBody = "你可以拖动滑块来调整字体大小。"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // ── 预览卡 ──
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Spacer(minLength: 0)
                        Text(sampleTitle.L)
                            .font(AppTheme.TypeScale.rowSubtitle.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(Color(.secondarySystemFill))
                            )
                    }

                    Text(sampleBody.L)
                        .font(AppTheme.TypeScale.body)
                        .foregroundStyle(.primary)

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .frame(minHeight: 260, alignment: .topLeading)
                .cardSurface()

                // ── 跟随系统 ──
                HStack {
                    Text("跟随系统")
                        .font(AppTheme.TypeScale.rowTitle)
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { settings.followSystem },
                        set: { settings.followSystem = $0 }
                    ))
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .cardSurface()

                // ── 滑块 ──
                VStack(spacing: 10) {
                    HStack {
                        Text("A")
                            .font(AppTheme.TypeScale.rowSubtitle.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(settings.followSystem ? "跟随系统" : settings.step.title)
                            .font(AppTheme.TypeScale.note)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("A")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(settings.step.rawValue) },
                            set: { settings.step = FontSizeStep(rawValue: Int($0.rounded())) ?? .standard }
                        ),
                        in: 0...Double(FontSizeStep.allCases.count - 1),
                        step: 1
                    )
                    .tint(AppTheme.accent)
                    .disabled(settings.followSystem)
                    .opacity(settings.followSystem ? 0.45 : 1)

                    HStack {
                        Text(settings.followSystem ? "跟随系统字号" : "当前：\(settings.step.title)")
                            .font(AppTheme.TypeScale.note)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding(16)
                .cardSurface()

                Text("字号只影响拾码自己，不改系统的文字大小。设置页、列表与卡片会一起变化。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("字体大小")
        .navigationBarTitleDisplayMode(.inline)
    }

}
