import SwiftUI
import UIKit

// MARK: ============================================================================
// 本地账户（2026-09-23 深夜二版：**单账户化**）
//
// 一版是"可多枚的本机档案"；主人深夜定稿：「不支持多账户了，也不支持
// 退出/登录功能，账户直接内置，用户可以自定义信息就可以了」。
//
// 所以现在的边界：
//   · **恒有且只有一个账户** —— 出厂内置，随 App 存在；没有清单、没有切换、
//     没有新建/删除；不登录、不联网、无密码；
//   · 用户能改的只有两样：**名字 + 头像**（含上传自定义头像）；
//   · 🔴 **取件记录不按账户隔离** —— 记录属于这台设备。
//
// 🔴 存储（保持向后兼容）：
//   · 老版本的多账户 JSON（`codeclip.localAccounts`）读进来后**收敛到一份**：
//     优先用"当前账户"，没有就用第一枚 —— 用户改过的名字与头像不丢；
//   · 自定义头像 = **App 沙盒** `Application Support/AccountAvatars/<uuid>.jpg`
//     （刻意不落 App Group：小组件与实时活动不显示头像）；
//   · 头像一律**居中裁方 + 缩到 512 + JPEG 0.85**。
// ============================================================================

// MARK: - 一个账户

/// 本机账户：**一个名字 + 一张头像**。没有任何身份凭证。
struct LocalAccount: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = LocalAccountStore.defaultName
    /// 头像款式（存 `rawValue` 而不是枚举，解码时好兜底）
    var avatarRaw: String = AccountAvatarStyle.fallback.rawValue
    /// 自定义头像的文件名（仅当用户上传过；文件在 `AccountAvatars/` 下）
    var customAvatarFileName: String?
    var createdAt: Date = Date()

    init(id: UUID = UUID(),
         name: String = LocalAccountStore.defaultName,
         avatar: AccountAvatarStyle = .fallback,
         customAvatarFileName: String? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.avatarRaw = avatar.rawValue
        self.customAvatarFileName = customAvatarFileName
        self.createdAt = createdAt
    }

    /// 🔴 款式名解不出来时回落到 `fallback` —— 用户降级、或我们哪天删掉某一款，
    ///    直接取 `rawValue` 当款式的写法会让头像变成一片空白。
    var avatar: AccountAvatarStyle {
        get { AccountAvatarStyle(rawValue: avatarRaw) ?? .fallback }
        set { avatarRaw = newValue.rawValue }
    }

    /// 首字头像用的那个字（中文取首字，英文转大写首字母）
    var initial: String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "码"
        }
        return String(first).uppercased()
    }

    // 手写解码：每个字段 decodeIfPresent + 默认值
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        let rawName = (try? container.decode(String.self, forKey: .name)) ?? ""
        name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? LocalAccountStore.defaultName : rawName
        avatarRaw = (try? container.decode(String.self, forKey: .avatarRaw))
            ?? AccountAvatarStyle.fallback.rawValue
        customAvatarFileName = try? container.decode(String.self,
                                                      forKey: .customAvatarFileName)
        createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? Date()
    }
}

// MARK: - 账户仓库

/// 全 App 唯一的账户仓库（`App` 与各视图共用一份）。
///
/// 之所以要 `ObservableObject` 而不是像以前那样的纯 `enum` 静态读写：
/// 现在改名与换头像会**立刻**影响三处显示（右上角头像、账户卡、账户页），
/// 发布机制能让它们自己重画，不必再靠手写的 `bump()` 回调逐个通知。
final class LocalAccountStore: ObservableObject {
    static let shared = LocalAccountStore()

    /// 出厂默认名。中性的一个词，谁都不冒犯，改不改都行。
    static let defaultName = "我的账户"

    /// 名字最大长度：不设限的话，一个 40 字的名字会把账户卡整行挤爆。
    static let nameLimit = 20

    /// 内部仍存数组（老版本 JSON 迁移需要），但**对外语义是单账户**：
    /// UI 只允许读写 `current`。
    @Published private(set) var accounts: [LocalAccount] = []

    private let defaults = UserDefaults.standard

    /// 🔴 `[UUID: UIImage?]`：外层区分"这个头像读过了没"、内层才是"读出来是什么"。
    /// 单层 Optional 没法区分这两件事 → 每帧都要重新读盘解图。
    private var avatarCache: [UUID: UIImage?] = [:]

    private static let accountsKey = "codeclip.localAccounts"
    private static let currentKey = "codeclip.currentAccountID"

    private init() { load() }

    // MARK: 读取

    /// 当前账户（= 唯一账户）。**恒有值**。
    var current: LocalAccount {
        accounts.first ?? LocalAccount()
    }

    /// 供 `AccountAvatar` 按账户取数据（组件保持通用，实际只会有 current 一个 id）。
    func account(_ id: UUID) -> LocalAccount {
        accounts.first { $0.id == id } ?? current
    }

    /// 传过的自定义头像；没上传过（或读不出来）时 nil。
    func customAvatarImage(for id: UUID) -> UIImage? {
        if let cached = avatarCache[id] { return cached }
        var image: UIImage?
        if let fileName = accounts.first(where: { $0.id == id })?.customAvatarFileName {
            image = UIImage(contentsOfFile: Self.avatarURL(fileName: fileName).path)
        }
        avatarCache.updateValue(image, forKey: id)
        return image
    }

    // MARK: 写入（只作用于唯一账户）

    /// 改名。空名字不接受。
    func renameCurrent(to raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !accounts.isEmpty else { return }
        accounts[0].name = String(trimmed.prefix(Self.nameLimit))
        persist()
    }

    func setAvatar(_ style: AccountAvatarStyle) {
        guard !accounts.isEmpty else { return }
        accounts[0].avatar = style
        persist()
    }

    /// 存入用户从相册选的照片（落盘 + 自动切到「自定义」款）。
    @discardableResult
    func saveCustomAvatar(_ data: Data) -> Bool {
        guard !accounts.isEmpty,
              let image = UIImage(data: data),
              let jpeg = Self.squareScaled(image, side: 512)
                  .jpegData(compressionQuality: 0.85) else { return false }

        let id = accounts[0].id
        let fileName = "\(id.uuidString).jpg"
        do {
            try jpeg.write(to: Self.avatarURL(fileName: fileName), options: .atomic)
        } catch {
            return false
        }

        accounts[0].customAvatarFileName = fileName
        accounts[0].avatar = .custom
        avatarCache.removeValue(forKey: id)      // 缓存作废，下次读盘拿新图
        persist()
        return true
    }

    // MARK: 持久化

    private func persist() {
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: Self.accountsKey)
        }
        if let first = accounts.first {
            defaults.set(first.id.uuidString, forKey: Self.currentKey)
        }
    }

    private func load() {
        // ① 已有数据（含老版本的多账户 JSON）：**收敛到一份** ——
        //    优先"当前账户"，没有就取第一枚。用户改过的名字与头像不丢。
        if let data = defaults.data(forKey: Self.accountsKey),
           let list = try? JSONDecoder().decode([LocalAccount].self, from: data),
           !list.isEmpty {
            let chosen: LocalAccount
            if let raw = defaults.string(forKey: Self.currentKey),
               let id = UUID(uuidString: raw),
               let hit = list.first(where: { $0.id == id }) {
                chosen = hit
            } else {
                chosen = list[0]
            }
            accounts = [chosen]
            persist()
            return
        }

        // ② 首次运行 / 更老版本：迁移三件套（老单账户键 + 沙盒根目录头像）
        accounts = [legacyMigratedAccount()]
        persist()
    }

    /// 更老版本的单账户三件套 → 收敛后的唯一账户。
    private func legacyMigratedAccount() -> LocalAccount {
        var account = LocalAccount()

        if let legacy = defaults.string(forKey: "codeclip.account.nickname") {
            let trimmed = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { account.name = String(trimmed.prefix(Self.nameLimit)) }
        }

        if let raw = defaults.string(forKey: "codeclip.account.avatar"),
           let style = AccountAvatarStyle(rawValue: raw) {
            account.avatar = style
        }

        // 老的自定义头像文件（沙盒根目录 `account-avatar.jpg`）搬进头像目录。
        // 用 copy 不用 move：迁移失败时老文件还在，不至于两头皆空。
        if let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask).first {
            let legacyURL = base.appendingPathComponent("account-avatar.jpg")
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                let fileName = "\(account.id.uuidString).jpg"
                if (try? FileManager.default.copyItem(at: legacyURL,
                                                      to: Self.avatarURL(fileName: fileName))) != nil {
                    account.customAvatarFileName = fileName
                    account.avatar = .custom
                }
            }
        }

        return account
    }

    // MARK: 头像文件

    private static var avatarDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("AccountAvatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func avatarURL(fileName: String) -> URL {
        avatarDirectory.appendingPathComponent(fileName)
    }

    /// 居中裁方 + 缩放。
    private static func squareScaled(_ image: UIImage, side: CGFloat) -> UIImage {
        let target = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1                    // 已经是 side px 的位图，不要再乘屏幕倍数
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            let scale = max(side / image.size.width, side / image.size.height)
            let drawn = CGSize(width: image.size.width * scale,
                               height: image.size.height * scale)
            image.draw(in: CGRect(x: (side - drawn.width) / 2,
                                  y: (side - drawn.height) / 2,
                                  width: drawn.width,
                                  height: drawn.height))
        }
    }

    // MARK: 截图脚手架

    /// 清空成默认账户（`ACCOUNTS` 注入前调用，保证每次截图状态一致）。
    /// ⚠️ 只在注入环境变量时走，正式运行永远不碰这个方法。
    func resetForScaffold() {
        for account in accounts {
            if let fileName = account.customAvatarFileName {
                try? FileManager.default.removeItem(at: Self.avatarURL(fileName: fileName))
            }
        }
        avatarCache.removeAll()
        accounts = [LocalAccount()]
        persist()
    }
}
