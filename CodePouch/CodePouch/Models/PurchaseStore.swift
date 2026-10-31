import Foundation
import StoreKit

// MARK: ============================================================================
// 内购（StoreKit 2）
//
// 2026-10-31 主人定：买断制从「粘凭证」改成 **App 内购买**（App Store 3.1.1 要求）。
// 老凭证体系**不删**：已经买过的人继续用凭证验签，改版不能让他们掉权限
// （与 `MembershipPlan` 只增不删是同一条纪律）。
//
// 产品形态：**非消耗型**（一次买断，永久有效，换机用「恢复购买」）。
// 产品 ID 必须与 App Store Connect 里建的一致，否则取不到商品。
//
// ⚠️ 调试方式：本地用 `CodePouch.storekit` 配置（Scheme → Run → StoreKit
//    Configuration 已挂上），模拟器里能走完整购买流程，不需要真实账号。
//    真机 + 免费 Personal Team 时取不到商品（没有 App Store Connect 记录），
//    这是预期现象，不是 bug。
// ============================================================================

@MainActor
final class PurchaseStore: ObservableObject {

    static let shared = PurchaseStore()

    /// 非消耗型「完整版」。改 ID 等于换商品，已购用户会全部丢权益 —— 别改。
    static let productID = "com.jikezhang.codeclip.pro"

    @Published private(set) var product: Product?
    /// 当前是否已购买（来自 `Transaction.currentEntitlements`，已验签）
    @Published private(set) var isOwned = false
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    /// 给界面看的一句话错误（取商品失败 / 用户取消不含在内）
    @Published private(set) var message: String?

    private var updatesTask: Task<Void, Never>?
    private var started = false

    private init() {}

    /// 显示用的价格。**拿不到商品时返回 nil**，界面据此禁用购买键 ——
    /// 不能写死「¥18」，那会和 App Store 上的实际定价对不上（价格由商店配置）。
    var priceText: String? { product?.displayPrice }

    // MARK: 启动

    /// 冷启动调用一次：拉起交易监听、取商品、刷新权益。
    func start() {
        guard !started else { return }
        started = true

        // 交易更新要**一直**听着：Ask to Buy 批准、跨设备购买、退款都会从这里来
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
            await loadProduct()
            await refreshEntitlement()
        }
    }

    // MARK: 取商品

    func loadProduct() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
            if product == nil {
                message = "暂时取不到商品信息，请稍后再试"
            }
        } catch {
            message = "取商品失败：\(error.localizedDescription)"
        }
    }

    // MARK: 购买 / 恢复

    func purchase() async {
        guard let product else {
            message = "商品还没加载好，请稍后重试"
            return
        }
        isPurchasing = true
        message = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlement()
                case .unverified:
                    // 走到这里说明收据没通过系统校验 —— 不放行
                    message = "购买凭据校验失败，请稍后重试"
                }
            case .userCancelled:
                break                       // 用户自己取消，不该弹错误
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
        isPurchasing = true
        message = nil
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()       // 会要求输入 Apple ID 密码
            // 同步之后仍为空 = 这个 Apple ID 确实没买过，此时降级是可信的
            await refreshEntitlement(allowDowngrade: true)
            if !isOwned { message = "这个 Apple ID 下没有找到已购买的记录" }
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
        }
    }

    // MARK: 权益刷新

    /// 以**商店返回的已购列表**为准，写进 App Group 快照供小组件读取。
    ///
    /// 🔴 `allowDowngrade` 的默认值是 **false**，这是刻意的：
    ///    `Transaction.currentEntitlements` 读的是**本机收据**，刚重装、离线、
    ///    或商店暂时不可用时，它会返回空 —— 但用户明明买过。
    ///    若无条件照空集合降级，用户会在换机/断网时莫名其妙变回免费版，
    ///    而且连报错都没有。所以这里只「升级」；**只有用户主动点「恢复购买」**
    ///    （`AppStore.sync()` 之后）才承认"确实没有"并降级。
    func refreshEntitlement(allowDowngrade: Bool = false) async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == Self.productID else { continue }
            guard transaction.revocationDate == nil else { continue }
            owned = true
        }

        if owned {
            isOwned = true
            EntitlementSnapshot.markStoreOwned(true)
        } else if allowDowngrade {
            isOwned = false
            EntitlementSnapshot.markStoreOwned(false)
        } else {
            // 商店没给出结论：沿用快照里已有的状态，别把用户降级
            isOwned = EntitlementSnapshot.load().storeOwned == true
        }
        PickupStore.shared.refreshEntitlement()
    }
}
