import SwiftUI
import FoundationModels

// MARK: ============================================================================
// 设置 › AI 能力检测（2026-11-05）
//
// 主人问过两次「我的 iPhone 到底能不能用端侧 AI」。答案只能从系统那里读：
// `SystemLanguageModel.default.availability`，以及它给出的具体原因。
//
// 这个页面的价值：
//   · 不用连电脑也能看，不用每次让开发者远程跑脚本；
//   · 换系统版本 / 换地区后，一眼能看出有没有放开；
//   · 「写作工具能用但这里不行」这种奇怪组合，页面上能直接对照出来。
//
// 🔴 不记录任何用户内容：只有机型、系统、地区、语言、可用性枚举。
// ============================================================================

@available(iOS 26.0, *)
struct AICapabilityView: View {
    @State private var refreshToken = 0
    /// 检测中的状态（2026-11-05 主人：点了没反应，以为没生效）
    @State private var isChecking = false
    /// 检测完成后短暂闪一下，让用户知道"刷新了"
    @State private var justChecked = false

    private var availability: SystemLanguageModel.Availability {
        _ = refreshToken
        return SystemLanguageModel.default.availability
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusCard
                detailCard
                explainCard
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Apple 智能")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: logOnce)
    }

    // MARK: 结论

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isAvailable ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isAvailable ? AppTheme.doneTint : AppTheme.pendingTint)
                Text(isAvailable ? "端侧模型可用" : "端侧模型不可用")
                    .font(AppTheme.TypeScale.rowTitleMedium)
                Spacer(minLength: 0)
            }

            Text(PickupAI.statusText)
                .font(AppTheme.TypeScale.body)
                .foregroundStyle(.secondary)

            Text("原始返回：\(rawReason)")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                guard !isChecking else { return }
                Task { await recheck() }
            } label: {
                HStack(spacing: 8) {
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppTheme.accent)
                    } else if justChecked {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(isChecking ? "检测中…" : (justChecked ? "已检测" : "重新检测"))
                        .font(AppTheme.TypeScale.bodyMedium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(AppTheme.accent.opacity(isChecking ? 0.20 : 0.13))
                )
                .foregroundStyle(AppTheme.accent)
                .scaleEffect(isChecking ? 0.98 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isChecking)
            .animation(.easeInOut(duration: 0.18), value: isChecking)
            .animation(.easeInOut(duration: 0.18), value: justChecked)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .opacity(isChecking ? 0.55 : 1)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.accent.opacity(justChecked ? 0.55 : 0), lineWidth: 1.5)
        }
        .animation(.easeInOut(duration: 0.22), value: isChecking)
        .animation(.easeOut(duration: 0.35), value: justChecked)
    }

    /// 真正"重新检测"：给一点可见的耗时，否则瞬间返回用户无法感知
    private func recheck() async {
        isChecking = true
        justChecked = false
        defer { isChecking = false }
        try? await Task.sleep(for: .milliseconds(700))
        refreshToken &+= 1
        logOnce()
        withAnimation(.easeOut(duration: 0.25)) { justChecked = true }
        try? await Task.sleep(for: .milliseconds(1200))
        withAnimation(.easeOut(duration: 0.3)) { justChecked = false }
    }

    // MARK: 设备信息

    private var detailCard: some View {
        VStack(spacing: 0) {
            row("机型", DeviceProfile.machineID)
            SettingsDivider()
            row("系统", ProcessInfo.processInfo.operatingSystemVersionString)
            SettingsDivider()
            row("地区", Locale.current.region?.identifier ?? "—")
            SettingsDivider()
            row("首选语言", Locale.preferredLanguages.prefix(2).joined(separator: ", "))
            SettingsDivider()
            row("支持中文", SystemLanguageModel.default.supportsLocale(Locale(identifier: "zh_CN")) ? "是" : "否")
            SettingsDivider()
            row("模型支持语言数", "\(SystemLanguageModel.default.supportedLanguages.count)")
        }
        .cardSurface()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(AppTheme.TypeScale.rowTitle)
            Spacer(minLength: 8)
            Text(value)
                .font(AppTheme.TypeScale.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: 说明

    private var explainCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("怎么看这个结果")
                .font(AppTheme.TypeScale.rowTitleMedium)
            Text("· **「需 iPhone 15 Pro 及以上」是官方最低要求，不是在说本机配置不够**；本机硬件满足，是系统层面没开放这个接口。\n· **写作工具能在任何 App 里用**，那是系统提供的能力，跟 App 自己调端侧模型是两条通道；它可用不代表这里可用。\n· 中国区机型由第三方模型提供服务，第三方 App 的端侧模型接口是否开放由系统决定，App 侧无法绕过、也无法伪造资格。\n· 不可用时拾码自动退回纯正则解析，收码与小组件功能不受影响。")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: 工具

    private var isAvailable: Bool {
        if case .available = availability { return true }
        return false
    }

    private var rawReason: String {
        switch availability {
        case .available:
            return "available"
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "deviceNotEligible（系统判定本机不符合条件）"
            case .appleIntelligenceNotEnabled: return "appleIntelligenceNotEnabled（未开启 Apple 智能）"
            case .modelNotReady: return "modelNotReady（模型未就绪，通常在后台下载）"
            @unknown default: return "未知原因"
            }
        }
    }

    /// 每次进页面记一条（只有设备与枚举，不含任何用户内容）
    private func logOnce() {
        DiagnosticsLog.record("aiCapability",
                              "machine=\(DeviceProfile.machineID) "
                              + "os=\(ProcessInfo.processInfo.operatingSystemVersionString) "
                              + "region=\(Locale.current.region?.identifier ?? "-") "
                              + "available=\(isAvailable) reason=\(rawReason)")
    }
}

// MARK: - 低版本占位（iOS 18）

/// 系统低于 iOS 26 时没有端侧模型框架，这一页只说明情况。
struct AICapabilityUnsupportedView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.seal.fill")
                        .foregroundStyle(AppTheme.pendingTint)
                    Text("本机系统版本不支持端侧模型")
                        .font(AppTheme.TypeScale.rowTitle)
                }

                Text("端侧模型（Apple 智能）需要 iOS 26 或更高版本。\n当前系统的拾码使用纯正则 + 系统分词解析，收码功能不受影响。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Apple 智能")
        .navigationBarTitleDisplayMode(.inline)
    }
}
