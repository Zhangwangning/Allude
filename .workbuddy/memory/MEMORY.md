# Allude 长期笔记 · 核心（2026-11-21 v3）

> 发版链路 / 真机安装重签 / 模拟器取证 / 内购实测 → 见同目录 **`OPS.md`**。

## 路径与固定标识（不可改）
- 仓库根 `/Volumes/ZWN/Downloads/Project/Allude/`（GitHub `Zhangwangning/Allude` 私有）；
  工程根 / App 源码 / target 三层同名 `Allude/Allude/Allude/`。
- Bundle `com.jikezhang.allude`、Widget `…AlludeWidget`、App Group `group.com.jikezhang.allude`、
  Widget kind `AlludePickupWidget`、iCloud `iCloud.com.jikezhang.allude`。
- 纯 iPhone（`TARGETED_DEVICE_FAMILY=1`），部署目标 iOS 17.0，`GENERATE_INFOPLIST_FILE=NO`
  → 增删 Info.plist 键必须改真实文件，`INFOPLIST_KEY_*` 不生效。
- 版本号 4 处 `CURRENT_PROJECT_VERSION`（App/Widget × Debug/Release）。pbxproj 改版本号必须
  「先读进变量再写回」，内联读写会截断成 0 字节。
- 🔴 工程是 **Xcode 16 同步文件夹**（`PBXFileSystemSynchronizedRootGroup`）：`Allude/` 下新增
  Swift/PNG **不用改 pbxproj**，自动进包（旧笔记「必须手动进 pbxproj 三处」已过时）。

## 构建
```
cd Allude && xcodebuild -project Allude.xcodeproj -scheme Allude \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/allude-verify build \
  CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS="-disable-sandbox"
```
- 缺 `-disable-sandbox` → 宏插件起不来，报假错（`'self' is immutable`、`StateMacro could not be found`）。
- 🔴 agent 会话内构建**必卡 CoreML**：`sandbox-exec: sandbox_apply: Operation not permitted`
  （Xcode 硬编码包 coremlc），`ENABLE_USER_SCRIPT_SANDBOXING=NO` 无效。
  绕过：临时 `mv AlludePickup.mlmodel{,.bak}` → 构建 → 还原。不需要生成 Swift 包装。
  （真机/发版时补回 `.mlmodelc` 的做法见 `OPS.md`。）

## 界面口径
- 卡片主名 `titlePrimary = courier ?? company`，副名 `secondaryLabel`（组名/驿站，驿站不进主名位）；
  列表卡 / 详情 / 锁屏 / 分组名 / 图标取色同口径。
- 取件码恒用 `iconBrand`；卡面 `brand = company.isEmpty ? iconBrand : brandColor`。
- 图标 26pt 与取件码 `.center` 对齐（`.lastTextBaseline` 沉 4pt）；多选圈高 44。
  待取 `PickupListView` 与已取 `HistoryView` 卡同构，改一处必须同步。
- 字号只用 `AppTheme.TypeScale`：rowTitle 17 / rowSubtitle 13 / body 15 / section 13 / note 12 /
  badge 11；强调只加 weight（例外：chevron 12–13、等宽码）。
- 通知：字段空就整段不出现，绝不用占位句凑行。
- 灵动岛展开必须用满 `.leading`/`.trailing`/`.bottom`，尺寸只在 `IslandExpandedMetrics` 改；
  改完强制 update 一次（有「内容一致跳过」分支，靠 `needsForcedRender`）。
- 灵动岛图片 `Contents.json` 必须 `template-rendering-intent: original` + 1x/2x/3x，否则折叠态纯色方块。
- Section header 里 `listRowInsets` 不生效 → 分组标题当普通行塞进 Section 首行。
- 版本历史页 `Entry.id` **不能用 `UUID()`**（视图重建换 ID，与 `@State` 存的旧 ID 对不上，折叠弹回）。
- 付费页 `FullVersionView` **必须一屏放得下**（form sheet 上限 890pt，2026-10-31 硬要求）；
  解锁清单固定 5 行，说明只写「免费版多少 / Pro 给什么」，不写全名、不写隐私定语（2026-11-21 精简）。
- 版本历史 / 内测记录是**给用户看的**：只写能感知的变化，不写页头 34pt、侧栏 440pt 这类开发者口径
  （2026-11-21 主人原话），也不要留 `*…**` 残留星号。

## 解析与数据
- `PickupParser` 四套正则 + 优先级链 code→waybill→tail→special；新正则必须注册进 `regexes`
  预编译表（否则静默 nil）。一码一卡：链式段须与首段同形（`codeShape`），纯数字段 ≥4 位。
- 三层误判防线：`isPendingDeliveryOnly` / `isPromotionalOnly`（营销话术 + 零取件线索双条件，
  不能只凭「拒收请回复R」）/ `isVersionLikeCode`（`glm-5`、`gpt-4` 不是码）。
  关键词闸门 `京东(?!卡)`——「京东卡」是营销奖品。
- 🔴 **升级 App 不会重解析存量记录**：解析修好只对之后 ingest 的生效，旧卡片仍错 → 删掉重加。
- 权益快照新字段一律 `decodeIfPresent`；`MembershipPlan` 只增不删（删 case = 老用户掉回免费版）；
  订阅必须写 `expiresAt`。
- `enforceStorageLimit()` 只在 `ingest()` 触发（免费 50 条 FIFO），启动不删。
- iCloud 写 `<容器>/Documents/records.json`。BYOK Key 只在 Keychain（service `com.jikezhang.allude.ai`）。

## 驿站组 / 驿站 ID / 排序
- `AlludeShared/StationGroups.swift`（App + Widget 双 target）。
- ID 前缀：内置 `NZYZ`、自定义 `DZYYZ`、组 `FZYD`，各 5 位补零；**首次发号落盘固化**
  （`station-identity.json`），之后只追加，不能按下标实时算。
- 组数据 `station-groups.json`：`id/name/memberIDs/createdAt/iconInheritMemberID/locationInheritMemberID`；
  关系挂**成员 ID**，改名走 `StationIdentity.rename`。
- 三段优先级：组驿站 > 未归组驿站 > 组内成员。⚠️ ②③ 前缀相同，靠 `memberIndex()` 分辨。
- 渲染：`PickupSortLogic.stationName` → 组名；`PickupNaming.secondaryLabel` → 「组名/原名」；
  待取卡 / 已取卡 / 详情 / 分享卡四处都改。
- 图标继承两路：内置成员 `CourierLogo`、自定义成员 `iconFiles`（只查 `iconFiles` 会把内置驿站
  按组名首字画）。
- 围栏：组优先、组内成员不单独监控；`matches` 先把记录驿站 resolve 成组名再比。
- `StationGroupStore.all()` **必须缓存** —— `StationLogo` 每画一格都问「这是不是组」。
- **取件码自然排序** `PickupCodeOrder`：切字母/数字段，数字段去前导零后先比位数再比字典序
  （等价比数值、不溢出 Int）；数字段排在字母段前；同形回落原文。自带三态 `Order` 不用
  `ComparisonResult`（单文件编译不可用）。`Character.isNumber` 对全角/罗马数字也 true →
  必须 `ch.isASCII && ch.isNumber`。
- 🔴 **并列必须走 `PickupSortLogic.tieBreak`**（2026-11-21 老大定）：短信是批量导入的，47 条待取
  只有 5 个时间戳、22 条并列在同一秒，而 Swift `sorted` 不稳定 → 同一份数据 App 与小组件排出
  两种顺序（用户看到「桌面顺序不对」）。
  **规则：时间一致 → 组内按取件码 0-9、A-Z 升序**（即 `PickupCodeOrder` 自然序；数字段按**数值**
  比，`8-4-999` 在 `8-4-1005` 前，不是逐字符），码也相同再比 id。恒升序，与当前排序方向无关。
  覆盖点：`StationInnerOrder.isOrderedBefore`、`PickupSortLogic.sort` ×3、待取页 `computedDisplayed`
  与 `searchBase`（`prefix` 截条数依赖它）、已取页 `computedOrderedList` 与公司桶、`PickupStore.pending`
  / `pickedUpRecords` / `enforceStorageLimit`、灵动岛与锁屏两处。
- 切「分组方式」后必须 `WidgetCenter.shared.reloadAllTimelines()`，只写 App Group 不会让
  桌面自己知道（能拖几小时）。

## 图标（15 套）
- 🔴 全部 `AppIconNN.imageset` **只放 `AlludeShared/Assets.xcassets`**（两 target 都编）；
  放 App catalog → 灵动岛/锁屏静默渲染灰块。
- 新增一套动四处：imageset（60/120/180 + original）、`Allude/AppIcons/IconNN@2x|@3x.png`、
  Info.plist 的 **`CFBundleIcons › CFBundleAlternateIcons`**（⚠️ 不在顶层）、`AppIconChoice`。
  `sips -z` 只改尺寸不改格式，源是 JPEG 必须加 `-s format png`。
- 编号连续 01…15，`fallback` = **`.icon06`（黑盒立体）**，Info.plist 注册 **14 条** alternate
  （06 是主图标，不能登记）。12–15 是 2026-11-21 晚追加的四套（纯追加不改已有序号 →
  `currentScheme` 仍为 `"3"`，`legacyMap` 无需扩）。只有「已有图标序号被改动」才扩 legacyMap + 升 scheme。
- **目录号** `AppIconChoice.catalogID` = `DZYTB%04d`，按网格从上到下、从左到右发号
  （DZYTB0001…DZYTB0015），网格下方显示「DZYTB0006 · 黑盒立体」，无障碍标签也带号。
- 🔴 **岛内图标随 `ContentState.appIconRaw` 传**，扩展别自己读 `AppIconStore.current`
  （App Group 一断就回落 fallback）。换完走 `refreshForAppIconChange()`。
- `AlludeWidget/Assets.xcassets` 只留 `AccentColor` + `WidgetBackground`。
- 模拟器截不到真实灵动岛，只能真机验。
- 🔴 **换图标模拟器差异**：iOS **17.4 模拟器完全正常**（实测切第 14 套成功）；iOS **26.1/27.2
  模拟器必失败**（宿主侧 CoreServicesUI 缺 upcall bundle：`Code=5 couldn't load upcall bundle
  principal class` / `Code=35 LSIconAlertManager`，重启/换干净模拟器/重装都无效）；**真机正常**。
  → 验切换用 iOS 17.4 runtime 那台或真机，26/27 模拟器只看网格渲染与选中态。
- ⚠️ 图标偏好**三处**存储，优先级从高到低：App Group `group.com.jikezhang.allude` 域
  （模拟器里也能用！）→ `<App容器>/Library/Application Support/appicon.txt` → standard 域。
  改模拟器状态必须三处一起改，只改镜像文件会被 App Group 旧值压过去；改完 `shutdown`+`boot`
  让 cfprefsd 重载。`simctl spawn defaults read` 读不到 App Group 域，要直接读 plist 文件。

## 现状（2026-11-21 晚）
- TestFlight 最新 **329**（VALID，`019d0ed6`，挂「Allude公测」）；324 及以下全部停测。
  发版细节见 `OPS.md`。
- 🔴 **1.0.0 = REJECTED（2.1 Information Needed）**，需先在 Resolution Center 补 6 项说明；
  草稿 `tools/appstore-review/1.0.0-resubmit-2.1.md`（3,861 字符 < 4,000）。
- 🔴 **内购价格在真机不显示 = 商品未过审**（lifetime `READY_TO_SUBMIT`、annual `CREATED`），
  不是代码问题；详见 `OPS.md`。
- 免费额度（代码为准）：`PickupLimits.freeVisible = 4`、`freeStorage = 50`、`widgetListCap = 60`。
- App 备案未完成（网站 ICP 陇ICP备2026011130号已过，App 备案是另一套编号）。
- 法务线上仓 `Zhangwangning/allude-legal`（GitHub Pages）；App 内文本 `Allude/Allude/Legal/*.html`，三副本同步改。
- 交接主文档 `交接说明_workbuddy_2026-11-21.md`（345 行）；`交接说明_dsh.md` 1,298 行（§1–§27 历史）。
- 性能范式：计算属性记忆化缓存放 **model（@StateObject 的 class）**，不放 View 的 `@State`
  （body 求值期间写 state 会二次重算）；缓存键用 `hashValue` 不用 `count`。
  `VStack` → `LazyVStack` 可消首帧冻结，代价 `proxy.scrollTo` 到未构建视图失效。
