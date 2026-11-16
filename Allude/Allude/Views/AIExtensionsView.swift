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

/// 二级页内部的路由（2026-11-14：分栏里 `NavigationLink(destination:)` 偶发不落地，
/// 改成 value-based push，目标注册在同一个栈上，稳定得多）。
enum AIHubRoute: Hashable, Identifiable {
    var id: Self { self }

    case appleIntelligence
    case extensions
}

/// 🔴 路由 → 视图的映射，**由外层的栈根注册**，不放在页面内部。
///
/// 2026-11-16 实测记录：把 `navigationDestination` 写在 `AIExtensionsHomeView` 里
/// （哪怕是 `item:` / `isPresented:` 形式）在 Duo 内屏**横屏分栏**下完全不落地 ——
/// 日志能证明 push 已被调用，界面纹丝不动。原因是这个页面处在
/// `paneContent(pane)` 的 `_ConditionalContent` 分支内部，注册会随分支丢失。
/// 修法：改成 value-based push，把 `navigationDestination(for:)` 挂在两个栈的
/// **根内容**上（分栏右栏栈、单列 `SettingsTabRoot` 栈各注册一次）。
struct AIHubDestination: View {
    let route: AIHubRoute

    var body: some View {
        switch route {
        case .appleIntelligence:
            if #available(iOS 26.0, *) {
                AICapabilityView()
            } else {
                AICapabilityUnsupportedView()
            }
        case .extensions:
            AIExtensionsListView()
        }
    }
}


/// 二级页：Apple 智能 + 扩展 两个入口。
///
/// 2026-11-15：改成**纯 value-based push**，目标注册在本页自己身上。
/// 之前两种写法都踩过坑：分栏里 `NavigationLink(destination:)` 会被吞；
/// 单栈里靠外部注入的闭包 append（外部没注入时就等于点了没反应）。
/// `navigationDestination` 注册在被 push 的页面上，SwiftUI 会挂到**外层同一个栈**，
/// 所以 iPhone 单栈与分栏详情栈都能正常 push，不需要任何外部回调。
struct AIExtensionsHomeView: View {
    /// 🔴 分栏右栏用：「把右侧切到指定面板」。
    ///
    /// 竖屏 / 外屏 / 直板机传 nil，走正常的 `NavigationLink` push；
    /// Duo 内屏**横屏**（分栏）必须传回调 —— 那里 push 不落地：
    /// 右栏的根内容是 `paneContent(pane)`，左侧换选中项时整棵树会被替换，
    /// 往这种"随时会被换掉"的容器里再推一层，系统会把推入当无效操作丢掉
    /// （日志能证明 push 被调用、界面纹丝不动）。
    /// 这与「外观与个性化 / 关于 Allude」用的是同一套做法。
    var openPane: ((SettingsPane) -> Void)? = nil

    @ViewBuilder
    private func hubRow(_ route: AIHubRoute, symbol: String, title: String, tint: Color) -> some View {
        let row = SettingsRow(symbol: symbol, title: title, showsChevron: true, tint: tint)
            .contentShape(.rect)

        if let openPane {
            // 分栏：切右栏（push 在那种容器里不落地）
            Button {
                openPane(route == .appleIntelligence ? .aiAppleIntelligence : .aiExtensions)
            } label: {
                row
            }
            .buttonStyle(.plain)
        } else {
            // 单列：**必须用 destination 型**。历史记录（2026-11-15）明确写过：
            // 外层是 destination push 进来的页面，内层再做 value-based push 不落地。
            // 所以这里千万不要改成 `NavigationLink(value:)`。
            NavigationLink {
                AIHubDestination(route: route)
            } label: {
                row
            }
            .buttonStyle(.plain)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 主人 2026-11-14：功能入口在上、标题不带解释，说明统一挪到下面。
                VStack(spacing: 0) {
                    hubRow(.appleIntelligence,
                           symbol: "brain.head.profile",
                           title: "Apple 智能",
                           tint: AppTheme.violet)

                    SettingsDivider()

                    hubRow(.extensions,
                           symbol: "puzzlepiece.extension.fill",
                           title: "扩展",
                           tint: AppTheme.accent)
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

    /// 分栏右栏用：把右侧切到指定面板（那里 push 不落地，理由见 `AIExtensionsHomeView`）。
    var openPane: ((SettingsPane) -> Void)? = nil

    /// 分栏态下点某家服务商：**在这页内部换成详情**，不走 push。
    /// 单列态恒为 nil，走正常的 `NavigationLink`。
    @State private var inlineProvider: AIProvider?

    private func refreshReady() {
        ready = Set(AIProvider.allCases.filter { AIProviderSettings.isReady($0) })
    }

    var body: some View {
        Group {
            // `inlineProvider` 只会在分栏态（`openPane != nil`）的行按钮里被赋值，
            // 所以这里只需判它，不用再判一次 openPane。
            if let provider = inlineProvider {
                AIProviderDetailView(provider: provider)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { inlineProvider = nil } label: {
                                Label("返回", systemImage: "chevron.backward")
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                    }
            } else {
                listBody
            }
        }
    }

    private var listBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 0) {
                    ForEach(Array(AIProvider.allCases.enumerated()), id: \.element.id) { index, provider in
                        if index > 0 { SettingsDivider() }
                        if openPane != nil {
                            Button { inlineProvider = provider } label: {
                                SettingsRow(symbol: provider.symbol,
                                            imageAsset: provider.iconAsset,
                                            title: provider.title,
                                            detail: ready.contains(provider) ? "已接入" : "未接入",
                                            showsChevron: true,
                                            tint: provider.tint)
                            }
                            .buttonStyle(.plain)
                        } else {
                            // 单列：destination 型（理由见 `hubRow` 里的注释）
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
                }
                .settingsCard()

                VStack(spacing: 0) {
                    if let openPane {
                        Button { openPane(.aiUsage) } label: {
                            SettingsRow(symbol: "chart.bar.xaxis",
                                        title: "用量统计",
                                        detail: AIUsageStore.costText(AIUsageStore.allTotals.costCNY),
                                        showsChevron: true,
                                        tint: AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            AIUsageView()
                        } label: {
                            SettingsRow(symbol: "chart.bar.xaxis",
                                        title: "用量统计",
                                        detail: AIUsageStore.costText(AIUsageStore.allTotals.costCNY),
                                        showsChevron: true,
                                        tint: AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .settingsCard()

                privacyCard
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

            Text("Allude 本身不联网：取件记录只存在这台设备上。只有你主动开启并触发了增强，那条短信原文才会由这台设备直接发给你选的服务商，连同本机正则解析出的字段一起交给模型复核，用来把取件码、地址、柜位这些信息认得更准——内容不经过我们，我们也看不到、存不到。API Key 只放本机 Keychain，不上传、不同步、不写日志；关掉开关后，App 不会向任何模型发起请求。\n\n接口只用各家官方端点，地址内置、不可改；请求由这台设备直连，不经开发者服务器。端侧的「Apple 智能」和这里是两条独立通道，可以只开一条。")
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
                // 版式照 Apple 的「Apple 智能与 Siri › 扩展」页（2026-11-14 主人指定）：
                // 最上面是「使用 X」开关 → 一段说明 → 账户（这里的账户就是 API Key）→ 确认请求 → 隐私链接。
                enableCard

                Text("Allude 可以用 \(provider.title) 复核短信里的取件信息，把取件码、地址、柜位认得更准。")
                    .font(AppTheme.TypeScale.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)

                SectionHeader(title: "API Key")
                credentialCard

                VStack(spacing: 0) {
                    NavigationLink {
                        LegalDocumentView(document: .privacy)
                    } label: {
                        HStack(spacing: 8) {
                            Text("关于 \(provider.title) 扩展与隐私…")
                                .font(AppTheme.TypeScale.note)
                                .foregroundStyle(AppTheme.accent)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

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
            Text("使用 \(provider.title)")
                .font(AppTheme.TypeScale.rowTitle)
        }
        .disabled(!canEnable)
        .padding(16)
        .settingsCard()
        .onChange(of: enabled) { _, on in
            AIProviderSettings.setEnabled(on, for: provider)
        }
    }

    /// 已开启的保持可关；没验证过的，不许打开（2026-11-14 主人：没测通就启用等于没用）。
    private var canEnable: Bool {
        enabled || AIProviderSettings.isVerified(provider)
    }

    // MARK: 凭证

    private var credentialCard: some View {
        VStack(spacing: 0) {
            // ① API Key
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Spacer()
                    Button("从剪贴板粘贴") {
                        if let text = UIPasteboard.general.string {
                            apiKey = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .font(AppTheme.TypeScale.rowSubtitle)
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)
                }

                HStack(spacing: 8) {
                    Group {
                        if isKeyVisible {
                            TextField(provider.keyHint, text: $apiKey)
                        } else {
                            SecureField(provider.keyHint, text: $apiKey)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 15, design: .monospaced))

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
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10, style: .continuous))

            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            SettingsDivider()

            // ② 模型
            Button {
                showModelSheet = true
            } label: {
                HStack(spacing: 10) {
                    Text("模型")
                        .font(AppTheme.TypeScale.rowTitle)
                    Spacer()
                    Text(model)
                        .font(.system(size: 17, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showModelSheet, arrowEdge: .top) {
                modelPanel.presentationCompactAdaptation(.popover)
            }

            if let url = provider.consoleURL {
                SettingsDivider()
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Text("去 \(provider.company) 开放平台创建 Key")
                            .font(AppTheme.TypeScale.note)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
            }

            SettingsDivider()

            // ③ 动作（系统设置式行内动作，不做大按钮）
            Button(action: save) {
                actionRow(title: savedHint ? "已保存" : "保存", tint: AppTheme.accent)
            }
            .buttonStyle(.plain)

            SettingsDivider()

            Button(action: runTest) {
                HStack(spacing: 8) {
                    Text("测试连接")
                        .font(AppTheme.TypeScale.rowTitle)
                        .foregroundStyle(AppTheme.accent)
                    Spacer()
                    if testState == .running { ProgressView().controlSize(.small) }
                    Text(testStatusText)
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(testState == .ok ? .green : .secondary)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .contentShape(Rectangle())
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
                    AIProviderSettings.setVerified(false, for: provider)
                    savedHint = true
                } label: {
                    actionRow(title: "清除此配置", tint: .red)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    /// 行内动作行：左标题、右侧留给状态；高度与系统设置一致。
    private func actionRow(title: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(AppTheme.TypeScale.rowTitle)
                .foregroundStyle(tint)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .contentShape(Rectangle())
    }

    /// 预设模型 + 当前已存值（豆包可能是 ep-xxx 这类接入点 ID，不能从列表里丢）。
    private var modelChoices: [String] {
        var names = provider.models
        let saved = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !saved.isEmpty && !names.contains(saved) { names.insert(saved, at: 0) }
        return names
    }

    // MARK: 操作

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
                case .success:
                    testState = .ok
                    AIProviderSettings.setVerified(true, for: provider)
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
