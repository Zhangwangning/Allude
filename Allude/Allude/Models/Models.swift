import Foundation
import Combine
import WidgetKit

// MARK: ============================================================================
// App 侧状态层
//
// 数据模型（PickupKind / DayGroup / PickupRecord）与持久化（PickupStorage）已移至
// `AlludeShared/` —— 小组件扩展需要复用同一套定义。
// 本文件保留 App 专属部分：示例数据、写入结果、全局状态、小组件刷新。
// ============================================================================

// MARK: - 示例数据（取自真实短信语料的解析结果）

enum SampleData {
    static func make() -> [PickupRecord] {
        let now = Date()
        func ago(_ minutes: Int) -> Date { now.addingTimeInterval(-Double(minutes) * 60) }
        func lastNight(_ hours: Double) -> Date {
            let calendar = Calendar.current
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return calendar.date(bySettingHour: Int(hours), minute: 0, second: 0, of: yesterday) ?? yesterday
        }
        /// 过去第 n 天的某个时刻（`hour` 支持小数，9.5 = 09:30）。
        ///
        /// 统计页要画「取件频率」的跨天分布，只有今天/昨天的样本是画不出趋势的
        /// —— 这里铺两周的历史已取件记录，让柱状图、公司占比、平均停留都有真实分母。
        func daysAgo(_ days: Int, _ hour: Double) -> Date {
            let calendar = Calendar.current
            let day = calendar.date(byAdding: .day, value: -days, to: now) ?? now
            let wholeHour = Int(hour)
            let minute = Int((hour - Double(wholeHour)) * 60)
            return calendar.date(bySettingHour: wholeHour, minute: minute, second: 0, of: day) ?? day
        }
        /// 一条**已取件**的历史记录：`afterHours` = 从收到到取走花了多久
        /// （统计页的「平均停留」直接由它算出）。
        func history(_ days: Int, _ hour: Double, after afterHours: Double,
                     _ company: String, _ code: String, _ address: String,
                     kind: PickupKind = .code) -> PickupRecord {
            let received = daysAgo(days, hour)
            return PickupRecord(company: company, code: code, kind: kind,
                                address: address,
                                rawMessage: "【\(company)】您的包裹已到达，取件码\(code)，地址：\(address)",
                                receivedAt: received,
                                isPickedUp: true,
                                pickedUpAt: received.addingTimeInterval(afterHours * 3600))
        }

        var records = SmsLibrary.parsedRecords()
        records.append(contentsOf: [
            // ── 历史已取件（过去两周，统计页跨天分布分母） ──────────────────────
            // 只为**统计页**存在：取件频率要跨天样本才画得出趋势，各快递占比需要
            // 足够分母才不会「第一名和最后一名都是 1 件」。全部落在过去 14 天内，
            // 且都是已取件 —— 不干扰首页待取件列表的任何一条口径。
            history(2, 9.5,  after: 3.5, "菜鸟驿站", "8-2-331", "馨月湖小区南门菜鸟驿站"),
            history(2, 19,   after: 1.5, "丰巢", "5521", "甘州院子南门丰巢智能柜"),
            history(3, 11,   after: 5,   "中通快递", "2-3-772", "甘州区西街街道中通驿站"),
            history(3, 17.5, after: 2,   "圆通速递", "9-3-556", "河西学院北门圆通妈妈驿站"),
            history(4, 10,   after: 4,   "兔喜生活", "C-1188", "舜耕中路恒大御府南门西侧3栋104号惠鲜果蔬店"),
            history(5, 14,   after: 1,   "顺丰速运", "6603", "顺丰驿站甘州店", kind: .tail),
            history(5, 16,   after: 22,  "韵达快递", "313105790123456", "张掖市甘州区馨月湖小区南门兴裕隆超市", kind: .waybill),
            history(6, 12,   after: 3,   "京东物流", "7712", "京东快递甘州营业部"),
            history(7, 9,    after: 6,   "菜鸟驿站", "8-1-207", "馨月湖小区南门菜鸟驿站"),
            history(8, 18,   after: 2.5, "极兔速递", "1017-2211", "馨月湖小区北门快递超市"),
            history(9, 13,   after: 4,   "中通快递", "1-2-990", "甘州区西街街道中通驿站"),
            history(10, 20,  after: 12,  "丰巢", "8801", "甘州院子南门丰巢智能柜"),
            history(11, 10.5, after: 3,  "申通快递", "3-8-15", "馨月湖小区北门申通驿站", kind: .special),
            history(12, 15,  after: 5,   "邮政EMS", "4420", "甘州区邮政EMS揽投部"),
            history(12, 11,  after: 2,   "菜鸟驿站", "8-2-004", "馨月湖小区南门菜鸟驿站"),
            history(13, 17,  after: 1.5, "圆通速递", "9-1-330", "河西学院北门圆通妈妈驿站"),
        ])
        return records
    }
}

// MARK: - 解析结果归一

extension PickupParseResult {
    /// 平台名过一遍品牌表纠错（见 `CourierNameCorrector`）。
    ///
    /// 预览与落库都必须用归一后的结果——否则会出现「预览写着免喜生活、
    /// 列表里却是兔喜生活」这种自相矛盾。
    var normalized: PickupParseResult {
        var copy = self
        copy.company = CourierNameCorrector.correct(company)
        return copy
    }
}

// MARK: - 写入结果（供 App 内状态提示 / 动作日志）

/// 一次写入的结果。
///
/// **可能对应多条**：一次粘贴常常就是好几条短信（从短信 App 多选复制），
/// 一张截图里也常有 2–4 条。所以这里是「集合」而不是单一 case，
/// 上层不必关心究竟写进去几条。
struct IngestOutcome: Equatable {
    struct Item: Equatable {
        let company: String
        let code: String
    }

    /// 新写入的条目（顺序 = 短信出现顺序）
    var added: [Item] = []
    /// 因「同码再进」被自动标记为已取的旧条取件码（旧口径，2026-10-30 起恒为空）
    var completed: [String] = []
    /// 本次因「重复通知」只刷新了时间的码（2026-10-30 新增）——
    /// 有了它才能区分「真的没识别到」和「识别到了、是同一件又催了一次」
    var updated: [String] = []
    /// 写入完成后待取件总数
    var pendingCount: Int = 0

    var isEmpty: Bool { added.isEmpty }

    /// 一句话描述本次写入结果。
    /// ⚠️ **不再用于快捷指令弹窗**（`ParsePickup*Intent` 刻意不返回 dialog，见 PickupIntents.swift 文件头），
    /// 现仅服务于 App 内状态提示与截图脚手架日志。
    var dialog: String {
        // 🔴 新增/重复/没认出 是**三种**结果，不能都落到「已忽略」上：
        //    2026-10-30 起同码重复短信不再新建（只更新时间），`added` 为空，
        //    旧文案就会对着一次正常的「更新时间」说「没识别到取件信息」——
        //    用户看到绿色对勾配一句失败文案，以为功能坏了。
        if added.isEmpty {
            if let updatedCode = updated.first {
                return updated.count == 1
                    ? "已更新 \(updatedCode) 的通知时间，当前待取 \(pendingCount) 件"
                    : "已更新 \(updated.count) 条的通知时间，当前待取 \(pendingCount) 件"
            }
            return "没识别到取件信息，已忽略"
        }
        guard let first = added.first else {
            return "没识别到取件信息，已忽略"
        }
        switch (added.count, completed.count) {
        case (1, 0):
            return "已记录 \(first.company) \(first.code)，当前待取 \(pendingCount) 件"
        case (let count, 0):
            return "已记录 \(count) 条取件信息，当前待取 \(pendingCount) 件"
        case (1, 1):
            return "已记录 \(first.company) \(first.code)（上一件同码已自动完成），当前待取 \(pendingCount) 件"
        default:
            return "已记录 \(added.count) 条，另有 \(completed.count) 条同码旧件已自动完成，当前待取 \(pendingCount) 件"
        }
    }
}

// MARK: - 全局状态

final class PickupStore: ObservableObject {
    /// 全局唯一实例：App 界面与 App Intent（快捷指令调用）共用同一份数据，
    /// 避免「快捷指令写进去、界面看不到」的两份状态问题。
    static let shared = PickupStore()

    @Published var records: [PickupRecord] {
        didSet {
            // 批量改动时挂起副作用，由 `batchUpdate` 收尾统一补一次（见下方说明）
            guard !isBatchUpdating else { return }
            persistSideEffects(from: oldValue)
        }
    }

    /// 正在批量改 `records`（2026-10-25 审查修）。
    ///
    /// 对数组元素赋值（`records[i].isPickedUp = true`）同样会触发 `didSet`，
    /// 而 `didSet` 里是「全量编码写盘 + 全量读盘解码重排通知 + 请求小组件刷新」。
    /// 20 条待取点一次「全部已取」= 20 次全量写 + 20 次全量读 + 20 次
    /// `reloadAllTimelines`，全在主线程同步跑 —— 卡顿之外，更实际的损害是
    /// **20 次刷新请求会当场烧掉系统当天给 App 的小组件刷新预算**，之后桌面就不再更新。
    private var isBatchUpdating = false

    /// 一次批量改动的收尾：只落盘 / 刷新一次
    private func batchUpdate(_ body: () -> Void) {
        guard !isBatchUpdating else { body(); return }
        let before = records
        isBatchUpdating = true
        body()
        isBatchUpdating = false
        persistSideEffects(from: before)
    }

    /// `records` 变更后的全部派生动作（写盘 / 小组件 / 实时活动 / 通知）
    private func persistSideEffects(from oldValue: [PickupRecord]) {
        PickupStorage.save(records)
        // 数据一变就请桌面小组件重画。WidgetKit 自身对刷新有预算控制，
        // 短时间内的多次请求会被系统合并，这里不再额外做去抖。
        WidgetCenter.shared.reloadAllTimelines()
        // 实时活动与桌面小组件同一时刻对齐：两条链路的触发点必须一致，
        // 否则会出现「小组件已更新、锁屏还挂着旧取件码」。
        PickupActivityController.sync(pending: pending)
        syncReminders(from: oldValue)
    }

    /// 把取件提醒与数据对齐（records 每次变动后调用）。
    ///
    /// 提醒是数据的**派生物**，同步逻辑集中在这里而不是散在各增删改方法里：
    ///   · 定期提醒的文案带「还有 N 件」快照 —— 数据一变就重排；
    ///   · 「N 小时未取」提醒逐条绑定记录 —— 新变待取的排上、不再待取的撤掉
    ///     （标记已取 / 删除 / 撤销，全部经由 records 变化自然走到这里）。
    /// 同标识的重复 `add` 会被系统覆盖，所以这里的排是幂等的。
    private func syncReminders(from oldValue: [PickupRecord]) {
        PickupNotifier.rescheduleDailyReminder()

        let nowPending = Set(records.filter { !$0.isPickedUp }.map(\.id))
        let beforePending = Set(oldValue.filter { !$0.isPickedUp }.map(\.id))

        for id in nowPending.subtracting(beforePending) {
            if let record = records.first(where: { $0.id == id }) {
                PickupNotifier.schedulePendingReminder(for: record)
            }
        }
        for id in beforePending.subtracting(nowPending) {
            PickupNotifier.cancelPendingReminder(for: id)
        }
    }

    /// 同屏展示上限（2026-11-01 主人定为 4；仅渲染裁剪，数据完整保留）。
    ///
    /// 🔴 **引用共享层常量，不要在这里另写数字**：App 列表与桌面小组件
    ///    必须同一个数字，否则会出现"列表 3 条、小组件 4 条"这种自相矛盾。
    static let freeVisibleLimit = PickupLimits.freeVisible
    /// 免费版短信存储上限（2026-10-30 主人定为 50；超出后 FIFO 淘汰最旧）
    static let freeStorageLimit = 50
    /// 「不限量」的替代值。**不要用 `Int.max`** —— `pending.count - limit`
    /// 这类减法会直接溢出崩溃；一个够大的常数能达到同样效果且安全。
    static let unlimitedCount = 9_999

    /// 当前权益档位 —— 由**本机凭证**决定（2026-10-30 买断制恢复，主人定）。
    ///
    /// 🔴 2026-09-21～2026-10-14 期间这里是恒 `.lifetime`（全功能化，VIP 退役）；
    ///    2026-10-30 起改为凭证驱动：默认 `.none` = 免费档，
    ///    导入有效买断凭证后变 `.lifetime`。
    ///    判定口径见 `refreshEntitlement()`，别直接读 `EntitlementSnapshot.isPro`。
    @Published private(set) var plan: MembershipPlan = .none

    /// 是否已解锁全部能力。
    /// 未解锁时的限制：同屏 4 条（`freeVisibleLimit`）、存储 50 条（`freeStorageLimit`）。
    var isPro: Bool { plan.isActive }

    /// 按本机凭证重算权益。**导入凭证成功后必须调一次**，否则界面还停在免费档。
    ///
    /// 判断本身在共享层 `EntitlementSnapshot.licensedPro` —— 小组件扩展也读同一份，
    /// 两边口径必须一致（App 判免费、桌面却给满量的那种事不能再有）。
    func refreshEntitlement() {
        let snapshot = EntitlementSnapshot.load()
        plan = EntitlementSnapshot.licensedPro ? snapshot.plan : .none
    }

    private init() {
        // 首次启动用示例数据铺底，之后一律以本地文件为准。
        // 🔴 判首启要看**文件在不在**，不能看「加载结果空不空」（2026-10-25 审查修）：
        // 用户把记录全删光后 json 就是 `[]`，用 `isEmpty` 判会把示例数据重新灌回去；
        // 同理，解码失败（文件损坏 / 未来模型改字段）也会被误判成首启，
        // 那等于用示例数据覆盖掉用户真实数据 —— 宁可显示空列表，也不能这样丢。
        let hasStoreFile = PickupStorage.fileExists
        let loaded = hasStoreFile ? PickupStorage.load() : []
        records = hasStoreFile ? loaded : SampleData.make()
        if !hasStoreFile { PickupStorage.save(records) }

        // 顺序有讲究：先「补空字段」，再「清仅货架地址」——
        // 反过来的话，刚补回来的地址会被下一条规则又清掉。
        normalizeDerivedFields()
        sanitizeShelfAddresses()
        dedupeIdenticalRecords()
        purgeInvalidCodes()
        // 放在最后：前面几步与权益无关，等数据就位再定档位。
        // 🔴 注意这里**不会**触发 `enforceStorageLimit()` —— 那个只在 `ingest()` 里跑，
        //    所以「免费档超量」不会在启动瞬间删数据，用户还有机会先导入凭证。
        refreshEntitlement()
    }

    /// 存量记录按**当前解析规则**刷新派生字段（2026-10-30）。
    ///
    /// 为什么需要：解析规则会演进（比如「柜A3」→「A3」、快递公司归一到标准名），
    /// 但旧记录里的字段是**入库那一刻**的快照，不会自己变。好在每条记录都存着
    /// `rawMessage`（原始短信），可以拿它重跑一遍解析。
    ///
    /// 三条原则，全部保守：
    ///  1. **只补空、不覆盖** —— 用户手工改过的字段（地址、驿站、货架）一律不动；
    ///  2. 只做「确定是格式问题」的改写：柜位去掉重复的「柜」前缀、公司名归一；
    ///  3. 幂等：没有命中就不写盘。
    private func normalizeDerivedFields() {
        var changed = false

        for index in records.indices {
            var record = records[index]
            var touched = false

            // ① 柜位：短信写「快递柜A3」，历史数据存成了「柜A3」→ 去掉重复前缀
            if let locker = record.locker?.trimmingCharacters(in: .whitespaces),
               locker.count > 1, locker.hasPrefix("柜") {
                record.locker = String(locker.dropFirst())
                touched = true
            }

            // ② 快递公司：历史数据可能只有词根（「申通」）→ 归一成标准名
            if let courier = record.courier?.trimmingCharacters(in: .whitespaces), !courier.isEmpty {
                let canonical = CourierBrand.canonicalName(for: courier)
                if canonical != courier {
                    record.courier = canonical
                    touched = true
                }
            }

            // ③ 拿原始短信重解析，**只补空字段**（解析没识别出来、后来又支持了的写法）
            if !record.rawMessage.isEmpty, let parsed = PickupParser.parse(record.rawMessage) {
                func fill(_ old: String?, _ new: String, _ assign: (String) -> Void) {
                    guard (old ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
                          !new.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    assign(new)
                    touched = true
                }
                fill(record.locker, parsed.locker) { record.locker = $0 }
                fill(record.shelf, parsed.shelf) { record.shelf = $0 }
                fill(record.waybill, parsed.waybill) { record.waybill = $0 }
                fill(record.tail, parsed.tail) { record.tail = $0 }
                fill(record.courier, CourierBrand.canonicalName(for: parsed.courier)) { record.courier = $0 }
                fill(record.address, parsed.address) { record.address = $0 }
            }

            if touched {
                records[index] = record
                changed = true
            }
        }

        if changed {
            PickupStorage.save(records)
            // 回填是一次性动作（不是每条记录变更），这里单独请桌面重画一次即可
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// 存量重复记录合并（2026-10-30）。
    ///
    /// 旧口径是「同码再进 → 旧条标已取 + 新条入列」，但历史上出现过两条**完全一样**
    /// 的待取记录同时躺着（真机实证：「韵达快递｜欢猫驿站｜7-4-2011」两条，
    /// 时间只差 15 秒）—— 多半是并发写入或旧版本漏拦留下的。
    ///
    /// 这里按指纹把重复的**待取**记录并成一条：留 `receivedAt` 最早的那条
    /// （统计口径不变），把各条的 `history` 合并排序写回去，其余删除。
    /// 已取记录一律不碰（那是历史，删掉会篡改统计）。
    private func dedupeIdenticalRecords() {
        var keep: [String: Int] = [:]          // 指纹 → records 里的下标
        var mergedHistories: [Int: [Date]] = [:]
        var removed = false
        var survivors: [PickupRecord] = []

        for record in records {
            guard !record.isPickedUp else {
                survivors.append(record)
                continue
            }
            let key = record.fingerprint
            if let index = keep[key] {
                // 命中重复：时间并入先前保留的那条
                var history = mergedHistories[index] ?? [survivors[index].receivedAt]
                history.append(contentsOf: record.history ?? [record.receivedAt])
                mergedHistories[index] = history
                removed = true
            } else {
                keep[key] = survivors.count
                survivors.append(record)
            }
        }

        guard removed else { return }

        for (index, history) in mergedHistories {
            let sorted = Array(Set(history)).sorted()
            survivors[index].history = sorted
            // receivedAt 保持最早那条不动，统计的停留时长才不失真
            survivors[index].receivedAt = sorted.first ?? survivors[index].receivedAt
        }

        records = survivors
        PickupStorage.save(records)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 清掉「取件码其实是整段短信」的垃圾记录（2026-10-30）。
    ///
    /// 起因：添加页的兜底分支曾把整段原文当成裸码写入，列表里出现
    /// 「手动添加 / 快递超市 / 您的圆通快递包裹已…」这种东西。
    /// 取件码的字符集里不可能有中文或空白，命中即判定为脏数据。
    private func purgeInvalidCodes() {
        let valid = records.filter { record in
            let code = record.code
            guard !code.isEmpty, code.count <= 24 else { return false }
            if code.contains(where: { $0.isWhitespace }) { return false }
            // CJK 统一表意文字区段（0x2E80 起）—— 取件码不会出现汉字
            if code.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) { return false }
            return true
        }
        guard valid.count != records.count else { return }
        records = valid
        PickupStorage.save(records)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 存量数据清洗：把「地址字段其实只是货架描述」的记录修正一次（2026-10-25）。
    ///
    /// 解析期的拦截只对**新短信**生效，之前入库的记录里地址仍然是「3号货架」
    /// 这种东西 —— 卡面上与「货架3」标签重复显示，详情页地图还会拿它去地理编码
    /// （永远解析失败，导航按钮形同虚设）。
    ///
    /// 幂等且保守：只动「地址完全等于货架描述」的，带门店名的一律不碰；
    /// 没有命中就完全不写盘。
    private func sanitizeShelfAddresses() {
        var changed = false
        for index in records.indices {
            guard PickupRecord.addressIsShelfOnly(records[index].address,
                                                 shelf: records[index].shelf)
            else { continue }
            records[index].address = ""
            changed = true
        }
        if changed { PickupStorage.save(records) }
    }

    // 🔴 2026-10-14 全功能化：`setPlan` / `reloadEntitlement` 随 VIP 体系一并退役 ——
    // 档位不再有任何运行时改写入口，「导入凭证」链路整个下线。

    // MARK: 派生集合

    var pending: [PickupRecord] {
        // 排序口径 = 卡面显示的时间（最后一次通知），与 `dayGroup` 保持一致
        records.filter { !$0.isPickedUp }.sorted { $0.lastNotifiedAt > $1.lastNotifiedAt }
    }

    var pickedUpRecords: [PickupRecord] {
        records.filter(\.isPickedUp).sorted { $0.receivedAt > $1.receivedAt }
    }

    /// 当前档位下的同屏上限（免费 4 条 / 全功能不限）
    var visibleLimit: Int {
        isPro ? Self.unlimitedCount : Self.freeVisibleLimit
    }

    var visiblePending: [PickupRecord] {
        Array(pending.prefix(visibleLimit))
    }

    var hiddenCount: Int {
        max(0, pending.count - visibleLimit)
    }

    var todayNewCount: Int {
        pending.filter { Calendar.current.isDateInToday($0.receivedAt) }.count
    }

    /// 今天**取走**的件数 —— 按 `pickupMoment`（取件时刻）算，不是按入库时刻。
    /// 🔴 与统计页 `PickupStats.pickedToday` 同口径（2026-10-25 审查修）：
    /// 以前这里用 `receivedAt`，于是「昨天收到、今天取走」的件在首页记 0、
    /// 在统计页记 1，同一天两个数字对不上；而且首页数字本身的语义也错了
    /// （它在数「今天收到的短信里已取的」）。
    var todayPickedCount: Int {
        pickedUpRecords.filter { Calendar.current.isDateInToday($0.pickupMoment) }.count
    }

    /// 存储占用
    var storageUsed: Int { records.count }
    var storageLimit: Int { isPro ? Self.unlimitedCount : Self.freeStorageLimit }

    /// 按「今天 / 昨天 / 更早」分组，空组自动剔除，顺序固定
    func grouped(_ list: [PickupRecord]) -> [(group: DayGroup, items: [PickupRecord])] {
        DayGroup.allCases.compactMap { group in
            let items = list.filter { $0.dayGroup == group }
            return items.isEmpty ? nil : (group, items)
        }
    }

    /// 统一筛选入口：只剩搜索词一个维度。
    ///
    /// 演进记录：曾同时支持 `company` 与 `kind` 两个筛选维度；2026-10-27 主人精简
    /// 筛选菜单后两者都没有入口了 —— 「按快递公司」改为**归类分组**（`PickupSortMode.company`），
    /// 不再是"只看某一家"的筛选。参数一并删除，避免留下死参数。
    func filtered(_ list: [PickupRecord], query: String = "") -> [PickupRecord] {
        list.filter { $0.matches(query) }
    }

    // MARK: 写入（快捷指令 → App）

    /// 解析一段文本并写入。**支持一次多条**：粘贴多行短信、截图里有多条，
    /// 都会逐条解析、逐条落库；识别不出取件信息的段直接跳过，不影响其它条。
    @discardableResult
    func ingest(_ text: String) -> IngestOutcome {
        let results = PickupParser.parseAll(text, ocrSource: false)
        // 只记「发生了什么」：来源、原文长度、解析出几条。**不记内容**。
        DiagnosticsLog.record("parse", "source=sms len=\(text.count) results=\(results.count)")
        // 分类器旁路观察（2026-11-05）：**只看不改**。
        // 快递短信漏一条就少一个码，模型在测试集里仍误杀 1 条 ——
        // 先在真实短信上积累对照，确认零误杀再考虑启用过滤。
        let verdict = PickupClassifier.classify(text)
        if verdict.verdict != .unavailable, results.isEmpty != (verdict.verdict == .other) {
            DiagnosticsLog.record("classifier",
                                  "disagree verdict=\(verdict.verdict.rawValue) "
                                  + "conf=\(String(format: "%.2f", verdict.confidence)) "
                                  + "parsed=\(results.count)")
        }
        return commitAll(results)
    }

    /// OCR 来源的写入（相册识别 / 扫码 / 手动粘贴）。
    ///
    /// 与 `ingest` 的差别只在**段内**要不要走多假设归一：短信原文的换行是语义
    /// 换行，直接解析即可；OCR 的换行多来自视觉折行，会切断定长 lookbehind 锚点，
    /// 必须先归一。切段规则两者相同（都以「【」起头为新的一条）。
    @discardableResult
    func ingestOCR(_ text: String) -> IngestOutcome {
        let results = PickupParser.parseAll(text, ocrSource: true)
        DiagnosticsLog.record("parse", "source=ocr len=\(text.count) results=\(results.count)")
        return commitAll(results)
    }

    /// 落库：所有入口共用同一套合并策略（`PickupMerge`）与存储上限。
    ///
    /// 改动的是**一次性提交**：先把结果攒在局部数组里，最后整体赋值给 `records`。
    /// 若在循环里逐条 append，`records` 的 `didSet` 会触发 N 次 —— N 次写盘 +
    /// N 次请小组件重画，5 条短信就是 5 遍，纯属浪费。
    private func commitAll(_ parsed: [PickupParseResult]) -> IngestOutcome {
        // 🔴 地址记忆：用户改过的驿站地址，优先于本次解析结果（2026-11-05）
        let parsed = parsed.map { result -> PickupParseResult in
            var copy = result
            if let station = StationDirectory.shared.matchedName(in: [result.rawText]),
               let remembered = PickupAddressMemory.address(for: station) {
                copy.address = remembered
            }
            return copy
        }
        var outcome = IngestOutcome()
        guard !parsed.isEmpty else {
            outcome.pendingCount = pending.count
            return outcome
        }

        let candidates = parsed.map { item -> PickupRecord in
            let item = item.normalized
            return PickupRecord(company: item.company,
                                code: item.value,
                                kind: item.kind,
                                address: item.address,
                                rawMessage: item.rawText,
                                receivedAt: Date(),
                                isPickedUp: false,
                                // 扩展字段（2026-09-23）：快递公司 / 次要凭证。
                                // 主凭证就是运单号 / 尾号时不重复存（nil），避免同一串
                                // 数字在卡片上出现两遍。
                                // 归一到品牌表标准名（「申通」→「申通快递」），2026-10-28
                                courier: item.courier.isEmpty ? nil
                                    : CourierBrand.canonicalName(for: item.courier),
                                waybill: item.kind == .waybill ? nil
                                    : (item.waybill.isEmpty ? nil : item.waybill),
                                tail: item.kind == .tail ? nil
                                    : (item.tail.isEmpty ? nil : item.tail),
                                shelf: item.shelf.isEmpty ? nil : item.shelf,
                                locker: item.locker.isEmpty ? nil : item.locker,
                                history: [Date()],
                                pickedUpAt: nil)
        }

        // 同码再进 → 旧条自动完成 + 新条入列（见 PickupMerge 的语义说明）
        let merged = PickupMerge.merge(records, with: candidates)
        outcome.added = merged.added.map { .init(company: $0.company, code: $0.code) }
        outcome.completed = merged.completed
        outcome.updated = merged.updated.map(\.code)

        records = merged.records
        enforceStorageLimit()
        // 通知**只对新写入的发**：被自动完成的旧条再发一遍毫无价值。
        // 放在落库之后，确保用户点通知进来时记录已经在列表里。
        PickupNotifier.notifyAdded(merged.added)

        // 🆕 端侧 AI 兜底（2026-10-28）：正则漏掉的字段，后台补。
        // ⚠️ 必须在 `records` 落库之后调用 —— 它要按 id 回写；
        //    也不阻塞返回值，列表先有条目、字段后到。
        if #available(iOS 26.0, *) {
            PickupAIEnhancer.schedule(merged.added)
        }

        outcome.pendingCount = pending.count
        return outcome
    }

    /// 免费版存储上限：超出后按时间淘汰最旧。全功能档不淘汰。
    private func enforceStorageLimit() {
        guard !isPro, records.count > Self.freeStorageLimit else { return }
        let newest = records.sorted { $0.receivedAt > $1.receivedAt }
            .prefix(Self.freeStorageLimit)
        records = Array(newest)
    }

    /// 手动 / 扫码添加一个「裸码」—— 手上只有一串取件码、没有短信原文时的入口。
    ///
    /// 复用 `commitAll`，因此与自动收件共用同一套归一与去重指纹：
    /// 自动收过的码再手动加一次会被正确拦下，不会因为走了不同入口就重复。
    @discardableResult
    func addManual(code rawCode: String,
                   company: String = "手动添加",
                   address: String = "") -> IngestOutcome {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return IngestOutcome() }

        return commitAll([PickupParseResult(kind: .code,
                                            value: code,
                                            company: company,
                                            address: address,
                                            rawText: code)])
    }

    /// 结构化入库：确认页上**用户校对过**的结果直接落库（2026-09-23）。
    ///
    /// 🔴 为什么不复用 `ingestOCR`：那条路径会拿**原文**重新跑一遍正则，
    /// 用户手改的字会被解析器当场覆盖回去 —— 改了等于没改。
    /// 识别不可靠时，人眼才是最终真相；所以确认页的数据源是草稿，
    /// 不再经过正则。段内切分、同码合并等落库策略仍共用 `commitAll`。
    ///
    /// 空码在这一层就滤掉（用户可能把某条整行删空），避免写进一条没有码的记录。
    @discardableResult
    func commitEdited(_ items: [PickupParseResult]) -> IngestOutcome {
        commitAll(items.filter {
            !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
    }

    // MARK: 变更

    /// 从共享容器重新读盘。
    ///
    /// 存在场景：**桌面小组件上的圆形勾选框**由扩展进程直接改 App Group 文件，
    /// 此时 App 可能正在后台持有旧的内存副本 —— 回到前台时不重读，
    /// 就会出现「桌面已勾、App 里还没勾」的两份状态。
    ///
    /// 比较口径刻意**不含时间戳**：`PickupStorage` 用 ISO8601 编码（无小数秒），
    /// 读回来的 `Date` 精度低于内存副本，若按整体 `==` 比较会永远判为「有变化」，
    /// 导致每次回前台都无谓写盘并触发一次小组件刷新。这里只比对
    /// 「记录 id 集合 + 各自的已取状态」，语义上正好覆盖小组件能改动的范围。
    func reloadFromStorage() {
        let loaded = PickupStorage.load()
        guard Self.signature(of: loaded) != Self.signature(of: records) else { return }
        records = loaded
    }

    private static func signature(of list: [PickupRecord]) -> Set<String> {
        Set(list.map { "\($0.id.uuidString)|\($0.isPickedUp)" })
    }

    func markPicked(_ record: PickupRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        setPicked(true, at: index)
    }

    /// 批量标记已取（多选「已取」专用）—— 一次落盘 / 一次刷新小组件。
    /// 逐条调上面的 `markPicked` 会触发 N 次全量写盘 + N 次 `reloadAllTimelines`
    /// （2026-10-25 审查修，理由见 `isBatchUpdating`）。
    func markPicked(_ list: [PickupRecord]) {
        batchUpdate {
            for record in list { markPicked(record) }
        }
    }

    func markPending(_ record: PickupRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        setPicked(false, at: index)
    }

    /// 编辑保存：按 id **整条替换**（卡片长按「编辑」与详情页「编辑」的唯一落点）。
    ///
    /// 走整条替换而不是逐字段拷：调用方传进来的就是校验过的新值（含归一后的
    /// 可选字段），逐字段拷迟早漏掉新加的字段。`id` / `receivedAt` / `isPickedUp` /
    /// `pickedUpAt` 不参与编辑 —— 传入值这些字段保持原记录即可（调用方用原记录打底）。
    func update(_ edited: PickupRecord) {
        guard let index = records.firstIndex(where: { $0.id == edited.id }) else { return }
        records[index] = edited
    }

    /// 卡片内一键切换（首页/记录页直接调用，无需进入详情）
    func toggle(_ record: PickupRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        setPicked(!records[index].isPickedUp, at: index)
    }

    /// 标记已取 / 恢复待取的**唯一落点** —— 状态与时间戳必须成对改。
    ///
    /// 时间戳不能散在各调用点自己写：漏一处就会出现「已取但查不到取件时刻」的记录，
    /// 统计页的平均停留会把它算成异常值（耗时被记为 0 或与入库时间混为一谈）。
    /// 翻到「已取」时只在原本没有时间戳的情况下补写 —— 重复标记不刷新取件时刻。
    private func setPicked(_ picked: Bool, at index: Int) {
        records[index].isPickedUp = picked
        records[index].pickedUpAt = picked ? (records[index].pickedUpAt ?? Date()) : nil
    }

    /// 批量标记已取，返回被改动的记录以便撤销
    @discardableResult
    func markAllPendingAsPicked() -> [PickupRecord] {
        let changed = pending
        let stamp = Date()
        batchUpdate {
            for record in changed {
                if let index = records.firstIndex(where: { $0.id == record.id }) {
                    records[index].isPickedUp = true
                    records[index].pickedUpAt = records[index].pickedUpAt ?? stamp
                }
            }
        }
        return changed
    }

    /// 撤销：把给定记录恢复为待取件。
    ///
    /// `pickedUpAt` 一并回退到**传入快照的值**（撤销「完成」时快照的该值为 nil）——
    /// 只翻 `isPickedUp` 会让已经取消的取件动作在统计里留下一条幽灵耗时。
    func restore(_ recordsToRestore: [PickupRecord]) {
        batchUpdate {
            for record in recordsToRestore {
                if let index = records.firstIndex(where: { $0.id == record.id }) {
                    records[index].isPickedUp = false
                    records[index].pickedUpAt = record.pickedUpAt
                }
            }
        }
    }

    /// 删除单条
    func delete(_ record: PickupRecord) {
        records.removeAll { $0.id == record.id }
    }

    /// 批量删除（记录页多选删除专用）。
    ///
    /// 一次性移除再让 didSet 统一落盘 / 刷新小组件 —— 不逐条调 `delete`，
    /// 避免 N 条 = N 次全量写盘。
    func deleteMany(_ recordsToDelete: [PickupRecord]) {
        let ids = Set(recordsToDelete.map(\.id))
        records.removeAll { ids.contains($0.id) }
    }

    /// 把记录放回库中 —— 撤销「删除」专用。
    ///
    /// 与 `restore` 的分工：`restore` 只翻转**已存在**记录的取件状态（撤销"标记为已取"），
    /// 记录被删掉后它找不到索引，什么也做不了。撤销删除必须用本方法重新插入。
    /// `records` 的数组顺序不影响任何展示（各派生集合都会自己按时间排序），
    /// 因此直接 append 即可，不必还原原位。
    func insert(_ recordsToInsert: [PickupRecord]) {
        let existing = Set(records.map(\.id))
        records.append(contentsOf: recordsToInsert.filter { !existing.contains($0.id) })
    }

    /// 清空已取件记录
    func clearPickedUp() {
        records.removeAll { $0.isPickedUp }
    }
}
