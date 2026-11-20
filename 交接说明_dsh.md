# Allude 项目移交说明（面向 dsh）

> 生成时间：**2026-11-20**，对应构建 **1.0.0 (321)**，工作区 `main` 分支干净。
> 本文所有结论都来自**本机实测 + App Store Connect 实际返回值**，不是回忆。凡标 ⚠️ 的地方，都建议你重新核对一次。
> 前一版交接文档 `交接说明_workbuddy.md`（2026-11-15，312）**已部分过时**，以本文为准。

---

## 0. 一页速览

| 项 | 现状（2026-11-20 实测） |
|---|---|
| 产品 | **Allude**：iOS 取件码收纳 App。核心承诺「数据只在本机，不联网、不上传、不需要注册」 |
| 形态 | 纯 iPhone（`TARGETED_DEVICE_FAMILY = 1`），部署目标 **iOS 17.0**，SwiftUI，零第三方依赖、零 SPM |
| 版本 | `MARKETING_VERSION = 1.0.0`，`CURRENT_PROJECT_VERSION = 321`（pbxproj 里四处同步） |
| 代码量 | **98 个 Swift 文件 / 37,273 行**（App 21,936 + 模型 7,044 + 共享 6,579 + 小组件 281 + 入口 1,391） |
| 仓库 | `https://github.com/Zhangwangning/Allude`（**私有**），分支 `main`，**430 次提交**，起点 2026-10-16（前身 CodeClip） |
| TestFlight | 构建 **321** 已 `VALID`，Beta 审核 **APPROVED**，已挂外部群组「Allude公测」，测试内容已写 |
| App Store | 1.0.0 = **REJECTED**（绑构建 309）—— 见 §2.1，这是接手后的**第一优先事项** |
| 内购 | `pro.lifetime`（非消耗型）、`pro.annual`（自动续期订阅）均为 **READY_TO_SUBMIT**，尚未随版本提交 |
| 免费额度 | 同屏 **4** 条、本机最多 **60** 条（FIFO 淘汰）、搜索到的记录打不开详情；Pro 全部放开 |

### 接手后必须立刻知道的三件事

1. **1.0.0 已被 App Review 拒了**（`appStoreState = REJECTED`，仍绑旧构建 309）。拒绝理由只能登录 App Store Connect → Resolution Center 看，公开 API 读不到。本文不臆测原因。
2. **两个内购还停在 `READY_TO_SUBMIT`**，没和任何版本一起提交过。App 免费下载 + 内购解锁是唯一商业模式，内购不提交 = 上线即无收入。
3. **中国大陆上架还缺 App 备案号**。网站 ICP（陇ICP备2026011130号）已通过，但 App 备案是**另一套流程**，见 §11.3。

---

## 1. 产品定位与商业模式

### 1.1 数据流

```
快递短信 → 快捷指令自动化（触发：信息内容包含「」/【）
        → App Intents 后台静默写入（不打开 App）
        → PickupParser 四套正则 + 优先级链解析
        → PickupStore 落盘（本机 JSON）
        → 待取列表 / 桌面小组件 / 灵动岛 / 锁屏实时活动 / 统计
```

**唯一网络行为**：① StoreKit（只连 Apple）；② 用户**自己**开的三方大模型增强（BYOK，App 直连服务商，不经开发者服务器）。没有账号体系、没有自建后端。

### 1.2 收费模型（免费下载 + 订阅解锁，参照 Infuse）

| 商品 | Product ID | 形态 | 备注 |
|---|---|---|---|
| 每年 | `com.jikezhang.allude.pro.annual` | 自动续期订阅 | 定价由 ASC 配，代码只读 `Product.displayPrice` |
| 终身 | `com.jikezhang.allude.pro.lifetime` | 非消耗型买断 | **主推** |
| ~~每月~~ | `pro.monthly` | 已下架 | `PurchaseStore.Plan.monthly` 只为解码老数据保留 |

- 权益判定：**任意一档有效 = 完整版**（`EntitlementSnapshot.licensedPro`）。
- 🔴 订阅必须把 `expiresAt` 写进权益快照（`entitlement.json`）。小组件进程不联网、不查 StoreKit，只读快照；漏了到期时间，订阅过期后小组件会一直按 Pro 渲染。
- 🔴 `MembershipPlan` 枚举**只增不删**：删 case = 老快照解码失败 = 用户静默掉回免费版。

### 1.3 免费 / Pro 边界（代码里的唯一事实来源）

`AlludeShared/PickupStorage.swift` → `enum PickupLimits`：

| 常量 | 值 | 含义 |
|---|---|---|
| `freeVisible` | **4** | 列表与小组件同屏条数 |
| `freeStorage` | **60** | 本机存储上限，超出 FIFO 淘汰最旧（只在 `ingest()` 触发，启动不删） |
| `unlimited` | 9,999 | 代替 `Int.max`，避免 `count - limit` 溢出崩溃 |
| `widgetListCap` | 60 | 小组件可翻动上限（头部总数仍显真实值） |

Pro 另解锁：不限条数、全尺寸小组件、实时活动、重复提醒、到达提醒、AI 增强。

---

## 2. 当前进度（逐项实测）

### 2.1 App Store 上架：**被拒**

```
版本 1.0.0 · appStoreState = REJECTED · reviewType = APP_STORE
releaseType = SCHEDULED · earliestReleaseDate = 2026-11-30T09:00:00-08:00
关联构建 = 309（VALID）· 本地化 zh-Hans · 截图集 APP_IPHONE_67（6.7 寸）
描述长度 403 字符 · 关键词 13 个
```

**要做的事**：
1. 登录 ASC → 该 App → **Resolution Center**，读拒信原文（Guideline 条款 + 截图/录屏附件）。
2. 按拒信修；`tools/appstore-review/1.0.0-notes.md` 里有上一轮给 Apple 的说明稿，可复用。
3. 修完把版本重新绑到新构建（`appStoreVersion` → build 关系），再提交。
4. ⚠️ `earliestReleaseDate` 是 **2026-11-30**，手动放行前不会自动上架。

### 2.2 TestFlight：正常

- 构建 321：`processingState = VALID`、Beta 审核 `APPROVED`，已挂「Allude公测」(`c90099fc-1862-4b2a-8f48-a7537111fe45`)。
- 历史构建 317 已过期，318/319/320/321 均 VALID。
- 发版脚本：`tools/testflight-publish.py`（挂群组 + 写测试内容 + 提交 Beta 审核，一条命令）。

### 2.3 内购：**待提交**

`pro.lifetime` / `pro.annual` 均为 `READY_TO_SUBMIT`，各有价格配置。首次必须**随 App 版本一起**提交审核；提交前在 ASC 里确认中国区价格已生效（历史上出现过「中国区价格未生成 → 沙盒回落 USD 基准价」）。

### 2.4 法务与备案

- 隐私政策 / 使用条款有**三份副本必须同步**：GitHub Pages（`Zhangwangning/allude-legal`，App Store 表单填这个）、Gitee 镜像（`zhang_wangning/allude-legal`）、App 内打包的 `Allude/Allude/Legal/{privacy,terms}.html`。
- 地址集中写在 `Allude/Models/LegalLinks.swift`。这些 URL 已填进 ASC 审核表单，**不要改**；确需更换必须让旧地址 301 过去。
- App 备案：见 §11.3。

---

## 3. 代码结构

### 3.1 三层同名，别数错目录

```
Allude/                        ← 仓库根（.git 在这里）
├── Allude/                    ← 工程根
│   ├── Allude.xcodeproj
│   ├── Allude/                ← App 源码（同步组，新增文件不用改 pbxproj）
│   │   ├── AlludeApp.swift    ← 入口 + 脚手架（1,391 行）
│   │   ├── Views/             ← 42 文件 / 21,936 行
│   │   ├── Models/            ← 32 文件 / 7,044 行
│   │   └── Legal/*.html       ← 隐私政策与条款（WKWebView 离线读）
│   ├── AlludeShared/          ← App 与小组件共用（🔴 显式 PBXGroup，新增文件必须手动进 pbxproj 三处）
│   ├── AlludeWidget/          ← 小组件扩展（🔴 同样是显式 PBXGroup）
│   ├── Config/*.entitlements
│   ├── Info.plist             ← GENERATE_INFOPLIST_FILE=NO，改键必须改这个真实文件
│   └── tools/                 ← 工程级自检（activity-race / parse-check）
├── tools/                     ← 仓库级脚本（发版、回归、素材）
├── .workbuddy/memory/         ← 逐日踩坑日志（**改模块前必翻**）
├── AGENTS.md                  ← 项目硬规则，先读完再动手
└── 交接说明_*.md
```

### 3.2 需要认识的文件（按重要度）

| 文件 | 行数 | 职责 |
|---|---|---|
| `AlludeApp.swift` | 1,391 | 入口、环境注入、**全部 `SCREEN=` 截图脚手架**、快捷指令回传路由 |
| `Views/PickupListView.swift` | 1,886 | 待取页：搜索、四种分组、多选、撤销、驿站内排序、性能缓存 |
| `Views/HistoryView.swift` | 1,503 | 已取页 + 统计页（`StatsCache`、图表自绘 Path） |
| `Views/ProfileView.swift` | 1,464 | 设置页根（`LazyVStack`，几十行设置项） |
| `Views/RootView.swift` | 1,239 | 四 Tab 容器、分栏判定 `PadLayout`、降级卡片回收 |
| `Views/DesignSystem.swift` | 1,137 | 快递公司/驿站管理网格、通用卡片与网格组件 |
| `Views/PickupShareCard.swift` | 1,037 | 分享卡渲染（图片导出） |
| `Views/ScanPickupSheet.swift` | 892 | 拍照/相册识别 → OCR → 解析 |
| `Views/ActivityPreviewGallery.swift` | 872 | 灵动岛/锁屏实时活动预览与验收 |
| `Views/RecordDetailView.swift` | 847 | 记录详情（Pro 门禁在搜索场景生效） |
| `Views/StationGroupEditView.swift` | 737 | 驿站组编辑（图标三格 + 位置 + 成员） |
| `Models/Models.swift` | 1,081 | `PickupRecord` / `PickupStore`（唯一状态源）、`PerfProbe`、`FrameMonitor` |
| `Models/PickupParser.swift` | 971 | 解析引擎（四正则 + 优先级链 + 三层误判闸门），**只依赖 Foundation，可独立编译回归** |
| `Models/SmsLibrary.swift` | 589 | 内置语料与品牌词表 |
| `Models/PickupNotifier.swift` | 441 | 本地通知、重复提醒 |
| `Models/PurchaseStore.swift` | 271 | StoreKit 2、权益快照写盘 |
| `AlludeShared/PickupStorage.swift` | 1,112 | 本机持久化、App Group 回落、`PickupLimits`、`PickupSortLogic` |
| `AlludeShared/PickupActivityAttributes.swift` | 924 | 灵动岛/锁屏实时活动数据与尺寸 |
| `AlludeShared/CourierBrand.swift` | 765 | 品牌词表 + 图标取色 |
| `AlludeShared/WidgetVisuals.swift` | 727 | 小组件视觉与裁剪逻辑 |
| `AlludeShared/PickupModels.swift` | 718 | 跨进程共享模型（`WidgetSnapshot` 等） |
| `AlludeShared/StationGroups.swift` | 608 | **驿站组 / 驿站 ID / 驿站内排序 / 取件码自然排序** |

### 3.3 改功能的入口索引

| 想改什么 | 去哪 |
|---|---|
| 解析规则 / 误判 | `Models/PickupParser.swift` + `tools/parser-regression/`（回归必须先跑） |
| 卡片长什么样 | `Views/PickupListView.swift`（待取）与 `Views/HistoryView.swift`（已取）**必须同构，改一处同步另一处** |
| 字号 / 颜色 / 圆角 | `AlludeShared/AppTheme.swift`（`TypeScale` 是唯一字号来源） |
| 小组件 / 灵动岛 | `AlludeWidget/` + `AlludeShared/PickupActivityAttributes.swift`（尺寸只在 `IslandExpandedMetrics`） |
| 驿站 / 组 / 排序 | `AlludeShared/StationGroups.swift` + `Views/DesignSystem.swift` + `Views/StationGroupEditView.swift` |
| 内购与权益 | `Models/PurchaseStore.swift` + `AlludeShared/OfflineLicense.swift` |
| iCloud 同步 | `Models/PickupSyncCore.swift`（纯合并规则）+ `PickupSyncStore.swift`（文件与通知） |
| 通知 | `Models/PickupNotifier.swift` / `PickupNotificationPresenter.swift` / `StationLocationService.swift`（围栏） |

---

## 4. 数据与存储

| 数据 | 位置 | 说明 |
|---|---|---|
| 取件记录 | App Group `Library/Application Support/pickup-records.json` | 无 App Group 时自动回落 App 自身 `Application Support`，不崩 |
| iCloud 副本 | `<iCloud 容器>/Documents/records.json`（容器 `iCloud.com.jikezhang.allude`） | 同步用；墓碑在 `pickup-sync-tombstones.json` |
| 驿站身份表 | 同目录 `station-identity.json` | 名字 ↔ 稳定 ID，**首次发号后落盘固化** |
| 驿站组 | 同目录 `station-groups.json` | 关系挂**成员 ID**，不挂名字 |
| 驿站位置 | `UserDefaults`（App Group 域）`station.locations.v1` | key 用**驿站名 / 组名** |
| 权益快照 | `entitlement.json` | 小组件只读它，必须带 `expiresAt` |
| BYOK 密钥 | **Keychain**（service `com.jikezhang.allude.ai`） | 绝不进 JSON、不进日志 |
| 偏好 | App Group 域 | `allude.appIcon`、`allude.list.sort`、`allude.station.innerOrder` 等 |

写入一律 `.atomic`。⚠️ 模拟器用 `CODE_SIGNING_ALLOWED=NO` 构建时**没有 App Group**，扩展读不到共享域 —— 跨进程问题只能真机验。

---

## 5. 解析子系统（最容易被改坏的地方）

### 5.1 结构

- 移植自 iOS 快捷指令「快递取件码」V7.3.0 的六套 ICU 正则，**优先级链**：`code → waybill → tail → special`。
- 一码一卡原则：链式段须与首段同形（`codeShape`），纯数字段 ≥4 位。
- 字段口径：`company` = 平台（【】里的品牌），`courier` = 承运方。两者不可混。
- 新正则**必须注册进 `regexes` 预编译表**，否则静默返回 nil（踩过）。

### 5.2 三层误判防线（都是真样本逼出来的）

1. `isPendingDeliveryOnly` —— 「已发货/派送中」没取件码，不算取件。
2. `isPromotionalOnly` —— **营销话术 + 零取件线索，两条同时成立**才算推广。🔴 不能只凭「拒收请回复R」判死，真实驿站短信也常带这句。
3. `isVersionLikeCode` —— `glm-5` / `gpt-4` / `claude-3` 是版本号不是取件码。
4. 关键词闸门 `京东(?!卡)` —— 「京东卡」是营销奖品，不是承运方。

### 5.3 回归与语料

```bash
cd tools/parser-regression && swiftc -O *.swift -o /tmp/pr && /tmp/pr
```

- 语料：`短信语料库_v1.md`（509 行正文，449 段）；基线 **175 命中 / 274 正确拒绝 / 60 条去重**。
- 最近一次回归（321 前）：**64/64 识别、63/64 地址无回退**，6 条边界用例（含 2 条带「拒收请回复R」的真实驿站短信）全部通过。
- 新增品牌 / 新形态短信：先用 `标注模板*.tsv` 标注，再跑回归，**不要凭单条样本改核心公式**。

### 5.4 AI 增强（可选，默认关）

- 端侧：`Models/PickupAI.swift`（FoundationModels，系统不可用即降级）。
- 三方 BYOK：`Models/AIExtensionEnhancer.swift` + `AIProviderStore.swift`，四家（DeepSeek / 豆包 / 千问 / Kimi），**App 直连、不经服务器、不记短信原文**。
- 字段护栏：地址/驿站/柜位可采用模型值；公司名必须能归一化到已知品牌；**取件码必须原样出现在原文里**才允许改（防幻觉）。

---

## 6. 界面口径（改动前必读）

- 卡片主名 `titlePrimary = courier ?? company`；副名 `secondaryLabel`（组名/驿站）。列表卡 / 详情 / 锁屏 / 分组名 / 图标取色同一口径。
- 取件码恒用 `iconBrand`；卡面 `brand = company.isEmpty ? iconBrand : brandColor`。
- 字号只用 `AppTheme.TypeScale`：`rowTitle 17 / rowSubtitle 13 / body 15 / section 13 / note 12 / badge 11`；强调**只加 weight 不加字号**。例外仅图形类：chevron 12–13、等宽码。
- 通知：字段空就整段不出现，绝不用占位句凑行。
- 灵动岛展开必须用满 `.leading/.trailing/.bottom`，尺寸只在 `IslandExpandedMetrics` 改，改完强制 update 一次（有「内容一致跳过」分支）。
- 版本历史页 `Entry.id` **不能用 `UUID()`**（视图重建换 ID，折叠状态会弹回）。
- 图标 16 套：imageset 全部放 `AlludeShared/Assets.xcassets`（放 App catalog → 灵动岛/锁屏渲染灰块）；`Contents.json` 必须 `template-rendering-intent: original` + 1x/2x/3x。
- 岛内图标随 `ContentState.appIconRaw` 传，扩展**别自己读** `AppIconStore.current`。

更细的口径与踩坑见 `AGENTS.md` 与 `.workbuddy/memory/MEMORY.md`。

---

## 7. 驿站组 / 驿站 ID / 排序（当前最复杂的子系统）

- `AlludeShared/StationGroups.swift`（App + Widget 双 target，新增文件必须手动进 pbxproj 三处）。
- ID 前缀：内置 `NZYZ`、自定义 `DZYYZ`、组 `FZYD`，各 5 位补零，**首次发号落盘固化**，之后只追加，不能按下标实时算。
- 组数据字段：`id / name / memberIDs / createdAt / iconInheritMemberID / locationInheritMemberID`；关系挂成员 ID，改名走 `StationIdentity.rename`。
- 监控优先级三段：**组驿站 > 未归组驿站 > 组内成员**（组只监一个围栏，避免同地点推三次）。
- 图标继承两路：内置成员走 `CourierLogo`、自定义成员走 `iconFiles`；只查 `iconFiles` 会把内置驿站按组名首字画。
- `StationGroupStore.all()` **必须缓存** —— `StationLogo` 每画一格都问「这是不是组」。
- 取件码自然排序 `PickupCodeOrder`（321 新增）：切字母段/数字段，数字段去前导零后**先比位数再比字典序**（等价数值比较且不溢出 Int）；数字段排字母段前；同形回落原文。自带三态 `Order`，不用 `ComparisonResult`（纯 Swift 单文件编译不可用）；判断数字必须 `ch.isASCII && ch.isNumber`（`Character.isNumber` 对全角/罗马数字也 true）。

---

## 8. 构建、调试、取证

### 8.1 模拟器构建（**必须带 `-disable-sandbox`**）

```bash
cd Allude
xcodebuild -project Allude.xcodeproj -scheme Allude \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/allude-verify build \
  CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS="-disable-sandbox"
```

- 缺 `-disable-sandbox` → 宏插件拉不起子进程，报**假错误**（`StateMacro could not be found`、`SwipeActionRow.swift` 的 `'self' is immutable`）。那是工具链问题，别改业务代码。
- 🔴 **在 agent 会话内构建必定卡 CoreML**（`sandbox-exec: sandbox_apply: Operation not permitted`）。绕过：`mv Allude/Resources/AlludePickup.mlmodel{,.bak}` → 构建 → 还原。不需要生成 Swift 包装（`PickupClassifier` 按 Bundle 找 `.mlmodelc`）。
- clean build 必须 0 warning。

### 8.2 截图取证（命令行点不了屏幕）

无 idb / applesimutils，AppleScript 驱动模拟器会被辅助功能权限拒绝（`-10004`）。**所有面板靠 `SCREEN` 环境变量直渲**：

```bash
UDID=$(xcrun simctl list devices | grep "iPhone 16 Pro" | ...)
xcrun simctl install $UDID /tmp/allude-verify/Build/Products/Debug-iphonesimulator/Allude.app
SIMCTL_CHILD_SCREEN=pending SIMCTL_CHILD_SKIP_PERM=1 \
  xcrun simctl launch --terminate-running-process $UDID com.jikezhang.allude
xcrun simctl io $UDID screenshot /tmp/shot.png
```

- 环境变量必须带 **`SIMCTL_CHILD_`**；`launch` 必须带 **`--terminate-running-process`**（否则只切前台，变量全不注入）。
- 装完**先核对 `CFBundleVersion`** 再截图，否则拍到上一版界面会误判「改动没生效」。
- 常用 `SCREEN`：`pending` / `pickedUp` / `stats` / `settings`（配 `SETTINGS_ANCHOR=about`）/ `gallery` / `stationGallery`（配 `STATION_ADD_DEMO=1`）/ `stationGroupEdit`（配 `GROUP_ID=`）/ `stationLocation` / `stationLocationPicker` / `detail` / `scan` / `share` / `notify` / `lockPreview` / `activityAudit`。
- 直写设置项的环境变量：`INNER_ORDER=codeAsc`、`CODE_OPACITY=`、`CODE_GROUP=1`、`SEED=<短信>`（配 `SCREEN=add`）、`SKIP_ONBOARDING=1`。
- ⚠️ **App Group 偏好不要用 `simctl spawn defaults write` 改**（写的是模拟器全局域，且 cfprefsd 会把旧值刷回容器 plist），用上面的环境变量接口。
- 模拟器 ID 会变，用 `xcrun simctl list devices` 现查。验 `if #available(iOS 27)` 必须用 iPhone 17 机型。

### 8.3 性能工具（DEBUG 专用）

- `PERF_LOG=1` → `PerfProbe` 统计各段耗时，写 `Documents/perf.log`（按总耗时降序）。
- `PERF_FPS=1` → `FrameMonitor` 记帧间隔分布 / 掉帧率 / 慢帧明细，写 `Documents/frames.log`。
- `xctrace record --template 'Time Profiler' --attach <pid> --time-limit 18s`，导出 `--xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'`；XML 里 frame 是 id 定义 + ref 引用，必须建表再解析。
- `Animation Hitches` 模板**模拟器不支持**，只能真机。
- 已做过的优化（321 前）：列表重计算记忆化（`displayed` 14 秒内 68 次访问只真算 1 次）、`revision` 版本号失效、设置页/统计页 `LazyVStack`、景深 blur 5→3、一键取件 O(n²)→O(n)、`windowSize` 100ms 缓存。范式：**计算属性缓存放 model（`@StateObject` 持有的 class），不放 View 的 `@State`**；缓存键用 `hashValue` 不用 `count`。

### 8.4 真机（唯一能验灵动岛的路）

```bash
DEST='platform=iOS,id=00008140-001138A92E01801C'    # iPhone 16 Pro
xcodebuild -project Allude.xcodeproj -scheme Allude -destination "$DEST" \
  -derivedDataPath /tmp/allude-device -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration OTHER_SWIFT_FLAGS="-disable-sandbox" build
```

`bash tools/install-device.sh` 已封装构建 + `devicectl` 装机。真机读写共享容器：

```bash
xcrun devicectl device copy from --device <UDID> \
  --domain-type appGroupDataContainer --domain-identifier group.com.jikezhang.allude \
  --source "Library/Application Support/pickup-records.json" --destination /tmp/
```

---

## 9. 发版链路（321 实操，命令可照抄）

**前置结论：`xcodebuild -exportArchive` 在本机不可用**（无 GUI 时 `ITunesSoftwareService` 起不来）。只能手搓 ipa。

```bash
# 1) 改版本号：pbxproj 四处 CURRENT_PROJECT_VERSION（必须"先读进变量再写回"，内联 sed 会截断成 0 字节）
# 2) 归档（临时移出 mlmodel 绕开 CoreML 沙箱）
cd Allude
mv Allude/Resources/AlludePickup.mlmodel Allude/Resources/AlludePickup.mlmodel.bak
xcodebuild -project Allude.xcodeproj -scheme Allude -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/allude-archive321/Allude.xcarchive \
  -allowProvisioningUpdates OTHER_SWIFT_FLAGS="-disable-sandbox" archive
mv Allude/Resources/AlludePickup.mlmodel.bak Allude/Resources/AlludePickup.mlmodel

# 3) 包内删 .bak、补模型
APP=/tmp/allude-archive321/Allude.xcarchive/Products/Applications/Allude.app
rm -f "$APP/AlludePickup.mlmodel.bak"
xcrun coremlc compile Allude/Resources/AlludePickup.mlmodel /tmp/mlc321
cp -R /tmp/mlc321/AlludePickup.mlmodelc "$APP/"

# 4) 换描述文件 + 用「清洗过的」entitlements 重签（先 appex 后 App）
cp /tmp/AlludeApp.mobileprovision    "$APP/embedded.mobileprovision"
cp /tmp/AlludeWidget.mobileprovision "$APP/PlugIns/AlludeWidget.appex/embedded.mobileprovision"
codesign --force --sign "iPhone Distribution: Wangnjng Zhang (8499X3S9X8)" \
  --entitlements /tmp/dist-widget.entitlements "$APP/PlugIns/AlludeWidget.appex"
codesign --force --sign "iPhone Distribution: Wangnjng Zhang (8499X3S9X8)" \
  --entitlements /tmp/dist-app.entitlements "$APP"

# 5) 打包（必须传 Payload 目录，不能加 --sequesterRsrc）
rm -rf /tmp/ipa321 && mkdir -p /tmp/ipa321/Payload
cp -R "$APP" /tmp/ipa321/Payload/
cd /tmp/ipa321 && ditto -c -k --norsrc --keepParent Payload /tmp/Allude-321.ipa

# 6) 校验 + 上传
xcrun altool --validate-app -f /tmp/Allude-321.ipa -t ios \
  --apiKey 34Z43R5SGY --apiIssuer e2936bfc-e52b-4931-a763-9f03dec868e3
xcrun altool --upload-app  -f /tmp/Allude-321.ipa -t ios \
  --apiKey 34Z43R5SGY --apiIssuer e2936bfc-e52b-4931-a763-9f03dec868e3

# 7) 2–3 分钟转 VALID 后，挂群组 + 写测试内容 + 提 Beta 审核
cd /Volumes/ZWN/Downloads/Project/Allude
python3 tools/testflight-publish.py --build 321 --notes-file tools/testflight-notes/1.0.0-321.md
```

### 9.1 凭证与标识（都在本机，不入库）

| 项 | 值 / 位置 |
|---|---|
| Apple 团队 | `8499X3S9X8`（付费账号，automatic signing） |
| 分发证书 | `P76B23FF7S`，到期 **2027-11-15** |
| Provisioning Profile | App `7H29P7MJ8Q`（Name: Allude App Store 313）、Widget `4F62FDJ8K2`（M53D3TXT6B），均到期 **2027-11-15T14:55Z** |
| ASC API Key | `34Z43R5SGY`，私钥 `~/.appstoreconnect/private_keys/AuthKey_34Z43R5SGY.p8` |
| ASC Issuer | `e2936bfc-e52b-4931-a763-9f03dec868e3` |
| ASC App ID | `6833046947` |
| TestFlight 群组 | 「Allude公测」`c90099fc-1862-4b2a-8f48-a7537111fe45` |

🔴 **entitlements 不能照抄 profile**：`icloud-services = *`、`icloud-container-environment`、`ubiquity-kvstore-identifier = 团队.*` 都会被拒（90045/90046/90211）。`/tmp/dist-app.entitlements` 与 `/tmp/dist-widget.entitlements` 是清洗过的版本，**重启机器后它们是临时文件，会被清掉** —— 内容见 §9.2，请尽快拷进仓库 `tools/signing/` 并加 `.gitignore` 例外（entitlements 本身不含私钥，可以入库）。

### 9.2 清洗后的 entitlements（重建用）

App：
```xml
application-identifier = 8499X3S9X8.com.jikezhang.allude
aps-environment = production
beta-reports-active = true
get-task-allow = false
com.apple.developer.team-identifier = 8499X3S9X8
com.apple.developer.icloud-services = [CloudDocuments]
com.apple.developer.icloud-container-identifiers = [iCloud.com.jikezhang.allude]
com.apple.developer.ubiquity-container-identifiers = [iCloud.com.jikezhang.allude]
com.apple.security.application-groups = [group.com.jikezhang.allude]
keychain-access-groups = [8499X3S9X8.com.jikezhang.allude]
```
Widget：同上，去掉 iCloud / aps，`application-identifier` 与 `keychain-access-groups` 换成 `…allude.AlludeWidget`。

---

## 10. 工具脚本

| 脚本 | 用途 |
|---|---|
| `tools/testflight-publish.py` | 挂 TestFlight 群组 + 写测试内容 + 提 Beta 审核（ASC API，纯标准库） |
| `tools/parser-regression/` | 解析回归（`cases.txt` / `expected.txt`，可独立 `swiftc` 编译） |
| `tools/station-check/` | 驿站匹配回归（含对抗用例） |
| `tools/multi-parse-check/`、`dedupe-check/`、`notify-check/`、`ocr-pipeline-check/`、`brand-check/` | 各子系统自检（都能独立编译跑） |
| `tools/unslop-audit.sh`、`unslop-ui-check.sh` | 「AI 味代码 / UI」质量门禁 |
| `tools/verify-ios17.sh` | iOS 17 兼容回归 |
| `tools/widget-shots.sh` | 小组件真实渲染截图验收 |
| `tools/install-device.sh` / `dev-entitlement.sh` | 真机装机 / 真机权益切换（free↔lifetime） |
| `tools/profile-expiry.sh` | 描述文件到期检查 |
| `tools/import_app_icon.py`、`make_app_icon.py`、`extract_brand_palette.py`、`import_brand_logos.py` | 素材生成与入库 |
| `tools/license-gen/` | 旧离线凭证签发（**仅为读老快照保留**，界面上已无入口，别再加回来） |

---

## 11. 已知问题与债务

### 11.1 上架阻塞（P0）

1. **1.0.0 REJECTED**，理由待查（§2.1）。修完重新绑构建提交。
2. **内购未提交**（§2.3），首次必须随版本走。
3. **App 备案未完成**（§11.3），中国大陆区上架需备案号。

### 11.2 技术与验证债

| # | 问题 | 影响 | 建议 |
|---|---|---|---|
| 1 | 无 XCTest 单测，全靠 `tools/*-check` 可执行自检 | 重构风险靠人肉守 | 先把 parser / station / sort 三组自检接进 CI 或 pre-commit |
| 2 | 真机项未系统验证：灵动岛折叠/展开、锁屏实时活动、小组件组名、到达提醒围栏触发 | 模拟器测不出（无 App Group、无真实灵动岛） | 拿 iPhone 16 Pro 真机跑一遍 §8.4 清单 |
| 3 | iCloud 多设备一致性未充分压测 | 冲突合并可能丢状态 | 用两台真机做删除/勾选交叉测试，`PickupSyncCore` 是纯函数，可先补用例 |
| 4 | iPhone Duo 折叠屏只验了部分场景 | 分栏/竖屏标题曾出问题 | 用 iPhone Duo 模拟器三态（折叠/展开竖/展开横）各截一遍 |
| 5 | 解析误判依赖语料分布 | 新品牌/新话术可能误收 | 新样本先标注进 `标注模板*.tsv`，跑回归再改代码 |
| 6 | `BetaBuildLog.swift` / `VersionHistoryView.swift` 里的构建记录是**手写**的 | 发版容易忘加条目 | 发版 checklist 里固定一步 |
| 7 | 法务文本三副本 | 只改一处会造成商店页与 App 内不一致 | 改之前先 grep `LegalLinks.swift` |
| 8 | 性能只在模拟器量化过 | 真机可能不同 | 用 `PERF_LOG=1` / `PERF_FPS=1` 在真机取一轮基线 |
| 9 | `tools/station-check` 跑不起来（实测） | 驿站匹配回归缺一块 | 直接 `swiftc *.swift` 报 `cannot find 'CourierBrand' in scope`；把 `AlludeShared/CourierBrand.swift` 一起编译又报 `cannot find 'BrandPalette' / 'UIImage' / 'BrandDebug'`（该文件混了 UIKit 绘制层）。建议把驿站名匹配（`stationMatch`）拆成只依赖 Foundation 的 `StationMatch.swift`，`CourierBrand` 转发调用 |
| 10 | 模拟器构建必须手动移出 `.mlmodel` | 自动化流水线会被卡 | 给 CI 加一步预处理，或改用 `coremlc` 预编译后走 `-skipPackagePluginValidation` 之外的方案 |

### 11.3 App 备案（中国大陆）

- 网站 ICP：**陇ICP备2026011130号**（2026-11-06 通过，甘肃）。
- App 备案是**另一套编号**，在 `beian.miit.gov.cn` 提交（主体信息 + App 信息 → 省通信管理局审核）。详见 `App备案准备清单_v1.md`。
- 单机不联网 App 在 App 内不显示 ICP 号；但 **App Store 中国区表单需要填备案号**。

---

## 12. 交接清单

### 12.1 账号与仓库

- GitHub：`Zhangwangning/Allude`（私有，HTTPS + `gh auth login`，**不用 SSH**）。
- Gitee 镜像：`zhang_wangning/*`（历史遗留，Gitee 侧常落后；`~/.workbuddy/bin/gitee-github-sync.sh` 为手动同步脚本）。
- App Store Connect：App ID `6833046947`，Team `8499X3S9X8`（zhang_wangning@126.com）。
- 法务仓库：`Zhangwangning/allude-legal`（GitHub Pages）。

### 12.2 本机环境

- **Xcode 27.2（27B52）+ iOS SDK 27.2**，部署目标仍为 iOS 17.0；`xcrun simctl` / `devicectl` / `altool` / `coremlc` 均可用。
- 模拟器参考：iPhone 16 Pro（iOS 26.1）作日常回归；iPhone 17（iOS 27.2）验 `#available(iOS 27)`；iPhone Duo（27.2）验折叠。
- 真机调试机：iPhone 16 Pro `00008140-001138A92E01801C`（已在团队内注册）。

### 12.3 密钥纪律

- `AuthKey_*.p8`、`license-gen/private-key.pem`、分发证书私钥：**绝不入库**（`.gitignore` 已覆盖 `.p8`）。
- BYOK 的用户密钥只存 Keychain，不进 JSON / 日志 / 诊断包。

### 12.4 接手路线（建议）

**第 1 天**
1. 读完 `AGENTS.md` → 本文 → `.workbuddy/memory/MEMORY.md`（三份，顺序别反）。
2. 跑通模拟器构建（记得移出 `.mlmodel`）+ 装到 iPhone 16 Pro 模拟器 + `SCREEN=pending` 截一张图。
3. 跑 `tools/parser-regression`、`tools/station-check`、`tools/dedupe-check`，确认基线仍有 175/274。
4. **登录 ASC 看 Resolution Center**，把拒信原文与条款记下来（这是唯一 P0）。

**第 1 周**
5. 按拒信修，重新绑 321+ 构建提交审核；内购一并提交。
6. 真机跑一遍 §11.2 第 2 项清单，把结果补进本文。
7. 处理 §11.3 备案，同步 §11.2 第 6/7 项的发版 checklist。

**之后**
8. 补测试（先把三组自检脚本接到 pre-commit）。
9. 性能基线真机化，再谈优化。

---

## 13. 文档索引

| 文件 | 内容 |
|---|---|
| `AGENTS.md` | **项目硬规则**：构建参数、不可改的标识、权益枚举、图标流程、界面口径。第一优先 |
| `.workbuddy/memory/MEMORY.md` | 长期笔记（路径 / 构建 / 发版 / 踩坑浓缩版） |
| `.workbuddy/memory/2026-11-*.md` | 逐日踩坑日志，**改哪个模块先翻对应日期** |
| `交接说明_workbuddy.md` | 上一版交接（312），部分过时，仅作历史参考 |
| `产品与商业模式规格_v1.md` | 定位、定价、免费/Pro 边界的产品侧说明 |
| `快递短信解析规格_V803.md` | 六套正则与优先级链的完整规格 |
| `短信语料库_v1.md` | 449 段语料 + 覆盖基线 |
| `iPhone Duo 适配规范_v1.md` / `iPhone Duo 官方设计规范笔记_v1.md` | 折叠屏适配约定与官方依据 |
| `App备案准备清单_v1.md` | 备案流程与材料 |
| `竞品拆解与重构方案_v1.md` | 竞品分析与取舍依据 |
| `tools/testflight-notes/1.0.0-*.md` | 每版测试内容（写新版的模板） |
| `tools/appstore-review/1.0.0-notes.md` | 给 Apple 的审核说明稿 |

---

## 14. 一句话总结

代码与发版链路都是通的（321 已在 TestFlight 正常分发），**卡住上架的只有三件外部事情**：App Review 的拒信要读、内购要提交、备案号要拿到。技术债集中在「没有单测、真机验证不系统、驿站与解析两个子系统逻辑密度高」。接手时先按 §12.4 走，不要一上来改代码。
