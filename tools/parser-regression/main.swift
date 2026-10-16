// 解析引擎回归脚本（独立运行，不进 App target）
//
// 用法：
//   swiftc -O -o /tmp/parser-regression \
//     "/Volumes/ZWN/Downloads/Project/CodeClip/CodeClip/CodeClip/Models/PickupParser.swift" \
//     /Volumes/ZWN/Downloads/Project/CodeClip/tools/parser-regression.swift
//   /tmp/parser-regression "/Volumes/ZWN/Downloads/Project/shortcuts-toolkit-master/快递取件码短信库.md"
//
// 说明：PickupParser 只依赖 Foundation，因此可与本文件单独编译，
// 不必构建整个 App —— 公式改动后可秒级回归。

import Foundation

// 解析引擎只需要 PickupKind 的类型名与 case，这里提供最小等价定义
enum PickupKind: String {
    case code, waybill, tail, special

    var label: String {
        switch self {
        case .code: "取件码"
        case .waybill: "运单号"
        case .tail: "尾号"
        case .special: "特殊取件码"
        }
    }
}

// MARK: - 读语料

let corpusPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "快递取件码短信库.md"

guard let corpus = try? String(contentsOfFile: corpusPath, encoding: .utf8) else {
    print("❌ 读不到语料文件：\(corpusPath)")
    exit(1)
}

// 语料支持两种形态（2026-09-21 扩容后语料改为纯行）：
//   ① 编号行 `12. 【xx】...`（历史格式）
//   ② 纯文本行  `【xx】...`（现行格式）
// 优先按编号解析；若一条都没解析到，退回「非空且非 Markdown 结构行」的纯行模式。
let numberedPattern = try! NSRegularExpression(pattern: #"^\s*\d+\.\s*(.+)$"#)
var cases: [String] = []
for line in corpus.split(separator: "\n", omittingEmptySubsequences: false) {
    let text = String(line)
    let range = NSRange(text.startIndex..., in: text)
    if let m = numberedPattern.firstMatch(in: text, range: range),
       let r = Range(m.range(at: 1), in: text) {
        cases.append(String(text[r]))
    }
}

if cases.isEmpty {
    // 纯行模式：跳过空行、标题行（#）、列表项（- / * / |）与代码围栏
    for line in corpus.split(separator: "\n", omittingEmptySubsequences: false) {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { continue }
        if text.hasPrefix("#") || text.hasPrefix("-") || text.hasPrefix("*")
            || text.hasPrefix("|") || text.hasPrefix(">") || text.hasPrefix("```") {
            continue
        }
        cases.append(text)
    }
}

// MARK: - 校验正则全部可编译

print("=== 正则编译自检 ===")
let patterns: [(String, String)] = [
    ("关键词", PickupParser.keywordPattern),
    ("取件码", PickupParser.codePattern),
    ("运单号", PickupParser.waybillPattern),
    ("尾号", PickupParser.tailPattern),
    ("特殊格式取件码", PickupParser.specialPattern),
    ("独立地址", PickupParser.standaloneAddressPattern),
    ("匹配地址", PickupParser.matchedAddressPattern),
    ("公司【】", PickupParser.companyBracketPattern),
    ("公司兜底", PickupParser.companyFallbackPattern),
]
var compileFailures = 0
for (name, pattern) in patterns {
    do {
        _ = try NSRegularExpression(pattern: pattern)
    } catch {
        compileFailures += 1
        print("  ❌ \(name) 编译失败：\(error.localizedDescription)")
    }
}
print(compileFailures == 0 ? "  ✅ 9/9 公式均可被 ICU 编译" : "  ⚠️ \(compileFailures) 条公式编译失败")

// MARK: - 逐条解析

print("\n=== 51 条语料解析结果 ===")
var kindCount: [String: Int] = [:]
var addressHit = 0
var standaloneAddressHit = 0
var unrecognized: [Int] = []
var seenValues: [String: Int] = [:]

for (index, sms) in cases.enumerated() {
    let serial = index + 1
    guard let result = PickupParser.parse(sms) else {
        unrecognized.append(serial)
        print(String(format: "%2d. ❌ 未识别", serial))
        continue
    }
    kindCount[result.kind.label, default: 0] += 1
    if !result.address.isEmpty { addressHit += 1 }
    seenValues[result.value, default: 0] += 1

    var extra: [String] = []
    if result.value.isEmpty { extra.append("⚠️值为空") }
    if result.address.isEmpty { extra.append("⚠️无地址") }
    let flag = extra.isEmpty ? "" : "  " + extra.joined(separator: " ")
    print(String(format: "%2d. [%@] %@  | %@  | %@%@",
                 serial, result.kind.label, result.value,
                 result.company, result.address, flag))
}

// 独立地址字段单独统计（parser 内部已优先使用，这里单独跑一遍看覆盖率）
let standaloneRegex = try! NSRegularExpression(pattern: PickupParser.standaloneAddressPattern)
for sms in cases {
    let range = NSRange(sms.startIndex..., in: sms)
    if standaloneRegex.firstMatch(in: sms, range: range) != nil { standaloneAddressHit += 1 }
}

// MARK: - 汇总

print("\n=== 汇总 ===")
print("语料条数：\(cases.count)")
print("识别成功：\(cases.count - unrecognized.count)/\(cases.count)")
if !unrecognized.isEmpty {
    print("未识别序号：\(unrecognized.map(String.init).joined(separator: ", "))")
}
print("类型分布：" + kindCount.sorted { $0.key < $1.key }
        .map { "\($0.key) \($0.value)" }.joined(separator: " / "))
print("地址提取：\(addressHit)/\(cases.count)（其中走独立「地址:」字段 \(standaloneAddressHit) 条）")
print("空值条数：\(seenValues[""] ?? 0)")

// 与 V7.3.0 基线对照
let baselineRecognized = 51
let baselineAddress = 50
let recognized = cases.count - unrecognized.count
print("\n=== 与 V7.3.0 基线对照 ===")
print("识别：\(recognized)/\(cases.count)（基线 \(baselineRecognized)/\(cases.count)）"
      + (recognized >= baselineRecognized ? "  ✅ 无回退" : "  ❌ 回退"))
print("地址：\(addressHit)/\(cases.count)（基线 \(baselineAddress)/\(cases.count)）"
      + (addressHit >= baselineAddress ? "  ✅ 无回退" : "  ⚠️ 需核对"))

exit(recognized >= baselineRecognized && compileFailures == 0 ? 0 : 2)
