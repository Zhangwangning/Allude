# Allude 项目长期笔记（2026-11-17 精简 v2）

## 路径与固定标识（不可改）
- 仓库根 `/Volumes/ZWN/Downloads/Project/Allude/`（GitHub `Zhangwangning/Allude` 私有）；
  工程根 / App 源码 / target 三层同名 `Allude/Allude/Allude/`。
- Bundle `com.jikezhang.allude`、Widget `…AlludeWidget`、App Group `group.com.jikezhang.allude`、
  Widget kind `AlludePickupWidget`、iCloud `iCloud.com.jikezhang.allude`。
- 纯 iPhone（`TARGETED_DEVICE_FAMILY=1`），部署目标 iOS 17.0，`GENERATE_INFOPLIST_FILE=NO`
  → 增删 Info.plist 键必须改真实文件，`INFOPLIST_KEY_*` 不生效。
- 版本号 4 处 `CURRENT_PROJECT_VERSION`（App/Widget × Debug/Release）。pbxproj 改版本号必须
  「先读进变量再写回」，内联读写会截断成 0 字节。
- `AlludeShared/`、`AlludeWidget/` 是显式 PBXGroup：**新增 Swift 必须手动进 pbxproj 三处**。

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

### 真机（唯一能验灵动岛的路）
```
DEST='platform=iOS,id=00008140-001138A92E01801C'   # iPhone 16 Pro
xcodebuild -project Allude.xcodeproj -scheme Allude -destination "$DEST" \
  -derivedDataPath /tmp/allude-device -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration OTHER_SWIFT_FLAGS="-disable-sandbox" build
```
- 团队 `8499X3S9X8` automatic signing。模拟器 `CODE_SIGNING_ALLOWED=NO` 的包**没有 App Group**。
- `coremlc compile` 手工可跑（只有 build rule 才包 sandbox-exec）→ `cp -R` 进 `Allude.app/` → **必须重签**；
  用 `codesign -d --entitlements :-` **导出的** entitlements（裸 `Config/*.entitlements` 缺
  `application-identifier`/`team-identifier`/`get-task-allow`，装了起不来），先 appex 后 App。
- `devicectl device install app`；`process launch --terminate-existing -e '{"SCREEN":"…"}'`；
  `process terminate --pid <pid>`（**只吃 pid**）。
- 真机读写：`devicectl device info files|copy from|copy to --domain-type appGroupDataContainer
  --domain-identifier group.com.jikezhang.allude`。真机启动会从 iCloud 同步，种子数据可能被覆盖。

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

## 解析与数据
- `PickupParser` 四套正则 + 优先级链 code→waybill→tail→special；新正则必须注册进 `regexes`
  预编译表（否则静默 nil）。一码一卡：链式段须与首段同形（`codeShape`），纯数字段 ≥4 位。
- 三层误判防线：`isPendingDeliveryOnly` / `isPromotionalOnly`（营销话术 + 零取件线索双条件，
  不能只凭「拒收请回复R」）/ `isVersionLikeCode`（`glm-5`、`gpt-4` 不是码）。
  关键词闸门 `京东(?!卡)`——「京东卡」是营销奖品。
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
- **取件码自然排序** `PickupCodeOrder`（2026-11-17）：切字母/数字段，数字段去前导零后先比位数
  再比字典序（等价比数值、不溢出 Int）；数字段排在字母段前；同形回落原文。自带三态 `Order`
  不用 `ComparisonResult`（单文件编译不可用）。`Character.isNumber` 对全角/罗马数字也 true →
  必须 `ch.isASCII && ch.isNumber`。

## 图标（16 套）
- 🔴 全部 `AppIconNN.imageset` **只放 `AlludeShared/Assets.xcassets`**（两 target 都编）；
  放 App catalog → 灵动岛/锁屏静默渲染灰块。
- 新增一套动四处：imageset（60/120/180 + original）、`Allude/AppIcons/IconNN@2x|@3x.png`、
  Info.plist 的 **`CFBundleIcons › CFBundleAlternateIcons`**（⚠️ 不在顶层）、`AppIconChoice`。
  `sips -z` 只改尺寸不改格式，源是 JPEG 必须加 `-s format png`。
- 编号连续 01…16，`fallback` = `.icon04`（C 标），Info.plist 只注册 15 条 alternate。
  重排靠迁移：`migrateLegacyNumberingIfNeeded()` + `allude.appIcon.scheme` 标记 + `legacyMap`。
  以后改编号：扩 `legacyMap` + 升 `currentScheme` 一起做。
- 🔴 **岛内图标随 `ContentState.appIconRaw` 传**，扩展别自己读 `AppIconStore.current`
  （App Group 一断就回落 fallback）。换完走 `refreshForAppIconChange()`。
- `AlludeWidget/Assets.xcassets` 只留 `AccentColor` + `WidgetBackground`。
- 模拟器截不到真实灵动岛，只能真机验。

## 模拟器取证
- 无 idb/applesimutils，AppleScript 被拒（-10004）→ 面板靠 `SIMCTL_CHILD_SCREEN=xxx` 直渲。
- `launch` 必须 `--terminate-running-process`；装完先核对 `CFBundleVersion` 再截图。
- 模拟器 ID 会变，用 `xcrun simctl list devices` 现查（本机 iPhone 16 Pro iOS 26.1、
  iPhone 17 iOS 27.2、iPhone Duo 27.2 分栏）。验 `if #available(iOS 27)` 必须用 iPhone 17。
- 性能：`xctrace record --template 'Time Profiler' --attach <pid> --time-limit 18s`，
  导出 xpath `/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]`；
  XML 里 frame/thread 是 id 定义 + ref 引用，必须建表再解析。`Animation Hitches` 模拟器不支持。

## TestFlight 发版（全命令行）
- 🔴 `-exportArchive` **本机不可用**（无 GUI 时 `ITunesSoftwareService` 起不来），别试。
- 分发证书 `P76B23FF7S`（2027-11-15）；profile：App `7H29P7MJ8Q`（bundleId `N42529Q6F6`）、
  Widget `4F62FDJ8K2`（`M53D3TXT6B`）。⚠️ 别用 `bids["data"][0]`（第一个是 Widget）。
- 🔴 entitlements 不能照抄 profile：`icloud-services=*`、`icloud-container-environment`、
  `ubiquity-kvstore-identifier=团队.*` 都会被拒。手写精简版：`CloudDocuments`（数组）、
  删 environment、`keychain-access-groups` 写具体 bundle id、`get-task-allow=false`、
  `aps-environment=production`、`beta-reports-active=true`。
- 链路：`mv .mlmodel .bak` → `xcodebuild archive -destination 'generic/platform=iOS'
  -allowProvisioningUpdates` → 删包内 `.bak` + 补 `.mlmodelc` → 下载 profile 重签（先 appex 后 App）
  → `cd /tmp && ditto -c -k --norsrc --keepParent Payload /tmp/Allude.ipa`
  （🔴 传 **Payload 目录**；**不能加 `--sequesterRsrc`**）
  → `xcrun altool --validate-app` / `--upload-app`（apiKey `34Z43R5SGY`，
  issuer `e2936bfc-e52b-4931-a763-9f03dec868e3`；`WILL RETRY` 是常态）
  → 2–3 分钟转 VALID 后 `python3 tools/testflight-publish.py --build NNN --notes-file …`。

## 现状（2026-11-17）
- 1.0.0 已提交审核（WAITING_FOR_REVIEW，绑 309）。320 已上传 VALID 并挂「Allude公测」+ Beta 审核。
- 两个内购仍 `CREATED`，中国区价格未生效 → TestFlight 沙盒回落 USD 基准价。
- 法务线上仓 `Zhangwangning/allude-legal`（GitHub Pages）；App 内文本 `Allude/Allude/Legal/*.html`，两边同步改。
- 性能范式：计算属性记忆化缓存放 **model（@StateObject 的 class）**，不放 View 的 `@State`
  （body 求值期间写 state 会二次重算）；缓存键用 `hashValue` 不用 `count`。
  `VStack` → `LazyVStack` 可消首帧冻结，代价 `proxy.scrollTo` 到未构建视图失效。
  DEBUG 探针：`PERF_LOG=1`（PerfProbe，写 Documents/perf.log）、`PERF_FPS=1`（FrameMonitor）。
