import SwiftUI

// MARK: ============================================================================
// 设置 › Apple 智能与扩展（2026-11-13 主人要求）
//
// 这一页把「智能识别」拆成两条独立通道，用户自己决定用不用：
//
//   1) **Apple 智能**：系统端侧模型，数据不出设备（原「AI 能力检测」页）；
//   2) **扩展**：用户自己的 API Key 接入 DeepSeek / 豆包 / 千问 / Kimi，
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

                Text("「Apple 智能」用系统端侧模型，数据不出设备；「扩展」用你自己的 API Key 直连第三方模型，把短信和本机解析结果一起复核。两条可以单独开关，扩展是可选的——不开也能正常收码。")
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
    /// 列表里的「已接入 / 未接入」是**读 Keychain + App Group 开关**算出来的，
    /// SwiftUI 观察不到这两个存储，所以从详情页返回时必须自己重算一次
    /// （2026-11-14 主人反馈：开了 DeepSeek 回来仍显示未接入）。
    @State private var ready: Set<AIProvider> = []
    @Environment(\.scenePhase) private var scenePhase

    private func refreshReady() {
        ready = Set(AIProvider.allCases.filter { AIProviderSettings.isReady($0) })
    }

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
                                        detail: ready.contains(provider) ? "已接入" : "未接入",
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
        .onAppear { refreshReady() }
        .onChange(of: scenePhase) { _, _ in refreshReady() }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关于数据")
                .font(AppTheme.TypeScale.rowTitleMedium)

            Text("Allude 本身不联网：取件记录只存在这台设备上。只有你主动开启并触发了增强，那条短信原文才会由这台设备直接发给你选的服务商，连同本机正则解析出的字段一起交给模型复核，用来把取件码、地址、柜位这些信息认得更准——内容不经过我们，我们也看不到、存不到。API Key 只放本机 Keychain，不上传、不同步、不写日志；关掉开关后，App 不会向任何模型发起请求。")
            .font(AppTheme.TypeScale.note)
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14, style: .continuous))
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
    @State private var testState: TestState = .idle
    @State private var showModelSheet = false

    private enum TestState: Equatable {
        case idle, running, ok, failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
        .onAppear {
            load()
            #if DEBUG
            if ProcessInfo.processInfo.environment["MODEL_SHEET"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showModelSheet = true }
            }
            #endif
        }
        
    }

    /// 模型选择：勾选标记放行尾（系统 Menu 的 inline picker 会把勾放左侧，主人要求右对齐）。
    private var modelPanel: some View {
        VStack(spacing: 0) {
            ForEach(modelChoices, id: \.self) { name in
                Button {
                    model = name
                    showModelSheet = false
                } label: {
                    HStack(spacing: 12) {
                        Text(name)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 20)

                        if name == model {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(.systemBlue))
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(width: 250, height: 42)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private var enableCard: some View {
        Toggle(isOn: $enabled) {
            Text("启用这家模型")
                .font(AppTheme.TypeScale.rowTitle)
        }
        .padding(16)
        .settingsCard()
        .onChange(of: enabled) { _, on in
            AIProviderSettings.setEnabled(on, for: provider)
        }
    }

    // MARK: 凭证

    private var credentialCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("API Key")
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("从剪贴板粘贴") {
                        if let text = UIPasteboard.general.string { apiKey = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    .font(AppTheme.TypeScale.note)
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)
                }

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

                if !apiKey.isEmpty {
                    Text("已保存在本机 Keychain；默认打码，点右侧眼睛可查看。")
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("模型")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
                Button {
                    showModelSheet = true
                } label: {
                    HStack {
                        Text(model)
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showModelSheet, arrowEdge: .top) {
                    modelPanel
                        .presentationCompactAdaptation(.popover)
                }


            }

            if let url = provider.consoleURL {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                        Text("去 \(provider.company) 开放平台创建 Key")
                        Spacer()
                    }
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    /// 预设模型 + 当前已存值（豆包可能是 ep-xxx 这类接入点 ID，不能从列表里丢）。
    private var modelChoices: [String] {
        var names = provider.models
        let saved = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !saved.isEmpty && !names.contains(saved) { names.insert(saved, at: 0) }
        return names
    }

    // MARK: 操作

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: save) {
                Text(savedHint ? "已保存" : "保存")
                    .font(AppTheme.TypeScale.rowTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppTheme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            VStack(spacing: 0) {
                Button(action: runTest) {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.horizontal.circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppTheme.accent)
                        Text("测试连接")
                            .font(AppTheme.TypeScale.rowTitle)
                            .foregroundStyle(.primary)
                        Spacer()
                        HStack(spacing: 6) {
                            if testState == .running { ProgressView().controlSize(.small) }
                            Text(testStatusText)
                                .font(AppTheme.TypeScale.note)
                                .foregroundStyle(testState == .ok ? .green : .secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .disabled(testState == .running)

                if case .failed(let message) = testState {
                    Text(message)
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if AIProviderKeychain.key(for: provider) != nil {
                    SettingsDivider()
                    Button(role: .destructive) {
                        AIProviderKeychain.delete(for: provider)
                        apiKey = ""
                        enabled = false
                        AIProviderSettings.setEnabled(false, for: provider)
                        savedHint = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .medium))
                            Text("清除这台设备上的 Key")
                                .font(AppTheme.TypeScale.rowTitle)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .settingsCard()
        }
    }

    private var testStatusText: String {
        switch testState {
        case .idle: return ""
        case .running: return "正在测试"
        case .ok: return "正常"
        case .failed: return "失败"
        }
    }

    private var testButtonTitle: String {
        switch testState {
        case .idle: return "测试连接"
        case .running: return "正在测试…"
        case .ok: return "连接正常"
        case .failed: return "重试连接"
        }
    }

    private var explainCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("说明")
                .font(AppTheme.TypeScale.rowTitleMedium)
            Text("""
            · Key 只存这台设备的 Keychain，不随 iCloud 同步、不写进诊断日志；
            · 只用官方接口，地址内置不可改；请求由本机直连，不经过开发者服务器；
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

    // MARK: 读写

    private func load() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MODEL_SHEET"] == "1" { showModelSheet = true }
        #endif
        enabled = AIProviderSettings.isEnabled(provider)
        apiKey = AIProviderKeychain.key(for: provider) ?? ""
        model = AIProviderSettings.model(provider)
    }

    private func save() {
        AIProviderKeychain.save(apiKey, for: provider)
        AIProviderSettings.setModel(model.trimmingCharacters(in: .whitespacesAndNewlines), for: provider)
        testState = .idle
        savedHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { savedHint = false }
    }

    private func runTest() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            testState = .failed("先填 API Key")
            return
        }
        testState = .running
        let target = provider.endpoint
        let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.defaultModel : model
        Task {
            let result = await Self.probe(endpoint: target, model: modelName, key: key)
            await MainActor.run {
                switch result {
                case .success: testState = .ok
                case .failure(let error): testState = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// 发一次最小请求，只为判断「地址通不通、Key 认不认、模型名对不对」。
    private static func probe(endpoint: String, model: String, key: String) async -> Result<Void, Error> {
        guard let url = URL(string: endpoint) else {
            return .failure(ProbeError("接口地址不合法"))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8,
            "messages": [["role": "user", "content": "ping"]]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                return .failure(ProbeError("没有收到 HTTP 响应"))
            }
            if (200..<300).contains(http.statusCode) { return .success(()) }
            if http.statusCode == 401 || http.statusCode == 403 { return .failure(ProbeError("HTTP \(http.statusCode)：Key 无效或没有权限")) }
            if http.statusCode == 404 { return .failure(ProbeError("HTTP 404：地址或模型名不对")) }
            if http.statusCode == 429 { return .failure(ProbeError("HTTP 429：额度用尽或被限流")) }
            let text = String(data: data, encoding: .utf8) ?? ""
            let brief = text.count > 120 ? String(text.prefix(120)) + "…" : text
            return .failure(ProbeError("HTTP \(http.statusCode)：\(brief)"))
        } catch {
            return .failure(ProbeError("连不上：\(error.localizedDescription)"))
        }
    }

    private struct ProbeError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
