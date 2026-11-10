import Foundation
import StoreKit

// MARK: ============================================================================
// 内购（StoreKit 2）· 免费下载 + 订阅解锁
//
// 2026-10-31 主人定（参考 Infuse）：App 免费下载，三档可选
//   · 每月  ¥1   自动续期订阅
//   · 每年  ¥9   自动续期订阅（比月付划算，主推）
//   · 终身  ¥18  非消耗型，一次买断（≈ 两年年费，两年回本后永久有效）
//
// 三档解锁的是同一件事，所以权益判定 = **任意一档有效即算完整版**。
//
// 🔴 订阅会过期，权益**必须带到期时间**写进快照：
//    小组件进程不联网、也不该去问 StoreKit，它只读 `entitlement.json`。
//    没有 `expiresAt` 的话，订阅过期后小组件会一直按完整版渲染，
//    直到用户恰好打开一次主 App —— 那是"过期了还在用"的口子。
//
// ⚠️ 调试：本地用 `Allude.storekit` 配置（Scheme → Run 已挂上），
//    只能在 Xcode 里跑通，`simctl launch` 不会注入该配置。
// ============================================================================

@MainActor
final class PurchaseStore: ObservableObject {

    // MARK: 商品

    /// 三档商品。`rawValue` 拼进 product ID —— 改名字等于换商品，已购用户会丢权益。
    enum Plan: String, CaseIterable, Identifiable {
        // 顺序即界面顺序：**买断排第一**（主推），订阅在后
        case lifetime, yearly, monthly

        var id: String { rawValue }

        /// 必须与 App Store Connect 里建的 ID 完全一致
        var productID: String { "com.jikezhang.allude.pro." + rawValue }

        var title: String {
            switch self {
            case .monthly: "每月"
            case .yearly: "每年"
            case .lifetime: "终身"
            }
        }

        /// 周期说明（买断没有周期）
        var period: String {
            switch self {
            case .monthly: "按月自动续期"
            case .yearly: "按年自动续期"
            case .lifetime: "一次付费，永久使用，不续期"
            }
        }

        /// 横排卡片第三行的极短说明（一行放得下）
        var shortPeriod: String {
            switch self {
            case .monthly: "按月"
            case .yearly: "按年"
            case .lifetime: "永久"
            }
        }

        /// 界面上的推荐位。2026-10-31 主人定：**主推买断** ——
        /// 一次付清、永久使用，用户不用记着取消订阅，售后也少。
        var isRecommended: Bool { self == .lifetime }
    }

    static let shared = PurchaseStore()

    /// 🔴 2026-11-08 主人：**只卖两档** —— 终身（主推）与每年。
    /// `monthly` 这个 case 留着只为兼容旧数据解码（App Store 里也已下架），
    /// 界面与商品请求都不再出现它。
    static var displayedPlans: [Plan] { [.lifetime, .yearly] }

    static var allProductIDs: [String] { displayedPlans.map(\.productID) }

    // MARK: 状态

    /// 已取到的商品（按 product ID 索引）。取不到时为空，界面据此禁用购买键。
    @Published private(set) var products: [String: Product] = [:]
    /// 当前是否已解锁（来自 `Transaction.currentEntitlements`，已验签）
    @Published private(set) var isOwned = false
    @Published private(set) var isLoading = false
    @Published private(set) var purchasingPlan: Plan?
    /// 给界面看的一句话提示（取商品失败 / 购买成功等）
    @Published private(set) var message: String?

    private var updatesTask: Task<Void, Never>?
    private var started = false

    private init() {}

    /// 某档的商店价格；取不到就是 nil，界面显示「—」并禁用按钮。
    /// **不要写死价格**：定价在 App Store Connect 改，代码里写死就对不上。
    func price(for plan: Plan) -> String? {
        products[plan.productID]?.displayPrice
    }

    var canPurchase: Bool { !products.isEmpty }

    // MARK: 启动

    func start() {
        guard !started else { return }
        started = true

        // 交易更新要一直听着：续期、Ask to Buy 批准、跨设备购买、退款都从这里来
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self.refreshEntitlement()
            }
        }

        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await Product.products(for: Self.allProductIDs)
            products = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
            if products.isEmpty {
                message = "暂时取不到商品信息，请稍后再试"
            } else {
                message = nil
            }
        } catch {
            message = "取商品失败：\(error.localizedDescription)"
        }
    }

    // MARK: 购买 / 恢复

    func purchase(_ plan: Plan) async {
        guard let product = products[plan.productID] else {
            message = "商品还没加载好，请稍后重试"
            return
        }
        purchasingPlan = plan
        message = nil
        defer { purchasingPlan = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlement()
                    message = "已解锁 Allude Pro"
                case .unverified:
                    message = "购买凭据校验失败，请稍后重试"
                }
            case .userCancelled:
                break                       // 用户自己取消，不弹错误
            case .pending:
                message = "购买待确认，完成后会自动生效"
            @unknown default:
                break
            }
        } catch {
            message = "购买失败：\(error.localizedDescription)"
        }
    }

    func restore() async {
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()       // 会要求输入 Apple ID 密码
            // 同步之后仍为空 = 这个 Apple ID 确实没有有效权益，此时降级是可信的
            await refreshEntitlement(allowDowngrade: true)
            if !isOwned { message = "这个 Apple ID 下没有找到有效订阅或购买记录" }
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
        }
    }

    // MARK: 权益

    /// 扫一遍已购列表，算出「是否解锁」与「最晚到期时间」。
    ///
    /// `currentEntitlements` 对订阅只返回**仍然有效**的那些，所以到期自然消失；
    /// 非消耗型则一直返回。两者混在一起取 max：有终身就是 nil（永不过期）。
    ///
    /// 🔴 `allowDowngrade` 默认 **false**：这个集合读的是本机收据，
    ///    刚重装 / 离线 / 商店暂时不可用时会返回空 —— 但用户明明买过。
    ///    无条件照空集合降级 = 换机断网就掉权益，而且没有报错。
    ///    只有用户主动「恢复购买」（`AppStore.sync()` 之后）才承认"确实没有"。
    func refreshEntitlement(allowDowngrade: Bool = false) async {
        var owned = false
        var latestExpiry: Date?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard Self.allProductIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            guard let expiry = transaction.expirationDate else {
                // 非消耗型：没有到期时间 = 永久
                owned = true
                latestExpiry = nil
                break
            }
            guard expiry > Date() else { continue }
            owned = true
            latestExpiry = max(latestExpiry ?? .distantPast, expiry)
        }

        if owned {
            isOwned = true
            EntitlementSnapshot.markStoreOwned(true, expiresAt: latestExpiry)
        } else if allowDowngrade {
            isOwned = false
            EntitlementSnapshot.markStoreOwned(false, expiresAt: nil)
        } else {
            // 商店没给出结论：沿用快照（快照自己会按 expiresAt 判过期）
            isOwned = EntitlementSnapshot.licensedPro
        }
        PickupStore.shared.refreshEntitlement()
    }
}
