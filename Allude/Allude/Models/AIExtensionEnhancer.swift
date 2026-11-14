import Foundation

// MARK: ============================================================================
// 第三方模型扩展（BYOK）—— 只用来**补空**的解析增强（2026-11-13）
//
// 主人原话：「…这3个用户可以通过API去接入，接入完了之后，用来对短信内容解析，
// 相当于是一个功能性增强。这个接入的时候，这个权限要给用户，我们的APP不进行
// 任何的数据处理，AI方面的保证，APP不参与网络请求」。
//
// 因此这一层的边界写死：
//   1. **默认关闭**：`AIProviderSettings.anyReadyProvider == nil` 时，一行代码都不会发请求；
//   2. **只补空、不改已有值**：正则解析出来的码/公司/地址一旦非空，模型结果一律丢掉
//      （取件码永远用正则值 —— 模型改一次码就是把别人的件标成已取）；
//   3. **本机直连**：URLSession 直接请求服务商官方接口，不经过开发者服务器，
//      也不写诊断日志（日志只记「发生了增强」这种事实，不记短信原文）。
//
// 这与 App 内的端侧「Apple 智能」是两个独立通道（见 `PickupAI.swift`）：
// 端侧不可用时用户仍可自备 Key 接入第三方模型，两者都关就退回纯正则。
// ============================================================================

/// 模型返回的字段（全部 optional：模型缺字段时按「没有」处理，不要给默认值）。
struct AIExtensionFields: Decodable {
    var code: String?
    var courier: String?
    var station: String?
    var address: String?
    var locker: String?
    var shelf: String?
}

enum AIExtensionEnhancer {

    /// 专门给增强用的 session：**请求 8 秒、整条 12 秒**就断。
    /// 默认 session 的 60 秒会让"网络一抖"变成"等一分钟"，这里必须短。
    /// `waitsForConnectivity = false`：没网就别排队等，直接失败退回正则。
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()

    /// 一条记录要不要请第三方模型帮忙（与端侧保持同一套判断）。
    ///
    /// 只在这几种「正则明显缺东西」的情况下发起请求，避免每条短信都调用一次：
    ///   · 取件地址空 —— 卡片与导航都要用，最值得补；
    ///   · 柜位/货架都空、但原文提到「柜 / 架」—— 说明位置信息漏了。
    static func needsHelp(_ record: PickupRecord) -> Bool {
        if record.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        let locker = record.locker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shelf = record.shelf?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if locker.isEmpty && shelf.isEmpty,
           record.rawMessage.contains("柜") || record.rawMessage.contains("架") {
            return true
        }
        return false
    }

    /// 新入库的记录排一轮后台补全（由 `commitAll` 调用）。
    ///
    /// 🔴 只有用户**同时**满足「打开了开关」+「本机存了 Key」才会走到这里；
    /// 否则直接 return，连 URLSession 都不创建。
    static func schedule(_ records: [PickupRecord]) {
        guard let provider = AIProviderSettings.anyReadyProvider,
              let key = AIProviderKeychain.key(for: provider) else { return }

        let model = AIProviderSettings.model(provider)
        let targets = records.filter(needsHelp)
        guard !targets.isEmpty else { return }

        DiagnosticsLog.record("ai-extension", "provider=\(provider.rawValue) targets=\(targets.count)")

        Task.detached(priority: .utility) {
            await run(targets, provider: provider, key: key, model: model)
        }
    }

    /// 并发上限 2：网络抖动时不至于同时挂十几条请求互相拖慢。
    /// 每条最多试 2 次（首次 + 一次重试），失败就放弃 —— 正则结果已经在界面上，
    /// 增强只是"有空就补一句"，绝不阻塞入库。
    private static func run(_ targets: [PickupRecord],
                            provider: AIProvider,
                            key: String,
                            model: String) async {
        await withTaskGroup(of: Void.self) { group in
            var iterator = targets.makeIterator()
            let limit = min(2, targets.count)

            func addNext() {
                guard let record = iterator.next() else { return }
                let id = record.id
                let text = record.rawMessage
                group.addTask {
                    for attempt in 1...2 {
                        if let fields = await request(text: text, provider: provider, key: key, model: model) {
                            await MainActor.run { apply(fields, to: id) }
                            return
                        }
                        if attempt < 2 { try? await Task.sleep(nanoseconds: 600_000_000) }
                    }
                    DiagnosticsLog.record("ai-extension", "gave_up code_kept=regex")
                }
            }

            for _ in 0..<limit { addNext() }
            while await group.next() != nil { addNext() }
        }
    }

    // MARK: 请求

    private static func request(text: String,
                                provider: AIProvider,
                                key: String,
                                model: String) async -> AIExtensionFields? {
        guard let url = URL(string: provider.endpoint) else { return nil }

        let instruction = """
        你是快递短信解析助手。从用户给的一条短信里抽取取件信息，只输出一个 JSON 对象，不要解释、不要 markdown。

        JSON 字段（没有就给空字符串）：
        - code：取件码（顾客报给店员或柜机上输入的那串字符，原样抄，不要加空格；没有就空）
        - courier：快递公司，如「圆通快递」「顺丰速运」（没有就空）
        - station：取件地点品牌，如「菜鸟驿站」「丰巢」「兔喜生活」「妈妈驿站」（没有就空）
        - address：取件地址（站点/柜机的完整地点描述，不要重复公司名；没有就空）
        - locker：快递柜格口，如「2号柜」「12-34格口」（没有就空）
        - shelf：货架号，如「A-12」（没有就空）
        """

        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": instruction],
                ["role": "user", "content": text]
            ],
            "response_format": ["type": "json_object"]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = data

        do {
            let (responseData, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                DiagnosticsLog.record("ai-extension", "http_error provider=\(provider.rawValue)")
                return nil
            }
            return decode(responseData)
        } catch {
            // 不记 error 详情（可能含 URL 查询），只记「失败了」。
            DiagnosticsLog.record("ai-extension", "request_failed provider=\(provider.rawValue)")
            return nil
        }
    }

    /// 从 OpenAI 兼容响应里取出 `choices[0].message.content`，再解成字段。
    private static func decode(_ data: Data) -> AIExtensionFields? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String,
            let contentData = content.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(AIExtensionFields.self, from: contentData)
    }

    // MARK: 合并

    /// 合并字段：**只填空，不覆盖**（与端侧 `PickupAIEnhancer.apply` 同一口径）。
    @MainActor
    static func apply(_ fields: AIExtensionFields, to id: UUID) {
        let store = PickupStore.shared
        guard let index = store.records.firstIndex(where: { $0.id == id }) else { return }
        var record = store.records[index]
        var changed = false

        func clean(_ raw: String?) -> String {
            (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let aiAddress = clean(fields.address)
        if record.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !aiAddress.isEmpty {
            record.address = aiAddress
            changed = true
        }

        let aiCourier = clean(fields.courier)
        if (record.courier ?? "").isEmpty, !aiCourier.isEmpty {
            record.courier = CourierBrand.canonicalName(for: aiCourier)
            changed = true
        }

        let aiLocker = clean(fields.locker)
        if (record.locker ?? "").isEmpty, !aiLocker.isEmpty {
            record.locker = aiLocker
            changed = true
        }

        let aiShelf = clean(fields.shelf)
        if (record.shelf ?? "").isEmpty, !aiShelf.isEmpty {
            record.shelf = aiShelf
            changed = true
        }

        // 仅供比对：模型与正则对取件码判断不一致时留痕，不改数据。
        let aiCode = clean(fields.code)
        if !aiCode.isEmpty, aiCode != record.code {
            DiagnosticsLog.record("ai-extension", "code_mismatch kept=regex")
        }

        guard changed else { return }
        DiagnosticsLog.record("ai-extension", "filled code=\(record.code)")
        store.update(record)
    }
}
