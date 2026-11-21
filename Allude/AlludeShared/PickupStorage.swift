import Foundation
import WidgetKit

// MARK: - 本地持久化（App 写入 / 小组件读取）
//
// 设计要点：
//  1) **优先 App Group 容器**（`group.com.jikezhang.allude`），以便与小组件扩展共享数据；
//     未配置 entitlement 时自动回落 App 自身容器，不报错、不崩。
//  2) 纯本地、无网络、无第三方 SDK —— 与产品「所有数据仅保存在本机」的承诺一致。
//  3) 写入用 `.atomic`，避免进程被系统回收时留下半截文件。
//
// ⚠️ App Group 生效前提：两个 target 的 Signing & Capabilities 中都勾选同一个
//    App Group。代码层已做好回落，因此「未开通」只是不共享，不会崩。

enum PickupStorage {
    /// App Group 标识（需在 Signing & Capabilities 中开通后生效）
    static let appGroupID = "group.com.jikezhang.allude"

    private static let fileName = "pickup-records.json"

    /// 数据目录：App Group 优先，回落 Application Support
    static var directory: URL {
        let fm = FileManager.default
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return group.appendingPathComponent("Library/Application Support", isDirectory: true)
        }
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        return base
    }

    static var fileURL: URL { directory.appendingPathComponent(fileName) }

    /// 是否正在使用 App Group 共享容器
    static var isUsingAppGroup: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    /// 列表排序 / 分组的键：主 App 写、小组件读（2026-11-15 主人：
    /// 「桌面小组件优先让小组件跟随待取页的排序逻辑会更统一」）。
    static let listSortKey = "allude.list.sort"

    /// 共享偏好域：App Group 优先；小组件进程读同一个域。
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// 当前排序方式（未知值一律回落「最近收到」）。
    static var listSort: PickupSortLogic.Mode {
        let raw = sharedDefaults.string(forKey: listSortKey)
            ?? UserDefaults.standard.string(forKey: listSortKey)
        return raw.flatMap(PickupSortLogic.Mode.init(rawValue:)) ?? .newest
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func load() -> [PickupRecord] {
        // 🔴 2026-11-17 驿站组：App / 桌面小组件 / 灵动岛是三个进程，
        //    组关系与驿站 ID 表由主 App 写、扩展进程只读。读盘时一并让缓存失效，
        //    扩展下一次 resolve 就能拿到最新映射 —— 否则会出现
        //    「App 里把两个驿站归成一组了，桌面小组件还按老驿站分成两坨」。
        StationGroupStore.invalidateCache()
        StationIdentity.invalidate()

        guard let data = try? Data(contentsOf: fileURL) else {
            // 文件都还没有（首启）时，日志里也不可能有有效条目
            return []
        }
        let records = (try? decoder.decode([PickupRecord].self, from: data)) ?? []
        // 🔴 2026-11-16 状态回滚专项：读盘统一过一层增量日志。
        //    放在 `load()` 里而不是各调用点，是因为 App / 桌面小组件 / 灵动岛
        //    是三个独立进程，任何一处漏掉就会出现「这边 4、那边 5」。
        return WidgetToggleJournal.applying(to: records)
    }

    /// 数据文件是否**已存在**（哪怕内容是空数组）。
    ///
    /// 🔴 专门给 `PickupStore.init` 判断「是不是真首启」用（2026-10-25 审查发现）：
    /// 以前 init 用 `loaded.isEmpty` 判断，无法区分「文件不存在」与「文件存在但一条记录都没有」，
    /// 于是**用户把记录全删光、重启 App 后示例数据又全部回来了**（已实测复现：
    /// 把 json 写成 `[]` 再启动，文件立刻被写回 34829 字节的示例数据）。
    static var fileExists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    @discardableResult
    static func save(_ records: [PickupRecord]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
            // ⚠️ 刷新请求**不放在这里**：`PickupStore.persistSideEffects` 已经在
            //    写盘后统一调用 `reloadAllTimelines`，这里再加一次只会翻倍消耗
            //    系统给 App 的小组件刷新预算（每天几十次），预算耗尽后桌面反而更久不更新。
            return true
        } catch {
            return false
        }
    }

    /// 供设置页展示「已用存储」时使用
    static var fileSizeDescription: String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? Int else { return "—" }
        if size < 1024 { return "\(size) B" }
        return String(format: "%.1f KB", Double(size) / 1024)
    }
}

// MARK: - 免费版额度（App 与小组件扩展共读）
//
// 放在共享层而不是 `PickupStore` 里：**小组件扩展不编译 App target**，
// 拿不到 `PickupStore`，但它同样要按档位裁剪列表。

enum PickupLimits {
    /// 同屏展示上限（仅渲染裁剪，数据完整保留）。
    ///
    /// 🔴 2026-11-01 主人：**统一 4 条** —— 待取/已取列表与小组件都按 4 条裁。
    ///    仍是唯一定义点：App 侧 `PickupStore.freeVisibleLimit` 与小组件的
    ///    `WidgetSnapshot` 都引用它，改额度只改这里。
    static let freeVisible = 4
    /// 存储上限，超出后 FIFO 淘汰最旧
    ///
    /// 🔴 2026-11-20 更正：这里原先写 60，但**全 App 从来没有任何地方读过它**，
    ///    真正生效的是 `PickupStore.freeStorageLimit`（硬编码 50），
    ///    订阅页与设置页显示的也是 50。现在两处合成一处：App 侧的
    ///    `PickupStore.freeStorageLimit` 直接引用本常量，所以这里必须等于真实额度 50。
    ///    改额度只改这里（小组件与本机数据都看它）。
    static let freeStorage = 50
    /// 「不限量」的替代值。**不要用 `Int.max`**：`count - limit` 这类减法会溢出崩溃。
    static let unlimited = 9_999
    /// 小组件单次可翻动的最大条数。
    ///
    /// 小组件不是浏览器：几千条待办摊进 6 行一页会得出几百页，
    /// 用户按到手抽筋也翻不完，且每次翻页都要重读整份 JSON。
    /// 头部数字仍显示**真实总数**（`pendingTotal`），这里截的只是「可翻动的量」。
    static let widgetListCap = 60
}

// MARK: - 小组件勾选增量日志（2026-11-16 主人：状态回滚专项）
//
// 背景：`pickup-records.json` 里已经有完整记录，小组件勾选也确实写了它。
// 但主 App 后台持有的**内存副本**可能比磁盘旧，任何一次 `records` 赋值都会
// 把旧状态整份写回去（这就是「点完变 4 → 打开 App 变 5 → 回桌面又变 5」）。
// 只靠 records 文件挡不住这种覆盖，因为覆盖者写的也是「合法的完整数据」。
//
// 所以按主人的方案留一份**极小的增量标记**：一次勾选只追加一条 `{id, picked, at}`
// （几十字节），`load()` 时按时间戳重放。这样三端（App / 桌面小组件 / 灵动岛）
// 任何一处读盘都自带最新状态，无需各自再写一遍合并逻辑。
//
// 三个不变式：
//   · **幂等**：`at <= 记录 updatedAt` 的条目跳过 —— App 里后来做的操作永远优先；
//   · **自清理**：记录已反映该状态（`updatedAt >= at`）、记录已删除、或条目超过 7 天，
//     由 App 落库后删掉，列表不会无限膨胀；
//   · **轻量**：只存状态字段，不复制短信原文；写入是一次 atomic 小文件写。
enum WidgetToggleJournal {
    struct Entry: Codable, Hashable {
        var id: String
        var picked: Bool
        /// 秒级 Unix 时间戳。
        /// 🔴 不用 Date + iso8601：records 文件的 `updatedAt` 也是秒精度，
        ///    两边精度不一致会让「记录已反映状态」永远判不成立、日志清不掉。
        var at: TimeInterval
    }

    private static let fileName = "widget-toggles.json"
    private static let maxEntries = 200
    private static let ttl: TimeInterval = 7 * 24 * 60 * 60

    /// 把任意 Date 归一到 records 写盘后的精度（秒）
    private static func tick(_ date: Date) -> TimeInterval {
        date.timeIntervalSince1970.rounded(.down)
    }

    private static var fileURL: URL {
        PickupStorage.directory.appendingPathComponent(fileName)
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func load() -> [Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? decoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }

    private static func write(_ entries: [Entry]) {
        guard let data = try? encoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: PickupStorage.directory,
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// 追加一条勾选。同一记录反复点只保留最后一次（含时间戳）。
    static func append(id: UUID, picked: Bool, at: Date) {
        var entries = load().filter { $0.id != id.uuidString }
        entries.append(Entry(id: id.uuidString, picked: picked, at: tick(at)))
        // 只保留最近 N 条 + 未过期的；超出就丢最旧的（那些状态早已落库）
        let floor = tick(Date()) - ttl
        entries = entries.filter { $0.at >= floor }.suffix(maxEntries)
        write(Array(entries))
    }

    /// 把尚未反映到 records 里的勾选重放上去。
    ///
    /// 只改三个状态字段，其余字段一律以 records 为准 —— 日志不是数据源，
    /// 只是一层「别把桌面刚点的那一下弄丢」的护栏。
    static func applying(to records: [PickupRecord]) -> [PickupRecord] {
        let entries = load()
        guard !entries.isEmpty else { return records }
        var out = records
        for entry in entries {
            guard let index = out.firstIndex(where: { $0.id.uuidString == entry.id }) else { continue }
            let currentStamp = tick(out[index].updatedAt ?? out[index].receivedAt)
            guard entry.at > currentStamp else { continue }   // App 里的后续操作优先
            let stamp = Date(timeIntervalSince1970: entry.at)
            out[index].isPickedUp = entry.picked
            out[index].pickedUpAt = entry.picked ? (out[index].pickedUpAt ?? stamp) : nil
            out[index].updatedAt = stamp
        }
        return out
    }

    /// App 落库成功后调用：删掉已经被 records 反映掉的条目。
    ///
    /// 🔴 判断依据是 `updatedAt >= at`，**不是**「save 成功」——
    ///    万一某条路径写的仍是旧数据，这条标记必须留着，等下次读盘继续生效。
    static func consume(records: [PickupRecord]) {
        let before = load()
        guard !before.isEmpty else { return }
        let byID = Dictionary(records.map { ($0.id.uuidString, $0) },
                               uniquingKeysWith: { first, _ in first })
        let floor = tick(Date()) - ttl
        let remaining = before.filter { entry in
            guard entry.at >= floor, let record = byID[entry.id] else { return false }
            return tick(record.updatedAt ?? record.receivedAt) < entry.at
        }
        if remaining.count != before.count { write(remaining) }
    }
}

// MARK: - 小组件翻页状态
//
// 小组件**不支持原生滚动**（此结论已对 iOS 27 SDK 的 WidgetKit / SwiftUI 接口核实：
// 不存在任何滚动相关 API，且 Apple 在 Meet WidgetKit 中明确说明 List / ScrollView
// 在小组件内不滚动）。因此「上下翻动查看取件码」用 iOS 17+ 的可交互小组件实现：
// 头部放一个上/下翻页控件，点按写回页码再重画时间线。
//
// 页码按**尺寸**存：中尺寸一页 3 条、大尺寸一页 6 条，
// 共用同一个页码会出现「在中尺寸翻到第 3 页、切到大尺寸直接落在空白页」。
//
// ⚠️ 同一尺寸的多个实例仍共用同一份页码 —— WidgetKit 不对扩展暴露实例标识，
//    没有干净的办法区分「我桌上左边那个」和「右边那个」。可接受：
//    两个同分类同尺寸的小组件展示的本就是同一批数据。

enum WidgetPaging {
    private static let fileName = "widget-pages.json"

    private static var fileURL: URL {
        PickupStorage.directory.appendingPathComponent(fileName)
    }

    static func key(family: String) -> String {
        family
    }

    private static func loadAll() -> [String: Int] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    static func page(family: String) -> Int {
        max(0, loadAll()[key(family: family)] ?? 0)
    }

    static func setPage(_ page: Int, family: String) {
        var all = loadAll()
        all[key(family: family)] = max(0, page)
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? FileManager.default.createDirectory(at: PickupStorage.directory,
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - 小组件分页规格

/// 尺寸 → 一页放几行。放在共享层：翻页意图（写）与可视层（读）必须用同一张表，
/// 否则会出现「点一下翻过两页」这种位数对不上的错乱。
enum WidgetPageSize {
    /// 各尺寸一页的行数。超大尺寸（iPad）与 iPhone 竖版超大（iOS 27）高度不同，故分开取。
    static func rowCount(family: String) -> Int {
        switch family {
        case "s": 1
        case "m": 3
        // 🔴 2026-10-28 主人：大尺寸一页放 8 条（原 6）。
        case "l": 8
        case "xl": 6
        // 🔴 2026-10-28 主人：竖版超大 10 条偏少，「应该放 13–15 条」→ 取 **14**。
        //    行视图是 `.frame(maxHeight: .infinity)`，行高自适应拉伸，
        //    690pt 高 ÷ 14 行 ≈ 45pt/行，不会溢出。
        case "xlp": 14
        default: 3
        }
    }

    /// `WidgetFamily` → 稳定短标识。
    ///
    /// ⚠️ 不要用 `WidgetFamily.rawValue` 直接落盘：它是系统内部编号，换版本可能变，
    /// 一变旧页码就全部错位。这里用自己定的短串，只在本工程内部解释。
    static func key(_ family: WidgetFamily) -> String {
        switch family {
        case .systemSmall: "s"
        case .systemMedium: "m"
        case .systemLarge: "l"
        case .systemExtraLarge: "xl"
        case .systemExtraLargePortrait: "xlp"
        default: "m"
        }
    }

    /// 小组件注册的尺寸集 —— 参数化注册后四类小组件共用同一份。
    ///
    /// 🔴 2026-10-30 主人定：**免费版只给小 / 中两个尺寸**。
    ///    大尺寸与超大尺寸一屏 6–10 条，等于把「免费只看 3 条」的限制从桌面绕过去；
    ///    而且中尺寸一页正好 3 条，与 App 内的同屏上限对得上。
    ///
    /// 判定读小组件进程自己的 `EntitlementSnapshot.licensedPro`，不依赖主 App 运行。
    ///
    /// 🔴 **2026-11-11 内测反馈修复：一律注册全部尺寸，不再按档位裁剪。**
    ///    WidgetKit 在**注册时**就缓存了 `supportedFamilies`，买完 Pro 也不会
    ///    动态变大 —— 用户看到的现象就是「已购会员后仍然只有小/中两个尺寸」。
    ///    现在尺寸集固定为全部，免费用户在大尺寸里渲染「解锁 Codelumi Pro」占位
    ///    （见 `WidgetLockedContent`）；购买后小组件重新取时间线即可显示内容，
    ///    不需要删掉重加，也不需要重装 App。
    static var supportedFamilies: [WidgetFamily] {
        allFamilies
    }

    /// 付费档：全部尺寸。
    /// 🔴 部署目标已降到 iOS 26：`systemExtraLargePortrait`（竖版超大）是 iOS 27 新增，
    ///    低版本系统上取这个枚举会崩，所以按可用性拼装。
    private static var allFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium,
                                        .systemLarge, .systemExtraLarge]
        if #available(iOS 27.0, *) {
            families.append(.systemExtraLargePortrait)
        }
        return families
    }

    /// 免费档：只有小 / 中。
    static let freeFamilies: [WidgetFamily] = [.systemSmall, .systemMedium]

    /// 当前尺寸是否属于免费档（小 / 中）。大尺寸以上要 Pro。
    static func isFreeFamily(_ family: WidgetFamily) -> Bool {
        freeFamilies.contains(family)
    }

    /// 补位空槽的**数量上限**。
    ///
    /// 空槽的作用是「补齐一页」并稳定行高，不是「填满整块」。按缺几补几的话，
    /// 竖版超大尺寸（一页 10 行）里只有 5 条数据时会铺出 5 行鬼影，
    /// 半个屏幕都是灰条 —— 看起来像组件坏了，而不是「就这些了」。
    /// 2 个足够传达「还有空位」，多出来的空间交给行高自然撑开。
    static let maxPlaceholderRows = 2
}

// MARK: - 小组件展示快照
//
// 小组件进程与主 App 是两个独立进程且启动时机不可控，因此不能复用 PickupStore。
// 这里定义「小组件需要知道的最小事实」，由小组件在渲染时直接从 App Group 反序列化。

struct WidgetSnapshot {
    /// 待办，**已按档位裁剪**（免费 4 条 / 付费至多 60 条），按时间倒序。
    /// 分页是可视层的事：这里给「可以翻的全部」，由页面按尺寸切片。
    let items: [PickupRecord]
    /// 待办**真实总数**（不受裁剪影响）—— 头部数字必须显示这个，
    /// 否则「待取 3」会被误读为只有 3 件。
    let pendingTotal: Int
    let pickedTodayCount: Int
    /// 「一张卡片多个取件码」开启时，代表记录 ID → 同组其它码。
    /// 小组件一行画不下整组，所以主码后补几个小号码；头部计数仍是**真实件数**。
    var extraCodes: [String: [String]] = [:]

    static let empty = WidgetSnapshot(items: [], pendingTotal: 0, pickedTodayCount: 0)

    /// 从共享容器读取并裁剪。
    ///
    /// 档位由小组件**自己判定**（读 `EntitlementSnapshot`），不依赖主 App 是否运行 ——
    /// 用户重启手机后首先被系统唤醒的可能就是小组件。
    static func load() -> WidgetSnapshot {
        // 用 `licensedPro` 而不是 `load().isPro`：后者在快照文件缺失时回落成付费档，
        // 全新安装的免费用户会拿到满量列表（等于免费版桌面能翻 60 条）。
        let isPro = EntitlementSnapshot.licensedPro
        let cap = isPro ? PickupLimits.widgetListCap : PickupLimits.freeVisible

        let all = PickupStorage.load()
        // 跟主 App 待取页同一套排序 / 分组（2026-11-15 主人要求）：
        // 主界面按驿站找件，桌面就按驿站排，不用切换认知。
        let pending = PickupSortLogic.sort(
            all.filter { !$0.isPickedUp },
            mode: PickupStorage.listSort
        )
        // 今天**取走**的件数：按取件时刻算（`pickupMoment` = pickedUpAt ?? receivedAt），
        // 与统计页 `PickupStats.pickedToday` 和 App 内 `todayPickedCount` 同口径
        // （2026-10-25 审查修：原来看 `receivedAt`，昨天收到今天取走的件会被漏掉）。
        let pickedToday = all
            .filter { $0.isPickedUp && Calendar.current.isDateInToday($0.pickupMoment) }
            .count

        // 🔴 2026-11-16「一张卡片多个取件码」：与 App 两页同一套显示层分组。
        //    小组件的「一行」等价于 App 的「一张卡」—— 同源多码只占一行，
        //    其余码挂在主码后面；`pendingTotal` 仍按真实记录数算，件数不缩水。
        var shown = pending
        var extras: [String: [String]] = [:]
        if CodeAppearanceSettings.groupsMultipleCodes {
            let representatives = PickupRecordGrouping.representativeIDs(pending)
            shown = pending.filter { representatives.contains($0.id) }
            for record in shown {
                let codes = PickupRecordGrouping.extraCodes(for: record, in: pending)
                if !codes.isEmpty { extras[record.id.uuidString] = codes }
            }
        }

        return WidgetSnapshot(items: Array(shown.prefix(cap)),
                              pendingTotal: pending.count,
                              pickedTodayCount: pickedToday,
                              extraCodes: extras)
    }

    var isEmpty: Bool { items.isEmpty }

    /// 可见条目是否被档位截断（免费版还有更多但看不到）—— 头部据此换成「免费版」提示
    var isTruncated: Bool { items.count < pendingTotal }

    func pageCount(pageSize: Int) -> Int {
        let size = max(1, pageSize)
        return max(1, Int(ceil(Double(items.count) / Double(size))))
    }

    /// 把任意页码夹到合法范围。数据变少时（用户把件取走了）页码可能越界，
    /// 不夹的话会翻到一页空白，看起来像「小组件坏了」。
    func clampedPage(_ page: Int, pageSize: Int) -> Int {
        min(max(0, page), pageCount(pageSize: pageSize) - 1)
    }

    func pageItems(_ page: Int, pageSize: Int) -> [PickupRecord] {
        let size = max(1, pageSize)
        let start = clampedPage(page, pageSize: size) * size
        guard start < items.count else { return [] }
        return Array(items[start ..< min(start + size, items.count)])
    }

    /// 本页空槽数量（稳定行高用，上限见 `WidgetPageSize.maxPlaceholderRows`）
    func placeholderRows(page: Int, pageSize: Int) -> Int {
        min(max(0, pageSize - pageItems(page, pageSize: pageSize).count),
            WidgetPageSize.maxPlaceholderRows)
    }
}

// MARK: - 会员档位（2026-09-23）
//
// 「全功能模式」升级成 **VIP 模式**：不再是开/关，而是三档会员
// （月付 / 年费 / 永久），未开通即免费版。
//
// 🔴 **这是跨进程契约**：档位会被编码进 App Group 的 `entitlement.json`，
//    由小组件扩展独立读取。两条纪律：
//      ① **不要改已有 case 的 rawValue** —— 旧数据会解不出来；
//      ② 新增档位只能**追加在末尾**（`none` 必须留在第一个，它是默认值）。

enum MembershipPlan: String, Codable, CaseIterable, Identifiable {
    /// 未开通 = 免费版
    case none
    /// 临时凭证（7 天有效，到期自动回落免费档）
    case trial
    /// 买断，永久
    case lifetime

    var id: String { rawValue }

    /// 是否已解锁全部能力（`none` 之外都算）
    var isActive: Bool { self != .none }

    /// 设置行尾 / 徽章上的档位名。
    ///
    /// 🔴 2026-10-30：`monthly` / `yearly` 两个订阅档已删除，改为「临时 / 买断」。
    ///    这是**买断制**，App 内不出现「会员」「年费」这类订阅话术。
    ///    老快照里若存着 `monthly` / `yearly`，解码会失败 —— 但 `EntitlementSnapshot`
    ///    的解码器对此有兜底（见 `init(from:)`），按 `isPro` 反推，不会把人打回免费。
    var title: String {
        switch self {
        case .none: return "未开通"
        case .trial: return "临时"
        case .lifetime: return "永久"
        }
    }

    // MARK: 价格（已整体移除 · 2026-09-23）
    //
    // 这里原有 `price` / `originalPrice` / `priceText` / `originalPriceText` /
    // `discountText` / `periodText` / `pitch` / `purchasable` 一整组价格派生属性。
    // 路线改为「纯离线 + 外部凭证解锁」之后，App 内**不再出现任何价格**，
    // 这组常量与话术随之退场。留着它们的风险不是占地方，而是将来某次改版
    // 很容易又被顺手接回 UI —— 而 App 内的任何价格展示都是审核风险。
}

// MARK: - 权益快照（小组件侧尺寸门控）
//
// 规格 v1.3 §「小组件层」：尺寸门控在 **Widget 侧**判定 —— 读 App Group 中的权益
// 快照，不依赖主 App 是否运行。
//
// 首发（TestFlight）注册 systemSmall + systemMedium，因此该快照当前不影响渲染；
// 它是为正式版的 `systemLarge` / 锁屏尺寸门控预置的通道，主 App 在购买状态
// 变化时写入，Widget 侧读取即可，无需唤醒主 App。

struct EntitlementSnapshot: Codable, Equatable {
    var isPro: Bool
    /// VIP 档位。`isPro` 与之永远同向（`plan.isActive == isPro`），
    /// 保留 `isPro` 是因为小组件/扩展侧只关心"能不能用"，
    /// 读一个 Bool 比解档位简单。
    var plan: MembershipPlan
    var updatedAt: Date

    /// 凭证到期时间（2026-09-23 随离线凭证体系加入）。
    /// `nil` = 不设到期 —— 这既是"永久档"的含义，也是**老快照的默认值**，
    /// 所以老用户升级上来不会被误判成过期。
    var expiresAt: Date?

    /// **历史见过的最大时间**（时间水位）。
    ///
    /// 存在的唯一理由：封堵「把系统时间调回到到期日之前，继续用过期凭证」。
    /// 每次读取时把水位往前推（每小时最多落一次盘），判定过期时取
    /// `max(当前时间, 水位)` —— 时间能被调回去，水位不会。
    var lastSeenAt: Date?

    /// 内购买断标记（2026-10-31）。
    ///
    /// 为什么写进快照而不是让小组件自己去问 StoreKit：扩展进程里拿
    /// `Transaction.currentEntitlements` 依赖网络与缓存，取时间线时不可靠；
    /// 而这份文件本来就在 App Group 里，主 App 购买成功后写一次，扩展直接读。
    var storeOwned: Bool?

    /// 原始凭证串。**存它是为了每次读取都重新验签** ——
    /// 只存档位的话，越狱用户改一下 `entitlement.json` 里的 `plan` 就等于
    /// 自造了永久会员；留着凭证，签名对不上就当场降级。
    var license: String?

    static let free = EntitlementSnapshot(isPro: false, plan: .none, updatedAt: .distantPast)

    /// 全功能档（2026-10-25 新增）。
    ///
    /// 🔴 用在「快照文件根本不存在」这一种情形：App 自 2026-10-14 起已全功能化
    /// （`PickupStore.isPro` 恒 `true`），**不再有任何代码写 `entitlement.json`**。
    /// 但共享层的实时活动 / 小组件仍在读它判门 —— 文件缺失时若返回 `.free`，
    /// 全新安装上实时活动**永远起不来**（每次 sync 都被 `guard isPro else { endAll() }`
    /// 收掉），且不留任何日志。模拟器实测该目录下确实没有 entitlement.json。
    static let lifetime = EntitlementSnapshot(isPro: true, plan: .lifetime, updatedAt: .distantPast)

    /// 「有凭证支撑的付费档」—— App 与小组件**必须用同一口径**判档。
    ///
    /// 🔴 为什么不直接用 `load().isPro`：`load()` 在**快照文件不存在**时回落到
    ///    `.lifetime`（见上方 `lifetime` 的理由：别让实时活动在全新安装上假死）。
    ///    直接采信它，没买过的用户一装就是「全功能」，买断制当场失效。
    ///    所以还要看快照里是否真的存着一串凭证 —— 那是导入凭证时才写进去的。
    ///
    /// 与 App 侧 `PickupStore.refreshEntitlement()` 是同一条判断，别各写一份。
    static var licensedPro: Bool {
        // 🧪 调试脚手架（仅 Debug）：`FORCE_FREE=1` 强制按免费档跑，
        // 方便真机上验收付费墙 —— 不必删凭证、也不用重装。
        // `FORCE_PRO=1` 反过来强制按 Pro 跑：模拟器里凭证不可控，
        // 验 Pro 才可见的设置项（如到达提醒实验室分组）靠这个入口直渲。
        #if DEBUG
        if ProcessInfo.processInfo.environment["FORCE_FREE"] == "1" { return false }
        if ProcessInfo.processInfo.environment["FORCE_PRO"] == "1" { return true }
        #endif
        let snapshot = load()
        let backed = !(snapshot.license ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        // 订阅会过期：`expiresAt == nil` 表示永久（买断），否则必须还没到点。
        // 这一步必须在**读侧**做 —— 小组件不联网、不跑 StoreKit，只信这份快照。
        let storeOwned = snapshot.storeOwned == true
            && (snapshot.expiresAt.map { $0 > Date() } ?? true)
        return snapshot.isPro && (backed || storeOwned)
    }

    /// 记录「内购买断」状态并落盘（主 App 在 StoreKit 结果变化时调用）。
    ///
    /// 只改这一个来源：**不会**动 `license` —— 老凭证买家的权益由验签决定，
    /// 内购退款/撤销不该把他们的凭证一起抹掉。
    /// - Parameter expiresAt: 订阅到期时间；`nil` = 永久（买断）
    static func markStoreOwned(_ owned: Bool, expiresAt: Date?) {
        var snapshot = load()
        let expiryChanged = owned && snapshot.expiresAt != expiresAt
        guard (snapshot.storeOwned ?? false) != owned || expiryChanged else { return }

        snapshot.storeOwned = owned
        // 有老凭证时不动它的到期时间：那份到期时间由凭证签名决定，不归内购管
        if (snapshot.license ?? "").isEmpty {
            snapshot.expiresAt = owned ? expiresAt : nil
        }
        if owned {
            snapshot.isPro = true
            snapshot.plan = .lifetime
        } else if (snapshot.license ?? "").isEmpty {
            // 没有凭证兜底时才降级；有凭证的交给 `load()` 重新验签
            snapshot.isPro = false
            snapshot.plan = .none
        }
        snapshot.updatedAt = .now
        _ = save(snapshot)
    }

    init(isPro: Bool, plan: MembershipPlan, updatedAt: Date,
         expiresAt: Date? = nil, lastSeenAt: Date? = nil, license: String? = nil) {
        self.isPro = isPro
        self.plan = plan
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.lastSeenAt = lastSeenAt
        self.license = license
    }

    /// 🔴 **手写解码**，只为一件事：老快照里没有 `plan` 这个键。
    ///
    /// 合成解码器遇到缺键会抛错，而 `load()` 是 `try? decode(...) ?? .free` ——
    /// 也就是说**一次解码失败 = 静默回落到免费版**。升级上来的已购用户
    /// 会当场被打回免费，且没有任何报错可循。所以这里对 `plan` 单独兜底：
    /// 缺键（或解不出来）时按 `isPro` 反推（已开通的老用户视为永久）。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isPro = try container.decode(Bool.self, forKey: .isPro)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        // 注意别写成两层 `if let`：Swift 5 起 `try?` 会**展平** Optional 层级
        // （SE-0230），`try? decodeIfPresent(...)` 已经是 `MembershipPlan?`，
        // 再解一层会被编译器判定"不是 Optional"。
        if let value = try? container.decodeIfPresent(MembershipPlan.self, forKey: .plan) {
            plan = value
        } else {
            // 老快照（或档位值是未来新增的未知值）：按 isPro 反推
            plan = isPro ? .lifetime : .none
        }

        // 后加的三个字段一律 `decodeIfPresent`：缺键是**正常情况**
        // （老快照里根本没有它们），不能因此让整个解码失败 ——
        // 那会连带把已购用户打回免费版（见上面那段说明）。
        expiresAt = try? container.decodeIfPresent(Date.self, forKey: .expiresAt)
        lastSeenAt = try? container.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        license = try? container.decodeIfPresent(String.self, forKey: .license)
        // 老快照没有这个键 —— 缺键是正常情况，不能因此解码失败
        storeOwned = try? container.decodeIfPresent(Bool.self, forKey: .storeOwned)
    }

    private static let fileName = "entitlement.json"

    private static var fileURL: URL {
        PickupStorage.directory.appendingPathComponent(fileName)
    }

    /// 读权益。**每次读取都重新验签一次凭证**（2026-09-23）。
    ///
    /// 代价是每次一次 P-256 验签（亚毫秒级，小组件取时间线也扛得住）；
    /// 换来的是「改 `entitlement.json` 里的档位字段无效」—— 签名对不上，
    /// 当场降级并落盘，没有留下任何"手改文件即可白嫖"的口子。
    static func load() -> EntitlementSnapshot {
        // 🔴 **文件不存在 ≠ 免费用户**（2026-10-25 审查修）。
        // 全功能化之后没有任何代码写这个文件，全新安装 100% 走这条分支；
        // 返回 `.free` 会让实时活动链路 `guard isPro else { await endAll() }` 永远收卡，
        // 用户看到的是「实时活动开关是开的，但锁屏/灵动岛什么都不显示」，且无任何报错。
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .lifetime }
        guard let data = try? Data(contentsOf: fileURL) else { return .lifetime }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var snapshot = try? decoder.decode(EntitlementSnapshot.self, from: data) else {
            // 文件在、但解不出来 = 损坏或被手改 → 这里仍然降级，
            // 不给「改坏文件就能解锁」留口子
            return .free
        }

        // 判定依据取「当前时间」与「历史水位」的较大者：时间能被调回去，水位不会
        let reference = max(Date(), snapshot.lastSeenAt ?? .distantPast)

        if let raw = snapshot.license, !raw.isEmpty {
            switch LicenseVerifier.verify(raw, now: reference) {
            case .success(let payload):
                snapshot.plan = payload.service.plan
                snapshot.expiresAt = payload.expiresAt
                snapshot.isPro = payload.service.plan.isActive

            case .failure(let error):
                // 🔴 设备类失败**不落盘**（2026-09-23，设备绑定引入后新增的分支）。
                //
                // 原因是一个真实存在的竞态：小组件扩展可以在 App 从未启动过的
                // 情况下先取时间线，此时 App Group 里还没有设备码缓存，
                // `verify` 会因为"读不到本机码"而判定不匹配。若在这里照常
                // 落盘降级，**扩展就把一张完全有效的凭证永久抹掉了**，
                // 用户下次打开 App 也读不回来。
                //
                // 所以只让本次渲染降级（保守：宁可暂时当免费版，也不放行），
                // 快照里的 `license` 原样保留 —— 等 App 启动、缓存写好，
                // 下一次 `load()` 自愈。真正的确定性失败（篡改 / 过期 /
                // 格式坏）仍照常落盘，那才是需要立即清掉的脏状态。
                switch error {
                case .unbound, .wrongDevice:
                    var degrade = EntitlementSnapshot.free
                    degrade.updatedAt = .now
                    degrade.lastSeenAt = reference
                    degrade.license = raw
                    return degrade

                default:
                    let downgraded = EntitlementSnapshot(isPro: false,
                                                         plan: .none,
                                                         updatedAt: .now,
                                                         lastSeenAt: reference)
                    _ = save(downgraded)
                    return downgraded
                }
            }
        }

        // ⚠️ 刻意**不**处理「`isPro == true` 但没有任何凭证」的情况。
        //    那种快照只可能来自两处：老版本升级上来的已购用户（当年还没有
        //    凭证体系），以及截图脚手架 `PLAN=`。对它们一律执行"无凭证即伪造"
        //    会当场误伤真实用户，代价远大于它挡住的收益（能改这个文件的人
        //    已经越狱，本来也拦不住）。

        // 水位推进。每小时最多落一次盘 —— 小组件每次取时间线都会走这里，
        // 每次都写文件是没必要的磁盘抖动。
        if snapshot.lastSeenAt == nil
            || Date().timeIntervalSince(snapshot.lastSeenAt ?? .distantPast) > 3600 {
            snapshot.lastSeenAt = reference
            _ = save(snapshot)
        }

        return snapshot
    }

    /// 写入一份**通过验签**的凭证（`LicenseActivation` 是唯一调用方）。
    ///
    /// 与 `PickupStore.setPlan`（测试脚手架用）的区别：这条必须带原始凭证 ——
    /// 它写入的是"可被复核的授权"，而不是"一个本地开关"。
    @discardableResult
    static func activate(plan: MembershipPlan, expiresAt: Date?, license: String) -> Bool {
        // 🔴 水位**只增不减**：写入时取「当前时间」与「已有水位」的较大者。
        //    原来这里直接写 `Date()`，用户把系统时间调回去再激活一次，
        //    就能把水位一起拉回过去，到期凭证等于复活。
        let previous = load()
        let reference = max(Date(), previous.lastSeenAt ?? .distantPast)
        return save(EntitlementSnapshot(isPro: plan.isActive,
                                        plan: plan,
                                        updatedAt: .now,
                                        expiresAt: expiresAt,
                                        lastSeenAt: reference,
                                        license: license))
    }

    @discardableResult
    static func save(_ snapshot: EntitlementSnapshot) -> Bool {
        do {
            try FileManager.default.createDirectory(at: PickupStorage.directory,
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - 桌面小组件总开关（已删除 · 2026-09-23）
//
// 这里原有 `WidgetSwitch`（App Group 里的一个 Bool，关掉后桌面小组件渲染停用态）
// 与配套的 `WidgetDisabledContent`。主人判定这个开关「没啥意义」，整体退场：
//   · 不想要小组件的人直接从桌面移除即可，不需要 App 里再塞一个开关；
//   · 它的"关闭"只是把桌面变成一块「已关闭」死牌子，不如没有；
//   · 二级入口埋得深，关掉之后想不起来在哪开，就成了死局。
//
// ⚠️ App Group 里 `allude.widgetsEnabled` 这个键仍然可能留着 `false`（历史用户），
//    但**已经没有读它的地方了** —— 删 UI 的同时必须删读侧门控，
//    只删 UI 会让 `false` 变成永久锁死。这条是删开关类功能的标准动作。

// MARK: - 小组件显示内容（2026-10-27 改为五个开关）
//
// 需求原话：「下面的显示内容的开关勾选直接做成开关：完整信息、显示取件地址、
// 显示快递公司、显示驿站、显示快递柜/货架这五个开关，完整信息与下面的互斥，
// 事实上与之前一样，但是形式变了」。
//
// 三条口径：
//   ① 🔴 **取件码永不参与配置** —— 它是这个小组件存在的唯一理由，
//      一个能把自己关掉的开关不叫设置，叫故障源。所以这里没有它的位置；
//   ② **「完整信息」= 其余四项全开**，是快捷全开 / 全关的 master 开关。
//      它与下面四项天然互斥：关掉任何一项，它就不再是全开、自己变回未选中，
//      不需要额外禁用或联动代码 —— 状态本身就是唯一真相；
//   ③ **驿站与地址互斥显示**（见 `PickupRecord.widgetSubtitle`：站名本来就是
//      地址的尾段，两个都画等于同一段字出现两次）。
//
// ⚠️ 跨进程契约（与 `EntitlementSnapshot` 同一纪律）：字段只增不改，
//    新增字段必须有解码兜底，否则老配置会让整份选项解不出来 → 静默回落到默认。

/// 小组件空槽（灰色占位骨架行）是否显示。
///
/// 默认显示：不足一页时补空槽，本来是想表达「就这些了」，
/// 但有用户反馈「以为是还有快递没显示出来」（2026-11-14），
/// 所以给一个开关让用户自己决定。
enum WidgetPlaceholderSetting {
    static let key = "allude.widget.showPlaceholders"

    /// 读 App Group。缺失时按 `true` —— 与历史行为一致。
    static var isOn: Bool {
        UserDefaults(suiteName: PickupStorage.appGroupID)?
            .object(forKey: key) as? Bool ?? true
    }

    /// 只落盘，不 reload；调用方负责 `WidgetCenter.shared.reloadAllTimelines()`。
    static func set(_ on: Bool) {
        UserDefaults(suiteName: PickupStorage.appGroupID)?.set(on, forKey: key)
    }
}

/// 小组件显示哪几项。
struct WidgetDisplayOptions: Codable, Equatable {
    /// 快递公司（顺丰速运 / 圆通快递…；判别不出时退回短信平台）
    var showsCompany: Bool
    /// 驿站 / 网点短名（从地址里提取，见 `PickupRecord.station`）
    var showsStation: Bool
    /// 取件地址（完整门牌）
    var showsAddress: Bool
    /// 快递柜格口 / 货架（取件码**后面**那一位，2026-10-27 新增）
    var showsLocker: Bool

    /// 四项全开 —— 页面上的「完整信息」，也是升级前的默认版式。
    /// 站名此时被地址盖住（互斥规则），所以视觉与旧版完整模板完全一致。
    static let full = WidgetDisplayOptions(showsCompany: true,
                                          showsStation: true,
                                          showsAddress: true,
                                          showsLocker: true)

    /// 四项全关 —— 只剩取件码，第二行整行不画、码后柜位也不画。
    static let codeOnly = WidgetDisplayOptions(showsCompany: false,
                                              showsStation: false,
                                              showsAddress: false,
                                              showsLocker: false)

    /// 四项全开 ⇒「完整信息」为开。互斥判断就靠这一条，不需要额外状态位。
    var isComplete: Bool {
        showsCompany && showsStation && showsAddress && showsLocker
    }

    private static let fileName = "widget-display.json"

    private static var fileURL: URL {
        PickupStorage.directory.appendingPathComponent(fileName)
    }

    private enum CodingKeys: String, CodingKey {
        case showsCompany, showsStation, showsAddress, showsLocker
    }

    /// `showsLocker` 给默认值：新增字段若设成必填，老调用点全要改。
    init(showsCompany: Bool, showsStation: Bool, showsAddress: Bool, showsLocker: Bool = true) {
        self.showsCompany = showsCompany
        self.showsStation = showsStation
        self.showsAddress = showsAddress
        self.showsLocker = showsLocker
    }

    /// 🔴 手写解码：每个字段都给默认值。
    /// 以后往这里加字段时，老配置文件缺键也不会让整份选项解码失败。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsCompany = (try? container.decodeIfPresent(Bool.self, forKey: .showsCompany)) ?? true
        showsStation = (try? container.decodeIfPresent(Bool.self, forKey: .showsStation)) ?? false
        showsAddress = (try? container.decodeIfPresent(Bool.self, forKey: .showsAddress)) ?? true
        // 老配置没有这个键 → 默认显示（升级前柜位一直显示，不能因为加了开关就消失）
        showsLocker = (try? container.decodeIfPresent(Bool.self, forKey: .showsLocker)) ?? true
    }

    static func load() -> WidgetDisplayOptions {
        guard let data = try? Data(contentsOf: fileURL) else { return .full }
        return (try? JSONDecoder().decode(WidgetDisplayOptions.self, from: data)) ?? .full
    }

    @discardableResult
    static func save(_ options: WidgetDisplayOptions) -> Bool {
        do {
            try FileManager.default.createDirectory(at: PickupStorage.directory,
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(options).write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - 预设组合（2026-10-27 起只服务脚手架）

/// 小组件显示内容的**预设组合**。
///
/// 设置页改成五个开关后，这里不再是"给人挑的模板"，只剩一个用途：
/// `DISPLAY=full|codeOnly|companyOnly|stationOnly` 脚手架一次性写入某种组合，
/// 让命令行能截到特定版式。保留命名是为了回归时能直接说"codeOnly 有没有变"。
///
/// ⚠️ 曾经还有 `.custom` 与 `title/subtitle/symbol/selectable` —— 那是四选一单选行
///    的配套，开关化之后全部失去消费者，已删（零死代码）。
enum WidgetDisplayPreset: String, CaseIterable {
    case full
    case codeOnly
    case companyOnly
    case stationOnly

    var options: WidgetDisplayOptions {
        switch self {
        case .full:
            return .full
        case .codeOnly:
            return .codeOnly
        case .companyOnly:
            return WidgetDisplayOptions(showsCompany: true, showsStation: false,
                                        showsAddress: false, showsLocker: true)
        case .stationOnly:
            return WidgetDisplayOptions(showsCompany: true, showsStation: true,
                                        showsAddress: false, showsLocker: true)
        }
    }
}


// MARK: - 列表排序 / 分组的共享实现
//
// 主 App 的待取页与桌面小组件必须用**同一套**排序，否则用户在列表里按驿站
// 找件、桌面却按时间排，认知要来回切换（2026-11-15 主人要求）。
// 放在 AlludeShared 里两边共用；原始值必须与 `PickupSortMode` 一致。

enum PickupSortLogic {
    enum Mode: String {
        case newest = "最近收到"
        case oldest = "最早收到"
        case company = "按快递公司"
        case station = "按快递驿站"
    }

    /// 未标注驿站时的分组名（与 App 内一致）
    static let noStation = "未标注驿站"

    static func stationName(of record: PickupRecord) -> String {
        // 2026-11-21：分组键改由**单一解析入口**给（含自定义驿站、记录级手工指定、
        // 多组不猜）。以前这里只是拿词表名去查组名，于是：
        //   · 用户自定义驿站建的组在小组件里掉进「未标注驿站」；
        //   · 详情页手工指定的组，列表上不认。
        record.stationResolution.displayName
    }

    static func companyName(of record: PickupRecord) -> String {
        // 与卡面主名同口径：快递公司标准名优先，没有就退到 company
        let name = (record.courierDisplay ?? record.company)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "其他" : name
    }

    /// 稳定排序：同组内仍按「最近收到」倒序。
    static func sort(_ records: [PickupRecord], mode: Mode) -> [PickupRecord] {
        switch mode {
        case .newest:
            return records.sorted { $0.receivedAt > $1.receivedAt }
        case .oldest:
            return records.sorted { $0.receivedAt < $1.receivedAt }
        case .company:
            return records.sorted {
                let a = companyName(of: $0), b = companyName(of: $1)
                if a != b { return a < b }
                return $0.receivedAt > $1.receivedAt
            }
        case .station:
            // 🔴 2026-11-21 统一口径（主人定）：**组间按件数多在前**，同数按名字，
            //    「未标注驿站」永远置底；组**内**的先后由「驿站内排序」决定。
            //    以前待取/已取按件数、桌面小组件按名字升序 —— 同一份数据两种顺序，
            //    手机上排好的顺序到桌面就乱了。
            let inner = StationInnerOrder.current
            var keys: [UUID: String] = [:]
            var counts: [String: Int] = [:]
            for record in records {
                let key = stationName(of: record)
                keys[record.id] = key
                counts[key, default: 0] += 1
            }
            return records.sorted {
                let a = keys[$0.id] ?? noStation, b = keys[$1.id] ?? noStation
                let aIsNone = (a == noStation), bIsNone = (b == noStation)
                if aIsNone != bIsNone { return bIsNone }   // 未标注驿站永远置底
                if a != b {
                    let ca = counts[a] ?? 0, cb = counts[b] ?? 0
                    if ca != cb { return ca > cb }          // 件数多的组在前
                    return a < b
                }
                // 组内先后与待取页同一个时刻：`lastNotifiedAt`（它本身就是
                // `history?.last ?? receivedAt`，没通知过自然回落收到时间）。
                // 2026-11-21 主人：「小组件的排序就和待取页面的分组排序保持一致就行」。
                let moment: (PickupRecord) -> Date = { $0.lastNotifiedAt }
                return inner.isOrderedBefore($0, $1, moment: moment)
            }
        }
    }
}

// MARK: - 取件码外观 / 卡片分组（App 写、小组件与灵动岛读 App Group）
//
// 2026-11-16 主人：「在设置页面中的桌面小组件的下面增加一个取件码管理」。
// 全端统一：待取 / 已取 / 详情 / 桌面小组件 / 灵动岛 / 分享卡共用这一份配置。
//
// 🔴 与 `WidgetDisplayOptions` 同一纪律：
//   · 全部落 **App Group `UserDefaults`**，小组件扩展与灵动岛渲染进程都读得到；
//   · 键只增不改，读不到一律回落**升级前的默认观感**（跟随品牌色 + 末四位强调）；
//   · 写一次 `WidgetCenter.shared.reloadAllTimelines()`，桌面立刻重画。
//
// ⚠️ 这里刻意不 import SwiftUI、不出现 `Color`：此文件同时被通知扩展等
//    非 UI target 编译。色板到 `Color` 的映射放在 `PickupModels.swift` 的
//    `CodeColorChoice` 里，本层只存 String / Double / Bool。
enum CodeAppearanceSettings {
    static let colorKey        = "allude.code.color"          // CodeColorChoice.rawValue
    static let opacityKey      = "allude.code.opacity"        // 整码统一透明度
    static let headOpacityKey  = "allude.code.headOpacity"    // 强调开启时前段透明度
    static let emphasisKey     = "allude.code.emphasis"       // 末四位强调开关
    static let groupMultipleKey = "allude.code.groupMultiple" // 一张卡片多个取件码

    private static var store: UserDefaults { PickupStorage.sharedDefaults }

    /// 颜色档位原始值。未知值一律回落 "brand"（跟随品牌色 = 升级前观感）。
    static var colorRaw: String {
        store.string(forKey: colorKey) ?? CodeAppearanceDefaults.brandColorRaw
    }

    static func setColorRaw(_ raw: String) {
        store.set(raw, forKey: colorKey)
        notifyChange()
    }

    /// 整条取件码的统一透明度（1.0 = 不透明）。
    static var opacity: Double {
        value(forKey: opacityKey, default: 1.0, allowed: opacityOptions)
    }

    static func setOpacity(_ value: Double) {
        store.set(value, forKey: opacityKey)
        notifyChange()
    }

    static let opacityOptions: [Double] = [1.0, 0.85, 0.7, 0.55]

    /// 末四位强调时，**前段**相对整码再乘的透明度。默认 0.45（升级前的值）。
    static var headOpacity: Double {
        value(forKey: headOpacityKey, default: 0.45, allowed: headOpacityOptions)
    }

    static func setHeadOpacity(_ value: Double) {
        store.set(value, forKey: headOpacityKey)
        notifyChange()
    }

    static let headOpacityOptions: [Double] = [0.3, 0.45, 0.6, 0.8]

    /// 末四位强调开关：关掉后整条取件码只剩一个颜色、一个透明度。
    static var emphasisEnabled: Bool {
        store.object(forKey: emphasisKey) as? Bool ?? true
    }

    static func setEmphasisEnabled(_ on: Bool) {
        store.set(on, forKey: emphasisKey)
        notifyChange()
    }

    /// 🔴 「一张卡片多个取件码」**默认关闭**（2026-11-16 主人明确）：
    ///    升级后仍是一码一卡，只有用户主动拨开关才合并。
    ///    这是唯一的默认值来源 —— 别在别处偷偷写 true，也别做「首次启动自动开」。
    static let defaultGroupsMultipleCodes = false

    /// 只影响**显示层**，数据仍是一码一 `PickupRecord`（件数、去重、勾选、iCloud 同步全不动）。
    static var groupsMultipleCodes: Bool {
        store.object(forKey: groupMultipleKey) as? Bool ?? defaultGroupsMultipleCodes
    }

    static func setGroupsMultipleCodes(_ on: Bool) {
        store.set(on, forKey: groupMultipleKey)
        notifyChange()
    }

    /// 偏好域里可能残留手改的脏值；只允许落在档位表内，否则回落默认值。
    private static func value(forKey key: String,
                              default fallback: Double,
                              allowed: [Double]) -> Double {
        guard let raw = store.object(forKey: key) as? Double,
              allowed.contains(where: { abs($0 - raw) < 0.001 }) else { return fallback }
        return raw
    }

    /// 样式一变，桌面小组件立刻重画。
    /// 灵动岛 / 锁屏实时活动不归 WidgetCenter 管，由设置页另外调
    /// `PickupActivityController.refreshRendering()` 强制 update 一次。
    static func notifyChange() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// 颜色档位的 rawValue 常量放在这里，让不 import SwiftUI 的存储层也能写默认值。
/// 完整的色板枚举（含 `Color` 映射）在 `PickupModels.swift`，名字是 `CodeColorChoice`。
enum CodeAppearanceDefaults {
    static let brandColorRaw = "brand"
}
