import SwiftUI

// MARK: ============================================================================
// 激活（2026-10-31 主人要求恢复）
//
// 背景：App 目前还没上架 App Store，买断靠的是**离线签名凭证**。
// 之前为了规避审核风险（3.1.1 不允许用 license key 绕过 IAP）把入口删了，
// 现在主人明确要求在设置里做一页：设备 UUID（打码显示、可复制）+ 凭证输入框。
//
// ⚠️ 上架前这个入口必须处理掉（改内购或隐藏），`AGENTS.md` 里已记这条待办。
// ============================================================================

struct ActivationView: View {
    @EnvironmentObject private var store: PickupStore
    @StateObject private var model = ActivationModel()

    private var deviceCode: String { LicenseDevice.current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                deviceSection
                voucherSection
                statusSection
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: AppTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("激活")
        .navigationBarTitleDisplayMode(.inline)
        // 截图脚手架：命令行点不了输入框，`ACTIVATE_VOUCHER=<凭证>` 时
        // 直接走一遍真实激活流程（验签 → 写快照 → 刷新权益），用来验收。
        .onAppear {
            guard let voucher = ProcessInfo.processInfo.environment["ACTIVATE_VOUCHER"],
                  !voucher.isEmpty, model.voucher.isEmpty else { return }
            model.voucher = voucher
            activate()
        }
    }

    // MARK: 设备码

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "设备 UUID")

            VStack(alignment: .leading, spacing: 12) {
                // 打码显示（2026-10-31 主人：UUID 加密显示）。
                // 首尾各 8 位保留、中间遮住 —— 截图或录屏时不会把整串摊出去，
                // 但用户一眼能核对是不是同一台机器。
                Text(LicenseDevice.masked(deviceCode))
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    Button {
                        copyDeviceCode()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: model.copiedDevice ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                            Text(model.copiedDevice ? "已复制" : "复制")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(model.copiedDevice ? AppTheme.doneTint : AppTheme.accent)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    Text("复制的是完整值，界面只显示部分")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()

            Text("把设备 UUID 发给卖家换取签名凭证。它只存在本机，不上传。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 凭证

    private var voucherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "签名凭证")

            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    if model.voucher.isEmpty {
                        Text("粘贴凭证，形如 CLIP1.…")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $model.voucher)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 96)
                        .scrollContentBackground(.hidden)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Button {
                    activate()
                } label: {
                    Text("激活")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(model.canActivate ? AppTheme.accent : Color(.tertiarySystemFill),
                                    in: .capsule)
                        .foregroundStyle(model.canActivate ? .white : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!model.canActivate)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    // MARK: 状态与结果

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "当前状态")

            VStack(spacing: 0) {
                SettingsPlainRow(title: "完整版") {
                    Text(store.isPro ? "已解锁" : "未解锁")
                        .font(.system(size: 17))
                        .foregroundStyle(store.isPro ? AppTheme.doneTint : .secondary)
                        .fixedSize()
                }

                SettingsDivider()

                // 2026-10-31 主人：凭证有 7 天 / 30 天 / 180 天 / 一年 / 永久五档，
                // 所以这里必须能看出"还剩多久"，只写"已解锁"用户不知道什么时候到期。
                SettingsPlainRow(title: "有效期") {
                    Text(validityText)
                        .font(.system(size: 15))
                        .foregroundStyle(validityIsUrgent ? AppTheme.pendingTint : .secondary)
                        .fixedSize()
                }
            }
            .cardSurface()

            if let result = model.result {
                Text(result)
                    .font(.system(size: 13))
                    .foregroundStyle(model.isError ? AppTheme.todayTint : AppTheme.doneTint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }
        }
    }

    // MARK: 有效期文案

    /// 当前权益的到期描述。永久 → 「永久」；限时 → 「2026-11-30 · 剩余 3 天」。
    private var validityText: String {
        guard store.isPro else { return "—" }
        guard let expiry = EntitlementSnapshot.load().expiresAt else { return "永久" }
        let days = remainingDays(until: expiry)
        let date = expiry.formatted(.dateTime.year().month().day())
        return days > 0 ? "\(date) · 剩余 \(days) 天" : "\(date) · 今天到期"
    }

    /// 剩余不到 7 天时标红，提醒续期。
    private var validityIsUrgent: Bool {
        guard store.isPro, let expiry = EntitlementSnapshot.load().expiresAt else { return false }
        return remainingDays(until: expiry) <= 7
    }

    private func remainingDays(until date: Date) -> Int {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: Date())
        let to = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    // MARK: 动作

    private func copyDeviceCode() {
        UIPasteboard.general.string = deviceCode
        withAnimation(.snappy(duration: 0.2)) { model.copiedDevice = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.snappy(duration: 0.2)) { model.copiedDevice = false }
        }
    }

    private func activate() {
        let raw = model.voucher
        switch LicenseActivation.activate(raw) {
        case .success(let payload):
            // 🔴 导入成功后必须重算一次，否则界面还停在免费档
            store.refreshEntitlement()

            let success: String
            if let expiry = payload.expiresAt {
                let days = remainingDays(until: expiry)
                let date = expiry.formatted(.dateTime.year().month().day())
                success = days > 0
                    ? "已激活 · 剩余 \(days) 天（\(date) 到期）"
                    : "已激活 · 今天到期（\(date)）"
            } else {
                success = "已激活 · 永久有效"
            }
            withAnimation {
                model.isError = false
                model.result = success
                model.voucher = ""
            }

        case .failure(let error):
            withAnimation {
                model.isError = true
                model.result = error.message
            }
        }
    }
}

@MainActor
final class ActivationModel: ObservableObject {
    @Published var voucher = ""
    @Published var copiedDevice = false
    @Published var result: String?
    @Published var isError = false

    var canActivate: Bool {
        !voucher.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
