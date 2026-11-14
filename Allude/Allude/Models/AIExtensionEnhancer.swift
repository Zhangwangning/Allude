import Foundation

// MARK: ============================================================================
// 第三方模型扩展（BYOK）—— 与正则**合并出最终结果**的解析增强（2026-11-14 改口径）
//
// 主人原话：「…这3个用户可以通过API去接入，接入完了之后，用来对短信内容解析，
// 相当于是一个功能性增强。这个接入的时候，这个权限要给用户，我们的APP不进行
// 任何的数据处理，AI方面的保证，APP不参与网络请求」。
//
// 因此这一层的边界写死：
//   1. **默认关闭**：`AIProviderSettings.anyReadyProvider == nil` 时，一行代码都不会发请求；
//   2. **模型参与判定、但字段有护栏**（2026-11-14 主人要求：AI 的作用是"结合正则结果
//      去优化解析"，不是"只补空"——有些字段本来就该是空的）：
//      · 地址 / 驿站 / 柜位 / 货架：模型给的值与正则不同时**可以采用**（这正是优化的价值）；
//      · 快递公司：只在能归一化到已知品牌时采用，避免模型自造公司名；
//      · 取件码：**必须原样出现在短信原文里**才允许改动（防幻觉），否则一律保留正则值；
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
    /// 这条记录要不要请第三方模型参与判定。
    ///
    /// 2026-11-14 改口径：**不再只在缺字段时调用**，而是每条新入库的记录都请模型
    /// 结合「短信原文 + 正则结果」复核一遍（主人：AI 的作用是优化解析，不是补空）。
    /// 只排除明显不是取件短信/过短的文本，避免白发请求。
    static func needsHelp(_ record: PickupRecord) -> Bool {
        let text = record.rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count >= 8
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
                group.addTask {
                    for attempt in 1...2 {
                        if let fields = await request(record, provider: provider, key: key, model: model) {
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

    private static func request(_ record: PickupRecord,
                                provider: AIProvider,
                                key: String,
                                model: String) async -> AIExtensionFields? {
        guard let url = URL(string: provider.endpoint) else { return nil }

        let instruction = """
        你是快递取件短信解析助手。用户会给你「短信原文」和「正则解析结果」。
        请以原文为准，逐字段复核正则结果：能确认的保留，能修正的改正，原文确实没有的留空。

        只输出一个 JSON 对象，不要解释、不要 markdown。字段：
        - code：取件码（顾客报给店员或柜机上输入的字符，**必须原样出现在原文里**；原文没有就空）
        - courier：快递公司，如「圆通快递」「顺丰速运」
        - station：取件地点品牌，如「菜鸟驿站」「丰巢」「兔喜生活」「妈妈驿站」
        - address：取件地址（站点/柜机的完整地点描述，不含公司名与取件码）
        - locker：快递柜格口，如「2号柜」「12-34格口」
        - shelf：货架号，如「A-12」
        - changed：你改动或补充了哪些字段名（数组，没改就给空数组）

        注意：原文真的没有的字段就留空字符串，不要猜、不要编造地址或公司。
        """

        let regex = """
        短信原文：
        \(record.rawMessage)

        正则解析结果（供复核，可能为空或有误）：
        code: \(record.code)
        courier: \(record.courier ?? "")
        station: \(record.station ?? "")
        address: \(record.address)
        locker: \(record.locker ?? "")
        shelf: \(record.shelf ?? "")
        """
        let payload = regex

        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": instruction],
                ["role": "user", "content": payload]
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
            AIUsageStore.record(provider: provider, model: model, responseData: responseData)
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

    /// 合并字段：**模型结果与正则结果一起决定最终值**（2026-11-14 改口径）。
    ///
    /// 与应用内端侧 `PickupAIEnhancer.apply` 的差别要说清：端侧仍只填空，
    /// 这里的第三方模型**可以修正**地址/柜位/货架/公司，因为用户明确要求
    /// 「AI 的作用是结合正则结果优化解析，不是只补空」。
    /// 护栏见上方注释：取件码必须出现在原文、公司必须能归一到已知品牌。
    @MainActor
    static func apply(_ fields: AIExtensionFields, to id: UUID) {
        let store = PickupStore.shared
        guard let index = store.records.firstIndex(where: { $0.id == id }) else { return }
        var record = store.records[index]
        var changed: [String] = []

        func clean(_ raw: String?) -> String {
            (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        /// 只在「新值非空且与现值不同」时写入。
        func take(_ newValue: String?, into keyPath: WritableKeyPath<PickupRecord, String?>, name: String, maxLength: Int = 40) {
            let value = clean(newValue)
            guard !value.isEmpty, value.count <= maxLength else { return }
            if (record[keyPath: keyPath] ?? "") == value { return }
            record[keyPath: keyPath] = value
            changed.append(name)
        }

        // 地址：模型可修正（这是优化的主要价值）。
        let aiAddress = clean(fields.address)
        if !aiAddress.isEmpty, aiAddress.count <= 80, aiAddress != record.address {
            record.address = aiAddress
            changed.append("address")
        }

        // 驿站：`station` 本身是派生值（品牌词表匹配原文），但模型若给出更准的名字，
        // 就写进 `stationOverride`（这是 `station` 优先读取的覆盖位）。
        take(fields.station, into: \PickupRecord.stationOverride, name: "station", maxLength: 24)

        // 柜位 / 货架：是存储字段，可直接改，长度设上限防模型啰嗦。
        take(fields.locker, into: \PickupRecord.locker, name: "locker", maxLength: 24)
        take(fields.shelf, into: \PickupRecord.shelf, name: "shelf", maxLength: 24)

        // 快递公司：只认能归一到已知品牌的名字，避免模型自造。
        let aiCourier = clean(fields.courier)
        if !aiCourier.isEmpty, aiCourier.count <= 20 {
            let canonical = CourierBrand.canonicalName(for: aiCourier)
            if canonical != aiCourier.trimmingCharacters(in: .whitespaces),
               canonical != "未知快递",
               canonical != record.courier {
                record.courier = canonical
                changed.append("courier")
            }
        }

        // 取件码：**必须原样出现在原文里**才允许改（防幻觉）。改动会写一条留痕。
        let aiCode = clean(fields.code)
        if !aiCode.isEmpty, aiCode != record.code {
            let compactText = record.rawMessage.replacingOccurrences(of: " ", with: "")
            let compactCode = aiCode.replacingOccurrences(of: " ", with: "")
            if compactText.contains(compactCode), aiCode.count <= 24 {
                record.code = aiCode
                changed.append("code")
                DiagnosticsLog.record("ai-extension", "code_replaced from=regex to=verified")
            } else {
                DiagnosticsLog.record("ai-extension", "code_rejected not_in_text")
            }
        }

        guard !changed.isEmpty else { return }
        DiagnosticsLog.record("ai-extension", "optimized fields=\(changed.joined(separator: ","))")
        store.update(record)
    }
}
