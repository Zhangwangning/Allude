import Foundation

// MARK: ============================================================================
// 第三方模型用量统计（2026-11-14 主人要求：App 内简单的消耗与花费统计）
//
// 只统计**我们自己发出的请求**：每次解析增强返回后，从响应的 `usage` 里取
// prompt/completion tokens，按各家官方价目表**估算**人民币。数字只留本机
// （App Group），不上传；按模型区分单价，模型改了自然按新价算。
//
// ⚠️ 这是估算：各家有阶梯价、缓存命中价、限时折扣，这里只取标准价。
// ============================================================================

enum AIUsageStore {

    struct Totals {
        var requests = 0
        var inputTokens = 0
        var outputTokens = 0
        var costCNY: Double = 0

        var tokens: Int { inputTokens + outputTokens }
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
    }

    private static func key(_ provider: AIProvider, _ field: String) -> String {
        "allude.ai.usage.\(provider.rawValue).\(field)"
    }

    // MARK: 价目（人民币 / 百万 tokens，标准价，估算用）

    /// 返回 (输入单价, 输出单价)，单位：元 / 1M tokens。
    static func price(for provider: AIProvider, model: String) -> (input: Double, output: Double) {
        let m = model.lowercased()
        switch provider {
        case .deepseek:
            if m.contains("reasoner") { return (4, 16) }
            return (2, 8)
        case .doubao:
            if m.contains("1.5-pro") { return (0.8, 2) }
            if m.contains("lite") { return (0.3, 0.6) }
            return (0.8, 8)
        case .qwen:
            if m.contains("max") { return (2.4, 9.6) }
            if m.contains("turbo") { return (0.3, 0.6) }
            if m.contains("long") { return (0.5, 2) }
            return (0.8, 2)
        case .kimi:
            if m.contains("128k") { return (60, 60) }
            if m.contains("32k") { return (24, 24) }
            if m.contains("k2") { return (4, 16) }
            return (12, 12)
        }
    }

    // MARK: 记账

    /// 从一次成功的响应里抽 `usage` 并累加。没有 usage 字段就只 +1 次请求。
    static func record(provider: AIProvider, model: String, responseData: Data) {
        var input = 0
        var output = 0
        if let root = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           let usage = root["usage"] as? [String: Any] {
            input = (usage["prompt_tokens"] as? Int) ?? (usage["input_tokens"] as? Int) ?? 0
            output = (usage["completion_tokens"] as? Int) ?? (usage["output_tokens"] as? Int) ?? 0
        }
        add(provider: provider, model: model, input: input, output: output)
    }

    static func add(provider: AIProvider, model: String, input: Int, output: Int) {
        let p = price(for: provider, model: model)
        let cost = Double(input) / 1_000_000 * p.input + Double(output) / 1_000_000 * p.output

        defaults.set(defaults.integer(forKey: key(provider, "requests")) + 1, forKey: key(provider, "requests"))
        defaults.set(defaults.integer(forKey: key(provider, "in")) + max(0, input), forKey: key(provider, "in"))
        defaults.set(defaults.integer(forKey: key(provider, "out")) + max(0, output), forKey: key(provider, "out"))
        defaults.set(defaults.double(forKey: key(provider, "cost")) + cost, forKey: key(provider, "cost"))
    }

    // MARK: 读取

    static func totals(for provider: AIProvider) -> Totals {
        Totals(
            requests: defaults.integer(forKey: key(provider, "requests")),
            inputTokens: defaults.integer(forKey: key(provider, "in")),
            outputTokens: defaults.integer(forKey: key(provider, "out")),
            costCNY: defaults.double(forKey: key(provider, "cost"))
        )
    }

    static var allTotals: Totals {
        AIProvider.allCases.reduce(into: Totals()) { sum, provider in
            let t = totals(for: provider)
            sum.requests += t.requests
            sum.inputTokens += t.inputTokens
            sum.outputTokens += t.outputTokens
            sum.costCNY += t.costCNY
        }
    }

    static func reset(_ provider: AIProvider? = nil) {
        let targets = provider.map { [$0] } ?? AIProvider.allCases
        for p in targets {
            for field in ["requests", "in", "out", "cost"] {
                defaults.removeObject(forKey: key(p, field))
            }
        }
    }

    // MARK: 展示

    static func costText(_ value: Double) -> String {
        if value == 0 { return "¥0.00" }
        if value < 0.01 { return "¥" + String(format: "%.4f", value) }
        return "¥" + String(format: "%.2f", value)
    }

    static func tokenText(_ value: Int) -> String {
        if value >= 100_000 { return String(format: "%.1f 万", Double(value) / 10_000) }
        return "\(value)"
    }
}
