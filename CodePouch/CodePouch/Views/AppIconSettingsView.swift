import SwiftUI

// MARK: ============================================================================
// App 图标（2026-11-01 主人）
//
// 系统级切换：`UIApplication.setAlternateIconName`。选中后桌面、设置、多任务、
// 通知里的图标会一起变 —— 除了「通知里显示的图标」这一类由系统接管的地方，
// 我们不用（也做不到）自己绘制。
//
// App 内能看到图标的地方（关于页、灵动岛/锁屏）读同一份选择，
// 见 `AppIconChoice` / `AppiconMark`。
// ============================================================================

struct AppIconSettingsView: View {
    @State private var selected = AppIconStore.current
    @State private var showError = false

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 18)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(AppIconChoice.allCases) { choice in
                        option(choice)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .cardSurface()

                Text("更换后，桌面、App 资源库、多任务和通知里的图标会一起改变。")
                    .font(.caption2)
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
        // 截图/验收脚手架：命令行点不了图标，`APP_ICON=envelope|cards|hand`
        // 在页面出现后延迟一拍再切 —— App.init 里调 setAlternateIconName 太早，
        // 场景还没连上，系统连回调都不给（实测：既不换图标也不报错）。
        .onAppear {
            guard let raw = ProcessInfo.processInfo.environment["APP_ICON"],
                  let choice = AppIconChoice(rawValue: raw) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                // 直接调系统 API，绕过「已选中就返回」的 guard（脚手架要能强制切换）
                AppIconStore.store(choice)
                UIApplication.shared.setAlternateIconName(choice.alternateName) { error in
                    DiagnosticsLog.record("appIcon", "scaffold=\(choice.rawValue) error=\(error.map { "\($0)" } ?? "none")")
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

    private func option(_ choice: AppIconChoice) -> some View {
        Button {
            apply(choice)
        } label: {
            VStack(spacing: 8) {
                Image(choice.assetName)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .clipShape(.rect(cornerRadius: 72 * 0.2237, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 72 * 0.2237, style: .continuous)
                            .strokeBorder(AppTheme.accent, lineWidth: selected == choice ? 2 : 0)
                            .padding(-4)
                    }

                HStack(spacing: 4) {
                    if selected == choice {
                        Image(systemName: "checkmark.circle.fill")
                            .font(AppTheme.TypeScale.note)
                            .foregroundStyle(AppTheme.accent)
                    }
                    Text(choice.title)
                        .font(.system(size: 13, weight: selected == choice ? .semibold : .regular))
                        .foregroundStyle(selected == choice ? AppTheme.accent : .secondary)
                }
            }
        }
        .buttonStyle(.plain)
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
                    // 失败就回滚选择，避免界面显示"已切换"但桌面没变
                    AppIconStore.store(selected)
                } else {
                    DiagnosticsLog.record("appIcon", "changed to \\(choice.rawValue)")
                    withAnimation(.snappy(duration: 0.2)) { selected = choice }
                }
            }
        }
    }
}
