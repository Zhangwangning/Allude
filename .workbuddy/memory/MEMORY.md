# 拾码 CodePouch 项目长期笔记（2026-10-30 改名版）

## 🔴 路径口径（2026-10-30 改名，旧笔记里的 CodeClip 路径全部作废）
- 仓库根：`/Volumes/ZWN/Downloads/Project/CodePouch/`
- 远端（2026-10-30 已改名并推送）：`https://github.com/Zhangwangning/CodePouch`（PRIVATE，main）
  旧地址 `github.com/Zhangwangning/CodeClip` 会 301 重定向到新地址。
- 工程根：`CodePouch/`（旧名 `CodeClip/`）
- App 源码：`CodePouch/CodePouch/`（三层同名，别数错）
- 工程文件：`CodePouch/CodePouch.xcodeproj`，scheme/target 均为 `CodePouch`
- **三项内部标识故意不改**（改了会丢数据/丢小组件）：App Bundle ID `com.jikezhang.codeclip`、
  Widget Bundle ID `...codeclip.CodeClipWidget`、App Group `group.com.jikezhang.codeclip`。
  第四项同类：小组件 `kind: "CodeClipPickupWidget"`（改了已添加的桌面小组件会失配）。
- 图标 macapp 数据目录 `~/Library/Application Support/CodeClipIssuer/` 也不改（台账在里面）。
- tools/ 下全部脚本已同步新路径；`install-device.sh` 与 `run.sh` 的 `DEVELOPER_DIR`
  已改为「有 beta 用 beta，否则 Xcode.app」（本机无 beta）。

## 构建（必须带 -disable-sandbox）
```
cd CodePouch && xcodebuild -project CodePouch.xcodeproj -scheme CodePouch \
  -destination 'generic/platform=iOS Simulator' build \
  CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS="-disable-sandbox"
```
- 环境：`/Applications/Xcode.app` **Xcode 27.2**，`simctl` 直接可用。
- 缺 `-disable-sandbox` → 宏展开失败，报一堆假 `cannot find '$x' in scope`。
  🔴 **真机构建同样必须带**：缺了宏服务崩溃，报
  `FoundationModelsMacros.GenerableMacro could not be found` +
  `swift-plugin-server produced malformed response`，并连带假的
  `'self' is immutable`（SwipeActionRow.swift 6 处）—— 2026-10-30 实测踩到。
- 产物：默认 DerivedData 目录名随工程改名变为 `CodePouch-<hash>`；稳妥做法是构建时
  显式 `-derivedDataPath`（本项目约定模拟器 `/tmp/codepouch-verify`、真机 `/tmp/codepouch-device`）。
- 项目内 `build/`、`build-sim/` 已全部清除（2026-10-30），不再有旧包误装风险。
- 🔴 clean build 必须 **0 warning**；弃用 API 当场迁移。

## 模拟器
- iPhone 16 Pro（回归基准）`272DD31C-D94F-46B4-9CC7-974A61439777`；iPhone Duo `4EBF7555-25F6-46D2-952D-02FBAD23BE3D`；18 Pro Max `B26F46C7-D209-4D54-8A36-B511A185BED7`。
- `simctl launch` 传环境变量**必须 `SIMCTL_CHILD_` 前缀**；重启用 `--terminate-running-process`（普通 terminate+launch 有时旧进程不退、变量不注入）。
- 截图必加 `SIMCTL_CHILD_SKIP_PERM=1`（通知弹窗点不掉）+ `SKIP_ONBOARDING=1`；首帧慢，sleep ≥4s（冷启动 6–8s）。
- SCREEN 值：`settings` / `courierGallery` / `stationGallery` / `pickedUp` / `share` / `stats` / `ingest` / `metrics`
  / **`add`**（添加面板，配 `SEED=<短信全文>` 预填识别）/ **`scan`** / **`scanPhoto`**（扫描面板）。
  `SCREEN=add` 是验证识别预览卡的唯一命令行路径 —— 面板要手点 `+` 才能开，而 App 未注册
  URL Scheme、本机无 idb/applesimutils、AppleScript 驱动模拟器被辅助功能权限拒绝（-10004）。
- 其他：`EDIT=1`、`DETAIL_MATCH=<码>`、`SEED=<短信>`、`GALLERY_ANCHOR=<分类>`、`SELECT_MODE=1`、`SWIPE_STRETCH=<pt>`、`COPY_TOAST=1`、`SORT=company|oldest|newest`。
- 分享面板取证：`SCREEN=share`（直渲，绕开长按菜单；`SHARE_HIT` 成功率仅约一半，已弃用）。
- `simctl io <udid> screenshot --display=<id> <file>`；Duo 外屏 `--display=1`，内屏需 `enumerate` 找 2007x2853 端口 UUID。
- Duo：runtime `iOS-27-2-iPhone19-4`；黑屏需 `open -a .../DeviceHub.app --args -CurrentDeviceUDID <udid>`。
- ✅ 可直接 Read PNG 看画面，布局验收「看图 + 像素量化」双证。

## Duo 宽屏适配（2026-10-25）
- Duo 内屏 951×669 @regular，右侧 84pt 系统标签栏；外屏 466×678 @compact，同样右侧竖排标签栏占 84pt。
- 待取/已取页 `.regular` → `NavigationSplitView` 平行视图，列宽**左右等分** `min 370 / ideal 434 / max 520`；`.compact` 保持原单栈（逐像素不变）。**别再试按铰链中轴分列**（系统夹死）。
- 右栏是**常驻详情**，不 push；未选中时回落列表第一条；入口统一 `openDetail(_:)`。
- 工具栏恒在 `.topBarTrailing`，不做边缘浮动栏。
- 统计页宽屏两列用**两个 VStack 手工分列**（勿用 LazyVGrid，卡高差极大）。
- 设置页：`SettingsPane` 枚举 + NavigationSplitView；侧栏宽按屏宽 40%；图标唯一实现 `SettingsGlyph`；**内容页底色必须 ZStack 独立铺一层**（`.background` 挂 ScrollView 在 detail 列撑不满 → 右栏整片白）。
- 账户功能已整体删除（2026-10-25），纯本地离线。

## 待取卡布局 v2（2026-10-19 定稿）
- 单个 `VStack`：上半文字（主名 / 地址 / 货架）左缘对齐；下半码行 = 图标 26pt + 取件码 30pt + Spacer + 右端 `CompleteButton`（多选态 44×44 选择圈）。
- 🔴 选择圈高度必须 44（曾写 44×36 导致整卡矮 8pt）。
- 🔴 **图标与取件码用 `.center` 对齐**（2026-10-28 主人改）：`.lastTextBaseline` 会把 26×26
  图标底边贴到文字基线，而数字无下行部 → 图标整体沉 4pt。实测 `.center` 下图标 78px
  （26pt）与码 66px（22pt）**中心完全重合**，上下各对称露 3px = 视觉垂直对齐。
  待取页 `PickupListView` 与已取页 `HistoryView` 两处卡同构，改一处必须同步另一处。
- 卡内无左侧独立勾选列；多选勾选在**卡片右端**（与已取页编辑态同位置同样式）。
- 右上角时间 = `record.shortTime`「M月d日 HH:mm」，**不用相对时长**（`storageAgeText` 已删）。
- 🔴 **主名口径（2026-10-28 改，全 App 统一）**：`titlePrimary = courier ?? company`，
  `titleSecondary = 驿站 ?? company`（都排除与主名相同）。**驿站不进主名位** ——
  曾经的 `courier > 驿站 > company` 会让「无 courier + 有驿站」时把超市名当主体
  （真机出现过「兴裕隆超市 ｜ 韵达快递」）。
  同口径适用于：待取卡、已取卡、锁屏卡（`ActivityLockScreenCard`）、分组名 `groupingName`、
  图标取色 `titleIconSource = titlePrimary`。
- 🔴 配色口径：`brand = company.isEmpty ? iconBrand : brandColor`（卡面/描边/勾选钮/货架胶囊）；**取件码恒用 `iconBrand`**（iconBrand = CourierBrand.color(for: titleIconSource)，titleIconSource = courier ?? station ?? company）。
- `StationDirectory`：ObservableObject 单例，29 个内置 + UserDefaults `station.customNames`，最长关键词匹配（扫 address + rawMessage）。

## 通知文案口径（2026-10-28 主人定）
- 🔴 **字段为空就整段不出现**，绝不用「未识别到取件地址」这类占位文案凑行。
  `PickupNotifier.notificationCopy` = `[company, address].filter{!isEmpty}.joined(" | ")`；
  两者全空 → body 为空（系统只显示标题=类别+码）。
- 标题恒为「取件码 X」；正文只有「平台 | 地址」一行，不设 subtitle（会被截断）。
- 同口径适用于每日提醒「最新：…」与超时提醒「记得去 …」，避免出现孤立「 | 」。
- 自检：`swiftc -O -o /tmp/notify-check CodePouch/CodePouch/Models/PickupNotifier.swift tools/notify-check/main.swift`。

## 灵动岛 / 实时活动（2026-10-28 三区定稿）
- 🔴 **改完灵动岛/锁屏卡必须强制 update 一次**：`PickupActivityController.apply` 有
  「内容一致就跳过 update」的省预算分支，重装后 `content.state` 没变就永远不重渲染 ——
  用户看到的还是旧画面，会一口咬定"你根本没改"。已加 `needsForcedRender`（每进程首次强刷）。
- 🔴 **展开态必须用满三个 region**：`.leading`（图标+公司名）、`.trailing`（待取计数）、
  `.bottom`（码 + 地址各一行）。只挂 `.bottom` 会让挖孔左右全空、内容整体沉底
  —— 主人原话「整体内容靠下，空间还大着呢」。
- 共用尺寸只在 `IslandExpandedMetrics` 里改：hInset 12 / punchHoleTopInset 20 / rowGap 13 /
  lineSpacing 3 / bottomInset 9 / trailingExtraInset 3 / punchHoleWidth 125.34。
  **顶部那块是「留白」不是「固定行高」** —— 早先给 header 行定死 40/64 再居中，
  文字顶只到行高一半，整岛要么矮 79pt 要么虚高 129pt。真机 = 顶部留白 20 + header 自然高度。
  整岛算下来约 110pt（真机实测 97pt）。
- 预览岛宽 = **屏宽 − 54**（`DeviceProfile.islandExpandedWidth`；iPhone 16 Pro → 348），
  **不要写死 371、也不要按 HIG 的「屏宽 − 22」**（那是 393 屏的上限值，实机更窄）。
- **设置页预览壳 `PhoneTopShell`（2026-10-28 定稿，官方机模 PNG 版）**：
  - 底图 `Assets.xcassets/PhoneFrame16Pro`（`Photoshop/iPhone 16 Pro.png`，1350×2760，
    带 alpha；**不要用剪贴板里的 jpg**，没 alpha 会出白底）。
  - 标尺 **3.08 px/pt**（机身外沿 1292px = 419.5pt ≈ 官方 420pt；校验：机身 2710px = 880pt ≈ 874）。
    → `designWidth 438.3 / designHeight 896.1`，全部按真实 pt 画，最后 `.scaleEffect(视口宽/438.3)`。
    **不要逐元素换算缩放**（算错一处就壁纸溢出/岛错位）。
  - 🔴 **边距基准是「屏幕顶边」不是「PNG 图片顶边」**：PNG 顶边往下 42px 才是屏幕
    （y26–40 机身边框 / y42 起屏幕黑边 / y69 起壁纸）→ `screenTopInImage = 13.6`。
  - 机模里**屏幕可见内容宽只有 394pt**（两侧各被机身压掉约 4pt），
    所以边距 `islandEdgeInset = (394−372)/2 = 11`，`holeTop = screenTopInImage + islandEdgeInset`（派生不写死）。
  - 实测三边各 28px（@3x）完全一致。岛宽 372 / `previewTotalHeight` 92。
  - 层级：机模（屏幕自带壁纸）→ 灵动岛。**不要叠假卡片、不要另铺屏幕截图**。
- 标定只认**同一张图里的手机本体宽度**（402pt）当标尺；带壳渲染图的内外沿差 8pt，别用。
- ⚠️ 换算比例只能用**同一张图内的已知尺寸**标定（如设置页卡片左右各 16pt）；
  没有参照物时优先信 Apple 官方值，别拿"看起来"当数。
- 真机展开态**无法脚本化截图**（要长按），只能装机让主人验。

## 详情页字段口径
- 顺序：取件码 → 短信平台 → 快递公司 → 快递驿站 → 取件地址 → 货架号 → 运单号 → 尾号 → 添加时间。
- 🔴 **快递驿站 ≠ 取件地址**：驿站 = `matchedName(in: [rawMessage])` 实时匹配、只读不落库；地址 = `record.address`（可编辑）。
- 编辑态所有字段恒显（`required || 有值 || 编辑态`），运单号/尾号只读。
- 顶部 `codeCard`：主名口径同列表卡；右上角入库时间，已取件改显「已取」徽章；无可见复制按钮（长按码复制）。
- 详细页标题恒为「详情」。

## 分享面板 SharePreviewSheet（2026-10-27 重构）
- `SharePresenter` 单例 + **RootView 顶层 ZStack** 渲染（不用页面级 sheet/cover，否则重新引入 Duo 标签栏与避让区）。
- 按 `horizontalSizeClass` 分流：`.compact` = `phoneLayout`（标准居中 + 底部三按钮横排）；`.regular` = `duoLayout`（原 Duo 定制：`UnevenRoundedRectangle` 左 16 右 55、按钮右竖排）。
- 🔴 面板圆角 = **`displayCornerRadius − inset(8)`**，从 `UIScreen._displayCornerRadius` 读（16 Pro/18 Pro Max 实测 **72** → 面板 64）；**禁止硬编码**（26、46 都错过）。
- 🔴 外层 `ignoresSafeArea` 里 `GeometryReader.safeAreaInsets` 读到 0 → 必须用 `SharePreviewSheet.windowSafeInsets`（UIKit 取 key window）。
- 卡片主色 = 图标主题色（courier > station > company），不用 brandColor。
- 底部按钮间距 `max(28, safeBottom + 20)`。

## 快递公司 / 驿站管理（2026-10-27 拆分）
- `CourierGalleryView(scope: .courier / .station)`：分类、标题、summary 随 scope 走。
  - `.courier` = 快递公司 / 国际快递 / 商家·电商；`.station` = 驿站·代收平台 / 智能快递柜（首格「添加驿站」）。
- 设置项 `SettingsPane.courier`（快递公司）+ `.station`（驿站管理），宽屏分组 `generalGroup`、窄屏两行。
- 🔴 LazyVGrid 格子必须与 brandCell 同构，复杂版式会让整格跳过渲染。

## 解析器 / 小组件
- `PickupParser` 四套独立正则 + 优先级链：code → waybill → tail → special（**不要照搬快捷指令的四合一**，会丢 kind 类型）。
- 2026-10-27 已同步快捷指令 V8.0.3 全部公式（剥掉其首位特殊格式分支）；新增 `locker` 字段（快递柜）。
- 🔴 **新增正则必须注册进 `regexes` 预编译表**，否则 `firstMatch` 恒 nil 且不报错。
- 🔴 **一码一卡口径（主人 2026-10-28 定）**：一条短信里有多个取件码，就拆成对应数量的卡片。
  展开由 `parseAll` 里的 `codeChainParts` 负责；**但链式段必须与首段同形**（`codeShape` 指纹：
  数字段 `d`、字母段 `a`），且单段纯数字至少 4 位 —— 否则「取件码8-2-4031，**2**号柜」的
  柜位号会被 `，` 当成第二件，凭空多出一张码为「2」的卡。（快捷指令不会犯这错，因为它只取第一段。）
- 回归：`swiftc -O -o /tmp/parser-regression CodePouch/CodePouch/Models/PickupParser.swift tools/parser-regression/main.swift`，语料 `/Volumes/ZWN/Downloads/Project/shortcuts-toolkit-master/快递取件码短信库.md`（64 条 / 61 地址基线）。
- 小组件：码后显示 `widgetLockerLabel`（柜优先，无柜退回「货架N」）；第二行 `courier ?? company` ｜地址；类型标签已全删。

## 地图导航
- `AddressMapCard`：MapKit 迷你预览 + 导航；`MKGeocodingRequest(addressString:)` + `getMapItems`；`MKMapItem(location:address:)`。工程 `IPHONEOS_DEPLOYMENT_TARGET = 27.0`，无需 `#available`。
- 短信库页已下线（`SmsLibrary.swift` Model 保留服务首装预置）；语料落盘 `短信语料库_v1.md`。

## Swift / SDK 踩坑
- 多行 raw string `#"..."#` 在该工具链有编译 bug → 用 `"""..."""`（收尾独占行）。
- `Color.quaternary` 返回 `some ShapeStyle`，不能与 `Color` 混三元。
- iOS 27 SDK：`UIColor.tertiaryLabelColor` → `tertiaryLabel`；`UIScreen.main` 已废弃。
- `Label(_, systemImage: "checkmark")` 在 Menu 行里图标**恒排最左**，要尾随勾号只能用字符「✓」。
