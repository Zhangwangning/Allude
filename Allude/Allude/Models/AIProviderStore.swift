import SwiftUI
import Security

// MARK: ============================================================================
// 三方模型扩展（BYOK，2026-11-13 主人要求）
//
// 只做三件事：
//   1) 记住用户「接入了哪一家」与「用的是哪个模型名」；
//   2) 把 API Key 放进**本机 Keychain**（不进 iCloud、不进日志、不进备份同步）；
//   3) 给上层一个「这一家现在能不能用」的判断。
//
// 🔴 隐私口径（写进页面文案与法务）：
//   · 请求由用户的设备**直连**服务商官方接口，不经过开发者任何服务器；
//   · 开发者看不到短信原文，也看不到 Key；
//   · 默认关闭；关掉后 App 不向任何模型发起请求；
//   · 端侧 Apple 智能走系统通道，与这套扩展互不影响。
// ============================================================================

/// 可接入的三家模型服务。只保留三家（2026-11-13 主人定）：DeepSeek、豆包、千问。
enum AIProvider: String, CaseIterable, Identifiable {
    case deepseek
    case doubao
    case qwen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .doubao:   return "豆包"
        case .qwen:     return "千问"
        }
    }

    var company: String {
        switch self {
        case .deepseek: return "深度求索"
        case .doubao:   return "字节跳动 · 火山方舟"
        case .qwen:     return "阿里云 · 百炼"
        }
    }

    /// 官方接口地址（App 内置，不开放自定义，避免被填进来路不明的端点）
    var endpoint: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com/chat/completions"
        case .doubao:   return "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
        case .qwen:     return "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        }
    }

    /// 默认模型名；豆包填的是「推理接入点 ID / 模型 ID」，由用户按自己控制台里看到的填。
    var defaultModel: String {
        switch self {
        case .deepseek: return "deepseek-chat"
        case .doubao:   return "doubao-seed-1.6"
        case .qwen:     return "qwen-plus"
        }
    }

    var modelFieldHint: String {
        switch self {
        case .deepseek: return "模型名，例如 deepseek-chat"
        case .doubao:   return "模型 ID 或推理接入点 ID（ep-…）"
        case .qwen:     return "模型名，例如 qwen-plus"
        }
    }

    var keyHint: String {
        switch self {
        case .deepseek: return "在 DeepSeek 开放平台创建的 API Key（sk-…）"
        case .doubao:   return "火山方舟控制台创建的 API Key"
        case .qwen:     return "阿里云百炼控制台创建的 API Key（sk-…）"
        }
    }

    var symbol: String {
        switch self {
        case .deepseek: return "sparkles"
        case .doubao:   return "bubble.left.and.text.bubble.right.fill"
        case .qwen:     return "cloud.fill"
        }
    }

    var tint: Color { AppTheme.violet }

    var keychainAccount: String { "allude.ai.provider." + rawValue }
}

/// 扩展的开关与模型名（App Group 存偏好；Key 只进 Keychain）。
enum AIProviderSettings {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
    }

    private static func enabledKey(_ p: AIProvider) -> String { "allude.ai.\(p.rawValue).enabled" }
    private static func modelKey(_ p: AIProvider) -> String { "allude.ai.\(p.rawValue).model" }

    static func isEnabled(_ p: AIProvider) -> Bool {
        defaults.bool(forKey: enabledKey(p))
    }

    static func setEnabled(_ on: Bool, for p: AIProvider) {
        defaults.set(on, forKey: enabledKey(p))
    }

    static func model(_ p: AIProvider) -> String {
        let v = defaults.string(forKey: modelKey(p)) ?? ""
        return v.isEmpty ? p.defaultModel : v
    }

    static func setModel(_ value: String, for p: AIProvider) {
        defaults.set(value, forKey: modelKey(p))
    }

    /// 用户显式开启、且真的填过 Key，才算「已接入」。
    static func isReady(_ p: AIProvider) -> Bool {
        isEnabled(p) && !(AIProviderKeychain.key(for: p) ?? "").isEmpty
    }

    /// 当前有没有任何一家可直接用（解析层用它决定要不要发起请求）。
    static var anyReadyProvider: AIProvider? {
        AIProvider.allCases.first(where: isReady)
    }
}

/// Keychain 读写：只存本机、仅本 App 可读（`kSecAttrAccessibleAfterFirstUnlock`）。
enum AIProviderKeychain {
    private static let service = "com.jikezhang.allude.ai"

    static func key(for provider: AIProvider) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    @discardableResult
    static func save(_ key: String, for provider: AIProvider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return delete(for: provider) }
        let data = Data(trimmed.utf8)

        var query = baseQuery(provider)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        query.merge(attributes) { _, new in new }
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete(for provider: AIProvider) -> Bool {
        let status = SecItemDelete(baseQuery(provider) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(_ provider: AIProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount
        ]
    }
}
