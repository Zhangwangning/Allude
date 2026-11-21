# 本项目踩过的坑（带证据链）

## 1. 「标签栏看得见、点不动」= 系统栏被摆进了保留区

**症状**：iPhone Duo 内屏横屏下，右侧那条竖排标签栏画得很正常，但点它没有任何反应；
待取页内部可以正常滑动和点击。外屏、内屏竖屏都正常。

**取证**（Debug 探针，`TABPROBE=1`，输出到 `Documents/tabprobe.txt`）：

```
window=951×669   safeArea=t0 l0 b34 r84        ← 右侧保留区从 951-84=867 开始
tabBars=1
  [0] frame=x882 y0 w69 h669  hidden=false alpha=1.0 interactive=true items=4
      superview=_UITouchPassthroughView
  _UITabButton[881,435,44,58] / [881,485] / [881,535] / [881,585]
  _UITabBarItemPlatterView[879,433,48,212]
```

整条标签栏落在 **x882…951**，而可交互区只到 **867** —— 它在摄像头/dock 保留区里。

**决定性验证**：给第 2 个 `_UITabButton` 程序化发 `sendActions(for: .touchUpInside)`，
界面**当场切到「已取」**。说明 `TabView` 与 selection 绑定全都没问题，**是触摸没送到**。

**结论**：这不是「系统标签栏的 bug 能不能点」的问题，而是**保留区里收不到触摸**。
任何被系统或我们自己放进那条带的交互元素都会失效。

**处置（本项目现行）**：Duo 内屏横屏不再用系统标签栏，改用与 iPad 同一条自绘底部栏
（`PadBottomBarGlassHost`，SwiftUI + 系统玻璃），整条落在底部安全区内：

```swift
// RootView.swift
if PadLayout.isPad || PadLayout.isExpandedFoldable { PadBottomBarGlassHost(…) }
.environment(\.suppressTabBarCloak, PadLayout.isPad || PadLayout.isExpandedFoldable)
// 4 处 .modifier(PadTabChrome(enabled: PadLayout.isPad || PadLayout.isExpandedFoldable))
```

⚠️ 换成自绘栏后，**详情栏顶部的「编辑 / 分享」也在 x884 一带**，可能同样不响应；
处理思路是把交互元素推出保留区（补 trailing 内边距），而不是再挪栏。

**通用教训**：只要界面元素进入 occlusion 保留区，就假设它**不可点**。
先查 `reservedRegions(kind: .occlusion)` 与 `safeAreaInsets`，再决定放哪。

---

## 2. 用 UIKit 抓 `UITabBar` 做动画 / 显隐 —— 永远不要

我们曾写过 `TabBarCloak`：抓 `UITabBar` 实例，改 `transform`、`alpha`、
`isUserInteractionEnabled = false` 来实现「进二级页收起标签栏」。

后果链：
- 系统在 regular 宽度会把栏**重新布局并可能换实例** → 手里的 `bar` 引用失效；
- 恢复逻辑依赖「同一个实例」，于是 `isUserInteractionEnabled = false` 再也改不回来；
- 表现就是「画得好好的，但整条不可交互」——**和保留区事故叠在一起，查了两轮**。

**正解**：只用 `.toolbar(.hidden, for: .tabBar)` / `.toolbar(.visible, for: .tabBar)`，
让系统自己做显隐与动画。本项目现版 `TabBarCloakModifier` 只剩这几行：

```swift
private struct TabBarCloakModifier: ViewModifier {
    @Environment(\.suppressTabBarCloak) private var suppressed
    func body(content: Content) -> some View {
        content.toolbar(suppressed ? .visible : .hidden, for: .tabBar)
    }
}
```

---

## 3. `UIScreen.main` 与「机型名」都不可靠

- Duo 展开时 `UIScreen.main.bounds` 仍报 **466×678（外屏）**；
- `UIDevice.model` 恒为 `iPhone`；`uname().machine` 在模拟器里是 `arm64`；
  `UIDevice.name` 是用户可改的名字。
- **唯一可靠的是窗口 bounds + size class**。

## 4. `ConcentricRectangle` 在根 overlay 里会变成直角

它从**容器的 `cornerConfiguration`** 推导半径；我们的分享面板挂在 `RootView` 顶层 overlay，
容器没有圆角配置 → 面板被裁成直角。自绘全屏面板里只能按屏幕半径显式算：
机身外缘 `displayCornerRadius − 8`、铰链侧 16pt（D 型屏四角同半径一定错位）。

## 5. sheet / 自绘面板的四边要自己补

面板挂在 `RootView` 顶层且 `ignoresSafeArea`，`GeometryReader` 报的是「安全区内」尺寸，
直接拿它算尺寸会少一圈。做法：从**窗口**读尺寸与 `safeAreaInsets`，再用
`UnevenRoundedRectangle` 按边给圆角。⚠️ 但也**不要**叠加 `safeBottom + x`，会翻倍。

## 6. 折叠时不要换布局，要压缩布局

HIG 原话：「避免极端的布局变化……突然消失或大幅移位的控制更难查找和追踪」。
实践中：单列 → 双列用 `LazyVGrid` 偶数列；分栏只在 regular **且** 宽 > 高时开；
竖屏内屏保持单列。本项目因此有 `PadLayout.isExpandedFoldable` 这条判据。

## 7. 布局判定不要用 `userInterfaceIdiom` / 方向

Apple 在《Preparing your app for iPhone Duo》里明确禁止用它俩做 UIKit 布局判断；
同一个 App 在 Duo 上会以 4 种以上几何出现，idiom 恒为 `.phone`。

## 8. 展开态右侧那条 84pt：系统自相矛盾（2026-11-21 实测，结论＝环境限制）

**症状**：内屏横屏下，右侧靠下的竖排标签栏、「编辑」、「分享」圆钮**全都点不动**；
同一时刻点左侧列表、点卡片完全正常；进程内对 `_UITabButton` 发
`sendActions(for: .touchUpInside)` 会立刻切页。→ 控件与逻辑都没问题，是那条带子不收触摸。

**取证**（`window.reservedRegions(kind:)`，iOS 27.1+）：

```
window=951x669  safe=t0.0 l0.0 b34.0 r84.0
occlusion.count=0
division.count=0
```

即**系统自己报告展开态没有任何保留区域**，可 `safeAreaInsets.right` 仍然是 84。
系统把这 84pt 当成「不可交互的安全区外边」，又把竖排栏摆在了 `x882…951`（正落在里面），
于是栏看得见、点不到。

**判断**：这是**模拟器给的幽灵安全区**（真机完全展开时右侧没有摄像头遮挡）。
App 侧无法移动系统栏的位置，也没有 API 能把这条带子「打开」。

**三条可选路，2026-11-21 主人选 A**：

| 方案 | 结果 |
|---|---|
| **A 保持原生竖排**（当前） | 符合 Duo 设计，模拟器里那条带子点不动，记为环境限制 |
| B `.toolbarVerticalBehavior(.disabled)`（iOS 27.1+） | 系统把栏摆回底部横排 → 能点，但不是 Duo 的竖排设计 |
| C 自绘竖栏 | 已被否决（能不用自绘就不用） |

⚠️ 把 `toolbarVerticalBehavior(.disabled)` 挂在 `NavigationSplitView` 上会让**分栏塌成单列**，
挂在根视图上则只影响标签栏、不影响详情列的工具栏 —— 两条都实测过。
