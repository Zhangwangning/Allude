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
- 缺 `-disable-sandbox` → 宏插件起不来，报假错（`SwipeActionRow` 的 `'self' is immutable`）。
- 🔴 **agent 会话内构建必然停在 CoreML 阶段**：`sandbox-exec: sandbox_apply: Operation not permitted`
  （Xcode 硬编码用 sandbox-exec 包 coremlc；本环境只允许最简 profile）。
  `ENABLE_USER_SCRIPT_SANDBOXING=NO` 与关沙箱都无效 → 构建验证只能请主人在宿主终端跑。
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

## 现状（2026-11-15）
- 1.0.0 已提交审核（WAITING_FOR_REVIEW），**绑构建 309**；312 已上传未挂。
- 两个内购仍 `READY_TO_SUBMIT`，**未随版本提交** → 必须先补内购审核，否则上线买不了。
- git `main` 领先 `origin/main` 7 个提交（305–312 未推）。
- Gitee Pages 法务镜像 404；GitHub Pages 正常。
