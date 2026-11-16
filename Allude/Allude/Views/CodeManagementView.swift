import SwiftUI
import WidgetKit

// MARK: ============================================================================
// 取件码管理（我的 › 设置 › 桌面小组件下面那一行）
//
// 2026-11-16 主人：「在设置页面中的桌面小组件的下面增加一个取件码管理，其二级页面中
//    可以设置取件码卡片中取件码的颜色……也可以设置一条取件码的透明度保持一个就行的，
//    还有一张卡片多个取件码的设置」。
//
// 四项设置，**全端统一**（待取 / 已取 / 详情 / 桌面小组件 / 灵动岛 / 分享卡）：
//   ① 取件码颜色：七档色板，默认「跟随品牌色」＝升级前观感；
//   ② 整码透明度：整条取件码只用一个透明度，不再前后段不一致；
//   ③ 末四位强调：保留原习惯（默认开），关掉后整串一个色一个透明度；
//      开的时候另有一档「前段透明度」可调；
//   ④ 一张卡片多个取件码：同一条短信拆出的多个码回到一张卡上，关掉立刻拆回一码一卡。
//
// 🔴 ④ 只改**显示层**：数据仍是一码一 `PickupRecord`（见 `PickupRecordGrouping`），
//    因此切换开关立即对全部历史生效，且不碰件数、去重、勾选、iCloud 同步。
//
// ⚠️ 所有值落在 App Group `UserDefaults`（`CodeAppearanceSettings`），
//    改完统一 `notifyChange()` 重画桌面时间线，再 `refreshRendering()` 重画实时活动 ——
//    ActivityKit 的活动不归 WidgetCenter 管，少这一步灵动岛要等下一条快递才变。
// ============================================================================

struct CodeManagementView: View {
    @State private var colorRaw = CodeAppearanceSettings.colorRaw
    @State private var opacity = CodeAppearanceSettings.opacity
    @State private var headOpacity = CodeAppearanceSettings.headOpacity
    @State private var emphasis = CodeAppearanceSettings.emphasisEnabled
    @State private var groupMultiple = CodeAppearanceSettings.groupsMultipleCodes

    @State private var showOpacityMenu = false
    @State private var showHeadMenu = false

    private var choice: CodeColorChoice {
        CodeColorChoice(rawValue: colorRaw) ?? .brand
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                previewSection
                colorSection
                styleSection
                groupingSection
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 6)
            .padding(.bottom, 60)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("取件码管理")
        .cloaksTabBar()
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 实时预览

    /// 直接用**真实的** `PickupCodeEmphasis.text` 渲染，所见即 nine 个渲染面的所取。
    /// 示例短信含两个码 —— 开关打开时正好演示「一张卡两个取件码」。
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "效果预览")

            previewCard
                .frame(maxWidth: .infinity, alignment: .center)

            Text(choice == .brand
                 ? "示例数据 · 默认跟随快递公司品牌色，已取件仍显示为灰色"
                 : "示例数据 · 全端统一使用「\(choice.title)」，已取件仍显示为灰色")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewCodes: [String] {
        groupMultiple ? ["8-4-3019", "8-4-3020"] : ["8-4-3019"]
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("圆通速递")
                    .font(.system(size: 15.5, weight: .semibold))
                Text("|")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                Text("菜鸟驿站")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Text("今天 14:32")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text("幸福里小区 3 号楼东侧门店")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 4)

            DashedDivider()
                .padding(.top, 8)

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 1) {
                    ForEach(previewCodes, id: \.self) { code in
                        PickupCodeEmphasis.text(code, tint: AppTheme.accent)
                            .font(.system(size: previewCodes.count > 1 ? 24 : 30,
                                          weight: .bold, design: .rounded))
                            .monospaced()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }

                Spacer(minLength: 6)

                Image(systemName: "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .frame(width: 44, height: 44)
            }
            .padding(.top, 7)
        }
        .padding(.horizontal, AppTheme.cardPadding)
        .padding(.vertical, 12)
        .cardSurface(tint: AppTheme.accent)
        .frame(maxWidth: 360)
    }

    // MARK: 颜色

    private var colorSection: some View {
        SettingsGroup(title: "取件码颜色",
                      note: "「跟随品牌色」按快递公司取色，是原来的样子；选固定色后，待取页、已取页、桌面小组件、灵动岛和分享卡一起换。") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(CodeColorChoice.allCases) { item in
                        Button {
                            CodeAppearanceSettings.setColorRaw(item.rawValue)
                            colorRaw = item.rawValue
                            refreshLiveActivity()
                        } label: {
                            swatch(item)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.title)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)

                SettingsDivider(style: .plain)

                HStack(spacing: 6) {
                    Text("当前")
                        .font(AppTheme.TypeScale.rowSubtitle)
                        .foregroundStyle(.tertiary)
                    Text(choice.title.L)
                        .font(AppTheme.TypeScale.rowSubtitle.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private func swatch(_ item: CodeColorChoice) -> some View {
        let selected = item == choice
        ZStack {
            // 「跟随品牌色」画成多色环，一眼区别于六个固定色
            if item == .brand {
                Circle()
                    .fill(AngularGradient(colors: [.red, .orange, .yellow, .green,
                                                   AppTheme.accent, AppTheme.violet, .red],
                                          center: .center))
                    .frame(width: 30, height: 30)
            } else {
                Circle()
                    .fill(item.swatch)
                    .frame(width: 30, height: 30)
            }

            if selected {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.55), lineWidth: 2)
                    .frame(width: 38, height: 38)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1.5)
            }
        }
        .frame(height: 40)
        .contentShape(.rect)
    }

    // MARK: 显示方式

    private var styleSection: some View {
        SettingsGroup(title: "显示方式",
                      note: "关掉「末四位强调」，整条取件码就只剩一个颜色、一个透明度；已取件始终显示为灰色，不跟随这些设置。") {
            SettingsPlainRow(title: "整码透明度") {
                Button {
                    showOpacityMenu = true
                } label: {
                    SettingsValueLabel(text: Self.percent(opacity))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showOpacityMenu, arrowEdge: .top) {
                    valueMenu(options: CodeAppearanceSettings.opacityOptions,
                              current: opacity,
                              label: Self.percent) { picked in
                        CodeAppearanceSettings.setOpacity(picked)
                        opacity = picked
                        refreshLiveActivity()
                        showOpacityMenu = false
                    }
                    .presentationCompactAdaptation(.popover)
                }
            }

            SettingsDivider(style: .plain)

            SettingsPlainRow(title: "末四位强调") {
                Toggle("", isOn: $emphasis)
                    .labelsHidden()
                    .tint(AppTheme.accent)
                    .onChange(of: emphasis) { _, newValue in
                        CodeAppearanceSettings.setEmphasisEnabled(newValue)
                        refreshLiveActivity()
                    }
            }

            if emphasis {
                SettingsDivider(style: .plain)

                SettingsPlainRow(title: "前段透明度") {
                    Button {
                        showHeadMenu = true
                    } label: {
                        SettingsValueLabel(text: Self.percent(headOpacity))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showHeadMenu, arrowEdge: .top) {
                        valueMenu(options: CodeAppearanceSettings.headOpacityOptions,
                                  current: headOpacity,
                                  label: Self.percent) { picked in
                            CodeAppearanceSettings.setHeadOpacity(picked)
                            headOpacity = picked
                            refreshLiveActivity()
                            showHeadMenu = false
                        }
                        .presentationCompactAdaptation(.popover)
                    }
                }
            }
        }
    }

    // MARK: 卡片分组

    private var groupingSection: some View {
        SettingsGroup(title: "卡片",
                      note: "一条短信里有两个取件码时，开启后回到同一张卡；关闭则立刻拆回一码一张卡，对全部历史同时生效。件数统计与记录本身不受影响。") {
            SettingsPlainRow(title: "一张卡片多个取件码") {
                Toggle("", isOn: $groupMultiple)
                    .labelsHidden()
                    .tint(AppTheme.accent)
                    .onChange(of: groupMultiple) { _, newValue in
                        CodeAppearanceSettings.setGroupsMultipleCodes(newValue)
                        refreshLiveActivity()
                    }
            }
        }
    }

    // MARK: 工具

    /// 自绘选单（不用系统 `Menu`：它会把值染成蓝色，破坏「灰字 + chevron」口径）。
    private func valueMenu(options: [Double],
                           current: Double,
                           label: @escaping (Double) -> String,
                           pick: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    pick(option)
                } label: {
                    HStack(spacing: 12) {
                        Text(label(option))
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 20)
                        if abs(option - current) < 0.001 {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(.systemBlue))
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(width: 168, height: 42)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// `WidgetCenter` 的重画已在各 setter 里做过；这里补 ActivityKit 那一半。
    private func refreshLiveActivity() {
        Task { await PickupActivityController.refreshRendering() }
    }
}
