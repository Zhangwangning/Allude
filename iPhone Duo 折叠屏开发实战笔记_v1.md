# iPhone Duo 折叠屏开发实战笔记 v1

> 写于 **2026-11-21**，对应构建 **1.0.0 (321)**，工程 `TARGETED_DEVICE_FAMILY = 1`（纯 iPhone，Duo 属 iPhone 家族）。
> 本文是**落地实现 + 踩坑记录**，不是设计规范。三份文档的分工：
>
> | 文档 | 定位 | 可信度 |
> |---|---|---|
> | `iPhone Duo 官方设计规范笔记_v1.md` | Apple 三场 Tech Talks 的逐字整理 | **最高**，与本文冲突时以它为准 |
> | `iPhone Duo 适配规范_v1.md` | 早期工作约定（2026-11-01） | 有旧名残留，见 §12 |
> | **本文** | 代码里实际怎么做的、踩过什么坑、怎么验 | 事实层，全部可在代码/日志里核到 |
>
> 所有尺寸都标注了来源（实测 / 官方 / 代码常量）。凡是「实测」的，都是本机 Duo 模拟器上量出来的。

---

## 1. 设备事实（先记住这组数）

### 1.1 三种形态的窗口尺寸

| 形态 | `window.bounds` | 安全区 | 对应代码分支 |
|---|---|---|---|
| **折叠（外屏）** | 466 × 678 | `top 0 / left 0 / right 84 / bottom 34` | compact，等价普通 iPhone |
| **展开（内屏竖屏）** | 669 × 951（横屏则 951 × 669，姿态会自己翻） | 常规 | `regular`，但**走单列** |
| **展开（内屏横屏）** | 951 × 669 | 常规 + 无遮挡 | `regular` + **分栏** |

像素对照（`@3x`，2026-11-21 本机 Duo 模拟器实测）：

| 显示 | 截图分辨率 | ÷3 = pt |
|---|---|---|
| `--display=1` 外屏 | 2034 × 1398 | 678 × 466 |
| `--display=3` 内屏 | 2853 × 2007 | 951 × 669 |

（截图出来是横向的还是纵向的，取决于当时姿态 —— 先看 `sips` 的宽高再解读，别硬套。）

### 1.2 三条铁律

1. 🔴 **`UIScreen.main` 在 Duo 上不可用**。内屏横屏时它报的是**外屏**尺寸：
   ```
   window.bounds = 951 × 669   ← 真实
   UIScreen.main = 466 × 678   ← 骗你的（外屏）
   ```
   一切尺寸从 `windowScene.windows` 取，见 `PadLayout.windowSize`。
2. 🔴 **外屏右侧 84pt 是保留区域**（摄像头 + 侧边标签栏），不是「随便留的边距」。
   任何铺满全屏的自绘面板都必须让开，且**不能写死 84**，要查 API（见 §5）。
3. 🔴 **外屏高度只有 678pt**，比直板机（852/874）矮得多。
   所有「一屏装下」的假设在这里都会破，弹层必须能滚。

### 1.3 内屏没有灵动岛

折叠态外屏有灵动岛，**展开态没有**。所以：

- 代码里不能假设「岛恒在」；
- 小组件/实时活动的视觉要在「没有岛」的情况下也成立；
- 灵动岛紧凑态的版式（`IslandCompactTrailing`）只在折叠态可见，**这是它唯一需要为 Duo 定制的原因**（§9）。

---

## 2. 设备判定：`PadLayout` 一个入口

### 2.1 为什么不直接看 `horizontalSizeClass`

Duo 内屏**竖屏也是 `regular`**。2026-11-16 就是这样炸的：设置页用 `horizontalSizeClass == .regular` 决定「子行是按钮还是 NavigationLink」，竖屏下渲染成按钮、点下去只改了 `pane` 变量，而竖屏走的是单列分支、`pane` 没绑定任何导航 —— **一点反应都没有**（外观与个性化四项、关于五项全点不动）。

结论：**「宽屏」不等于「分栏」**。判定必须集中在 `Allude/Views/RootView.swift` 的 `enum PadLayout`，视图只读结论。

### 2.2 五个成员

```swift
enum PadLayout {
    static var isPad: Bool                  // idiom == .pad && iOS 26+
    private static var windowSize: CGSize   // keyWindow，100ms 缓存
    static var isExpandedFoldable: Bool     // Duo 内屏且横屏
    static var usesSplit: Bool              // iPad 或 Duo 内屏（设备级门槛）
    static var splitMinWidth: CGFloat       // iPad 900 / Duo 520
    static var splitColumnIdeal: CGFloat    // iPad 440 / Duo 466
}
```

**`isExpandedFoldable`（2026-11-15 实测 + 11-16 修订）**

```swift
static var isExpandedFoldable: Bool {
    guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
    #if DEBUG
    if ProcessInfo.processInfo.environment["FORCE_SPLIT"] == "1" { return true }
    #endif
    let size = windowSize
    guard size != .zero else { return false }
    return min(size.width, size.height) > 600 && size.width > size.height
}
```

- 判据用**最短边 > 600**，与方向无关：
  ```
  Duo 内屏 951×669 → 669 > 600 ✅
  Duo 外屏 678×466 → 466 ✗
  直板机   874×402 → 402 ✗（横屏也是 402）
  ```
- **必须再要求 `width > height`**：竖屏内屏 669×951 分两栏，每栏只剩约 330pt，卡片挤成一团。这是 2026-11-16 定下的「Duo 竖屏单列，不要分列」。
- `idiom == .phone` 这道闸不能省，否则 iPad 分屏窗口也会被判成 Duo。

**`splitMinWidth` 为什么是 520**

Duo 内屏展开后，右侧系统标签栏吃掉约 84pt，内容区约 585pt。阈值必须低于它，否则永远不分栏。iPad 那 900 是另一套（mini 竖屏 744 不分栏，避免两栏把详情挤出屏外）。

**`splitColumnIdeal` 为什么是 466**

设计决策（2026-11-15）：「左侧卡片区域宽度做成和外屏一样」。466 就是 Duo 外屏宽度 —— 左列卡片尺寸与折叠态**完全一致**，翻折切换姿势时视觉不跳。

### 2.3 判定矩阵（照着背）

| 设备 / 形态 | idiom | 最短边 | width>height | usesSplit | 实际布局 |
|---|---|---|---|---|---|
| 直板机 竖 | phone | 402 | 否 | ❌ | 单列 |
| 直板机 横 | phone | 402 | 是 | ❌ | 单列（横屏也不分栏） |
| Duo 外屏 | phone | 466 | 否 | ❌ | 单列，等价直板机 |
| Duo 内屏 竖 | phone | 669 | **否** | ❌ | **单列**（1620 高，不分两栏） |
| Duo 内屏 横 | phone | 669 | 是 | ✅ | **分栏**（左 466 / 右详情） |
| iPad | pad | — | — | ✅（再按 900 判） | 分栏 |

### 2.4 `windowSize` 的性能坑（2026-11-17）

`PadLayout.usesSplit` 会在 `row(for:)` 里被**每一行卡片**间接触发，50 行就是 50 次
`connectedScenes → windows → first(isKeyWindow)` 遍历。加了 **100ms 缓存**：
足够覆盖「一次 body + 它的整轮行构建」，又短到 Duo 翻折后下一帧就会重新取值。

```swift
private static var sizeCache: (size: CGSize, at: CFAbsoluteTime)?
```

⚠️ 不要改成永久缓存 —— 折叠展开必须立刻生效。

---

## 3. 三种形态的布局策略

### 3.1 外屏（compact）：什么都不做，但要验安全区

折叠态「behaves like other iPhone models」（官方原话），**版式与直板机完全一致**，不需要 Duo 分支。

要验的只有两件：

1. 右侧 84pt 有没有被内容侵入（尤其自绘全屏面板、横向滚动的条）；
2. 高度只有 678pt，弹层/长页面能不能滚到底（订阅页在这里就要滚，属正常）。

### 3.2 内屏横屏（regular + 横）：分栏

| 页面 | 分栏形态 |
|---|---|
| 待取 | 左列表（`NavigationSplitView`，列宽 400–600，ideal 466）/ 右详情 |
| 已取 | 同上（与待取同一套写法） |
| 设置 | 左目录（`List`，分组标题为空）/ 右面板（`paneContent(pane)`） |
| 统计 | **不分栏**，但 regular 宽度下总览全宽 + 五张分析卡**两列**并排 |

**待取/已取的实现**（`PickupListView.splitLayout` / `HistoryView.splitLayout`）：

```swift
NavigationSplitView(columnVisibility: $columnVisibility) {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()   // 左列也要铺灰
        NavigationStack { listPane }
    }
    .navigationSplitViewColumnWidth(min: 400,
                                    ideal: PadLayout.splitColumnIdeal,
                                    max: 600)
} detail: {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()   // 右列整列铺灰
        if detailLocked {
            ProLockedSplitPlaceholder { showPaywall = true }
        } else if let record = splitDetailRecord {
            RecordDetailView(record: record).id(record.id)  // 🔴 必须加 .id
        }
    }
}
```

这段骨架里三个**业务层**不能省的点（结构性规矩见 §3.3）：

1. **`.id(record.id)` 必须加**。右栏是同一个视图标识，换记录只是换入参，而详情的 `draft` / `edit` 是 `@StateObject`、只认第一次 init 的值 —— 不加就会出现「切了记录但内容不变」。
2. **右栏是常驻区域，没有「点击」可拦**。Pro 门禁必须换成占位视图（`ProLockedSplitPlaceholder`），不能靠 `onTap` 拦截 —— 不换就等于白送详情。
3. **`splitSelection == nil` 时回落第一条**（`splitDetailRecord`），否则右栏一直空白，看起来像坏了。

### 3.3 分栏骨架的六条硬规矩

三页（待取 / 已取 / 设置）用的是同一套 `NavigationSplitView` 骨架，六条规矩每条都对应一次真实翻车：

1. **左列必须包一层 `NavigationStack`**。
   缺了它，左列标题会退化成导航栏中间的小字（inline），与另一列的大标题对不齐。
   2026-11-15 在设置页实测：不包 `NavigationStack` 时「设置」标题变成 17pt 居中，而不是 34pt 左对齐。

2. **大标题自绘，不用 `navigationTitle`**。
   `PadSidebarHeader`（`RootView.swift`）：`Text(title).font(.system(size: 34, weight: .bold))`，
   `padding` 为 leading 18 / trailing 12 / top 8，导航栏只留按钮。
   三个页面必须同高同字号，折叠状态下才看不出差别。

3. **右栏 `NavigationStack` 不能带 `path:`，也不能加 `.id(pane)`**。
   两个都会让 destination 型 `NavigationLink` 在常驻 pane 里**推不动**：
   加 `.id(pane)` 会让整棵内容树（连同挂在上面的 `navigationDestination`）每次切面板都重建，
   实测「push 有日志、界面纹丝不动」。现在栈上没有 path、也没有 `.id`，
   SwiftUI 按正常语义管理 —— 切 `pane` 时内容树本来就不一样，栈自然重置。

4. **右栏要三层铺灰**。
   iOS 26 的导航栏是玻璃材质、会取样背后内容，漏一层就露白：
   ① `ZStack { Color(.systemGroupedBackground).ignoresSafeArea() }`；
   ② `NavigationStack` 自身再垫一层灰；
   ③ 导航栏 `toolbarBackground(.hidden)` + 内容底色（默认 `systemBackground` 是白）。

5. **左右列底色必须一致**。Duo 展开时左浅灰、右白是最刺眼的割裂（2026-10-25 被指出两次）。

6. **`navigationSplitViewColumnWidth` 用 `min / ideal / max`，别写死**。
   三页统一 `min 400 / ideal 466 / max 600`。
   ⚠️ `ProfileView` 里那段注释还写着「横屏 951 → 380、竖屏 669 → 280」，那是 2026-10-25 的旧方案，
   **代码已改成 400–600**；按注释改会退回到「竖屏侧栏占 65%、右栏被挤扁」的老问题。

### 3.4 内屏竖屏（regular + 竖）：单列，但判定要用 `usesSplit`

竖屏**不分栏**，但它的 `sizeClass` 仍是 `regular` —— 所以任何「是不是分栏」的判断都要用**同一个条件**，不能一处用 `sizeClass`、一处用 `usesSplit`。

`ProfileView` 的收口写法（2026-11-16 修 318 时立的规矩）：

```swift
private var isSplitLayout: Bool {
    PadLayout.usesSplit
        && horizontalSizeClass == .regular
        && ProcessInfo.processInfo.environment["SETTINGS_COMPACT"] != "1"
}
```

`body` 里选 `splitSettings` / `stackedSettings`、以及**所有**给子视图传 `openPane` 的地方，全部读这一个属性。四个调用点曾各自判断，导致分叉（§7.2）。

⚠️ `SETTINGS_COMPACT=1` 是截图脚手架：在宽屏模拟器上强制走窄屏样式，用来拍 iOS 26 玻璃行的窄屏效果。正式运行不存在。

### 3.5 统计页：不分栏，但宽屏两列

统计是单列信息流（总览 + 五张分析卡），硬分「左列表/右详情」没有意义，所以**不进分栏**。
但宽屏下会改排两列（`StatsTabView`）：

```swift
if horizontalSizeClass == .regular {
    VStack(spacing: 16) {
        overviewCard                 // 总览三格独占一行全宽（仪表盘主视觉，不该被挤半宽）
        HStack(alignment: .top, spacing: 16) {
            VStack { frequencyCard; companyCard }     // 左列
            VStack { efficiencyCard; hourlyCard; … }  // 右列
        }
    }
}
```

三个细节：

1. **用手工两个 `VStack` 分列，不用 `LazyVGrid`**。五张卡高度差很大（快递统计能长到一两屏），
   网格按行等高会在矮卡下方留大片空白；手工分列各自堆叠，观感紧实。
2. 这里判据是 `sizeClass == .regular` 而**不是** `usesSplit` —— 故意的：
   Duo 内屏竖屏（669pt）两列各约 326pt 也读得下，没必要为了「和分栏保持一致」退回单列。
   ⚠️ 这是全项目唯一一处在 regular 下「不做分栏但改版式」的页面，改动时别套用设置页的 `isSplitLayout`。
3. 顺序按信息层级：效率是「结论」放右上，时段分布是明细往下排（2026-10-28 调整）。

---

## 4. 分栏下的导航：三种写法、两个禁忌

这是 Duo 上最容易反复踩的一类问题，**症状都是「点不动」**。

### 4.1 禁忌一：在「会被整棵替换」的容器里 push

右栏内容是 `paneContent(pane)` —— 左列一换选中项，这棵树就被整棵替换。往这种容器里再 `push` 一层，系统把推入当**无效操作丢掉**：日志能看到 push 被调用，界面纹丝不动。

实测无效的四种尝试（2026-11-16，AI 子树）：

- 去 `NavigationStack(path:)` —— 无效；
- 去 `.id(pane)` —— 无效；
- 在子视图内部注册 `navigationDestination(isPresented:)` / `(item:)` —— 无效；
- 在栈根注册 value-based destination —— 无效。

**结论：分栏右栏里 `NavigationLink` 整体不可靠。**

### 4.2 禁忌二：value-based `NavigationLink` 套在 destination push 的栈里

单列分支里，外层已经是 `.navigationDestination { … }` 型 push，再加 value-based link 也不落地。

### 4.3 三种可靠写法

| 场景 | 写法 |
|---|---|
| 分栏下换「面板」 | **切 `pane`**（`Button { openPane(item) }`），与设置页目录项一致 |
| 单列下进二级页 | **destination 型** `NavigationLink { Destination() }`，不要 value-based |
| 分栏下的「列表 → 详情」 | 页内 `@State` 换内容 + 自绘返回按钮（AI 扩展列表点服务商就是这套） |

**AI 子树的实际改法**（可作为模板）：

```swift
// SettingsPane 增加三个「内部面板」，不进任何目录数组，只为右栏当内容
case aiAppleIntelligence, aiExtensions, aiUsage

// 组件同时支持两种模式
struct AIExtensionsHomeView: View {
    var openPane: ((SettingsPane) -> Void)?     // nil = 单列
    var body: some View {
        if let openPane {
            Button { openPane(.aiExtensions) } label: { row }
                .buttonStyle(.plain)            // 分栏
        } else {
            NavigationLink { AIExtensionsListView() } label: { row }   // 单列，destination 型
        }
    }
}
```

**验收探针**（`ProfileView.onAppear`，DEBUG）：

```
[allude-layout] isSplit=false sizeClass=regular
```

Duo 内屏竖屏必须打出 `isSplit=false` + `sizeClass=regular` 这一行 —— 这就是 318 那个 bug 的现场特征，反过来说明判定与渲染一致。

---

## 5. 安全区与保留区域（Reserved Regions）

### 5.1 84pt 的来源

官方口径：铰链与摄像头会**瓜分可用空间**，叫 reserved regions，处理方式与 iPadOS 窗口控件同等。

| 类型 | kind | 何时 active |
|---|---|---|
| 折痕 | `.division` | **只在半折时**；完全展开宽度为 0 |
| 摄像头 | `.occlusion` | 有摄像头的一侧（外屏 → 右侧） |

查询（iOS 27.1+，工程部署目标 17.0，必须 `#available` 保护）：

```swift
guard #available(iOS 27.1, *) else { return .zero }
for region in window.reservedRegions(kind: .occlusion) where region.isActive {
    let f = region.frame, b = window.bounds, tol: CGFloat = 1
    if f.maxX >= b.maxX - tol { insets.right  = max(insets.right,  b.maxX - f.minX) }
    if f.minX <= b.minX + tol { insets.left   = max(insets.left,   f.maxX - b.minX) }
    if f.maxY >= b.maxY - tol { insets.bottom = max(insets.bottom, b.maxY - f.minY) }
    if f.minY <= b.minY + tol { insets.top    = max(insets.top,    f.maxY - b.minY) }
}
```

实测结果仍然是右侧 84pt，但来源从「硬编码」变成了「系统告知」——
换机型、换姿势、半折状态都不用改代码。

### 5.2 与安全区分边取大

```swift
static var effectiveInsets: UIEdgeInsets {
    let occ = occlusionInsets, safe = windowSafeInsets
    return UIEdgeInsets(top: max(occ.top, safe.top),
                        left: max(occ.left, safe.left),
                        bottom: max(occ.bottom, safe.bottom),
                        right: max(occ.right, safe.right))
}
```

**不能相加**，也不能只取其中一个：摄像头区域与 Home 条可能落在不同边。

### 5.3 `ignoresSafeArea()` 的面板要手动补回

背景图可以铺出去，**交互内容不行**。凡是 `.ignoresSafeArea()` 的全屏自绘面板（分享面板、各类 cover），都要用 `effectiveInsets` 把内容缩回来。

### 5.4 官方反例（我们踩过）

```swift
// ❌ 假设左右相等：Duo 外屏左 0 右 84，这样算会整体偏 42pt
let width = view.bounds.width - view.safeAreaInsets.left * 2
// ✅ 每边独立
let width = view.bounds.inset(by: view.safeAreaInsets).width
```

---

## 6. 自绘全屏面板：分享面板的 Duo 版（最细的一块）

`Allude/Views/PickupShareCard.swift`。这块是**唯一仍为 Duo 保留定制版式**的界面，其余页面已统一走系统容器。

### 6.1 为什么挂在 `RootView` 顶层 overlay

不是页面级 cover。页面级 cover 会把 Duo 右侧 84pt 标签栏、底部 34pt 安全区**重新引入**，
面板宽度和按钮位置都控不住。挂顶层 + `ignoresSafeArea()` + 自己算 inset，才是可控的。

### 6.2 分流条件：`horizontalSizeClass == .regular`

```swift
if horizontalSizeClass == .regular { duoLayout } else { phoneLayout(in: Self.windowSize) }
```

⚠️ 这里用 sizeClass 而不是 `usesSplit` 是**故意的**：Duo 内屏竖屏也是 regular，
分享面板在那时同样需要「顶栏 + 右侧竖排操作条」的版式（竖屏 669 宽也放得下）。
2026-10-27 曾反过来把所有屏都套 Duo 版式，结果普通 iPhone 上面板左方右圆、
按钮悬到屏幕外 —— 现在两套互不污染。

### 6.3 尺寸不能从 `GeometryReader` 读

```swift
// 🔴 面板层级被 ignore 了安全区，GeometryReader 仍报「安全区内」的尺寸
phoneLayout(in: Self.windowSize)   // 用窗口尺寸，不用 proxy.size
```

Duo 外屏会因此少掉上下两条边，面板变得不满屏。

### 6.4 卡片尺寸：双约束 + 整体缩 10%

```swift
let hPad: CGFloat = 6, gap: CGFloat = 8, actionsWidth: CGFloat = 44
let cardScale: CGFloat = 0.9
let availW = proxy.size.width - hPad * 2 - gap - actionsWidth
let fitW   = min(availW, proxy.size.height * ratio)   // 宽/高双约束取小
let cardW  = fitW * cardScale
```

**为什么不能交给 `HStack { Image; Spacer; actions }` 自动布局**：`Image` 与 `Spacer`
同为 flexible，宽度会被 `Spacer` 抢走 —— 实测只长到理想尺寸的 87%（340×436 而非 390×500），
底部还悬空 84pt。

### 6.5 顶栏三个数字的来历（都是实测）

| 元素 | 值 | 依据 |
|---|---|---|
| 「完成」胶囊高度 | **34pt** | 右上角前置摄像头挖孔直径：屏幕 466pt 对应 915px，挖孔 66.8px ⇒ 34.0pt |
| 「完成」右距 | `padding(.trailing, 61)` | 胶囊右缘距屏右 = 61 + 14 + 6 ≈ 81pt，与首页顶栏胶囊组（83pt）基本重合，同时让开挖孔（占距屏右 35…64pt） |
| 顶栏上边距 | `padding(.top, 30)` | 面板圆角 46，y≈30 处安全水平界限约 3pt；距顶/左右必须 > 圆角，否则「完成」落在弧线上被切 |

「完成」用 `Text + onTapGesture` 而不是 `Button`：裸 `Button` 在 iOS 26 会被套一层玻璃底，
浅色面板上表现为一块淡蓝模糊、看不见字，`.buttonStyle(.plain)` 也去不掉。

### 6.6 右侧三个操作按钮：对齐状态栏中心线

不能按「84pt 标签栏的几何中心（距屏右 42pt）」算 —— 系统把状态栏画得更靠内。实测（1398px = 466pt）：

```
时间「12:17」 x 1197…1309，中心 1252px
Wi-Fi 图标    x 1193…1315，中心 1253px
→ 状态栏中心距屏幕右缘 48.3pt
→ 按钮半径 22pt，中心落在 48.3 ⇒ 右边缘距屏右 26.3pt
→ 扣掉面板 padding 6 ⇒ padding(.trailing, 20)
```

卡片左距不是重新算的，而是**从居中公式还原**（`(width - cardW - gap - actionsWidth) / 2`），
保证「按钮只右移、卡片分毫不动」。

### 6.7 圆角：屏幕半径 − 8，铰链侧 16

- 面板圆角 = 屏幕真实圆角 − 内缩量（8pt），两者弧线才同心平行；
- `ConcentricRectangle` 在**根 overlay** 里会被裁成**直角**（容器没有 `cornerConfiguration`），
  所以这里仍按屏幕半径显式算；
- 铰链侧用 16pt 小圆角（`UnevenRoundedRectangle`），因为那一侧贴着折痕。

⚠️ 等这块面板改成真正的 `sheet`（系统会给它 cornerConfiguration）时，再换回 `ConcentricRectangle`。

### 6.8 外屏要隐藏状态栏

```swift
.statusBarHidden(compact)
```

外屏的状态栏时间画在内容区内部右上角，正压在「完成」胶囊上。分享面板是模态的，
紧凑态直接隐藏状态栏（2026-11-01 截图发现）。

---

## 7. 三个真实事故（症状 → 根因 → 修法）

### 7.1 内屏竖屏「标题不见了」（2026-11-16，发版 316 修）

**症状**：统计页、设置页的大标题占位还在（顶部一大片留白），文字一个都不画；
只有 regular 宽度（内屏竖 669pt）复现，外屏正常。

**根因**：`AlludeApp.init()` 里给全局 `UINavigationBarAppearance` 整体替换：

```swift
let navAppearance = UINavigationBarAppearance()
navAppearance.configureWithOpaqueBackground()
navAppearance.backgroundColor = .systemGroupedBackground
UINavigationBar.appearance().standardAppearance = navAppearance
// …compact / scrollEdge / compactScrollEdge
```

整体替换后 **`largeTitleTextAttributes` 变成空值**，系统不补默认值 → 不画字。
用 `PLAIN_NAVBAR=1` 跳过它做对照，标题立刻回来。

**修法**：整套删掉。它当初是为「待取左上角白块」加的，但白块真正的修法是
`RootView` 给 TabView 铺 `systemGroupedBackground`（iOS 26 玻璃导航栏取样窗口背景）。
删掉后四页标题全正常、白块也没回来。

**通用教训**：碰 `UINavigationBarAppearance` 必须显式补
`largeTitleTextAttributes` / `titleTextAttributes`，或者干脆别碰 appearance proxy。

### 7.2 内屏竖屏「子项全部点不动」（2026-11-16，发版 318 修）

**症状**：外观与个性化（4 项）、关于 Allude（5 项）点不进去，其他功能正常。

**根因**：`ProfileView.destination(_:)` 给子视图传 `openPane` 的条件是
`horizontalSizeClass == .regular`；竖屏 669pt 也满足 → 渲染成 `Button { openPane(item) }`，
但竖屏走 `stackedSettings`，`pane` 没绑定导航，**点了只改一个没人用的变量**。

**修法**：抽出 `isSplitLayout`（§3.4），四个调用点全部改读它。

**教训**：「宽屏」不等于「分栏」。看到 `== .regular` 就问一句「这时候真的在分栏吗」。

### 7.3 内屏横屏「AI 子树点不进去」（2026-11-16）

**症状**：只有分栏态下「Apple 智能」「扩展」两个入口点不动。

**根因**：右栏是 `paneContent(pane)`，会被整棵替换；往里 push 被系统丢弃。

**修法**：见 §4.3（`openPane` 闭包 + 内部面板 + 页内 `@State` + 自绘返回）。

---

## 8. 弹层：订阅页的 sizing 矩阵（实测）

Duo 内屏可用的高度比直板机矮（横屏 669），`sheet` 的 sizing 参数在宽屏上行为很不一样。

| sizing 写法 | 实测结果 | 结论 |
|---|---|---|
| `.form` | 铺满整屏、铺满高 | Duo 上完全无效（没有「表单卡片」的收敛） |
| `.page` | 几乎铺满 | 内容全显示，但太宽 |
| `.fitted` 只给 `minHeight` | 居中窄卡片，高度被 clamp 到 ~890 | 底部差一条 |
| `.fitted` 只给 `width` | **塌成一条横条** | 不能只给宽度 |
| `fitted(horizontal:vertical:)` | **算出 0，弹层不可见** | 实例方法能编译但是坑 |
| `.fitted` + `minWidth/idealWidth/maxWidth + minHeight` | 见下 | ✅ 采用 |

**最终参数**：`420 / 450 / 470` + `minHeight 1000` ——
横屏实测渲染 515pt、弹层吃满可用高度；同一套参数在 460/500/520 时渲染约 570pt，也验过一屏装得下。

⚠️ **别拿横屏结果推竖屏**：内屏横屏可用高约 669、竖屏约 951（当前 runtime 实测，扣掉标签栏与安全区后更小），
弹层上限约 895。内容自然高度在窄档约 950 → 竖屏会超，宽档约 890 → 刚好。
⚠️ 上面这组参数最早是在内屏 **762×1080** 的旧 runtime 上定下来的（当时可用高 762 / 1080），
换 runtime 或换机型后**必须复验一次**，别直接套用结论。

配套的内容收紧（`FullVersionView`）：外层 spacing 18→10、planCard vertical 16→12、
说明行 34→30、标题 26→24pt、底部 padding 20→8。改完直板机回归确认仍一屏显示、底部法务链接完整。

---

## 9. 灵动岛与小组件

### 9.1 内屏没有岛

代码里凡是「假设岛一定存在」的地方都要改成存在性判断。折叠态才有 `DynamicIsland`，
展开态是普通宽屏。

### 9.2 `DuoOuterDisplay`：把结论过进程边界

灵动岛由**小组件进程**渲染，它看不到主 App 的窗口尺寸。所以主 App 启动时把结论写进 App Group：

```swift
enum DuoOuterDisplay {
    private static let key = "allude.duoOuter"
    static var isActive: Bool {
        // 脚手架：DUO_OUTER=1|0 强制覆盖，便于在任何模拟器上拍两种形态
        if let raw = ProcessInfo.processInfo.environment["DUO_OUTER"] { return raw == "1" }
        let d = UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
        return d.bool(forKey: key)
    }
    static func refresh(windowHeight: CGFloat) {
        // 🔴 先按 idiom 闸掉 iPad：台前调度/分屏时窗口高也可能 < 720
        if UIDevice.current.userInterfaceIdiom != .phone { … return }
        let duo = windowHeight < 720     // 直板机最矮 852，永不满足
        …写共享域
    }
}
```

调用点：`RootView.onAppear` → `DuoOuterDisplay.refresh(windowHeight: window.bounds.height)`。

### 9.3 外屏紧凑态只留数字

Duo 外屏的岛很窄，「待取」两个字占掉近一半可画宽 —— 所以紧凑态尾部**只留数字**。

```swift
GeometryReader { proxy in
    Text(cappedCount)                     // 超过 99 显示 99+
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
}
```

⚠️ `.frame(maxWidth: .infinity)` **撑的是内容宽度、不是区域宽度**，数字会贴着图标一侧。
必须用 `GeometryReader` 拿区域真实尺寸再居中。

直板机保持原样（数字带「待取」二字，有上下文）。宽度账（HIG 真实单侧可画宽）：
紧凑态单侧 52.33pt（393×852）/ 62.33pt（430×932），「待取」10pt×2 + 间距 3 + 数字 15 = 32.2pt（一位）/ 41.4pt（两位），仍有余量。

### 9.4 小组件尺寸

Duo 上系统可能给出 `systemExtraLarge` 一类家族。原则：**先只保证不崩、不乱**，
不要为 Duo 单独设计尺寸版式（那会跟直板机分叉）。

### 9.5 图标资源

灵动岛/锁屏用的 `AppIconNN.imageset` 必须在 `AlludeShared/Assets.xcassets`（两个 target 都编译），
`Contents.json` 必须写 `"template-rendering-intent": "original"` + 1x/2x/3x，
否则折叠态渲染成纯色方块。岛内图标随 `ContentState.appIconRaw` 过进程边界，扩展别自己读偏好域。

---

## 10. 验证方法（命令行可复现）

### 10.1 模拟器与显示

```bash
xcrun simctl list devices | grep -i duo        # UDID 会变，必须现查
xcrun simctl io <UDID> screenshot --display=1 /tmp/outer.png   # 折叠态外屏
xcrun simctl io <UDID> screenshot --display=3 /tmp/inner.png   # 展开态内屏
```

- 设备类型 `com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`；
- **不带 `--display=` 会报 `Invalid argument`**；
- 折叠时内屏是黑的，只能截到外屏。

### 10.2 四个必须知道的坑

1. **姿态会自己变**。同一 UDID 一会儿 951×669、一会儿 669×951。截图后先
   `sips -g pixelWidth -g pixelHeight` 确认朝向再解读，否则会把「竖屏」当「横屏」分析。
2. **shutdown / boot 之后回到折叠态**：内屏黑屏，且内屏启动慢（实测 20–40 秒，App 未必起得来）。
   **别靠重启模拟器「复位」** —— 代价是丢掉内屏。
3. **`simctl` 没有 fold/unfold 命令**，展开态只能在模拟器菜单里手动切。
4. 本机 `open -a Simulator` 找不到应用，`System Events` 被拒（-10004），
   **命令行转不了屏**。

### 10.3 转不了屏怎么验分栏

`PadLayout.isExpandedFoldable` 里留了 `FORCE_SPLIT=1`（仅 DEBUG）：

```bash
SIMCTL_CHILD_FORCE_SPLIT=1 SIMCTL_CHILD_SCREEN=settings \
  xcrun simctl launch --terminate-running-process <UDID> com.jikezhang.allude
```

🔴 **竖屏下强制分栏 ≠ 横屏分栏**：669×951 时 `NavigationSplitView` 会自己把左列折叠成
detailOnly，只能用来验「左列组件的颜色/字色」，**不能验布局**。真实横屏仍需真机或手动切姿态。

### 10.4 脚手架开关清单（全部仅 DEBUG 或环境变量，正式包零影响）

| 开关 | 作用 |
|---|---|
| `SCREEN=<name>` | 直渲指定页面（面板类唯一的取证方式） |
| `TAB=pending\|picked\|stats\|settings` | 启动即切标签 |
| `FORCE_SPLIT=1` | 强制 `isExpandedFoldable = true`（竖屏点验分栏） |
| `SETTINGS_COMPACT=1` | 设置页强制走单列（宽屏拍窄屏样式） |
| `SETTINGS_OPEN=<pane>` | 直接打开某设置面板（分栏分支有效） |
| `PAYWALL_SHEET=1` | 设置页直接弹订阅页（竖屏单列也能弹） |
| `PLAIN_NAVBAR=1` | 跳过全局导航栏外观（§7.1 的对照实验） |
| `DUO_OUTER=1\|0` | 强制灵动岛紧凑态样式（不切屏） |
| `SHOW_STATS=0` | 拍「统计已关」形态 |
| `AUTO_TAB=1` | 每 1.2 秒循环切标签（性能采样） |
| `PERF_LOG=1` / `PERF_FPS=1` | 分段耗时 / 帧间隔日志 |

### 10.5 真机

真机才能验：真实分栏比例、折痕位置、姿态切换的连续性、外屏挖孔与「完成」胶囊的实际关系、
灵动岛紧凑态（模拟器截不到真实岛）。装机：

```bash
bash tools/install-device.sh    # 自动探测 Team、构建、devicectl 安装
```

---

## 11. 新增页面时的 Duo 检查清单

写完一页，按这十条过一遍：

1. **布局判定**读 `PadLayout.usesSplit`（+ `paneWidth >= splitMinWidth`），不要只读 `sizeClass`。
2. **判定的条件只写一处**（`isSplitLayout` 之类），`body` 与所有子视图传参共用它。
3. **分栏下不要 push**：换 `pane`，或用页内 `@State` + 自绘返回。
4. **单列下用 destination 型** `NavigationLink`。
5. 分栏左右列**各自铺** `Color(.systemGroupedBackground).ignoresSafeArea()`。
6. 右栏空白要有兜底（回落第一条 / 占位视图），不能一片白。
7. 任何 `ignoresSafeArea()` 的面板，交互内容用 `effectiveInsets` 缩回。
8. 不要假设灵动岛存在；紧凑态若要定制，走 `DuoOuterDisplay`。
9. 卡片在宽屏会被拉宽，但**取件码字号不跟着放大**（它是识别码，不是标题）。
10. **直板机回归**：`SCREEN=settings/help/about/appicon`，待取/已取条数仍 4，卡片配色不变。

---

## 12. 与旧文档的三处出入（以本文为准）

1. **`CODEPOUCH_DEVICE` 不存在**。`iPhone Duo 适配规范_v1.md` 第 1 节写的
   「环境变量 `CODEPOUCH_DEVICE=slab|duo` 最优先」是早期设想，**从未实现**。
   现存的设备级脚手架只有 `FORCE_SPLIT`（分栏）与 `DUO_OUTER`（岛样式）。
   设备的真实分流一律靠 `PadLayout` 的几何判定。
2. **`DeviceClass` 没有建成**。适配规范要求「判定集中在 `DeviceClass`」，实际落地成了
   `PadLayout`（同一个思路，名字不同）。新增判定请加进 `PadLayout`，别再开第二个类型。
3. **「侧边竖排标签栏是 bug」已撤回**。官方明确这是设计意图
   （"position your toolbars, tab bars and controls along the side"）。
   现状：iPhone（含 Duo）统一用系统原生 `TabView`，Duo 内屏的侧边竖排由系统给；iPad 另走自绘底部栏。

---

## 13. 待办与不建议做的事

**待办**

- 真机（Duo）跑一遍三态截图 + 姿态切换连续性；
- 半折状态下的 `.division`（折痕）避让：目前只在分享面板处理了 `.occlusion`，折痕没有专门处理；
- 评估 `ArrangementView`（iOS 27.1）能否替代自绘面板的「预览 + 操作条」排布；
- 自绘栏（若将来做）应改用 `ReservedRegion` 主动认领可用区域，而不是算 inset；
- 全项目清一遍 `UIScreen.main` 残留（官方明确要弃用）。

**不要做**

- 不要为 Duo 换图标、配色、字号体系（那是全局的，不是设备级的）；
- 不要在 Duo 分支里顺手「优化」直板机（分开提交，方便单独回退）；
- 不要改 Bundle ID / App Group / 小组件 `kind`；
- 不要用 `NavigationSplitView` 之外的容器自己重写分栏（官方明确 `List`/`ScrollView`/
  `NavigationStack`/`NavigationSplitView`/`TabView` 对折痕与姿态是自动适配的）。

---

## 14. 一句话总结

Duo 适配在本项目里从来不是「为折叠屏写一套 UI」，而是**三件事**：
判定要准（`PadLayout`，别拿 sizeClass 当分栏）、宽屏容器里的导航要换写法（切 pane，别 push）、
自绘面板要认系统给的安全区（`reservedRegions`，别写死 84）。
剩下 90% 的坑，都在「内屏竖屏也是 regular」这一个事实上。

---

## 15. 附录：本文数字怎么复核

文档里的尺寸都可在本机复现，别只信文字。

**窗口尺寸与安全区**（临时探针，验完删掉）：

```swift
if let w = UIApplication.shared.connectedScenes
    .compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow) {
    print("[duo] bounds=\(w.bounds) safe=\(w.safeAreaInsets)")
    if #available(iOS 27.1, *) {
        for r in w.reservedRegions(kind: .occlusion) where r.isActive {
            print("[duo] occlusion=\(r.frame)")
        }
    }
}
```

对着 §1.1 的表看：外屏应是 466×678 + right 84，内屏横应是 951×669。

**判定结果**（DEBUG 已有探针）：

```
[allude-layout] isSplit=<bool> sizeClass=<regular|compact>
```

在 Duo 内屏竖屏必须是 `isSplit=false sizeClass=regular`；横屏必须是 `isSplit=true`。

**截图像素与朝向**：

```bash
sips -g pixelWidth -g pixelHeight /tmp/inner.png    # 2007×2853 = 竖，2853×2007 = 横
```

**模拟器 UDID**：`xcrun simctl list devices | grep -i duo`，不要抄文档里的旧值（重装 runtime 会变）。

---

## 16. 文档维护

- 最后核对：2026-11-21，构建 **1.0.0 (321)**，Xcode 27.2 / iOS SDK 27.2，模拟器 iPhone Duo（iOS 27.2）。
- 代码位置会漂：本文引用的函数名（`PadLayout`、`splitLayout`、`isSplitLayout`、`DuoOuterDisplay`、
  `PadSidebarHeader`、`occlusionInsets`）都比行号稳定，按名字搜。
- 改完 Duo 相关代码，**回来更新 §7 事故表与 §10 脚手架清单** —— 这两节是最容易过期的。
