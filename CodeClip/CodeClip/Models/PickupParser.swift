import Foundation

// MARK: ============================================================================
// 解析引擎：把 iOS 快捷指令「快递取件码」V7.3.0 的六套正则与优先级链移植进 App。
//
// 关键前提：App 与快捷指令的「匹配文本」动作同用 ICU（NSRegularExpression），
// 因此公式可逐字移植，行为一致——包括 lookbehind 必须定长、`\w`/`\d`/`\s`
// 的字符类语义（ICU 下 `\w` 含 CJK）。
//
// 本文件只依赖 Foundation，可独立编译做 51 条语料回归（见 tools/parser-regression）。
// ============================================================================

/// 一次解析的结果
///
/// 🔴 **字段口径（2026-09-23 主人定）**：`company` = **平台**（【】里的品牌），
/// `courier` = **快递公司**（承运方，正文里找）——「【拼多多】您的圆通快递…」
/// 平台是拼多多、快递公司是圆通快递，两者必须分开，不能混成一个字段。
/// `waybill` / `tail` 是**次要凭证**：主凭证（`kind` + `value`）按优先级链只取一个，
/// 短信里同时出现的运单号 / 尾号落在其次要字段里，**没有就留空串**。
struct PickupParseResult: Equatable {
    var kind: PickupKind
    var value: String
    var company: String
    var address: String
    var rawText: String
    /// 快递公司（承运方）。判别不出时为空串。
    var courier: String = ""
    /// 运单号（主凭证是运单号时与 `value` 相同，否则为短信里另带的运单号）。
    var waybill: String = ""
    /// 尾号（主凭证是尾号时与 `value` 相同，否则为短信里另带的尾号）。
    var tail: String = ""
    /// 货架号（2026-10-14 参照「码上取」补的字段：菜鸟驿站等场景下，
    /// 货架号比取件码更能直接定位包裹 —— 「3号货架」「货架号：3-12」）。
    var shelf: String = ""
}

// MARK: ============================================================================
// （行程字段 TravelFields 已随出行功能下线一并移除 —— 码夹回归快递单一主业。）
// ============================================================================

enum PickupParser {

    // MARK: - 正则真值（V7.3.0 本体实测，逐字移植）

    /// 关键词：V7.3.0 中作为**闸门**使用（凭证全空或关键词为空即拒绝写入）
    static let keywordPattern =
        #"快递|快件|速递|取件|包裹|近邻宝|兔喜生活| 顺丰|圆通|申通|中通|韵达|邮政|百世|德邦|京东|优速|速运|极兔|菜鸟|鸟箱|驿站"#

    /// 取件码（V7.3.0 本体值；`[:："\s]*` 在 lookbehind 之后属匹配内容，
    /// 故结果可能带前导 `"` / `：` —— App 侧统一 trimLeadingSeparators 清理）
    static let codePattern =
        #"(?<=盒|用|暂存码?|凭「?|“|"|(提|取)货?件?(验证)?码?「?为?|、|，|,[A-Z]?)\s*[:："\s]*\s*(?!(\+?86)?1[3-9]\d{9})(((\d+(-|—))+\d+)|(\d?\+?[A-Za-z]+?(-?\d+)+)|(\d+[A-Za-z]\d+)|\d{5,})"#

    /// 运单号（V7.3.0 已补「快件」分支）
    static let waybillPattern =
        #"((?<=(包裹|(快|速)(递|件)】?|邮件))[A-Z]{0,3}\d{11,})|(?<=(快递|件|运单)尾号为?)\s*[:："\s]*\s*(?!(\+?86)?1[3-9]\d{9})(((\d+-)+\d+)|(\d?\+?[A-Za-z]+?(-?\d+)+)|(\d+[A-Za-z]\d+)|\d{4,})"#

    /// 尾号（V7.3.0 本体排除词 + 完整版补的 `储蓄`）
    static let tailPattern =
        #"(?<=尾号为?)\s*[:：”"\s]*\s*(?!(\+?86)?1[3-9]\d{9})(((\d+-)+\d+)|(\d?\+?[A-Za-z]+?(-?\d+)+)|(\d+[A-Za-z]\d+)|\d{4,})(?!\d)(?!.*(?:支付|快捷|(信用|银行)卡|扣款|储蓄|消费|交易|转账))"#

    /// 特殊格式取件码（保持原样；匹配后把 `、`/`,` 归一为 `-`）
    static let specialPattern =
        #"(?<=快递码)(\d+?(,|、)){2}\d+?(?=，)"#

    /// 独立「地址:」字段（优先级高于主地址公式）
    static let standaloneAddressPattern =
        #"(?<=地址[:：])\s*([^。]+?)\s*(?=。|$)"#

    /// 匹配取件地址（V7.2.1 合并单条 v3 + 2026-09-19 宽容 lookahead）
    static let matchedAddressPattern =
        #"(?<=暂存)\S+\s?\d+?(?=，暂存码)|他人签收|(?<=至|前往|由|已?放?在|已?暂存在?|暂存到|到达「|到「|到达|到(?!达))\s*([^\s到「，凭在码]+?(?:站点)?)\s*(?=\s*(?:代签|滞留|请凭|免费|领?取件?|暂存码|取件码|取货码|码|[，,。]|$))"#

    /// 快递公司名：优先 `【】` 内的品牌名
    static let companyBracketPattern = #"(?<=【)[^】]{1,20}(?=】)"#
    /// 兜底：正文里的「xx快递/速递/物流/驿站/速运/快运」
    static let companyFallbackPattern = #"[\u4E00-\u9FA5A-Za-z]{2,6}(?:快递|速递|物流|驿站|速运|快运)"#

    // MARK: 快递公司（承运方）识别

    /// 快递公司品牌词根。**只收快递公司**，不含驿站 / 代收点 / 商家 ——
    /// 「【拼多多】您的圆通快递…」要从正文里捞出「圆通」，而不能把平台自己算进去。
    /// （与 `CourierBrand` 表里 company 分类的词根保持同集；这里单独维护一份，
    ///  是为了保住本文件「只依赖 Foundation、可独立编译回归」的红线。）
    static let courierCompanyKeys = [
        "中国邮政", "邮政", "EMS", "顺丰", "圆通", "申通", "中通", "韵达",
        "百世", "德邦", "京东", "极兔", "天天", "优速", "宅急送", "跨越",
        "安能", "中铁", "速尔",
    ]

    /// 平台名若长这样（圆通快递 / 顺丰速运 / 中国邮政…），它本身就是快递公司。
    /// 🔴 用**白名单**而不是「以快递结尾就算」：【微快递】是驿站品牌，
    ///     「以快递结尾」会把它误判成快递公司。
    private static let platformIsCourierPattern =
        #"^(?:中国)?(?:顺丰|圆通|申通|中通|韵达|百世|德邦|京东|极兔|天天|优速|宅急送|跨越|安能|中铁|速尔)(?:快递|速递|速运|物流|快运)?$|^(?:中国邮政|EMS)$"#

    /// 快递公司后缀词：品牌词根后面紧跟这些字时一并算进公司名（「圆通」→「圆通快递」）
    private static let courierSuffixes = ["快递", "速递", "速运", "物流", "快运"]

    /// 一码多件的链式取件码（「取货码0909-0022、0909-0014」「取件码为260108,260110」）。
    /// lookbehind 各分支**定长**（ICU 红线），`、`/`,`/`，` 分隔 ≥2 段才算链。
    static let codeChainPattern =
        #"(?<=取件码为|取件码[:：]|取件码|取货码为|取货码[:：]|取货码)\s*[「“"]?\s*[\dA-Za-z][\dA-Za-z\-—]*(?:\s*[、,，]\s*[\dA-Za-z][\dA-Za-z\-—]*)+"#

    // MARK: 货架号（2026-10-14）

    /// ① 显式「货架号：3-12」（lookbehind「货架号：」定长，ICU 合法）
    static let shelfExplicitPattern =
        #"(?<=货架号[:：])\s*[0-9A-Za-z]{1,4}(?:[-—][0-9A-Za-z]{1,4})?"#
    /// ② 「货架3-12」紧贴写法（lookbehind「货架」定长）
    static let shelfGluedPattern =
        #"(?<=货架)\s*[0-9]{1,3}[-—][0-9]{1,4}"#
    /// ③ 「3号货架」前置写法（捕获在货架词之前，无 lookbehind）
    static let shelfLeadingPattern =
        #"[0-9]{1,3}(?:[-—][0-9]{1,4})?\s*号货架"#

    /// 货架号提取：三种写法按「显式 > 紧贴 > 前置」顺序试。
    /// 「3号货架」命中后把后缀「号货架」裁掉，只留编号本身。
    static func shelf(from text: String) -> String {
        if let hit = firstMatch(shelfExplicitPattern, in: text) {
            return trimLeadingSeparators(hit)
        }
        if let hit = firstMatch(shelfGluedPattern, in: text) {
            return trimLeadingSeparators(hit)
        }
        if let hit = firstMatch(shelfLeadingPattern, in: text) {
            return hit
                .replacingOccurrences(of: "号货架", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    // MARK: - 编译缓存（正则只编译一次）

    private static let regexes: [String: NSRegularExpression] = {
        var map: [String: NSRegularExpression] = [:]
        for pattern in [keywordPattern, codePattern, waybillPattern, tailPattern,
                        specialPattern, standaloneAddressPattern, matchedAddressPattern,
                        companyBracketPattern, companyFallbackPattern,
                        platformIsCourierPattern, codeChainPattern] {
            map[pattern] = try? NSRegularExpression(pattern: pattern)
        }
        return map
    }()

    /// 正则是否全部编译通过（供自检 / 回归脚本使用）
    static var allPatternsValid: Bool {
        [keywordPattern, codePattern, waybillPattern, tailPattern,
         specialPattern, standaloneAddressPattern, matchedAddressPattern,
         companyFallbackPattern, companyBracketPattern,
         platformIsCourierPattern, codeChainPattern].allSatisfy { regexes[$0] != nil }
    }

    // MARK: - 匹配工具

    /// 取第一个匹配的**整段匹配文本**（等价于快捷指令的 Text Match `m[0]`，不要取分组）
    private static func firstMatch(_ pattern: String, in text: String,
                                   group: Int = 0) -> String? {
        guard let regex = regexes[pattern] else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        guard group < match.numberOfRanges,
              let r = Range(match.range(at: group), in: text) else { return nil }
        return String(text[r])
    }

    /// 归一：全角/引号类前导分隔符与空白一律去掉
    private static func trimLeadingSeparators(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let junk: Set<Character> = [":", "：", "\"", "“", "”", "、", "，", ",", "；", ";"]
        while let first = result.first, junk.contains(first) {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    /// `、` / `,` → `-`（特殊格式取件码归一，对应快捷指令里的「替换文本」动作）
    private static func normalizeSeparators(_ value: String) -> String {
        value.replacingOccurrences(of: #"[、,]"#, with: "-", options: .regularExpression)
    }

    // MARK: - 快递公司识别

    /// **短信平台** = `【】` 内的内容（发短信的平台）。2026-10-18 主人定：
    /// 平台严格等于【】内文本；短信不含【】时平台为空串，不再回落正文或「未知快递」哨兵。
    static func company(from text: String) -> String {
        guard let bracketed = firstMatch(companyBracketPattern, in: text) else { return "" }
        var name = bracketed.trimmingCharacters(in: .whitespaces)
        // 「【中国邮政】」这类前缀去掉更贴近用户叫法
        for prefix in ["中国", "国内"] where name.hasPrefix(prefix) && name.count > 4 {
            name.removeFirst(prefix.count)
        }
        return name
    }

    /// **快递公司（承运方）**：与平台（`company(from:)`）分开的两个概念。
    ///
    /// 规则：
    ///   1. 平台名本身就是快递公司（【圆通快递】【中国邮政】…命中白名单）→ 直接用它；
    ///   2. 否则在**正文**里找快递公司品牌词根的最早出现，后缀（快递/速递/…）一并带上
    ///      （「您的圆通快递YT886…」→「圆通快递」；「您的中国邮政包裹」→「中国邮政」）；
    ///   3. 找不到 → 空串（**留空**，不编造）。
    /// **快递公司（承运方）** —— 2026-10-18 主人定口径：
    ///   1. 先在 `【】` **以外**的正文里找快递公司品牌词根（最早出现、带后缀）；
    ///   2. 正文没有，则看 `【】` 内内容（platform）本身是不是快递公司（白名单）；
    ///   3. 都不是 → 空串（**留空**，不编造）。
    /// 与 `company(from:)`（平台=【】内）彻底分离，不再互为回填。
    static func courierCompany(from text: String, platform: String) -> String {
        // ① 正文（去掉【】内）优先
        let body = stripBracket(text)
        if let name = firstCourierKey(in: body) { return name }

        // ② 正文无 → 看【】内是否为快递公司
        if !platform.isEmpty,
           let regex = regexes[platformIsCourierPattern],
           regex.firstMatch(in: platform, options: [],
                            range: NSRange(platform.startIndex..., in: platform)) != nil {
            return platform
        }
        return ""
    }

    /// 去掉 `【…】` 片段，得到纯粹的「正文」用于快递公司匹配
    private static func stripBracket(_ text: String) -> String {
        text.replacingOccurrences(of: #"【[^】]*】"#, with: "", options: .regularExpression)
    }

    /// 在给定文本里找最早的快递公司词根（带后缀），无则 nil
    private static func firstCourierKey(in text: String) -> String? {
        var best: (start: String.Index, name: String)?
        for key in courierCompanyKeys {
            guard let range = text.range(of: key) else { continue }
            if let found = best {
                if range.lowerBound > found.start { continue }
                if range.lowerBound == found.start && key.count <= found.name.count { continue }
            }
            var end = range.upperBound
            for suffix in courierSuffixes where text[end...].hasPrefix(suffix) {
                end = text.index(end, offsetBy: suffix.count)
                break
            }
            best = (range.lowerBound, String(text[range.lowerBound..<end]))
        }
        return best?.name
    }

    /// 链式取件码（一码多件）：整段匹配文本按 `、`/`,`/`，` 切开。
    /// 返回 nil = 不是链式（单码）。调用方拿**首段**与主解析结果对齐。
    static func codeChainParts(in text: String) -> [String]? {
        guard let matched = firstMatch(codeChainPattern, in: text) else { return nil }
        let parts = matched
            .components(separatedBy: CharacterSet(charactersIn: "、,，"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.contains(where: \.isNumber) }
        return parts.count >= 2 ? parts : nil
    }

    // MARK: - 主流程

    /// 解析一条短信。返回 nil 表示「不是快递短信」（凭证与关键词双闸门均未通过）。
    static func parse(_ rawText: String) -> PickupParseResult? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // ① 四套凭证公式
        let code = firstMatch(codePattern, in: text).map(trimLeadingSeparators).flatMap { $0.isEmpty ? nil : $0 }
        let waybill = firstMatch(waybillPattern, in: text).map(trimLeadingSeparators).flatMap { $0.isEmpty ? nil : $0 }
        let tail = firstMatch(tailPattern, in: text).map(trimLeadingSeparators).flatMap { $0.isEmpty ? nil : $0 }
        let special = firstMatch(specialPattern, in: text).map(normalizeSeparators).flatMap { $0.isEmpty ? nil : $0 }

        // ② 全局闸门：四套全空 → 直接拒绝（V7.3.0 动作 51–62 的语义）
        guard code != nil || waybill != nil || tail != nil || special != nil else { return nil }

        // ③ 关键词闸门：为空 → 拒绝，防止非快递短信触发写入
        guard firstMatch(keywordPattern, in: text) != nil else { return nil }

        // ④ 优先级链：取件码 → 运单号 → 尾号 → 特殊格式（命中即止）
        let outcome: (PickupKind, String)
        if let code {
            outcome = (.code, code)
        } else if let waybill {
            outcome = (.waybill, waybill)
        } else if let tail {
            outcome = (.tail, tail)
        } else {
            outcome = (.special, special ?? "")
        }

        // ⑤ 地址两级口径：独立「地址:」字段优先，未命中回落主公式
        let address = firstMatch(standaloneAddressPattern, in: text)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? firstMatch(matchedAddressPattern, in: text)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        // ⑥ 次要凭证与快递公司（2026-09-23 扩展：字段尽量全，没有就留空）：
        //    主凭证之外的运单号 / 尾号落进次要字段（「凭A-9182…取运单尾号7872包裹」
        //    主凭证是取件码，运单尾号 7872 也要带上）；快递公司按平台 / 正文两级判别。
        let platform = company(from: text)
        var result = PickupParseResult(kind: outcome.0,
                                       value: outcome.1,
                                       company: platform,
                                       address: address,
                                       rawText: rawText)
        result.waybill = outcome.0 == .waybill ? outcome.1 : (waybill ?? "")
        result.tail = outcome.0 == .tail ? outcome.1 : (tail ?? "")
        result.courier = courierCompany(from: text, platform: platform)
        result.shelf = shelf(from: text)

        // 平台与快递公司彻底分离（2026-10-18 主人定）：平台=【】内（无则空），
        // 快递公司=正文优先→【】内兜底→空，两者各算各的，不再互为回填。

        // 运单号公式里带「(快递|件|运单)尾号」分支（V7.3.0 本体行为），
        // 「取运单尾号7872包裹」会同时命中运单号与尾号两套公式 —— 同一串数字
        // 在两个字段里出现两遍是错的：它是尾号，把运单号字段清掉。
        if outcome.0 != .waybill, !result.waybill.isEmpty, result.waybill == result.tail {
            result.waybill = ""
        }

        // 地址误锚兜底：公式的「已?放?在」分支让 bare-在 也是锚点，
        // 「正在派送」会锚出「派送」这类状态词 —— 不是地址，整段弃用。
        if AddressFalseAnchors.contains(address) {
            result.address = ""
        } else if let parenRange = result.address.range(of: "（请") {
            // 「…2号柜（请前往自提）超72小时收费…」：括注是取件说明不是地址，
            // 从「（请」起整段截掉。
            result.address = String(result.address[..<parenRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result
    }

    /// 地址字段的整段弃用黑名单（精确匹配）
    private static let AddressFalseAnchors: Set<String> = [
        "派送", "派件", "投递", "送达", "上门", "代收点", "自提柜",
    ]

    // MARK: - OCR 来源的多假设解析

    /// 面向 OCR 文本的解析入口。
    ///
    /// **为什么需要单独一条入口**：公式的 lookbehind 是定长的（ICU 限制），
    /// 一旦锚点被切开就再也接不回来 —— 而 OCR 恰恰会在**视觉折行**处插入换行，
    /// 例如把「取件码为C-4082」读成两行「取件码」+「为C-4082」，
    /// 使 `取件码为` 这个锚点中间多出一个 `\n`，公式随即失配。
    /// 这个换行来自排版折行、并非语义分段，无法先验判断，只能生成若干候选逐个尝试。
    ///
    /// 候选顺序按「越保守越靠前」排列，命中即止。
    static func parseOCR(_ raw: String) -> PickupParseResult? {
        for candidate in OCRTextNormalizer.candidates(raw) {
            if let parsed = parse(candidate) { return parsed }
        }
        return nil
    }

    // MARK: - 一次多条

    /// 把一段文本切成若干「独立短信段」。
    ///
    /// **为什么需要**：一次粘贴常常就是好几条短信（从短信 App 多选复制），
    /// 一张截图里也常有 2–4 条。`parseOCR` 是「命中第一条就收工」，
    /// 拿它处理这种输入会把后面的全丢掉。
    ///
    /// **切法**：快递短信几乎都以「【品牌】」起头，所以
    /// - 以「【」开头的行 → 开启新的一段；
    /// - 不以「【」开头的行 → 视作**上一条的视觉折行**，直接接回去（不加空格）。
    ///
    /// 第二条规则是关键：OCR 在视觉折行处会插 `\n`，如果见换行就切，
    /// 一条短会被误切成两条半截的，反而全都解析不出来。
    static func segments(_ raw: String) -> [String] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return [] }

        // 没有任何一行以「【」起头 → 不是「多条」的形态，整体当一条处理
        // （可能是单行裸码，也可能是完全不带品牌括号的短信）。
        guard lines.contains(where: { $0.hasPrefix("【") }) else {
            return [normalized.trimmingCharacters(in: .whitespacesAndNewlines)]
        }

        var out: [String] = []
        var current = ""
        for line in lines {
            if line.hasPrefix("【") {
                if !current.isEmpty { out.append(current) }
                current = line
            } else {
                current = current.isEmpty ? line : current + line
            }
        }
        if !current.isEmpty { out.append(current) }

        return out
    }

    /// 解析整段文本，返回**全部**可识别的取件信息（顺序 = 出现顺序）。
    ///
    /// `ocrSource` 决定段内是否要走 OCR 的多假设归一：
    /// 短信原文的换行是语义换行，直接解析即可；截图 / 相册来的换行多是视觉折行，
    /// 必须先归一。两者在这一层分开，是因为**切段**规则对它们是一样的。
    ///
    /// `fallback` = **非快递场景的兜底解析器**（当前是出行）。
    ///
    /// 它只在**同一个候选文本的快递公式全部落空之后**才被调用，顺序严格是
    /// 「先快递、后兜底」，因此快递用户看到的结果与不传它时逐位一致 ——
    /// 这条不变量由 tools/parser-regression 守着。
    /// 传 `nil`（默认）时行为与改动前完全相同。
    static func parseAll(_ raw: String,
                         ocrSource: Bool,
                         fallback: ((String) -> PickupParseResult?)? = nil) -> [PickupParseResult] {
        var results: [PickupParseResult] = []
        for segment in segments(raw) {
            let candidates = ocrSource ? OCRTextNormalizer.candidates(segment) : [segment]
            for candidate in candidates {
                if let parsed = parse(candidate) {
                    results.append(parsed)

                    // 🔴 一码多件（「取货码0909-0022、0909-0014」）：
                    //    主公式只吃第一段，把链上其余的码逐个补成独立结果 ——
                    //    与首条同平台 / 同地址，落库后各自成行、各自去重。
                    //    仅当主凭证就是取件码时才展开，避免误伤运单号 / 尾号。
                    if parsed.kind == .code,
                       let parts = codeChainParts(in: candidate), parts.count >= 2,
                       parts[0] == parsed.value {
                        for extra in parts.dropFirst() where extra != parsed.value {
                            var copy = parsed
                            copy.value = extra
                            results.append(copy)
                        }
                    }
                    break
                }
                if let extra = fallback?(candidate) {
                    results.append(extra)
                    break
                }
            }
        }
        return results
    }
}

// MARK: - OCR 文本归一化

enum OCRTextNormalizer {

    /// 生成候选文本。顺序即优先级。
    static func candidates(_ raw: String) -> [String] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        let unwrapped = text.replacingOccurrences(of: "\n", with: "")
        let spaced = text.replacingOccurrences(of: "\n", with: " ")

        var out: [String] = [text]
        out.append(contentsOf: splitByBrandBracket(unwrapped))
        out.append(unwrapped)
        out.append(spaced)

        // 保序去重
        var seen = Set<String>()
        return out.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// 按「【」切段。
    ///
    /// 快递短信几乎都以【 开头，所以一张截图里若有两条以上短信，切完自然分段 ——
    /// 段内公式的「读到句号或结尾」就不会一路读到下一条短信上去。
    /// 段内同样要去折行，理由见 `parseOCR` 的说明。
    private static func splitByBrandBracket(_ text: String) -> [String] {
        var pieces: [String] = []
        var current = ""

        for character in text {
            if character == "【", !current.isEmpty {
                pieces.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { pieces.append(current) }

        return pieces
    }
}
