import SwiftUI
import OSLog

// MARK: ============================================================================
// App 图标（2026-11-01 主人）
//
// 版式照**快递公司页**那一套：白色卡片里 4 列自适应网格，格子 = 54pt 圆角方块 + 一行名字。
// 换图标是系统级动作（`UIApplication.setAlternateIconName`），选中后桌面、设置、
// 多任务、通知里的图标会一起变；灵动岛与关于页读同一份选择。
// ============================================================================

struct AppIconSettingsView: View {
    @State private var selected = AppIconStore.current
    @State private var showError = false

    /// 与快递公司页同口径：自适应列，最小 72pt（54 方块 + 左右留白）
    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(AppIconChoice.allCases) { choice in
                        cell(choice)
                    }
                }
                .padding(14)
                .cardSurface()

                Text("更换后，桌面、App 资源库、多任务和通知里的图标会一起改变。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("App 图标")
        .navigationBarTitleDisplayMode(.inline)
        // 截图/验收脚手架：命令行点不了格子，`APP_ICON=icon05` 强制切换。
        .onAppear {
            guard let raw = ProcessInfo.processInfo.environment["APP_ICON"],
                  let choice = AppIconChoice(rawValue: raw) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                AppIconStore.store(choice)
                UIApplication.shared.setAlternateIconName(choice.alternateName) { error in
                    Logger(subsystem: "com.jikezhang.codeclip", category: "appIcon")
                        .notice("scaffold=\(choice.rawValue, privacy: .public) error=\(error.map { "\($0)" } ?? "none", privacy: .public)")
                    DispatchQueue.main.async {
                        if error == nil { selected = choice }
                    }
                }
            }
        }
        .alert("更换图标失败", isPresented: $showError) {
            Button("好", role: .cancel) {}
        } message: {
            Text("系统暂时不能更换图标，请稍后再试。")
        }
    }

    /// 与快递公司页一致：分类图标 + 标题 + 数量 + 说明
    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "app.badge.fill")
                .font(AppTheme.TypeScale.badge)
                .foregroundStyle(AppTheme.accent)
            Text("可选图标")
                .font(AppTheme.TypeScale.rowSubtitle.weight(.semibold))
            Text("\(AppIconChoice.allCases.count)")
                .font(AppTheme.TypeScale.note)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
    }

    private func cell(_ choice: AppIconChoice) -> some View {
        let isOn = choice == selected

        return Button {
            apply(choice)
        } label: {
            VStack(spacing: 7) {
                Image(choice.assetName)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 54, height: 54)
                    .clipShape(.rect(cornerRadius: 54 * 0.29, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 54 * 0.29, style: .continuous)
                            .strokeBorder(AppTheme.accent, lineWidth: isOn ? 2 : 0)
                            .padding(-3)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isOn {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.accent)
                                .background(Circle().fill(.white).padding(1.5))
                                .offset(x: 4, y: 4)
                        }
                    }

                Text(choice.title.L)
                    .font(.system(size: 10))
                    .foregroundStyle(isOn ? AppTheme.accent : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(height: 14, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(choice.title)图标")
    }

    private func apply(_ choice: AppIconChoice) {
        guard choice != selected else { return }
        guard UIApplication.shared.supportsAlternateIcons else {
            showError = true
            return
        }

        // 先写共享状态：灵动岛/关于页立刻跟着变；系统图标随后换。
        AppIconStore.store(choice)
        UIApplication.shared.setAlternateIconName(choice.alternateName) { error in
            DispatchQueue.main.async {
                if error != nil {
                    showError = true
                    AppIconStore.store(selected)
                } else {
                    Logger(subsystem: "com.jikezhang.codeclip", category: "appIcon")
                        .notice("changed to \(choice.rawValue, privacy: .public)")
                    withAnimation(.snappy(duration: 0.2)) { selected = choice }
                }
            }
        }
    }
}
