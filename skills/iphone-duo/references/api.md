# iPhone Duo 相关 API（签名与可用性以 iPhoneOS27.2.sdk 为准）

所有条目都核对过 `*.swiftinterface` / 头文件；可用性标注即 SDK 里的真实标注（`anyAppleOS 27.1` 在 iOS 上就是 **iOS 27.1**）。
本项目部署目标是 iOS 17.0，所以下面这些都要 `if #available(iOS 27.1, *)` 或包在一个只有 Duo 会走的分支里
（Duo 出厂即 iOS 27，见 `AGENTS.md`「系统兼容基线」）。

---

## 1. 保留区 ReservedRegion

### SwiftUI

```swift
@available(anyAppleOS 27.1, *)
public struct ReservedRegion: Equatable, Hashable, Identifiable, Sendable {
    public var id: ReservedRegion.ID { get }
    public var kind: ReservedRegion.Kind { get }
    public var frame: CGRect { get }
    public var margins: EdgeInsets { get }
    public var isActive: Bool { get }
}

@available(anyAppleOS 27.1, *)
extension ReservedRegion {
    public struct Kind { public static var occlusion: Kind { get }; public static var division: Kind { get } }
}
```

查询（`SwiftUICore.GeometryProxy`）：

```swift
public func reservedRegions(
    kind: ReservedRegion.Kind,
    options: ReservedRegion.QueryOptions = [],
    layoutDirectionBehavior: LayoutDirectionBehavior = .mirrors
) -> [ReservedRegion]
```

最小用法：

```swift
GeometryReader { proxy in
    let hits = proxy.reservedRegions(kind: .occlusion).filter(\.isActive)
    content
        .padding(.bottom, hits.last.map { proxy.size.height - $0.frame.minY } ?? 0)
}
```

⚠️ `kind` 是**两个独立查询**：折痕用 `.division`，相机用 `.occlusion`，不存在「一次拿全部」的默认值。
⚠️ 只对 `isActive` 的 region 做偏移。折痕在完全展开时 `isActive == false`，照它偏移会白让一块。

### UIKit

```objc
@interface UIView (ReservedRegion)
- (NSArray<UIViewReservedRegion *> *)reservedRegionsOfKind:(UIViewReservedRegionKind *)kind
    API_AVAILABLE(ios(27.1)) NS_REFINED_FOR_SWIFT;
- (NSArray<UIViewReservedRegion *> *)reservedRegionsOfKind:(UIViewReservedRegionKind *)kind
    options:(UIViewReservedRegionQueryOptions)options
    API_AVAILABLE(ios(27.1)) NS_REFINED_FOR_SWIFT;
@end
```

`UIViewReservedRegion` 暴露 `identifier` / `kind`，`UIViewReservedRegionIdentifier` 用于区分同一类里的多个区域。

---

## 2. 排列视图 ArrangementView

```swift
@available(anyAppleOS 27.1, *)
public struct ArrangementView<Primary: View, Secondary: View>: View {
    public init(@ContentBuilder primary: () -> Primary,
                @ContentBuilder secondary: () -> Secondary)
}

extension View {
    @available(anyAppleOS 27.1, *)
    public func arrangementViewStyle(_ style: some ArrangementViewStyle) -> some View
}
```

样式：

- `.split` —— 宽 > 高时左右分；高 > 宽时上下分。
- `.overlay` —— 主视图压在从视图上；**部分折叠时**按折痕分到两侧。
- 都可再限定轴，例如 `.split.axes(.horizontal)`。

UIKit 对应 `UIArrangementViewController`（`updateArrangement(_:)` / `state(for:)`）。

🔴 **不要**把 `ArrangementView` 放进 `NavigationSplitView` / `List` / `ScrollView` 里 ——
官方点名会让部分视图变得不可达。导览容器要放在它**外面**。

---

## 3. 垂直（侧边）控制

| 目的 | SwiftUI | UIKit |
|---|---|---|
| 顶部留给返回/关闭 | `ToolbarItem(placement: .cancellationAction)` | `leadingItemGroups` |
| 醒目操作（完成） | `ToolbarItemPlacement.topBarPinnedTrailing` | `pinnedTrailingGroup` |
| 自动组间距 | `ToolbarItemGroup` | `UIBarButtonItemGroup` |
| 溢出取舍顺序 | `.visibilityPriority(_:)`（`ToolbarItemVisibilityPriority`） | `visibilityPriority` |
| 直接进溢出菜单 | `ToolbarOverflowMenu`（iOS 27+） | `additionalOverflowItems` |
| 该不该竖排 | `.axisBehavior(_:)`（`ToolbarItemAxisBehavior`） | `axisBehavior` |
| 感知当前是否竖排 | `@Environment(\.toolbarVerticalEdge)` | `verticalBarEdge` trait |
| 关掉竖排（如 sheet） | `.toolbarVerticalBehavior(.disabled)`（iOS 27.1+） | `preferredVerticalBarBehavior` |
| sheet 摆放位置 | `.presentationPlacement(_:)` | `preferredPlacement` |
| 背景延伸到竖排栏下 | `.backgroundExtensionEffect()` | `UIBackgroundExtensionView` |
| 压缩策略 | `ToolbarVerticalCompressionBehavior` | `UIVerticalBarCompressionBehavior` |

签名（SDK 原件）：

```swift
@available(anyAppleOS 27.1, *)
extension View { public func toolbarVerticalBehavior(_ behavior: ToolbarVerticalBehavior) -> some View }

public struct ToolbarVerticalBehavior: Hashable, Sendable {
    public static let automatic: ToolbarVerticalBehavior
    public static let disabled: ToolbarVerticalBehavior
}

extension ToolbarContent {
    nonisolated public func visibilityPriority(_ priority: ToolbarItemVisibilityPriority) -> some ToolbarContent
    nonisolated public func axisBehavior(_ behavior: ToolbarItemAxisBehavior) -> some ToolbarContent
}
```

🔴 竖排的硬条件（官方明说）：

- 项目**只有标题、没有图标** → 系统**不**竖排它；
- 项目是**自定义 view**（不是 title/icon）→ 同样**不**竖排；
- 竖排时只用图标；横排优先图标；溢出菜单里图标 + 标题都显示。

所以「给每个非纯文本工具栏项同时提供 `label`（图标）和 `title`」是 Duo 适配里最划算的一行改动。

---

## 4. 分屏浏览与标签栏

- `NavigationSplitView` / `UISplitViewController` 会自己在外屏折叠成单面板、在内屏展开；
  系统还会按内屏对称性调整列宽与外边距 —— **不要重写**。
- 标签栏侧边化：`TabView { … }.defaultTabBarPlacement(.sidebar)`（可选），
  UIKit `tabBarController.sidebar.preferredPlacement = .sidebar`。
- 标签栏最小化：`tabBarMinimizeBehavior(_:)`（iOS 26+；本项目有 `TabBarMinimizeNever` 兼容层）。

---

## 5. 相机（如果 App 有拍照）

- Duo 有三路相机：外屏前置、内屏前置（藏屏下）、后置。
- 折叠/展开/旋转会改变所在屏与相机朝向 → 用 `AVCaptureDevice` 的朝向选择逻辑，不要缓存同一种相机的引用。
- 完全展开时用后置拍摄，可以在**外屏**同时显示内容（`Registering a camera capture accessory on iPhone Duo`）。

本项目现状：`AVFoundation` 只在「拍照识别」里用到，走系统 `UIImagePickerController`，
没有自绘取景器，因此这部分无需 Duo 专门处理。

---

## 6. 构建与工程

- **Xcode 26 及更早构建的包**，App 不会延伸到状态栏与相机下方；要用 Xcode 27+ 才能吃满 Duo 的屏幕。
- 本机：Xcode 27.2 在外置盘 `/Volumes/ZWN/Applications/Xcode.app`，SDK `iPhoneOS27.2.sdk`。
- `preferredContentSizeCategory` / `horizontalSizeClass` 等 trait 变化要**自动跟踪**，不要缓存一次。
