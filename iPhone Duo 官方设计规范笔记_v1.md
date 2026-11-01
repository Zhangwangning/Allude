# iPhone Duo 官方设计规范笔记 v1

> 来源：Apple Developer 官方 Tech Talks（2026-09-08 发布），2026-11-01 逐字查阅整理。
> 三篇是官方口径的唯一依据，本文件凡是带「官方」的都可在原视频里核到：
>
> - [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/)
> - [Design for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111466/)
> - [Strike a pose with adaptive layouts on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111463/)
>
> 🔴 本文件**优先于** `iPhone Duo 适配规范_v1.md` 里我自己猜的部分；
> 两份冲突时以这份为准，并回改另一份。

---

## 1. 设备事实

| 项 | 官方说法 |
|---|---|
| 屏幕 | **多块屏**，每块有自己的 size class |
| 外屏 | 宽度 compact（"behaves like other iPhone models"） |
| 内屏 | **两个维度都是 regular**，宽度足够放侧栏 |
| 内屏方向 | **不遵循 `supportedInterfaceOrientations`** —— 布局判断只看 size class，不看方向 |
| 姿势 | 闭合 / 展开 / 书本式半折 / 帐篷式立在桌上 / 平放 …… "many different poses" |

⚠️ 我这边的实测：外屏 466×678pt、`safeAreaInsets = t0 l0 **r84** b34`。
**r84 不是"随便留的"，它是保留区域折算进安全区的结果**（见第 4 节）。

## 2. 三条设计原则（官方）

1. **只为两种 size class 设计**：compact 与 regular。
   > "Don't design a custom layout for each pose, instead focus on two sizes classes"
   想做某个姿势的定制版式，必须保证**功能与层级不被破坏**。
2. **控件靠边**：iPhone Duo 把按钮/控件移到屏幕**外侧边缘**，把纵向空间留给内容。
   工具栏、标签栏都在**侧边**，可触及性优于底部。
3. **可缩放**：Split View 多任务与视频 PiP 让同一个 App 以不同宽高比出现，必须支持 resizable。

## 3. 安全区与布局边距

- 用 **layout margins + safe area insets**，不要写死留白。
- 🔴 **安全区常常是非对称的**（我们实测右边 84、左边 0）。
  官方给的反例正是我们踩到的：
  ```swift
  // ❌ 假设左右相等
  let width = view.bounds.width - view.safeAreaInsets.left * 2
  // ✅ 每边独立处理
  let width = view.bounds.inset(by: view.safeAreaInsets).width
  ```
- 交互内容在安全区内；**背景图**才用 `ignoresSafeArea()` 或 `view.bounds` 铺出去。
- 外屏"大多数内容都需要偏移，否则会被控件挡住"——这由安全区自动完成。
  例外：**不滚动的沉浸式界面**可以整体居中铺满，或"通栏背景 + 内缩正文"混用。

## 4. 保留区域 Reserved Regions（iOS 27.1 新 API）

官方定义：铰链与摄像头会**瓜分可用空间**，这些区域叫 reserved regions，
处理方式与 iPadOS 的窗口控件同等。

| 类型 | `kind` | 代表什么 | 何时 active |
|---|---|---|---|
| **division**（分割） | `.division` | 折痕：把一个区域切成两个 | **只在半折时**；完全展开时宽度为 0 |
| **occlusion**（遮挡） | `.occlusion` | FaceTime 摄像头 | 有摄像头的一侧 |

查询方式：

```swift
// SwiftUI
GeometryReader { proxy in
    let regions = proxy.reservedRegions(kind: .division)            // 只看 active
    let all     = proxy.reservedRegions(kind: .division, options: .includeInactive)
    let frames  = regions.map(\.frame)
}

// UIKit
let regions = view.reservedRegions(kind: .division)
```

- 默认只返回 **active** 的；`includeInactive` 能拿到全部。
- 非 active 的也有用：官方举例——判断"该用偶数还是奇数列网格"这种高层决策。
- 另外 iOS 27.1 还有 `ReservedRegion`（SwiftUI）/ `UIViewReservedRegion`（UIKit），
  让**自绘控件**主动认领"我最多能占到哪"，用于自定义栏与全屏设计。

🔴 **对我们的直接价值**：分享面板现在写死 `safeAreaInsets.right`，
更稳的做法是查询 `.occlusion` 区域的 frame，摄像头换位置/换姿势都跟得上。

## 5. 折痕避让 Displacement

- 书本式半折时屏幕从中间弯折，**跨折痕的内容会读不成一个整体**（官方比喻：书脊）。
- 位移（displacement）是**调整元素 frame**，粒度可以从一个按钮到一个容器：
  - 能独立适应的就**单独移动**，成组的就**整组移动**；
  - 不要过度移动，会破坏视觉关系；
  - **连续滚动的内容（文章、列表）不要位移**。
- 位移的目的地随使用方式变：
  - 书本式半折：弹窗移到**尾侧**，离"合上后出现的位置"更近；
  - 立在桌上：**上部**放远观内容，**下部**放交互控件。
- 系统会自动把 action sheet、alert、菜单、popover 挪开保留区域。
- `List` / `ScrollView` 与 `NavigationStack` / `NavigationSplitView` / `TabView`
  对折痕**自动适配（for free）**。

## 6. 侧边控件与标签栏（重要：纠正我们之前的判断）

官方原话：

> "position your toolbars, tab bars and controls along the side of the device so they're easier to reach"

- **侧边竖排标签栏是设计意图，不是 bug。**
  我们之前把"Duo 外屏标签栏变成右侧竖排"记成问题，**这条判断要撤回**。
- 侧边这条竖带同时被状态栏、实时活动占用；**空间不够时控件会收进溢出菜单**。
- 例外：**太宽放不进竖带的控件**不走这套。

## 7. Sheet 在两种屏上的行为

- 外屏：sheet 用**竖排控件**呈现；
- 内屏：用**横条（horizontal bars）**；
- 折叠时 sheet 会**滑到一边避开折痕**。

→ 我们自绘的分享面板属于"自定义 sheet"，这些行为得自己对标实现。

## 8. 内屏（写 UI 时的第一原则）

- 内屏宽松："take advantage of the wide inner display to show more content"；
- 首选**分栏**（暴露更多层级）或**两列布局**；
- 官方明确：`NavigationSplitView`、`TabView` 等系统容器会自动在两种屏之间折叠/平铺，
  **不要自己重写**。
- 可选：内屏上 `TabView { … }.defaultTabBarPlacement(.sidebar)`，
  UIKit 对应 `tabBarController.sidebar.preferredPlacement = .sidebar`。

## 9. 版面容器 ArrangementView（iOS 27.1 新增）

用于"两个视图按规则排布"的场景（官方例子：播放器 + 待播列表）。

```swift
NavigationStack {
    ArrangementView {
        PlayerView()            // primary
    } secondary: {
        UpNextView()            // secondary
    }
    .arrangementViewStyle(.split)            // 或 .overlay
    // .arrangementViewStyle(.split.axes(.horizontal))   // 限制只在横向分
}
```

- `.split`：默认按宽高比分（宽 > 高横分，否则纵分）；**分不出来时只显示一个视图**。
- `.overlay`：优先上下叠放，设备折起来时变成左右并排；
  用 `@Environment(\.overlayArrangementZIndex)` 感知叠放层级，切换收起/展开态。
- UIKit 对应 `UIArrangementViewController`（`updateArrangement(_:)`、`state(for:)`）。
- 选取原则：现有 `HStack/VStack` → split；`ZStack` → overlay；
  有明确前景/背景关系用 overlay，有明显主从关系用 split（两者都不该被遮挡）。
- ⚠️ 不要嵌套导航容器；不要把 `ArrangementView` 放进可滚动容器。

## 10. 圆角：跟随屏幕轮廓

- 用 **`ConcentricRectangle`（SwiftUI）/ `UICornerConfiguration`（UIKit）**
  （iOS 26 起的 Concentricity API）去贴合屏幕四角，
  官方示例：
  ```swift
  ConcentricRectangle()
      .fill(Color.green)
      .padding(8.0)
      .ignoresSafeArea()
  ```
- 🔴 这条**替代**了我们手写的"读 `displayCornerRadius` 再减 8"和
  "左侧 16 / 右侧 55 硬编码"——D 型屏的非同心圆角，用这个 API 才跟得准。

## 11. 不要碰 `UIScreen.main`

> "Don't reference the main screen on a two-display device — it's ambiguous and will be deprecated."

- 屏幕从 **window scene** 拿：`window?.windowScene?.screen`
- 缩放用 `traitCollection.displayScale`
- 这一条我们已经在 build 59 改过（`Self.windowSize` 从 key window 读），
  但项目里还留着别的 `UIScreen` 用法，需要清一遍。

## 12. SDK 版本影响

- **iOS 27 SDK**：内容可以延伸到内屏状态栏左侧；
- **iOS 27.1 SDK**：可以到屏幕边缘，标准导航/工具栏按钮**自动竖排**；
  并带来 `ReservedRegion` / `ArrangementView`。
- 我们工程是 iOS 27.2 SDK 构建，两条能力都在。

---

## 对照：本项目现状（2026-11-01）

| 项 | 现状 | 结论 |
|---|---|---|
| 外屏右侧竖排标签栏 | 系统自动 | ✅ **符合官方意图**，不改 |
| 分享面板写死 `safeAreaInsets.right` | 自绘面板 | ⚠️ 可用 `.occlusion` 区域替代 |
| 面板圆角硬编码 16 / 55 | 自绘 | ⚠️ 应换 `ConcentricRectangle` |
| 列表单列被拉宽 | 未处理 | ❌ 官方要求：regular 宽度下用**两列或分栏** |
| 内屏（regular） | 走 `duoLayout`（自定义） | ⚠️ 官方建议优先系统容器 `NavigationSplitView` / `ArrangementView` |
| `UIScreen.main` 残留 | 有 | ❌ 官方明确要弃用，需清 |
| 首启/sheet 折叠避让 | 未实现 | ➕ 系统给的自动行为，自绘面板要自己补 |
