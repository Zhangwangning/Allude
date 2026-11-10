// 自检脚本用的 macOS 侧垫片。
//
// 为什么需要它：`CourierBrand.swift` 除了品牌表，还带一段 SwiftUI 图标渲染
// （`Image(uiImage:)` / `.widgetAccentedRenderingMode(.fullColor)`，这两个是 iOS /
// WidgetKit 才有的 API），而 `BrandDebug` 又依赖 App Group 的 `PickupStorage`。
// 用 CommandLineTools 的 swiftc 按 macOS 目标单独编译这些共享源码时会全部报错。
//
// 垫片只补「够编译」的最小定义，不改变任何匹配逻辑：
// - `UIImage` → `NSImage`，`Image(uiImage:)` 转 `Image(nsImage:)`
// - `widgetAccentedRenderingMode` 直接返回自身（自检不渲染图标）
// - `BrandDebug.trace` 空实现（自检不写 App Group 日志）
//
// 用法见 AGENTS.md「自检脚本」：编译 station-check / brand-check 时一并传入。
import SwiftUI

#if os(macOS)
import AppKit

typealias UIImage = NSImage

enum WidgetAccentedRenderingMode { case fullColor }

extension Image {
    init(uiImage: NSImage) { self.init(nsImage: uiImage) }
    func widgetAccentedRenderingMode(_ mode: WidgetAccentedRenderingMode) -> Image { self }
}
#endif

enum BrandDebug {
    static func trace(_ line: String) {}
}
