import Foundation
import WidgetKit

// MARK: - 本地持久化（App 写入 / 小组件读取）
//
// 设计要点：
//  1) **优先 App Group 容器**（`group.com.jikezhang.codeclip`），以便与小组件扩展共享数据；
//     未配置 entitlement 时自动回落 App 自身容器，不报错、不崩。
//  2) 纯本地、无网络、无第三方 SDK —— 与产品「所有数据仅保存在本机」的承诺一致。
//  3) 写入用 `.atomic`，避免进程被系统回收时留下半截文件。
//
// ⚠️ App Group 生效前提：两个 target 的 Signing & Capabilities 中都勾选同一个
//    App Group。代码层已做好回落，因此「未开通」只是不共享，不会崩。

enum PickupStorage {
    /// App Group 标识（需在 Signing & Capabilities 中开通后生效）
    static let appGroupID = "group.com.jikezhang.codeclip"

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
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([PickupRecord].self, from: data)) ?? []
    }

    @discardableResult
    static func save(_ records: [PickupRecord]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
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
// 拿不到 `PickupStore`，但它同样要按档位裁剪列表（免费版桌面也只给 4 条）。

enum PickupLimits {
    /// 同屏展示上限（仅渲染裁剪，数据完整保留）
    static let freeVisible = 4
    /// 存储上限，超出后 FIFO 淘汰最旧
    static let freeStorage = 60
    /// 「不限量」的替代值。**不要用 `Int.max`**：`count - limit` 这类减法会溢出崩溃。
    static let unlimited = 9_999
    /// 小组件单次可翻动的最大条数。
    ///
    /// 小组件不是浏览器：几千条待办摊进 6 行一页会得出几百页，
    /// 用户按到手抽筋也翻不完，且每次翻页都要重读整份 JSON。
    /// 头部数字仍显示**真实总数**（`pendingTotal`），这里截的只是「可翻动的量」。
    static let widgetListCap = 60
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
        case "l": 6
        case "xl": 6
        case "xlp": 10
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
    /// 部署目标已是 iOS 27，`systemExtraLargePortrait` 无需可用性分支。
    static let supportedFamilies: [WidgetFamily] = [
        .systemSmall, .systemMedium, .systemLarge,
        .systemExtraLarge, .systemExtraLargePortrait,
    ]

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

    static let empty = WidgetSnapshot(items: [], pendingTotal: 0, pickedTodayCount: 0)

    /// 从共享容器读取并裁剪。
    ///
    /// 档位由小组件**自己判定**（读 `EntitlementSnapshot`），不依赖主 App 是否运行 ——
    /// 用户重启手机后首先被系统唤醒的可能就是小组件。
    static func load() -> WidgetSnapshot {
        let isPro = EntitlementSnapshot.load().isPro
        let cap = isPro ? PickupLimits.widgetListCap : PickupLimits.freeVisible

        let all = PickupStorage.load()
        let pending = all
            .filter { !$0.isPickedUp }
            .sorted { $0.receivedAt > $1.receivedAt }
        let pickedToday = all
            .filter { $0.isPickedUp && Calendar.current.isDateInToday($0.receivedAt) }
            .count

        return WidgetSnapshot(items: Array(pending.prefix(cap)),
                              pendingTotal: pending.count,
                              pickedTodayCount: pickedToday)
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
    case monthly
    case yearly
    case lifetime

    var id: String { rawValue }

    /// 是否已解锁全部能力（`none` 之外都算）
    var isActive: Bool { self != .none }

    /// 设置行尾 / 徽章上的档位名
    var title: String {
        switch self {
        case .none: return "未开通"
        case .monthly: return "月付会员"
        case .yearly: return "年费会员"
        case .lifetime: return "永久会员"
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

    /// 原始凭证串。**存它是为了每次读取都重新验签** ——
    /// 只存档位的话，越狱用户改一下 `entitlement.json` 里的 `plan` 就等于
    /// 自造了永久会员；留着凭证，签名对不上就当场降级。
    var license: String?

    static let free = EntitlementSnapshot(isPro: false, plan: .none, updatedAt: .distantPast)

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
        guard let data = try? Data(contentsOf: fileURL) else { return .free }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var snapshot = try? decoder.decode(EntitlementSnapshot.self, from: data) else {
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
        save(EntitlementSnapshot(isPro: plan.isActive,
                                 plan: plan,
                                 updatedAt: .now,
                                 expiresAt: expiresAt,
                                 lastSeenAt: Date(),
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
// ⚠️ App Group 里 `codeclip.widgetsEnabled` 这个键仍然可能留着 `false`（历史用户），
//    但**已经没有读它的地方了** —— 删 UI 的同时必须删读侧门控，
//    只删 UI 会让 `false` 变成永久锁死。这条是删开关类功能的标准动作。

// MARK: - 小组件显示内容（2026-09-23 主人要求）
//
// 需求原话：「可以选择显示/隐藏快递平台、驿站、取件地址等信息，但是取件码不可以……
// 就做好几个模板，提供选择，当然免费版全显示，自定义是付费功能」。
//
// 三条设计口径：
//   ① 🔴 **取件码永不参与配置** —— 它是这个小组件存在的唯一理由，
//      一个能把自己关掉的开关不叫设置，叫故障源。所以这个结构体里没有它的位置；
//   ② **免费版 = 完整模板**（平台 + 地址，即改版前的版式）。免费不是"少几项"，
//      而是"没得挑"—— 锁挂在**模板**上，不挂在字段上；
//   ③ 自定义三项独立开关，但**驿站与地址互斥显示**（见 `PickupRecord.widgetSubtitle`：
//      站名本来就是地址的尾段，两个都画等于同一段字出现两次）。
//
// ⚠️ 跨进程契约（与 `EntitlementSnapshot` 同一纪律）：字段只增不改，
//    新增字段必须有解码兜底，否则老配置会让整份选项解不出来 → 静默回落到默认。

/// 小组件二级信息行显示哪几项。
struct WidgetDisplayOptions: Codable, Equatable {
    /// 快递平台（顺丰速运 / 菜鸟驿站 / 兔喜生活…）
    var showsCompany: Bool
    /// 驿站 / 网点短名（从地址里提取，见 `PickupRecord.station`）
    var showsStation: Bool
    /// 取件地址（完整门牌）
    var showsAddress: Bool

    /// 改版前的版式，也是免费版唯一可用的形态。
    static let full = WidgetDisplayOptions(showsCompany: true,
                                           showsStation: false,
                                           showsAddress: true)

    /// 两项全关 → 只剩取件码，副标题行整行不渲染。
    var hidesAllDetail: Bool { !showsCompany && !showsStation && !showsAddress }

    private static let fileName = "widget-display.json"

    private static var fileURL: URL {
        PickupStorage.directory.appendingPathComponent(fileName)
    }

    private enum CodingKeys: String, CodingKey {
        case showsCompany, showsStation, showsAddress
    }

    init(showsCompany: Bool, showsStation: Bool, showsAddress: Bool) {
        self.showsCompany = showsCompany
        self.showsStation = showsStation
        self.showsAddress = showsAddress
    }

    /// 🔴 手写解码：每个字段都给默认值。
    /// 以后往这里加字段时，老配置文件缺键也不会让整份选项解码失败。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsCompany = (try? container.decodeIfPresent(Bool.self, forKey: .showsCompany)) ?? true
        showsStation = (try? container.decodeIfPresent(Bool.self, forKey: .showsStation)) ?? false
        showsAddress = (try? container.decodeIfPresent(Bool.self, forKey: .showsAddress)) ?? true
    }

    /// 读取时按档位夹一道：**免费版恒为完整形态**。
    ///
    /// 写入侧（设置页）已经把非免费模板锁住了，这里是第二道保险 ——
    /// 万一旧版本、调试命令或直接改文件写进了"仅取件码"，免费用户的桌面
    /// 也不该出现一个会员功能。🔴 门控放在**读**这一侧才对：
    /// 小组件扩展根本不与设置页通信，它只认这份文件。
    static func effective(isPro: Bool) -> WidgetDisplayOptions {
        isPro ? load() : .full
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

    /// 命中的预设模板（三项组合不完全等于任何模板时是 `.custom`）
    var matchedPreset: WidgetDisplayPreset {
        WidgetDisplayPreset.allCases.first { $0.options == self } ?? .custom
    }
}

// MARK: 预设模板

/// 小组件显示内容的**预设模板**。
///
/// 为什么要有模板而不是只给三个开关：绝大多数用户只想"选一个样子"，
/// 不想理解"平台 / 驿站 / 地址"分别是什么。模板是给人挑的，
/// 三个开关是给挑不出的人自己拧的。
enum WidgetDisplayPreset: String, CaseIterable, Identifiable {
    /// 平台 + 地址（改版前的版式，**免费版唯一可用**）
    case full
    /// 只有取件码 —— 屏幕上最干净的一种
    case codeOnly
    /// 取件码 + 快递平台
    case companyOnly
    /// 取件码 + 快递平台 + 驿站短名（适合"地址长、但一直固定在某个驿站"的人）
    case stationOnly
    /// 三个开关自己拧（付费）
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "完整信息"
        case .codeOnly: return "只要取件码"
        case .companyOnly: return "码 + 快递平台"
        case .stationOnly: return "码 + 驿站"
        case .custom: return "自定义"
        }
    }

    var subtitle: String {
        switch self {
        case .full: return "快递平台｜取件地址"
        case .codeOnly: return "只有取件码，最干净"
        case .companyOnly: return "只看是哪个快递"
        case .stationOnly: return "平台 + 驿站短名，适合固定驿站"
        case .custom: return "平台 / 驿站 / 地址 逐项开关"
        }
    }

    var symbol: String {
        switch self {
        case .full: return "list.bullet.rectangle"
        case .codeOnly: return "number"
        case .companyOnly: return "shippingbox"
        case .stationOnly: return "building.2"
        case .custom: return "slider.horizontal.3"
        }
    }

    /// 模板对应的字段组合；`.custom` 没有固定组合（由三个开关决定）
    var options: WidgetDisplayOptions? {
        switch self {
        case .full:
            return .full
        case .codeOnly:
            return WidgetDisplayOptions(showsCompany: false, showsStation: false, showsAddress: false)
        case .companyOnly:
            return WidgetDisplayOptions(showsCompany: true, showsStation: false, showsAddress: false)
        case .stationOnly:
            return WidgetDisplayOptions(showsCompany: true, showsStation: true, showsAddress: false)
        case .custom:
            return nil
        }
    }

    /// 免费版可用的模板只有「完整信息」。
    var isFree: Bool { self == .full }

    /// 可点选的模板（`custom` 走下面的独立开关行，不在这条单选链里）
    static var selectable: [WidgetDisplayPreset] { allCases.filter { $0 != .custom } }
}
