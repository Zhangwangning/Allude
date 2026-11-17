import Foundation
import WidgetKit

// MARK: - 驿站 ID 登记表（2026-11-17 主人定稿：全驿站 ID 化）
//
// 老大定下的三种前缀：
// ```
// 内置驿站    NZYZ00001、NZYZ00002 ……
// 用户添加    DZYYZ00001、DZYYZ00002、DZYYZ00003 ……
// 分组驿站    FZYD00001、FZYD00002 ……
// ```
//
// 🔴 首次发号**落盘固化**，之后只往末尾追加。
//    为什么不能按数组下标实时算：内置清单是从 `CourierBrand.table` 过滤出来的，
//    中间插一个品牌会让后面所有驿站的 ID 整体后移，已经挂在这些 ID 上的组关系
//    会全部错位（表现为「组里换成了别的驿站」）。
//
// 表落在 **App Group 容器**里（不是 `UserDefaults.standard`）：桌面小组件与
// 灵动岛是两个独立扩展进程，都要按同一份映射做 resolve。

enum StationIdentity {

    /// 三类 ID 前缀
    enum Kind: String {
        case builtin = "NZYZ"
        case custom  = "DZYYZ"
        case group   = "FZYD"
    }

    struct File: Codable {
        /// 驿站名 → 驿站 ID（内置 + 自定义合并一张表）
        var names: [String: String] = [:]
        var nextBuiltin: Int = 1
        var nextCustom: Int = 1
        var nextGroup: Int = 1
    }

    private static let fileName = "station-identity.json"

    private static var fileURL: URL {
        PickupStorage.directory.appendingPathComponent(fileName)
    }

    /// 内存快照。落盘一次读一次，之后走这个（列表渲染时 `displayName` 每条记录都要查）。
    private static var snapshot: File?

    // MARK: 读写

    static func current() -> File {
        if let snapshot { return snapshot }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(File.self, from: data) else {
            let empty = File()
            snapshot = empty
            return empty
        }
        snapshot = decoded
        return decoded
    }

    private static func write(_ file: File) {
        snapshot = file
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func invalidate() {
        snapshot = nil
    }

    // MARK: 查询

    /// 驿站名 → 驿站 ID。没登记过返回 nil（调用方应当回落「按名字处理」）
    static func id(for name: String) -> String? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return current().names[key]
    }

    /// 驿站 ID → 驿站名
    static func name(for id: String) -> String? {
        current().names.first { $0.value == id }?.key
    }

    /// 全部登记项（名字 → ID），供上层做反查
    static func allNames() -> [String: String] {
        current().names
    }

    static func isGroupID(_ id: String) -> Bool {
        id.hasPrefix(Kind.group.rawValue)
    }

    // MARK: 发号

    /// 分配一个新的组 ID（每次调用都递增，即使中途放弃建组也不复用 —— 复用会让
    /// 已经删掉的组留下的位置 / 图标文件被新组认领）
    static func issueGroupID() -> String {
        var file = current()
        let id = String(format: "\(Kind.group.rawValue)%05d", file.nextGroup)
        file.nextGroup += 1
        write(file)
        return id
    }

    /// 把内置 / 自定义清单同步进登记表（**只在主 App 调用**，扩展进程只读）。
    ///
    /// · 内置：没 ID 的追加末尾；品牌表里删掉的名称**保留**登记（历史记录还能对上号）
    /// · 自定义：没 ID 的追加；已被用户删掉的**摘除**（避免幽灵条目占着号）
    static func sync(builtins: [String], customs: [String]) {
        var file = current()
        var changed = false

        for name in builtins where file.names[name] == nil {
            file.names[name] = String(format: "\(Kind.builtin.rawValue)%05d", file.nextBuiltin)
            file.nextBuiltin += 1
            changed = true
        }

        for name in customs where file.names[name] == nil {
            file.names[name] = String(format: "\(Kind.custom.rawValue)%05d", file.nextCustom)
            file.nextCustom += 1
            changed = true
        }

        // 自定义驿站被删 → 摘掉登记。先收集再删，别在遍历时改字典。
        let customSet = Set(customs)
        let stale = file.names.compactMap { name, id -> String? in
            (id.hasPrefix(Kind.custom.rawValue) && !customSet.contains(name)) ? name : nil
        }
        for name in stale {
            file.names.removeValue(forKey: name)
            changed = true
        }

        if changed { write(file) }
    }

    /// 自定义驿站改名：ID 跟着名字走，组关系（挂 ID）因此不会断
    static func rename(_ from: String, to: String) {
        let old = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !old.isEmpty, !new.isEmpty, old != new else { return }
        var file = current()
        guard let id = file.names.removeValue(forKey: old) else { return }
        file.names[new] = id
        write(file)
    }

    /// 自定义驿站删除
    static func remove(_ name: String) {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var file = current()
        guard file.names.removeValue(forKey: key) != nil else { return }
        write(file)
    }
}

// MARK: - 驿站组（2026-11-17 主人：组驿站 = 一个全新的驿站）
//
// 主人的原话拆成可执行的口径：
// ```
// ① 组是一个**一等公民驿站**，有自己的名称 / 图标 / 位置；
// ② 名称、图标、位置三项**各自独立**，可以自定义，也可以「只从某一个成员继承」；
// ③ 一个驿站只能进一个组；组不能套组；
// ④ 成员被归组后不再单独显示（待取 / 已取），但实体还在，随时可以退出；
// ⑤ 卡面副名显示「新组/原始匹配驿站」。
// ```
//
// 🔴 组关系挂 **成员 ID**，不挂名字 —— 成员改名（`StationIdentity.rename`）
//    会带着 ID 一起走，组里不会出现幽灵成员。

struct StationGroup: Codable, Identifiable, Hashable {
    var id: String
    /// 组名（全站唯一：不能与内置驿站、自定义驿站、其它组同名）
    var name: String
    /// 成员驿站 ID（`NZYZ…` / `DZYYZ…`）
    var memberIDs: [String]
    var createdAt: Date

    /// 图标来源：nil = 用组自己的（自定义图 / 名称首字兜底）；
    /// 非 nil = 继承该成员驿站的图标
    var iconInheritMemberID: String?

    /// 位置来源：nil = 用组自己的位置（存在 `StationLocationStore`，key = 组名）；
    /// 非 nil = 继承该成员驿站的位置
    var locationInheritMemberID: String?
}

enum StationGroupStore {

    private static let fileName = "station-groups.json"

    private static var fileURL: URL {
        PickupStorage.directory.appendingPathComponent(fileName)
    }

    /// 成员名 → 组名 的内存索引。列表渲染会给每条记录查一次，必须缓存。
    private static var cachedMemberIndex: [String: String]?

    /// `all()` 的缓存。
    /// 🔴 必须缓存：`StationLogo` 每画一个格子都会问「这是不是一个组」，
    ///    驿站管理页 30+ 个格子、待取页每张卡一个图标 —— 每次都读文件解码会直接卡成幻灯片。
    private static var cachedGroups: [StationGroup]?

    // MARK: 读写

    static func all() -> [StationGroup] {
        if let cachedGroups { return cachedGroups }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([StationGroup].self, from: data) else {
            cachedGroups = []
            return []
        }
        cachedGroups = decoded
        return decoded
    }

    static func save(_ groups: [StationGroup]) {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        try? data.write(to: fileURL, options: .atomic)
        cachedGroups = groups
        invalidateCache()
    }

    static func invalidateCache() {
        cachedMemberIndex = nil
        cachedGroups = nil
    }

    // MARK: 派生索引

    /// 成员驿站名 → 组名。
    ///
    /// 走「成员 ID → 成员名」反查，所以成员改名后自动跟到新名字上，
    /// 不需要任何字符串迁移。
    static func memberIndex() -> [String: String] {
        if let cachedMemberIndex { return cachedMemberIndex }

        let names = StationIdentity.allNames()
        var idToName: [String: String] = [:]
        for (name, id) in names where idToName[id] == nil {
            idToName[id] = name
        }

        var map: [String: String] = [:]
        for group in all() {
            for memberID in group.memberIDs {
                if let memberName = idToName[memberID] {
                    map[memberName] = group.name
                }
            }
        }
        cachedMemberIndex = map
        return map
    }

    /// 记录里的驿站名 → 该显示的名字（被归组就是组名，否则原名）。
    /// 空串原样返回（上层会换成「未标注驿站」）。
    static func displayName(for stationName: String) -> String {
        let name = stationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return name }
        return memberIndex()[name] ?? name
    }

    /// 若这个驿站已被归组，返回组名；否则 nil
    static func memberGroupName(for stationName: String) -> String? {
        let name = stationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return memberIndex()[name]
    }

    static func group(named name: String) -> StationGroup? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return all().first { $0.name == key }
    }

    static func group(id: String) -> StationGroup? {
        all().first { $0.id == id }
    }

    /// 某个成员驿站当前属于哪个组（按成员 ID 查）
    static func group(containingMemberNamed name: String) -> StationGroup? {
        guard let memberID = StationIdentity.id(for: name) else { return nil }
        return all().first { $0.memberIDs.contains(memberID) }
    }

    /// 组内成员的驿站名（按成员 ID 反查，顺序与保存时一致）
    static func memberNames(of group: StationGroup) -> [String] {
        group.memberIDs.compactMap { StationIdentity.name(for: $0) }
    }

    /// 还没被任何组收编的驿站名
    static func ungroupedNames(in candidates: [String]) -> [String] {
        let index = memberIndex()
        return candidates.filter { index[$0] == nil }
    }

    /// 已被归组的驿站名
    static func groupedNames(in candidates: [String]) -> [String] {
        let index = memberIndex()
        return candidates.filter { index[$0] != nil }
    }

    // MARK: 校验

    /// 组名唯一性：不能与内置驿站 / 自定义驿站 / 其它组同名。
    /// `excluding` 传自己（改名时允许保留原名）。
    static func isValidGroupName(_ raw: String,
                                 excluding id: String?,
                                 builtinAndCustom names: [String]) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        if names.contains(name) { return false }
        return !all().contains { $0.name == name && $0.id != id }
    }

    // MARK: 增删改

    @discardableResult
    static func create(name: String,
                       memberIDs: [String],
                       iconInheritMemberID: String? = nil,
                       locationInheritMemberID: String? = nil) -> StationGroup? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var groups = all()
        guard !groups.contains(where: { $0.name == trimmed }) else { return nil }

        let group = StationGroup(id: StationIdentity.issueGroupID(),
                                 name: trimmed,
                                 memberIDs: memberIDs,
                                 createdAt: Date(),
                                 iconInheritMemberID: iconInheritMemberID,
                                 locationInheritMemberID: locationInheritMemberID)
        groups.append(group)
        save(detach(group, in: groups))
        StationGroupLocationBridge.syncRegions()
        return group
    }

    /// 更新组（同时把成员从别的组里摘掉 —— 一个驿站只能进一个组）
    static func update(_ group: StationGroup) {
        var groups = all()
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index] = group
        save(detach(group, in: groups))
        // 组的名字 / 成员 / 位置来源任何一项变了，围栏都可能要重排
        StationGroupLocationBridge.syncRegions()
    }

    /// 把 `group.memberIDs` 从其它组的成员表里移除
    private static func detach(_ group: StationGroup, in groups: [StationGroup]) -> [StationGroup] {
        let owned = Set(group.memberIDs)
        return groups.map { other -> StationGroup in
            guard other.id != group.id else { return other }
            var copy = other
            copy.memberIDs = other.memberIDs.filter { !owned.contains($0) }
            if let inherit = copy.iconInheritMemberID, owned.contains(inherit) {
                copy.iconInheritMemberID = nil
            }
            if let inherit = copy.locationInheritMemberID, owned.contains(inherit) {
                copy.locationInheritMemberID = nil
            }
            return copy
        }
    }

    /// 某个成员驿站被删 / 被解除归组：从所有组里摘掉它。
    /// 不摘会留下一个「反查不到名字的 ID」—— 它不再影响显示，但会占着组的成员数。
    static func dropMember(stationID: String) {
        var groups = all()
        var changed = false
        for index in groups.indices {
            if groups[index].memberIDs.contains(stationID) {
                groups[index].memberIDs.removeAll { $0 == stationID }
                changed = true
            }
            if groups[index].iconInheritMemberID == stationID {
                groups[index].iconInheritMemberID = nil
                changed = true
            }
            if groups[index].locationInheritMemberID == stationID {
                groups[index].locationInheritMemberID = nil
                changed = true
            }
        }
        guard changed else { return }
        save(groups)
        StationGroupLocationBridge.syncRegions()
    }

    /// 解散组：成员原地恢复独立显示（`memberIndex` 里没有它们了，天然回落原名）。
    /// 组的自定义图标文件与位置一起清掉，别留孤儿。
    static func delete(id: String) {
        var groups = all()
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        let removed = groups.remove(at: index)
        save(groups)
        StationGroupAppearanceBridge.cleanUp(removed)
        StationGroupLocationBridge.syncRegions()
    }

    // MARK: 图标 / 位置继承

    /// 组当前实际取图标的驿站名：继承成员优先，否则返回组名（组自己的自定义图 /
    /// 名称首字兜底都在 `StationLogo` 里处理）
    static func iconSourceName(for group: StationGroup) -> String {
        if let memberID = group.iconInheritMemberID,
           let memberName = StationIdentity.name(for: memberID) {
            return memberName
        }
        return group.name
    }

    /// 组当前实际读位置的 key：继承成员优先，否则组名
    static func locationSourceName(for group: StationGroup) -> String {
        if let memberID = group.locationInheritMemberID,
           let memberName = StationIdentity.name(for: memberID) {
            return memberName
        }
        return group.name
    }
}

// MARK: - 与 App 层（图标 / 位置 / 围栏）的桥
//
// `StationDirectory`、`StationLocationStore`、`StationLocationService` 都在 App target，
// 而本文件要给小组件一起编译 —— 所以只留协议式的挂点，App 启动时把实现塞进来。

enum StationGroupAppearanceBridge {
    /// 由 App 启动时注册：删组后清掉该组自己的图标文件与位置
    static var cleanUp: (StationGroup) -> Void = { _ in }
}

enum StationGroupLocationBridge {
    /// 由 App 启动时注册：组的位置来源变了要重排围栏
    static var syncRegions: () -> Void = {}
}

// MARK: - 驿站内排序（2026-11-17 主人定稿）
//
// 「根据取件码的大小排序，如果取件码存在英文，则由 A-Z / Z-A，数字 0-9 / 9-0，
//   就从取件码的从左至右一位一位去比较排序」
//
// 即**逐字符字典序**，不是数值序：
//   `8-4-1005` < `8-4-3019` < `8-4-999`
// Swift 的 `String <` 正好符合需要的字符权重（`-` 0x2D < `0` 0x30 < `A` 0x41），
// 前缀相同时短的在前 —— 直接用即可，不必自己写比较器。
//
// ⚠️ 只在「按快递驿站」分组模式下起作用（老大明确过）。

enum StationInnerOrder: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case codeAsc
    case codeDesc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest:   "收到时间 · 新→旧"
        case .oldest:   "收到时间 · 旧→新"
        case .codeAsc:  "取件码 · 0→9、A→Z"
        case .codeDesc: "取件码 · 9→0、Z→A"
        }
    }

    private static let key = "allude.station.innerOrder"

    static var current: StationInnerOrder {
        let raw = PickupStorage.sharedDefaults.string(forKey: key)
        return raw.flatMap(StationInnerOrder.init(rawValue:)) ?? .newest
    }

    static func set(_ order: StationInnerOrder) {
        PickupStorage.sharedDefaults.set(order.rawValue, forKey: key)
        // 待取页、桌面小组件、灵动岛都按这套排，写完立刻重画
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 驿站**内部**的先后判定（外部由调用方按驿站名分桶）。
    ///
    /// `moment` 让调用方决定「时间」用哪个时刻：待取页一直按 `lastNotifiedAt`
    /// （最后一次通知）排，已取页与小组件按 `receivedAt`（收到时间）排 ——
    /// 两套口径本来就有，这里不强行统一，由调用方传。
    func isOrderedBefore(_ a: PickupRecord,
                         _ b: PickupRecord,
                         moment: (PickupRecord) -> Date = { $0.receivedAt }) -> Bool {
        switch self {
        case .newest:
            return moment(a) > moment(b)
        case .oldest:
            return moment(a) < moment(b)
        case .codeAsc, .codeDesc:
            switch PickupCodeOrder.compare(a.code, b.code) {
            case .before: return self == .codeAsc
            case .after:  return self == .codeDesc
            // 同码（或空码）回落时间倒序，保证排序稳定、不会每帧跳
            case .same:   return moment(a) > moment(b)
            }
        }
    }
}

// MARK: - 取件码的自然排序（2026-11-17 主人）

/// 取件码排序的**唯一口径**。
///
/// 🔴 以前是把码大写后直接做字符串比较 —— 逐字符比，于是：
/// ```
///   8-4-1005  <  8-4-999     ← 因为 '1' < '9'，但 1005 明显大于 999
///   110226    <  90050       ← 同理，'1' < '9'
/// ```
/// 主人 2026-11-17 指正：数字就该按数值比，一段一段比。
///
/// 规则（三种形态统一成一套）：
/// · 纯数字 `110226`：一个数字段，比数值；
/// · 带连接符 `8-4-1005`：数字段 `8` / `4` / `1005`，从左到右逐段比数值；
/// · 带字母 `YT169555`：字母段 `YT` 比字典序，再比后面的数字段 `169555`。
///
/// 分隔符（`-` `_` `/` 空格…）**只起分段作用，不参与比较** ——
/// `8-4-1005` 与 `8 4 1005` 视为同形。数字段排在字母段之前
/// （与 ASCII 里数字小于大写字母一致），所以 `8-4-1005` 会排在 `YT169555` 前面。
enum PickupCodeOrder {

    /// 三态比较结果。自带一个而不用 `ComparisonResult` —— 这个类型要被
    /// App 与 Widget 两个 target 共用，不依赖 Foundation 的桥接类型更省心。
    enum Order {
        case before, same, after
    }

    private enum Piece: Equatable {
        case digits(String)
        case letters(String)
    }

    /// 把码切成「字母段 / 数字段」交替的序列。
    ///
    /// ⚠️ 只用 ASCII 的 `isNumber` / `isLetter` 判断：`Character.isNumber` 对
    /// 罗马数字、全角数字也返回 true，会把它们混进数字段算出奇怪的顺序。
    private static func pieces(_ code: String) -> [Piece] {
        var out: [Piece] = []
        var buffer = ""
        var bufferIsDigits: Bool?

        func flush() {
            guard !buffer.isEmpty, let isDigits = bufferIsDigits else { return }
            out.append(isDigits ? .digits(buffer) : .letters(buffer))
            buffer = ""
        }

        for ch in code.uppercased() {
            let isDigits = ch.isASCII && ch.isNumber
            let isLetters = ch.isASCII && ch.isLetter
            if isDigits || isLetters {
                if let current = bufferIsDigits, current != isDigits { flush() }
                bufferIsDigits = isDigits
                buffer.append(ch)
            } else {
                // 分隔符：把当前段收尾，自己丢掉
                flush()
                bufferIsDigits = nil
            }
        }
        flush()
        return out
    }

    /// 数字段比较：**去前导零后先比位数、再比字典序**。
    /// 这样既等价于比数值，又不会在超长数字上溢出 Int。
    private static func compareDigits(_ x: String, _ y: String) -> Order {
        let a = x.drop(while: { $0 == "0" })
        let b = y.drop(while: { $0 == "0" })
        if a.count != b.count { return a.count < b.count ? .before : .after }
        if a == b { return .same }
        return a < b ? .before : .after
    }

    static func compare(_ lhs: String, _ rhs: String) -> Order {
        let a = pieces(lhs)
        let b = pieces(rhs)

        for index in 0..<min(a.count, b.count) {
            switch (a[index], b[index]) {
            case let (.digits(x), .digits(y)):
                let result = compareDigits(x, y)
                if result != .same { return result }
            case let (.letters(x), .letters(y)):
                if x != y { return x < y ? .before : .after }
            case (.digits, .letters):
                return .before
            case (.letters, .digits):
                return .after
            }
        }

        if a.count != b.count {
            return a.count < b.count ? .before : .after
        }
        // 分段后完全同形（例如仅分隔符不同）：回落原文，保证全序、排序稳定
        if lhs == rhs { return .same }
        return lhs < rhs ? .before : .after
    }
}
