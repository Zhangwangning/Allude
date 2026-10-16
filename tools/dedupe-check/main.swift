// 合并策略（同码再进）回归自检 —— 独立运行，不进 App target
//
// 用法：
//   swiftc -O -o /tmp/dedupe-check \
//     "/Volumes/ZWN/Downloads/Project/CodeClip/CodeClip/CodeClipShared/PickupModels.swift" \
//     "/Volumes/ZWN/Downloads/Project/CodeClip/CodeClip/CodeClipShared/CourierBrand.swift" \
//     "/Volumes/ZWN/Downloads/Project/CodeClip/CodeClip/CodeClipShared/BrandPalette.swift" \
//     "/Volumes/ZWN/Downloads/Project/CodeClip/tools/dedupe-check/main.swift"
//   /tmp/dedupe-check
//
// 断言的语义（2026-09-21 主人要求）：
//   「软件如果收到相同的取件码信息的短信，就要自动完成上一条，新增这一条」
// 即：同码再进 → 旧条转「已取件」+ 新条入列，**不再**当作重复直接丢弃。

import Foundation
import SwiftUI

// 回归工具只编 shared 层的模型与品牌表；`Color(hex:)` 的正规实现在 App target 的
// DesignSystem.swift 里（依赖大量 UI 代码，不适合拖进来）。这里补一份等价实现，
// 仅供本工具编译通过 —— 颜色本身不参与合并策略的任何断言。
extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0,
                  opacity: 1.0)
    }
}

var failures = 0
var checks = 0

func expect(_ condition: Bool, _ label: String, detail: String = "") {
    checks += 1
    if condition {
        print("  ✅ \(label)")
    } else {
        failures += 1
        print("  ❌ \(label)\(detail.isEmpty ? "" : "  →  \(detail)")")
    }
}

func make(_ company: String, _ code: String, _ address: String,
          kind: PickupKind = .code, picked: Bool = false) -> PickupRecord {
    PickupRecord(company: company, code: code, kind: kind, address: address,
                 rawMessage: "【\(company)】取件码 \(code)", receivedAt: Date(),
                 isPickedUp: picked)
}

func marks(_ list: [PickupRecord]) -> String {
    list.map { "\($0.code)\($0.isPickedUp ? "(已取)" : "(待取)")" }.joined(separator: " → ")
}

print("=== 合并策略（同码再进）回归自检 ===\n")

// ── 用例 1：核心语义 —— 同码再进，旧条自动完成 + 新条入列
do {
    print("① 同码再进 → 自动完成上一条 + 新增这一条")
    let old = make("兔喜生活", "C-4082", "舜耕中路104号惠鲜果蔬店")
    let new = make("兔喜生活", "C-4082", "舜耕中路104号惠鲜果蔬店")
    let r = PickupMerge.merge([old], with: [new])
    expect(r.added.count == 1, "新增 1 条（不再被丢弃）", detail: "实际 \(r.added.count)")
    expect(r.completed == ["C-4082"], "旧条记为已自动完成", detail: "\(r.completed)")
    expect(r.records.count == 2, "列表 2 条（历史 1 + 最新 1）", detail: "实际 \(r.records.count)")
    expect(r.records[0].isPickedUp, "旧条已转为已取件", detail: marks(r.records))
    expect(!r.records[1].isPickedUp, "新条为待取件", detail: marks(r.records))
    print("     最终：\(marks(r.records))")
}

// ── 用例 2：已经取过件的同码，不再被二次翻动
do {
    print("\n② 已取件的同码旧条不被翻动")
    let old = make("菜鸟驿站", "8-2-109", "馨月湖小区南门菜鸟驿站", picked: true)
    let new = make("菜鸟驿站", "8-2-109", "馨月湖小区南门菜鸟驿站")
    let r = PickupMerge.merge([old], with: [new])
    expect(r.completed.isEmpty, "不产生「自动完成」记录", detail: "\(r.completed)")
    expect(r.records[0].isPickedUp, "历史条保持已取件")
    expect(!r.records[1].isPickedUp, "新条为待取件")
}

// ── 用例 3：不同取件码互不干扰
do {
    print("\n③ 不同取件码各自独立")
    let a = make("申通快递", "16-4-6683", "临沂大学申通快递")
    let b = make("申通快递", "9-15-34", "惠旺家便利店")
    let r = PickupMerge.merge([a], with: [b])
    expect(r.completed.isEmpty, "无自动完成")
    expect(r.records.count == 2 && !r.records[0].isPickedUp && !r.records[1].isPickedUp,
           "两条均为待取件", detail: marks(r.records))
}

// ── 用例 4：同一批里出现两次同码
do {
    print("\n④ 同一批内同码两次（一条输入含多条短信）")
    let b1 = make("兔喜生活", "260108", "甘州院子南门馨月湖南门兔喜生活")
    let b2 = make("兔喜生活", "260108", "甘州院子南门馨月湖南门兔喜生活")
    let r = PickupMerge.merge([], with: [b1, b2])
    expect(r.added.count == 2, "两条都写入", detail: "实际 \(r.added.count)")
    expect(r.completed == ["260108"], "先写入的那条被自动完成", detail: "\(r.completed)")
    expect(r.records[0].isPickedUp && !r.records[1].isPickedUp,
           "批内先写的那条转已取、后写的是待取", detail: marks(r.records))
}

// ── 用例 5：地址不同 → 不算同一件
do {
    print("\n⑤ 取件码相同但地址不同 → 两条并存")
    let a = make("韵达快递", "0425-0007", "馨月湖小区南门兴裕隆超市")
    let b = make("韵达快递", "0425-0007", "甘州区滨河新区屋兰路82号")
    let r = PickupMerge.merge([a], with: [b])
    expect(r.completed.isEmpty, "不触发自动完成（指纹含地址）")
    expect(r.records.count == 2 && !r.records[0].isPickedUp && !r.records[1].isPickedUp,
           "两条均待取", detail: marks(r.records))
}

// ── 用例 6：类别不同 → 不算同一条
do {
    print("\n⑥ 凭证相同但类别不同 → 两条并存")
    let a = make("中国邮政", "0412", "投递中", kind: .tail)
    let b = make("中国邮政", "0412", "投递中", kind: .waybill)
    let r = PickupMerge.merge([a], with: [b])
    expect(r.completed.isEmpty, "不触发自动完成（指纹含类别）")
    expect(r.records.count == 2, "两条并存", detail: marks(r.records))
}

// ── 用例 7：既有顺序保持，新增追加在末尾
do {
    print("\n⑦ 既有顺序不变，新条追加在末尾")
    let a = make("中通快递", "1-1-9069", "旭辉御府")
    let b = make("韵达快递", "7-3-1141", "旭辉御府13栋102")
    let c = make("中通快递", "1-1-9069", "旭辉御府")
    let r = PickupMerge.merge([a, b], with: [c])
    expect(r.records.map(\.code) == ["1-1-9069", "7-3-1141", "1-1-9069"],
           "顺序 = 既有(2 条，原序) + 新增(1 条)", detail: r.records.map(\.code).joined(separator: " → "))
    expect(r.records[1].code == "7-3-1141" && !r.records[1].isPickedUp,
           "中间那条不受影响")
}

// ── 用例 8：多条混合（现实场景：一次粘贴 3 条短信，其中 1 条同码）
do {
    print("\n⑧ 混合场景：3 条新短信，其中 1 条与既有同码")
    let old = make("兔喜生活", "230376", "甘州院子南门馨月湖南门兔喜生活")
    let n1 = make("兔喜生活", "230376", "甘州院子南门馨月湖南门兔喜生活")
    let n2 = make("圆通速递", "0587", "北门架子上")
    let n3 = make("中通快递", "0629-8032", "门卫快递收发室")
    let r = PickupMerge.merge([old], with: [n1, n2, n3])
    expect(r.added.count == 3, "3 条全部写入", detail: "实际 \(r.added.count)")
    expect(r.completed == ["230376"], "仅同码那条触发自动完成", detail: "\(r.completed)")
    expect(r.records.count == 4, "列表共 4 条", detail: "实际 \(r.records.count)")
    let pending = r.records.filter { !$0.isPickedUp }.count
    expect(pending == 3, "待取 3 件", detail: "实际 \(pending)")
}

print("\n=== 汇总 ===")
print("断言 \(checks) 项，失败 \(failures) 项")
if failures == 0 {
    print("✅ 合并策略符合「同码再进 → 自动完成上一条 + 新增这一条」")
} else {
    print("❌ 有 \(failures) 项不符合预期")
}
exit(failures == 0 ? 0 : 1)
