import Foundation
import SwiftUI

// MARK: ============================================================================
// 共享数据模型（App 与小组件扩展共同编译）
//
// 这里只放「纯数据 + 纯计算」：两端都要用来渲染的类型。
// 解析引擎（PickupParser）、全局状态（PickupStore）留在 App target —— 小组件
// 只读展示，不需要正则能力，也不应承担解析成本。
// ============================================================================

// MARK: - 取件信息类别（对应快捷指令 V7.3.0 的四级优先级链：取件码 → 运单号 → 尾号 → 特殊格式）

enum PickupKind: String, CaseIterable, Identifiable, Codable {
    case code
    case waybill
    case tail
    case special

    var id: String { rawValue }

    var label: String {
        switch self {
        case .code: "取件码"
        case .waybill: "运单号"
        case .tail: "尾号"
        case .special: "特殊取件码"
        }
    }

    var symbol: String {
        switch self {
        case .code: "shippingbox.fill"
        case .waybill: "doc.text.fill"
        case .tail: "number"
        case .special: "sparkles"
        }
    }

    /// 单字简写，**仅供极窄场景**（如锁屏 `accessoryRectangular`）与 `KindTag(compact:)` 使用。
    ///
    /// ⚠️ 首页 / 记录页 / 小组件一律用完整 `label`，不要退回单字：
    /// 「码」字同时命中取件码、取餐码、退货码，用户无法据此判断该报什么去取。
    var shortLabel: String {
        switch self {
        case .code: "码"
        case .waybill: "单"
        case .tail: "尾"
        case .special: "特"
        }
    }
}


// MARK: - 时间分组（首页与记录页共同使用，给列表一个稳定的骨架）

enum DayGroup: String, CaseIterable, Identifiable {
    case today = "今天"
    case yesterday = "昨天"
    case earlier = "更早"

    var id: String { rawValue }
}

// MARK: - 单条取件信息

struct PickupRecord: Identifiable, Hashable, Codable {
    var id = UUID()
    var company: String
    var code: String
    var kind: PickupKind
    var address: String
    var rawMessage: String
    var receivedAt: Date
    var isPickedUp: Bool = false

    /// **快递公司（承运方）**，与 `company`（平台）分开：
    /// 「【拼多多】您的圆通快递…」→ company=拼多多、courier=圆通快递。
    /// 🔴 Optional + 默认 nil：合成 Codable 走 decodeIfPresent，
    ///    旧版本 JSON 缺这些 key 也能正常解出（2026-09-23 扩展字段）。
    var courier: String? = nil
    /// 次要凭证：运单号（主凭证就是运单号时不重复存，为 nil）
    var waybill: String? = nil
    /// 次要凭证：尾号（主凭证就是尾号时不重复存，为 nil）
    var tail: String? = nil
    /// **货架号**（2026-10-14 参照「码上取」补的字段）：菜鸟驿站等场景下，
    /// 货架号比取件码更能直接定位包裹（「3号货架」「货架号：3-12」）。
    /// 🔴 Optional + 默认 nil：旧版本 JSON 缺这个 key 也能正常解码。
    var shelf: String? = nil

    /// **取件发生的时刻**（勾选「已取」的那一下），未取件时为 nil。
    ///
    /// 与 `receivedAt`（短信到达 = 入库时刻）配对，才能回答统计页里两个真问题：
    ///   · 「取件频率」—— 用户实际是在哪几天去取的（只看 receivedAt 只能得到「收短信的频率」）；
    ///   · 「平均停留」—— 从收到通知到取走平均花了多久，这是这个 App 最有价值的自省指标。
    ///
    /// ⚠️ 声明为 **Optional** 而非给一个默认时间：`Codable` 合成的解码对可选字段走
    /// `decodeIfPresent`，**旧版本写下的 JSON 缺这个 key 也能正常解码**（读到 nil），
    /// 不会因为升级 App 就让整份取件记录解不出来。历史数据没有这个值，
    /// 统计侧统一以 `pickedUpAt ?? receivedAt` 兜底，不会出现空洞。
    var pickedUpAt: Date? = nil

    /// 「取件发生时间」的统一读取口径：老数据没记 `pickedUpAt` 时回退到入库时间。
    var pickupMoment: Date { pickedUpAt ?? receivedAt }

    /// 去重指纹：同一类别 + 同一凭证 + 同一地址视为同一条
    var fingerprint: String {
        "\(kind.rawValue)|\(code)|\(address)"
    }

    /// 快递公司品牌色（内容层配色来源）
    var brandColor: Color { CourierBrand.color(for: company) }

    /// 全局搜索命中判断（取件码 / 快递公司 / 平台 / 地址 / 运单号 / 尾号 / 原文）
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return code.localizedCaseInsensitiveContains(q)
            || company.localizedCaseInsensitiveContains(q)
            || address.localizedCaseInsensitiveContains(q)
            || rawMessage.localizedCaseInsensitiveContains(q)
            || (courier?.localizedCaseInsensitiveContains(q) ?? false)
            || (waybill?.localizedCaseInsensitiveContains(q) ?? false)
            || (tail?.localizedCaseInsensitiveContains(q) ?? false)
    }

    var dayGroup: DayGroup {
        let calendar = Calendar.current
        if calendar.isDateInToday(receivedAt) { return .today }
        if calendar.isDateInYesterday(receivedAt) { return .yesterday }
        return .earlier
    }

    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var shortTime: String { Self.shortTimeFormatter.string(from: receivedAt) }

    /// 只显示时:分的紧凑时间（同一天内使用）
    var clockTime: String { Self.clockFormatter.string(from: receivedAt) }

    var relativeTime: String {
        let interval = Date().timeIntervalSince(receivedAt)
        if interval < 60 { return "刚刚" }
        // 数字与单位之间不留空格：卡片第一行横向预算只有约 190pt，
        // 每处省下的 3~4pt 都直接决定「取件码 + 标签 + 时间」能否同排显示。
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86_400 { return "\(Int(interval / 3600))小时前" }
        if interval < 172_800 { return "昨天" }
        return shortTime
    }

    /// 地址过长时截断，供小组件单行展示
    func trimmedAddress(_ limit: Int = 14) -> String {
        let text = address.trimmingCharacters(in: .whitespaces)
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    // MARK: 驿站 / 网点短名（2026-09-23）

    /// 短信地址里的**站点词**，命中它就算找到了"驿站"这一层信息。
    ///
    /// 顺序即优先级：「驿站」最明确，其余是各地常见的代收点形态。
    private static let stationKeywords = [
        "驿站", "快递柜", "自提柜", "便利店", "超市", "营业点",
        "服务点", "网点", "代收点", "收发室", "门卫", "物业",
    ]

    /// **驿站 / 网点短名** —— 从地址里裁出来的那一小段。
    ///
    /// 为什么是裁剪而不是新加一个字段：取件短信里根本没有"驿站"这个结构化字段，
    /// 站点名与地址在原文里是同一句话（「到**菜鸟驿站**取件，地址：恒大御府东门菜鸟驿站」）。
    /// 加字段意味着**改解析引擎、改正则真值表、改历史数据**——为一个展示选项动
    /// 核心解析是亏的。而地址里的站名对用户来说本来就是可辨识的一段字，
    /// 按站点词往前收 2 个字就够了。
    ///
    /// 取 2 个字的理由（对照真实语料）：
    ///   · 恒大御府东门**菜鸟驿站** → 菜鸟驿站 ✓（取 3 会得到"门菜鸟驿站"）
    ///   · 河西学院北门圆通**妈妈驿站** → 妈妈驿站 ✓
    ///   · 馨月湖小区南门**兴裕隆超市** → 裕隆超市（略截，可接受）
    ///   · 万寿街**顺丰营业点** → 顺丰营业点 ✓
    /// 没有站点词时返回空串（例如「恒大御府南门西侧3栋104号」），
    /// 调用侧据此自动退回完整地址。
    var station: String {
        let text = address.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return "" }

        for keyword in Self.stationKeywords {
            guard let range = text.range(of: keyword) else { continue }
            // 往前收 2 个字作为店招。用 character 数而不是 utf8 偏移 ——
            // 中文地址里 index 走错一位就会把字割坏。
            let head = text[text.startIndex ..< range.lowerBound]
            let prefix = String(head.suffix(2))
            return prefix + keyword
        }
        return ""
    }

    // MARK: 小组件二级信息行

    /// 按显示配置拼出小组件的第二行；**没有任何内容可显示时返回 nil**（该行整行不画）。
    ///
    /// 两条拼装规则：
    ///   · **驿站与地址互斥**：站名本身就是地址的尾段，两个都画等于同一段字出现两次
    ///     （「菜鸟驿站｜恒大御府东门菜鸟驿站」）。同时开启时以地址为准，
    ///     站名只在"地址被关掉"时顶上来 —— 这一点在设置页的说明里也写给用户了。
    ///   · 关掉站名时地址放宽到 16 字，开着站名时收窄到 12 字：
    ///     第二行本来就只有一行宽，加上站名更容易被截断，先让地址让位。
    /// `addressLimit` 留空时按是否同行显示站名自动取值；小尺寸（允许折两行）
    /// 显式传更宽的上限，那里有第二行的预算。
    func widgetSubtitle(_ options: WidgetDisplayOptions,
                        addressLimit: Int? = nil) -> String? {
        let limit = addressLimit ?? (options.showsStation ? 12 : 16)
        var parts: [String] = []

        if options.showsCompany, !company.isEmpty {
            parts.append(company)
        }

        // 货架号（2026-10-14）：排在你地址**前面** —— 到店场景它是比地址更高频
        // 被看的信息，行宽不够被截断时，牺牲的应该是地址而不是货架。
        if let shelf, !shelf.isEmpty {
            parts.append("货架\(shelf)")
        }

        // 驿站与地址**互斥**：站名本就是地址的尾段，两个都画等于同一段字出现两次
        // （「菜鸟驿站｜恒大御府东门菜鸟驿站」）。同时开启时以地址为准 ——
        // 它是完整信息，站名只是它的简写。
        if options.showsStation, !options.showsAddress {
            let name = station
            // 提不出站名就别让这一项变成空白：退回完整地址 ——
            // 用户要的是"位置信息"，站名只是它的一种简称。
            // ⚠️ 回落时同样要截断，否则这一条会比相邻几条长出一大截，
            //    在列表里看起来像换了一种版式。
            let location = name.isEmpty ? trimmedAddress(limit) : truncated(name, limit: limit)
            if !location.isEmpty { parts.append(location) }
        }

        if options.showsAddress {
            let text = trimmedAddress(limit)
            if !text.isEmpty { parts.append(text) }
        }

        // 去重：平台名与站名撞车是常事（「菜鸟驿站」既是平台也是站点，
        // 兔喜生活、妈妈驿站同理），不去重就会渲染成「菜鸟驿站｜菜鸟驿站」。
        var unique: [String] = []
        for part in parts where !unique.contains(part) {
            unique.append(part)
        }

        return unique.isEmpty ? nil : unique.joined(separator: "｜")
    }

    /// 按指定上限截断任意文本（站名复用地址那一套截断口径）
    private func truncated(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }

}

// MARK: - 取件码末四位强调（2026-10-14，参照上岛记「快递末四位」可读性优化）
//
// 用户在驿站真正用到的只有最后几位：报给店员、输进柜机的都是那一小段。
// 全码同权重渲染时，长码（15 位运单号）的重点被淹没 —— 这里把**前段弱化、
// 末四位保持全色**，视线自然落在该看的地方。
//
// 返回 `Text` 而非 View：九个渲染面（首页卡 / 浏览卡 / 详情 / 分享卡 /
// 小组件 / 灵动岛）各自控制字号与版式，此处不锁死任何排版参数。
//
// 🔴 做成**吃 code 字符串**的独立构造器而非只扩展 PickupRecord：
//    灵动岛的状态里跑的是轻量副本 `PickupActivityAttributes.Item`，
//    它不是 PickupRecord —— 挂在字符串上，两种状态模型都能用。

enum PickupCodeEmphasis {

    /// 取件码前段（去掉末四位）
    static func head(_ code: String) -> String {
        code.count > 4 ? String(code.dropLast(4)) : code
    }

    /// 取件码末四位 —— 报取件时真正念的那一段
    static func tail(_ code: String) -> String {
        String(code.suffix(4))
    }

    /// 末四位强调的取件码 `Text`：前段按 `headOpacity` 弱化，末四位全色。
    /// 已取态整串转次级色（划线仍由调用处叠）。码长 ≤ 4 时不拆分，整串全色。
    static func text(_ code: String,
                     isDone: Bool = false,
                     tint: Color,
                     headOpacity: Double = 0.45) -> Text {
        let tailColor = isDone ? Color.secondary : tint
        guard code.count > 4 else {
            return Text(code).foregroundColor(tailColor)
        }
        return Text(head(code))
            .foregroundColor(isDone ? Color.secondary : tint.opacity(headOpacity))
            + Text(tail(code)).foregroundColor(tailColor)
    }
}

extension PickupRecord {

    /// 取件码前段（去掉末四位）
    var codeHead: String { PickupCodeEmphasis.head(code) }

    /// 取件码末四位 —— 报取件时真正念的那一段
    var codeTail: String { PickupCodeEmphasis.tail(code) }

    /// 末四位强调的取件码 `Text`（详见 `PickupCodeEmphasis.text`）
    func emphasizedCodeText(isDone: Bool = false,
                            tint: Color,
                            headOpacity: Double = 0.45) -> Text {
        PickupCodeEmphasis.text(code, isDone: isDone, tint: tint,
                                headOpacity: headOpacity)
    }
}

// MARK: - 合并策略（同码再进 → 自动完成旧条 + 新增新条）

/// 一批新记录与既有列表的合并规则。
///
/// **语义（2026-09-21 定案）**：收到**同一件包裹**的再次通知（同类别 + 同取件码 +
/// 同地址）时，说明上一条的使命已经结束 —— 把旧条**自动标记为已取**，
/// 本次短信作为**新的一条**写入。
///
/// 典型场景：同一件包裹先收到「已到站」，几小时后又收到「滞留 1 天未取，请尽快取件」，
/// 两条取件码相同。旧行为是把后一条当重复**直接丢弃**，结果是用户**看不到最新一条**
/// （新短信里的地址、时限、状态更准），而旧条永远停在待取列表里。
///
/// 与「去重」的分工：过滤的是**重复的短信**，保留的是**同一件的状态演进**。
/// 完全相同的短信被重复推送也走这条路径 —— 旧条转已取 + 新条入列，
/// 用户视角仍是「最新一条待取、历史一条已取」，与真实取件过程一致。
///
/// ⚠️ 只在**未取件**的记录里找同码旧条：已取件的是历史，不该被再次翻动。
enum PickupMerge {
    struct Result {
        /// 合并后的完整列表（顺序 = 既有顺序 + 新写入顺序）
        var records: [PickupRecord]
        /// 本次真正新建的记录
        var added: [PickupRecord]
        /// 因同码再进而被自动标记为已取的旧取件码
        var completed: [String]
    }

    static func merge(_ existing: [PickupRecord],
                      with candidates: [PickupRecord]) -> Result {
        var working = existing
        var added: [PickupRecord] = []
        var completed: [String] = []

        for candidate in candidates {
            if let index = working.firstIndex(where: {
                !$0.isPickedUp && $0.fingerprint == candidate.fingerprint
            }) {
                working[index].isPickedUp = true
                // 自动完成也要落时间戳，否则它统计不到「这批件取走了」这一事实。
                // 用**新短信的到达时刻**而非 `Date()`：这条旧件的使命是被新通知终结的，
                // 两者是同一件事，时刻应当一致。
                working[index].pickedUpAt = candidate.receivedAt
                completed.append(working[index].code)
            }
            working.append(candidate)
            added.append(candidate)
        }

        return Result(records: working, added: added, completed: completed)
    }
}

