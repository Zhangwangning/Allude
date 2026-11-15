# Allude 项目长期笔记（2026-11-15 重写，取代 CodePouch 版）

## 路径与标识
- 仓库根 `/Volumes/ZWN/Downloads/Project/Allude/`（GitHub `Zhangwangning/Allude` 私有）。
  工程根、App 源码、target 三层同名 `Allude/Allude/Allude/`。
- 🔴 不可改：App Bundle `com.jikezhang.allude`、Widget `…AlludeWidget`、App Group
  `group.com.jikezhang.allude`、Widget kind `AlludePickupWidget`、iCloud `iCloud.com.jikezhang.allude`。
- 纯 iPhone（`TARGETED_DEVICE_FAMILY=1`），部署目标 **iOS 17.0**，`GENERATE_INFOPLIST_FILE=NO`
  → 增删 Info.plist 键改真实文件，`INFOPLIST_KEY_*` 不生效。
- 版本号 4 处 `CURRENT_PROJECT_VERSION`（App/Widget × Debug/Release）。现 `1.0.0 (312)`。

## 构建
```
cd Allude && xcodebuild -project Allude.xcodeproj -scheme Allude \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/allude-verify build \
  CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS="-disable-sandbox"
```
- 缺 `-disable-sandbox` → 宏插件起不来，报假错（`SwipeActionRow` 的 `'self' is immutable`、
  `StateMacro could not be found`、一堆 `cannot find '$xxx' in scope`）。
- 🔴 **agent 会话内构建必然停在 CoreML 阶段**：`sandbox-exec: sandbox_apply: Operation not permitted`
  （Xcode 硬编码用 sandbox-exec 包 coremlc；本环境只允许最简 profile）。
  `ENABLE_USER_SCRIPT_SANDBOXING=NO` 与关沙箱都无效。
  **绕过**：临时 `mv AlludePickup.mlmodel{,.bak}` → 构建 → 立刻还原。
  ⚠️ **不需要**生成 CoreML 的 Swift 包装（`PickupClassifier` 只按 Bundle url 找 `.mlmodelc`，
  不引用生成的类），上一轮以为必须，实测多余。

### 真机（2026-11-15 跑通，唯一能验灵动岛的路）
``` 
DEST='platform=iOS,id=00008140-001138A92E01801C'   # iPhone 16 Pro，真机名「Huawei Mate XT非凡大师1TB」
xcodebuild -project Allude.xcodeproj -scheme Allude -destination "$DEST" \
  -derivedDataPath /tmp/allude-device -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration OTHER_SWIFT_FLAGS="-disable-sandbox" build
```
- 团队 `8499X3S9X8` automatic signing；证书 `Apple Development: zhang_wangning@126.com (K2FQFHU46Z)`。
- 真机包签名完整（`application-groups` + iCloud + aps + `get-task-allow`）；模拟器
  `CODE_SIGNING_ALLOWED=NO` 的包**没有 App Group**，扩展读不到共享域 —— 两回事。
- **补 `.mlmodelc`**：`xcrun coremlc compile x.mlmodel /tmp/mlc` 手工跑得动（只有 Xcode 的
  build rule 才包 sandbox-exec）→ `cp -R` 进 `Allude.app/` → **必须重签**。
  重签要用**导出的** entitlements（`codesign -d --entitlements :-`），裸 `Config/*.entitlements`
  缺 `application-identifier`/`team-identifier`/`get-task-allow`，装了起不来。先签 appex 再签 App。
- 装 / 启动 / 退出：
  `devicectl device install app`；`process launch --terminate-existing -e '{"SCREEN":"…"}'`；
  `process terminate --pid <pid>`（**只吃 pid**，不吃 bundle id）。
- 真机读写文件：`devicectl device info files|copy from|copy to`，
  `--domain-type appGroupDataContainer --domain-identifier group.com.jikezhang.allude`。
  偏好 `Library/Preferences/group.com.jikezhang.allude.plist`、记录 `…/Application Support/pickup-records.json`。
- 真机 App 一启动会从 iCloud 同步真实数据，`SCREEN=ingest` 的种子可能被覆盖。
- pbxproj 改版本号必须「先读进变量再写回」，内联读写会截断成 0 字节。
- `AlludeShared/`、`AlludeWidget/` 是显式 PBXGroup：新增 Swift 必须手动进 pbxproj 三处。

## 界面口径（仍有效）
- 卡片主名：`titlePrimary = courier ?? company`，`titleSecondary = 驿站 ?? company`（排除同名）。
  驿站**不进主名位**。列表卡/详情首页卡/锁屏卡/分组名/图标取色同口径。
- 取件码恒用 `iconBrand`；卡面用 `brand = company.isEmpty ? iconBrand : brandColor`。
- 图标 26pt 与取件码用 `.center` 对齐（`.lastTextBaseline` 会沉 4pt）；多选圈高度必须 44。
  待取 `PickupListView` 与已取 `HistoryView` 卡同构，改一处必须同步。
- 字号只用 `AppTheme.TypeScale`：rowTitle 17 / rowSubtitle 13 / body 15 / section 13 / note 12 / badge 11。
  强调只加 weight。例外仅：chevron 12–13、等宽码。
- 通知文案：字段空就整段不出现，绝不用占位句凑行；标题恒「取件码 X」，正文一行「平台 | 地址」。
- 灵动岛展开必须用满 `.leading` / `.trailing` / `.bottom` 三区，尺寸只在 `IslandExpandedMetrics` 改。
  改完必须强制 update 一次（有「内容一致就跳过」分支，靠 `needsForcedRender`）。
- 给灵动岛的图片资源 `Contents.json` 必须写 `template-rendering-intent: original` + 1x/2x/3x 三档，
  否则折叠态渲染成纯色方块。
- Section header 里 `listRowInsets` 完全不生效 → 分组标题当普通行塞进 Section 首行。

## 解析与数据
- `PickupParser` 四套正则 + 优先级链 code → waybill → tail → special；新增正则必须注册进
  `regexes` 预编译表（否则静默 nil）。一码一卡：链式段须与首段同形（`codeShape`），纯数字段≥4 位。
- 权益快照新增字段一律 `decodeIfPresent`；`MembershipPlan` 只增不删（删 case = 老用户掉回免费版）。
  订阅必须写 `expiresAt`，否则小组件永远按完整版渲染。
- `enforceStorageLimit()` 只在 `ingest()` 触发（免费 50 条 FIFO），启动不删。
- iCloud 写 `<容器>/Documents/records.json`，`NSUbiquitousContainerIsDocumentScopePublic=false`。
- BYOK Key 只在 Keychain（service `com.jikezhang.allude.ai`），接口地址内置不可改，测通才启用。

## 模拟器取证
- 无 idb / applesimutils，AppleScript 被辅助功能拒绝（-10004）→ 一切面板靠 `SIMCTL_CHILD_SCREEN=xxx` 直渲。
- `launch` 必须 `--terminate-running-process`，否则只切前台、变量不注入。
- 装完先核对 `CFBundleVersion` 再截图（install/terminate 异步，旧进程会被静默沿用）。
- 基准机 iPhone 16 Pro `272DD31C-D94F-46B4-9CC7-974A61439777`。

## 图标（21 套，2026-11-15 从 13 套扩到 21 套）
- 🔴 全部 `AppIconNN.imageset` **只放 `AlludeShared/Assets.xcassets`**（2026-11-15 迁入）：
  App 与小组件两个 target 都编这份 catalog，扩展才取得到图；放 App 的 catalog 里 →
  灵动岛/锁屏 `Image("AppIconNN")` 静默渲染成**灰块**（312 的实际故障）。
- 新增一套要动四处：imageset（60/120/180 + `template-rendering-intent: original`）、
  `Allude/AppIcons/IconNN@2x.png`(120) / `@3x.png`(180)、`Info.plist` 的
  **`CFBundleIcons › CFBundleAlternateIcons`**（⚠️ 不在顶层！顶层查不到）、
  `AppIconChoice` 的 case/number/title。`App/` 是同步组 → 不改 pbxproj。
- ⚠️ `sips -z` **只改尺寸不改格式**：源是 JPEG 时必须加 `-s format png`，
  否则 `.png` 里装的是 JPEG 数据（actool 会不认）。
- 第 13 套「快递箱」按主人要求图形内缩 1/5（内容占 60%，白底合成去 alpha）；
  第 14–21 套是 1536 满幅方图，**明确要求不裁切**，等比缩放即可。
- 源图统一归档 `tools/appicon-source/iconNN-source.{png,jpg,svg}`。
- 🔴 **岛内图标随 `ContentState.appIconRaw` 传**（2026-11-15 修，commit 1286c28）：
  扩展进程别自己读 `AppIconStore.current` —— App Group 那条链一断就回落到
  `AppIconChoice.fallback`（第 7 套 C 标），表现为「桌面换了、岛里还是旧图标」。
  `AppMarkIcon(choice:)` 由调用方传 `state.appIcon`；换图标成功后走
  `PickupActivityController.refreshForAppIconChange()` 即时刷新活动。
- ⚠️ `AlludeWidget/Assets.xcassets` 只许留 `AccentColor` + `WidgetBackground`。
  曾经有 AppIcon01–08 的副本，与 Shared catalog 同名同 target 编两遍（归属不确定）。
- ⚠️ 模拟器截不到真实灵动岛（前台/后台/主屏都无胶囊），只能真机验。

## 现状（2026-11-15）
- 1.0.0 已提交审核（WAITING_FOR_REVIEW），**绑构建 309**；312 已上传未挂。
- 两个内购仍 `READY_TO_SUBMIT`，**未随版本提交** → 必须先补内购审核，否则上线买不了。
- git `main` 领先 `origin/main` 7 个提交（305–312 未推）。
- Gitee Pages 法务镜像 404；GitHub Pages 正常。
