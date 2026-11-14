import SwiftUI

// MARK: ============================================================================
// 设置 › Apple 智能与扩展（2026-11-13 主人要求）
//
// 这一页把「智能识别」拆成两条独立通道，用户自己决定用不用：
//
//   1) **Apple 智能**：系统端侧模型，数据不出设备（原「AI 能力检测」页）；
//   2) **扩展**：用户自己的 API Key 接入 DeepSeek / 豆包 / 千问，
//      由**本机直连**服务商官方接口，用作短信解析的功能增强。
//
// 🔴 权限归用户：默认全部关闭；关着时不发起任何请求；
//    Key 只存本机 Keychain，不上传、不同步、不进日志。
// ============================================================================

/// 二级页：Apple 智能 + 扩展 两个入口。
struct AIExtensionsHomeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 主人 2026-11-14：功能入口在上、标题不带解释，说明统一挪到下面。
                VStack(spacing: 0) {
                    NavigationLink {
                        appleIntelligenceDestination
                    } label: {
                        SettingsRow(symbol: "brain.head.profile",
                                    title: "Apple 智能",
                                    showsChevron: true,
                                    tint: AppTheme.violet)
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    NavigationLink {
                        AIExtensionsListView()
                    } label: {
                        SettingsRow(symbol: "puzzlepiece.extension.fill",
                                    title: "扩展",
                                    showsChevron: true,
                                    tint: AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .settingsCard()

                Text("「Apple 智能」用系统端侧模型，数据不出设备；「扩展」用你自己的 API Key 直连 DeepSeek / 豆包 / 千问。两条可以单独开关，扩展是可选的——不开也能正常收码。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Apple 智能与扩展")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var appleIntelligenceDestination: some View {
        if #available(iOS 26.0, *) {
            AICapabilityView()
        } else {
            AICapabilityUnsupportedView()
        }
    }
}

/// 二级页：三家模型服务列表。
struct AIExtensionsListView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 0) {
                    ForEach(Array(AIProvider.allCases.enumerated()), id: \.element.id) { index, provider in
                        if index > 0 { SettingsDivider() }
                        NavigationLink {
                            AIProviderDetailView(provider: provider)
                        } label: {
                            SettingsRow(symbol: provider.symbol,
                                        imageAsset: provider.iconAsset,
                                        title: provider.title,
                                        detail: AIProviderSettings.isReady(provider) ? "已接入" : "未接入",
                                        showsChevron: true,
                                        tint: provider.tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .settingsCard()

                privacyCard

                Text("接口地址固定为各家官方端点，只填你自己的 API Key；四家可以只开一家。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("扩展")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关于数据")
                .font(AppTheme.TypeScale.rowTitleMedium)

            Text("""
            · 开启后，需要增强的那条短信原文会由这台设备**直接发送**给你选择的服务商处理；
            · Allude 没有服务器，不经手、不中转、也不记录这些内容；
            · API Key 只保存在本机 Keychain，不上传、不同步、不写日志；
            · 关掉开关后，App 不会向任何模型发起请求。
            """)
            .font(AppTheme.TypeScale.note)
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.violet.opacity(0.08), in: .rect(cornerRadius: 14, style: .continuous))
    }
}

/// 二级页：单家服务商的接入配置。
struct AIProviderDetailView: View {
    let provider: AIProvider

    @State private var enabled = false
    @State private var apiKey = ""
    @State private var model = ""
    @State private var isKeyVisible = false
    @State private var savedHint = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                enableCard
                credentialCard
                actionCard
                explainCard
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(provider.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private var enableCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("启用这家模型")
                        .font(AppTheme.TypeScale.rowTitle)
                    Text(enabled ? "解析时会用 \(provider.title) 增强" : "关闭时不向 \(provider.title) 发任何请求")
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .settingsCard()
        .onChange(of: enabled) { _, on in
            AIProviderSettings.setEnabled(on, for: provider)
        }
    }

    private var credentialCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("接入凭证")
                .font(AppTheme.TypeScale.section)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if isKeyVisible {
                        TextField(provider.keyHint, text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 15, design: .monospaced))
                    } else {
                        SecureField(provider.keyHint, text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 15, design: .monospaced))
                    }
                    Button {
                        isKeyVisible.toggle()
                    } label: {
                        Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isKeyVisible ? "隐藏 Key" : "显示 Key")
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("模型 / 接入点")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                TextField(provider.modelFieldHint, text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 15, design: .monospaced))
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10, style: .continuous))
            }

            Text("接口地址（内置，不可改）：\(provider.endpoint)")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    private var actionCard: some View {
        VStack(spacing: 10) {
            Button(action: save) {
                Text(savedHint ? "已保存" : "保存")
                    .font(AppTheme.TypeScale.rowTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.accent.opacity(0.16), in: Capsule())
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)

            if AIProviderKeychain.key(for: provider) != nil {
                Button(role: .destructive) {
                    AIProviderKeychain.delete(for: provider)
                    apiKey = ""
                    enabled = false
                    AIProviderSettings.setEnabled(false, for: provider)
                    savedHint = true
                } label: {
                    Text("清除这个 Key")
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var explainCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("说明")
                .font(AppTheme.TypeScale.rowTitleMedium)
            Text("""
            · Key 只存这台设备的 Keychain，不随 iCloud 同步、不会写进诊断日志；
            · 请求由本机直连 \(provider.company) 的官方接口，不经过开发者服务器；
            · 用法与额度受你自己的账号限制，扣费也在服务商那边；
            · 端侧「Apple 智能」与这里是两条独立通道，可以只开一条。
            """)
            .font(AppTheme.TypeScale.note)
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    private func load() {
        enabled = AIProviderSettings.isEnabled(provider)
        apiKey = AIProviderKeychain.key(for: provider) ?? ""
        model = AIProviderSettings.model(provider)
    }

    private func save() {
        AIProviderKeychain.save(apiKey, for: provider)
        AIProviderSettings.setModel(model.trimmingCharacters(in: .whitespacesAndNewlines), for: provider)
        savedHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { savedHint = false }
    }
}
