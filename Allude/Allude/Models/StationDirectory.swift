import Foundation
import SwiftUI
import UIKit

// MARK: - 驿站名称库（2026-10-14 主人定稿）
//
// 卡片行 1 的显示逻辑（主人原话）：
//   「显示快递公司及其图标……快递公司后面一个管道符，然后是快递驿站/取件平台的名称，
//     如果没有快递公司，则优先显示快递驿站名称及图标，若快递驿站也没有，
//     就直接显示取件平台的名称和图标」
//
// 驿站名称 = 内置一批（来自 CourierBrand 的驿站 / 快递柜品牌）+ 用户自定义，
// 用「包含匹配」在短信原文 / 地址里命中即认为这条记录有驿站名。
// 内置清单不落盘（跟 CourierBrand 表同步）；自定义存 UserDefaults。
//
// 自定义图标（2026-10-15 主人定稿）：
//   · 内置驿站**只读**（不可改名、不可换图、不可删）；
//   · 自定义驿站支持**重命名 / 更换图标 / 删除**；
//   · 图标来源不限（相册任何图片），统一缩放 216px 存 JPEG，
//     **显示层一律按圆角矩形裁切**（与 CourierLogo 同 0.29×size 圆角）。

final class StationDirectory: ObservableObject {

    static let shared = StationDirectory()

    /// 自定义驿站名的 UserDefaults 键
    private static let storeKey = "station.customNames"
    /// 自定义驿站名 → 图标文件名的 UserDefaults 键（图片本体在 StationIcons/ 目录）
    private static let iconKey = "station.iconFiles"

    // MARK: 内置驿站 / 快递柜名称（只读，不可增删改）

    /// 内置展示清单：CourierBrand 里驿站 / 快递柜两类品牌的规范名（保持表内顺序、去重）
    static let builtinNames: [String] = {
        var seen = Set<String>()
        return CourierBrand.table
            .filter { $0.category == .station || $0.category == .locker }
            .compactMap { info -> String? in
                guard seen.insert(info.name).inserted else { return nil }
                return info.name
            }
    }()

    /// 内置匹配已迁移到 `CourierBrand.stationMatch`（2026-10-18）：词表 / 图标 /
    /// 分类在 CourierBrand 单一维护，StationDirectory 只负责「内置 + 自定义」叠加。

    // MARK: 自定义驿站名

    @Published private(set) var customNames: [String]

    /// 自定义驿站名 → 图标文件名（图片本体存 Application Support/StationIcons/）
    @Published private(set) var iconFiles: [String: String]

    private let defaults: UserDefaults

    /// 图标内存缓存（磁盘读图只在冷启动后第一次）
    private var iconCache: [String: UIImage] = [:]

    /// 图标文件目录：Application Support/StationIcons/
    private var iconDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StationIcons", isDirectory: true)
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 截图/回归脚手架：`SIMCTL_CHILD_SEED_STATIONS=名字1,名字2` 注入自定义驿站名
        // （simctl spawn defaults 写的是模拟器用户级偏好、到不了 app 容器，
        //  命令行验证自定义驿站只能走这条路；仅注入不落盘，正常启动无副作用）。
        if let seed = ProcessInfo.processInfo.environment["SEED_STATIONS"], !seed.isEmpty {
            self.customNames = seed.split(separator: ",").map { String($0) }
            self.iconFiles = [:]
        } else {
            self.customNames = defaults.stringArray(forKey: Self.storeKey) ?? []
            self.iconFiles = defaults.dictionary(forKey: Self.iconKey) as? [String: String] ?? [:]
        }
    }

    /// 添加自定义驿站名（去重、去空白；与内置重名也无意义 → 一并拦下）
    func add(_ raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        guard !customNames.contains(name),
              !Self.builtinNames.contains(name) else { return false }
        customNames.append(name)
        persist()
        return true
    }

    /// 重命名（仅自定义允许；空名 / 与内置或已有重名 → 拒绝）。
    /// 图标随名迁移（映射的 key 是名字）。
    func rename(_ from: String, to raw: String) -> Bool {
        let to = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !to.isEmpty, to != from else { return false }
        guard !customNames.contains(to),
              !Self.builtinNames.contains(to) else { return false }
        guard let index = customNames.firstIndex(of: from) else { return false }
        customNames[index] = to
        if let file = iconFiles.removeValue(forKey: from) {
            iconFiles[to] = file
            if let cached = iconCache.removeValue(forKey: from) { iconCache[to] = cached }
        }
        persist()
        // 位置表以名字为 key，改名要一起搬（2026-11-16 到达提醒）
        StationLocationStore.shared.rename(from: from, to: to)
        return true
    }

    func remove(named: String) {
        customNames.removeAll { $0 == named }
        if let file = iconFiles.removeValue(forKey: named) {
            try? FileManager.default.removeItem(at: iconDirectory.appendingPathComponent(file))
        }
        iconCache.removeValue(forKey: named)
        persist()
        // 别留一条指向已删除驿站的孤儿围栏
        StationLocationStore.shared.remove(named: named)
    }

    // MARK: 自定义图标

    /// 存入自定义图标：任意来源图片统一缩放 216px（54pt @4x）、居中裁方、JPEG 0.85。
    /// 显示层负责按圆角矩形裁切 —— 这里不碰形状。
    func setIcon(_ data: Data, for name: String) {
        guard customNames.contains(name) else { return }
        guard let image = UIImage(data: data),
              let scaled = Self.scaledSquare(image),
              let jpeg = scaled.jpegData(compressionQuality: 0.85) else { return }

        do {
            try FileManager.default.createDirectory(at: iconDirectory, withIntermediateDirectories: true)
        } catch { return }

        let file = "\(UUID().uuidString).jpg"
        do {
            try jpeg.write(to: iconDirectory.appendingPathComponent(file), options: .atomic)
        } catch { return }

        // 换图成功后再删旧文件，避免写坏丢图
        if let old = iconFiles[name] {
            try? FileManager.default.removeItem(at: iconDirectory.appendingPathComponent(old))
        }
        iconFiles[name] = file
        iconCache[name] = scaled
        persist()
    }

    /// 读自定义图标（有缓存走缓存；无自定义图标返回 nil，由显示层兜底 CourierLogo）
    func iconImage(for name: String) -> UIImage? {
        if let cached = iconCache[name] { return cached }
        guard let data = iconData(for: name),
              let image = UIImage(data: data) else { return nil }
        iconCache[name] = image
        return image
    }

    /// 读自定义图标的原始文件数据（编辑页预填预览用）
    func iconData(for name: String) -> Data? {
        guard let file = iconFiles[name] else { return nil }
        return try? Data(contentsOf: iconDirectory.appendingPathComponent(file))
    }

    /// 居中裁方 + 缩放到 216×216（等比 cover，不拉伸变形）
    private static func scaledSquare(_ image: UIImage) -> UIImage? {
        let side: CGFloat = 216
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { _ in
            let size = image.size
            guard size.width > 0, size.height > 0 else { return }
            let ratio = max(side / size.width, side / size.height)
            let draw = CGSize(width: size.width * ratio, height: size.height * ratio)
            let origin = CGPoint(x: (side - draw.width) / 2, y: (side - draw.height) / 2)
            image.draw(in: CGRect(origin: origin, size: draw))
        }
    }

    private func persist() {
        defaults.set(customNames, forKey: Self.storeKey)
        defaults.set(iconFiles, forKey: Self.iconKey)
    }

    // MARK: 匹配

    /// 在给定文本里做「包含匹配」，返回命中的驿站名。
    /// 内置品牌走 `CourierBrand.stationMatch`（与图标 / 分类共用同一张表，零漂移）；
    /// 再叠加用户自定义驿站名（最长优先）。
    ///
    /// ⚠️ 调用方**只传短信原文**（2026-10-18 主人定：驿站从短信匹配，不是从地址），
    /// 传入地址会让「恒大御府东门菜鸟驿站」这类地址噪声被误判成驿站品牌。
    func matchedName(in texts: [String]) -> String? {
        var best = CourierBrand.stationMatch(in: texts)
        for name in customNames {
            guard texts.contains(where: { $0.localizedCaseInsensitiveContains(name) }) else { continue }
            if best == nil || name.count > best!.length { best = (name, name.count) }
        }
        return best?.name
    }
}
