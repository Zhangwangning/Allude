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
                purposeCard
                // 🔴 2026-11-08 主人：国行用不了端侧接口，给个「去开启」按钮点了也没用。
                //    只在**系统确实有开关**（Apple 智能未开启）时才展示这一卡。
                // 🔴 2026-11-20 主人：原「可选：千问扩展」卡片删除 —— App 只留 Apple
                //    端侧能力，不引导、不提及任何第三方模型服务。
                if needsSystemEnable {
                    enableHintCard
                }
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 18)
            .padding(.bottom, 40)
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
                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppTheme.accent)
                } else {
                    Image(systemName: isAvailable ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isAvailable ? AppTheme.doneTint : AppTheme.pendingTint)
                }
                Text(isChecking ? "正在检测…" : (isAvailable ? "可以用" : "暂时用不了"))
                    .font(AppTheme.TypeScale.rowTitleMedium)
                Spacer(minLength: 0)
            }

            // 🔴 2026-11-08 主人：用户只关心「能不能用」，不关心枚举。
            Text(isChecking
                 ? "正在向系统查询本机是否可用…"
                 : (isAvailable
                    ? "Allude会用 iPhone 本机的智能来识别短信，不联网、不上传。"
                    : "这台 iPhone 目前没向Allude开放本机智能，Allude会自动改用正则解析，收码照样正常。"))
                .font(AppTheme.TypeScale.body)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
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
            .animation(AppMotion.quick, value: isChecking)
            .animation(AppMotion.quick, value: justChecked)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
        .opacity(isChecking ? 0.55 : 1)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.accent.opacity(justChecked ? 0.55 : 0), lineWidth: 1.5)
        }
        .animation(AppMotion.standard, value: isChecking)
        .animation(AppMotion.standard, value: justChecked)
    }

    /// 真正"重新检测"：给一点可见的耗时，否则瞬间返回用户无法感知
    private func recheck() async {
        isChecking = true
        justChecked = false
        defer { isChecking = false }
        try? await Task.sleep(for: .milliseconds(700))
        refreshToken &+= 1
        logOnce()
        withAnimation(AppMotion.standard) { justChecked = true }
        try? await Task.sleep(for: .milliseconds(1200))
        withAnimation(AppMotion.standard) { justChecked = false }
    }

    // MARK: 为什么有这个功能 / 系统开关提示

    private var purposeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("为什么有这个功能")
                .font(AppTheme.TypeScale.rowTitleMedium)

            bullet("shield.lefthalf.filled",
                   "Allude用 iPhone 自己的端侧智能辅助识别短信，**不联网、不上传**——数据一直在本机。")
            bullet("text.alignleft",
                   "识别主力是本机正则；端侧智能在旁边补齐、校对，结果更完整。系统没开放时只是少了这层辅助，收码照常。")
            bullet("questionmark.circle",
                   "能不能用由 iOS 决定，Allude没法绕过，也不会伪造。")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.sky)
                .frame(width: 18)
            Text(text.richText)
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var enableHintCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("怎么打开")
                .font(AppTheme.TypeScale.rowTitleMedium)

            Text("Apple 智能默认是关的，可以在 **设置 › Apple 智能与 Siri** 里打开。开不开这个开关由系统和你的账号地区决定，Allude 不代你判断，也不会为此联网。")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("前往系统设置")
                    .font(AppTheme.TypeScale.body.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .appGlass(.capsule, tint: AppTheme.accent, interactive: true)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    // MARK: 工具

    /// 系统明确表示「Apple 智能未开启」—— 这种才值得引导用户去设置里打开。
    /// 国行返回的是 `deviceNotEligible`（第三方接口没开放），引导也没用，不显示。
    private var needsSystemEnable: Bool {
        if case .unavailable(let reason) = availability,
           case .appleIntelligenceNotEnabled = reason {
            return true
        }
        return false
    }

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

                Text("端侧模型（Apple 智能）需要 iOS 26 或更高版本。\n当前系统的Allude使用纯正则 + 系统分词解析，收码功能不受影响。")
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
