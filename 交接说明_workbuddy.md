# Allude 项目交接说明（面向 workbuddy）

> 写于 2026-11-15，版本 **1.0.0 (312)**。
> 目标读者：接手继续开发 / 上架的 agent（workbuddy）。
> 所有结论都来自本机实测与 App Store Connect 实际返回值，不是推测。

---

## 0. 30 秒速览

| 项 | 现状 |
|---|---|
| 产品 | **Allude**：iOS 取件码收纳 App。核心承诺「数据只在本机，不联网、不上传、不需要注册」 |
| 形态 | **纯 iPhone**（`TARGETED_DEVICE_FAMILY = 1`），部署目标 **iOS 17.0**，SwiftUI，零第三方依赖、零 SPM |
| 版本 | `MARKETING_VERSION = 1.0.0`，`CURRENT_PROJECT_VERSION = 312`（四处同步） |
| TestFlight | 构建 **312** 已挂外部群组「Allude公测」(`c90099fc-1862-4b2a-8f48-a7537111fe45`)，测试内容已写 |
| App Store | 1.0.0 处于 `PREPARE_FOR_SUBMISSION`；6 张截图已上传、内购已 `READY_TO_SUBMIT`；**差 3 件人工事**（见 §6） |
| 代码量 | 88 个 Swift 文件，约 30.4k 行（`Allude/` + `AlludeShared/` + `AlludeWidget/`） |
| 仓库 | `https://github.com/Zhangwangning/Allude`（私有），分支 `main`，工作区干净 |
| 商业模式 | 免费下载 + 内购解锁：年订阅 **¥1**、终身买断 **¥9.9**（主推买断） |
| 付费档 | 免费：同屏 4 条、最多 50 条存储、小组件小/中；Pro：不限条数/50→无限、全尺寸小组件、实时活动 |

---

## 1. 这个项目是什么

快递短信进来 → 自动解析出**取件码 / 快递公司 / 驿站 / 地址 / 柜位** → 存到本机列表 → 桌面小组件、灵动岛、锁屏实时活动、统计页。

- **不联网**：唯一网络行为是 StoreKit（只连 Apple），以及**用户主动开启**的第三方大模型增强（BYOK，直连服务商）。
- **不注册、无服务器**：没有账号体系，没有开发者后端。
- **解析分层**：四套独立正则 + 优先级链（code → waybill → tail → special），可选「端侧 Apple 智能」或「第三方模型（DeepSeek / 豆包 / 千问 / Kimi）复核」。
- **法律口径**：单机不联网 App，App 内不显示备案号（网站备案号另有，见 §9）。

### 绝不能改的内部标识（改了就是数据事故）

| 项 | 值 | 改了会怎样 |
|---|---|---|
| App Bundle ID | `com.jikezhang.allude` | 数据容器换新，用户记录全丢 |
| Widget Bundle ID | `com.jikezhang.allude.AlludeWidget` | 系统判成新扩展，桌面小组件要全部重加 |
| App Group | `group.com.jikezhang.allude` | 主 App 与小组件数据通道断 |
| Widget `kind` | `AlludePickupWidget` | 已添加的小组件失配 |
| iCloud 容器 | `iCloud.com.jikezhang.allude` | 同步数据读不到（历史数据留在旧容器） |

对外名称改 `CFBundleDisplayName` 即可，不影响上面任何一项。

---

## 2. 目录与构建

```
Allude/                     ← 仓库根（.git 在这里）
├── Allude/                 ← 工程根
│   ├── Allude.xcodeproj
│   ├── Allude/             ← App 源码（Views / Models / Resources / Legal）
│   ├── AlludeShared/       ← App 与小组件共用（显式 PBXGroup！新增文件必须手动进 pbxproj）
│   ├── AlludeWidget/       ← 小组件扩展
│   ├── Config/             ← entitlements
│   └── tools/              ← 构建、安装、签发、自检脚本
├── tools/                  ← 仓库级脚本（发布、自检、质检）
├── *.md                    ← 规格文档（解析规格、Duo 规范、商业模式…）
├── .workbuddy/memory/      ← 逐日踩坑日志（按日期，改模块前值得翻）
└── 交接说明_workbuddy.md    ← 本文件
```

### 构建（必须带 `-disable-sandbox`）

```bash
cd Allude
xcodebuild -project Allude.xcodeproj -scheme Allude \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/allude-verify build \
  CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS="-disable-sandbox"
```

⚠️ 这个参数是**防沙箱，不是修代码**：宏插件要拉子进程，被沙箱包住时报
`could not be found` / `swift-plugin-server produced malformed response`，并连带抛一堆**假错误**（典型是 `SwipeActionRow.swift` 的 `'self' is immutable`）。别为了消错去改业务代码。

### 真机安装

```bash
bash tools/install-device.sh      # 自动探测 Team、构建、devicectl 装机
```
免费 Personal Team 签名，描述文件 **7 天**（从苹果签发那刻算，不是从装机算），到期重跑。

### 环境（本机）

- Xcode 27.2 在 `/Volumes/ZWN/Applications/Xcode.app`（`/Applications` 是软链，**别从 App Store 更新**）
- `DEVELOPER_DIR` 必须显式指过去；DerivedData 在外置盘
- 模拟器 GUI 是 **DeviceHub.app**（没有 Simulator.app）；`simctl` 没有点击能力

---

## 3. 已经做完的功能（按用户可见顺序）

### 3.1 取件与列表
- 短信解析：四套正则 + 优先级链；一条短信多个码会拆成多张卡（链式段必须与首段同形）
- 列表：待取 / 已取；**分组**：按时间（今天/昨天/更早）、按快递公司、按快递驿站（未标注驿站置底）
- **排序/分组会记住**（`allude.list.sort`，写进 App Group，重开 App 保持）
- **桌面小组件跟随同一套排序**（`PickupSortLogic`，主 App 与小组件共用）
- 搜索、多选（含**全选 / 取消全选**，作用于当前可见集合）、滑动操作、批量标记已取/删除
- 取件后 4 秒内可撤销删除；「清空已取」要过**随机四位数字**确认

### 3.2 详情与会话
- 卡片详情：取件码、快递公司、短信平台、地址、柜位、尾号、原始短信（可复制）
- 解析结果可手动编辑；驿站可「记住这个地址 → 驿站」

### 3.3 小组件 / 灵动岛 / 锁屏
- 桌面小组件：小、中、大、超大（Pro 才有大尺寸）；分页、占位行开关（`显示占位符`）、`显示驿站/公司/地址/柜位` 四个开关
- **灵动岛 / 锁屏实时活动**（仅 Pro）：显示最新待取码；iPhone Duo 外屏只显示数字、居中、>99 显示 `99+`
- 小组件设置页有实时预览（改开关立刻反映）

### 3.4 设置（列表顺序即用户看到的结构）
Pro 横幅 → 快捷指令 → 通知 → 桌面小组件 → 实时活动 → iCloud 同步 → Apple 智能与扩展 → 外观与个性化 → 存储空间 → 帮助与反馈 → 快递公司 / 驿站管理 / 关于 Allude

- **快捷指令**：`收到短信 → 自动收码`。iOS 27+ 支持一键导入（iCloud 链接 / 文件）；**iOS 26 及更早不支持导入带触发器的自动化，只能手动建**（页面已按系统分支给出 3 步 / 4 步图文）。页内有 **35 秒视频教程**（4.3MB HEVC，打进包、离线播、自绘播放层）
- **Apple 智能与扩展**：两条独立通道。端侧 Apple 智能（iOS 26+）+ BYOK 第三方模型（DeepSeek / 豆包 / 千问 / Kimi）。**必须先「测试连接」成功才能启用**；Key 只存本机 Keychain；接口地址内置不可改；有「用量统计」（次数 / token / 估算人民币）
- **外观与个性化**：自定义 App 图标（12 套，默认第 7 套「C 标」）、外观（自动/浅色/深色）、字体大小（7 档全局倍率）、语言、液态玻璃开关（iOS 26+）、显示「统计」
- **存储空间**：已存记录 / 待取 / 已取 / 数据文件大小 + **一键清除数据**
- **诊断日志**：本地滚动 256KB，反馈时可作为附件发出（**绝不记录用户内容**）

### 3.5 首次启动
同意条款（`LegalConsentView`，须勾选）→ 引导（3 页）→ 列表。条款页明确写：数据只在本机，卸载或删除后无法恢复。

### 3.6 本地化
简体中文为源；**繁体中文**通过 `zh-Hant.lproj/Localizable.strings`（键=简体原文，值=繁体，约 789 条）。动态字符串要显式 `x.L`。

---

## 4. 上架与发布状态（App Store Connect 实况）

| 项 | 状态 |
|---|---|
| App ID | `6833046947`（SKU `allude-001`，类别：工具，次要类别未填） |
| iOS 版本 | 1.0.0，`0d47d7bf-888e-4589-8a03-838658d34a4d`，`PREPARE_FOR_SUBMISSION` |
| 版本绑定构建 | 309 → **正在改绑 312**（`409 pre-release build could not be added`，已挂后台重试；若失败，用网页「构建版本」下拉选 312） |
| 截图 | 6 张（6.7"/6.9" 一套，`APP_IPHONE_67`，全部 `COMPLETE`）：待取 / 详情 / 已取 / 统计 / 设置 / 快捷指令 |
| 标题素材 | `AppStoreHeader-5244x2950.png`、`AppStoreHeader-3840x1646.png`、`AppStoreSearch-3840x2560.png`（仓库根目录，**ASC 没有 API，只能网页拖入**） |
| 内购 · 终身 | `com.jikezhang.allude.pro.lifetime`（id `6833100079`，非消耗型）→ `READY_TO_SUBMIT`，价格 ¥9.9 **需网页设**（API 全封） |
| 内购 · 年订阅 | `com.jikezhang.allude.pro.annual`（id `6833105878`，组 `22565648`）→ `READY_TO_SUBMIT`，已是 **¥1** |
| 审核信息 | 联系人已填（王宁 张 / +8619269367710 / zhang_wangning@126.com）、备注已填、年龄分级 4+、`ITSAppUsesNonExemptEncryption = false` |
| 内容版权 / 许可协议 | 「是，拥有对第三方内容的必要权利」+「Apple 标准许可协议」——**填对了**（App 展示快递/平台品牌图标） |
| 隐私问卷 | **未填**（ASC 无公开 API，只能网页） |

### TestFlight 群组

- 群组「Allude公测」`c90099fc-1862-4b2a-8f48-a7537111fe45`
- 现在只有 **312**；历史构建已全部 `expired`（不可逆）
- 挂构建 / 写测试内容：`python3 tools/testflight-publish.py --build 312 --notes-file tools/testflight-notes/1.0.0-312.md`

---

## 5. 发布流水线（照抄即可）

```bash
export DEVELOPER_DIR=/Volumes/ZWN/Applications/Xcode.app/Contents/Developer
cd /Volumes/ZWN/Downloads/Project/Allude

# 1) 升构建号：project.pbxproj 里 4 处 CURRENT_PROJECT_VERSION 一起改
#    ⚠️ 必须「先读进变量再写回」，内联 open(p,'w').write(open(p).read()…) 会截断成 0 字节

# 2) 提交
git add -A && git commit -m "feat/fix/style: …；1.0.0 (NNN)"

# 3) Archive → Export → 预校验
xcodebuild -project Allude/Allude.xcodeproj -scheme Allude -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/allude-archiveNNN/Allude.xcarchive \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=8499X3S9X8 archive
xcodebuild -exportArchive -archivePath /tmp/allude-archiveNNN/Allude.xcarchive \
  -exportPath /tmp/allude-exportNNN -exportOptionsPlist /tmp/export245-export.plist \
  -allowProvisioningUpdates
xcrun altool --validate-app -f /tmp/allude-exportNNN/Allude.ipa --type ios \
  --apiKey 34Z43R5SGY --apiIssuer e2936bfc-e52b-4931-a763-9f03dec868e3

# 4) 上传 + 挂群组（🔴 上传前必须经主人确认）
xcrun altool --upload-app -f /tmp/allude-exportNNN/Allude.ipa --type ios \
  --apiKey 34Z43R5SGY --apiIssuer e2936bfc-e52b-4931-a763-9f03dec868e3
python3 tools/testflight-publish.py --build NNN --notes-file tools/testflight-notes/1.0.0-NNN.md
```

### 发布纪律（USER.md 里的硬规矩）

1. **TestFlight 上传 / 挂外部群组前必须先经主人确认**，不许自行连着推。
2. 上传后 ASC 有处理延迟：新构建要几分钟才出现在列表（脚本 `find_build` 已用 `limit:200`，但太早仍会 404）。
3. 构建「过期」不可逆；不要顺手把新构建过期掉。

---

## 6. 还差什么（接手后的待办，按优先级）

### P0 · 上架三件人工事（必须网页做，API 全封）
1. **App 隐私问卷**：不收集数据、不跟踪；唯一要如实交代的是「第三方模型增强时，短信原文由本机直连所选服务商」。
2. **终身买断定价 ¥9.9**（ASC › 内购 › `Allude Pro 永久` › 价格）。
3. **「标题和搜索结果」拖图**：把 `AppStoreHeader-5244x2950.png` 拖进 ASC。
4. 之后：**「添加以供审核」→ 选 312 → 提交**。

### P1 · 需要真机验证的遗留
- 「显示占位符」关掉后，小组件是否真的不画灰条
- 「显示驿站」关掉后，重进设置是否仍然关着
- 灵动岛/锁屏实时活动（模拟器抓不到岛，只能真机看）
- 带附件的反馈邮件编辑器（模拟器 `canSendMail()` 为 false）

### P2 · 内容与运营
- **4 条 iCloud 快捷指令链接仍是旧绑定**：需要主人用新包重新分享后回填 `ShortcutAutomation.icloudLinks`（`Allude/Allude/Models/ShortcutAutomation.swift`）
- Gitee Pages 镜像仍 404（法务三处副本要同时可用）
- iPad 版式已**明确放弃**（用户 2026-11-15 决定只做 iPhone）；别再花时间

---

## 7. 踩过的坑（省你几小时）

### 构建 / 工程
- **pbxproj 内联覆盖会截断文件**：`open(p,'w').write(open(p).read().replace(...))` → 0 字节 → `Unable to read project`。必须先读进变量。
- **`AlludeShared/` 与 `AlludeWidget/` 是显式 PBXGroup**：新增 Swift 文件必须手动加 `PBXFileReference` + `PBXBuildFile` + 对应 target 的 Sources 阶段，否则编译不进。
- 升版本号要改 **4 处** `CURRENT_PROJECT_VERSION`（App / Widget × Debug / Release）。
- clean build 必须 **0 warning**；弃用 API 当场迁移，不留 `@available` 兜底。

### SwiftUI
- **`Section { } header: { }` 里 `listRowInsets` 对 header 完全不生效** —— 想让分组标题紧贴列表，必须把标题当**普通行**塞进 Section 第一行，配 `.listRowInsets` + `.listRowBackground(Color(.systemGroupedBackground))` + `.listRowSeparator(.hidden)`。这是"改了没反应"的真因。
- **`NavigationLink` 在这套设置栈里要用 destination 型**：`NavigationLink { 目标 } label: { SettingsRow(...).contentShape(.rect) }`；value-based（`NavigationLink(value:)` + `navigationDestination`）在这里不落地（点了没反应）。
- 别把 `TabView(.sidebarAdaptable)` 和 `NavigationSplitView` 混搭：系统标签栏只落在详情列那一行。iPad 已放弃，不用再碰。
- 页内视频：`VideoPlayer` 会带一整套系统 UI；要"只有播放/暂停 + 进度条"，得用 `AVPlayerLayer` 自绘（`PlayerSurface: UIViewRepresentable`）。**播放本身绕不开 AVPlayer**（AVKit 只是 UI 封装）。
- 液态玻璃：所有 `.glassEffect` 统一走 `appGlass()`（`AlludeShared/GlassCompat.swift`），iOS < 26 回落 `.ultraThinMaterial`。

### 数据 / 存储
- **`enforceStorageLimit()` 只在 `ingest()` 触发**（免费档 50 条 FIFO）；启动时不删。改权益/限额前先问「会不会让在用用户掉数据」。
- 权益快照新增字段一律 `decodeIfPresent` 给默认值；`MembershipPlan` 只增不删（删 case 会让老快照解码失败 → 用户当场掉回免费版）。
- **模拟器里 App Group 偏好不能用 `defaults write` 改**：要写 `…/AppGroup/<ID>/Library/Preferences/group.com.jikezhang.allude.plist`，或用 `xcrun simctl get_app_container <UDID> com.jikezhang.allude groups` 找到容器再改。
- iCloud：现在写 `<容器>/Documents/records.json`，且 `NSUbiquitousContainerIsDocumentScopePublic = false`（**不再出现在「文件」App**）。改这个 key 前想清楚：公开 = 用户能在文件 App 里看到/删掉同步文件。

### 模拟器取证
- 没有 idb / applesimutils，AppleScript 驱动模拟器会被辅助功能拒绝（`-10004`）。**所有面板类界面靠 `SIMCTL_CHILD_SCREEN=xxx` 脚手架直渲**（case 列表在 `Allude/Allude/AlludeApp.swift`）。
- `launch` 必须带 **`--terminate-running-process`**，否则 App 在后台时只切前台、`SIMCTL_CHILD_*` 一个都不传。
- 装完先核对 `CFBundleVersion` 再截图；`simctl install`/`terminate` 是异步的，旧进程没死就 launch 会**静默沿用旧进程**。
- 常用脚手架：`SCREEN=settings|help|about|consent|contact|appicon|widgets|activity|storage|aiHub|aiExtensions|aiUsage|autoRecord|detail|stats|legal`；`TAB=pending|picked|stats|settings`；`SORT=company|oldest|newest|station`；`SELECT=1|all`；`MODEL_SHEET=1`；`FORCE_MANUAL_SHORTCUT=1`。

### 三方模型（BYOK）
- Key 只在 Keychain（service `com.jikezhang.allude.ai`），**绝不写日志**。
- 接口地址内置、不可改（用户明确要求：只允许官方端点）。
- 「测通才能启用」：`AIProviderSettings.isVerified`（比对 Key 指纹），换 Key 即失效。
- 解析复核有护栏：取件码必须在原文里仍能找到才允许改，否则记 `code_rejected not_in_text`。

---

## 8. 自检脚本（改完就跑）

```bash
# 短信解析回归（必须传语料路径）
swiftc -O -o /tmp/parser-regression \
  Allude/Allude/Models/PickupParser.swift tools/parser-regression/main.swift
/tmp/parser-regression 短信语料库_v1.md          # 全量库基线：识别 192/514、地址 189

# 驿站匹配（绝对路径编译，工具靠 #filePath 找语料）
swiftc -O -o /tmp/station-check "$PWD/Allude/AlludeShared/CourierBrand.swift" \
  "$PWD/Allude/AlludeShared/BrandPalette.swift" "$PWD/tools/station-check/main.swift" && /tmp/station-check

# 品牌表 + 资源落盘（已知 2 项既有差异，别去"修"）
swiftc -O -o /tmp/brand-check "$PWD/Allude/AlludeShared/CourierBrand.swift" \
  "$PWD/Allude/AlludeShared/BrandPalette.swift" "$PWD/tools/brand-check/main.swift" && /tmp/brand-check

# UI 去 AI 味 / 质量门禁
bash tools/unslop-ui-check.sh      # 自动项，退出码 1 = 有命中
bash tools/unslop-audit.sh         # 默认屏蔽字号规则；基线 8 error / 41 warning
```

---

## 9. 敏感与合规

- **签名私钥绝不入库**：`tools/license-gen/private-key.pem` 已在 `.gitignore`。
- 旧的「离线签名凭证 / 绑定设备」体系已于 2026-10-31 停用（从未售卖）。`LicenseVerifier` / `license-gen` 只为读得懂老快照里的 `license` 字段；**界面上没有粘贴凭证入口，别再把它加回来**（App Store 3.1.1 靶子）。
- 法务三处**必须一起改**：GitHub Pages（`Zhangwangning/allude-legal`）、Gitee 镜像（`zhang_wangning/allude-legal`）、App 内 `Allude/Allude/Legal/{privacy,terms}.html`。托管地址集中在 `Allude/Allude/Models/LegalLinks.swift`，**不要改**（App Store 表单已填），确需更换必须先 301。
- 网站备案号 `陇ICP备2026011130号`（2026-11-06 通过）——**App 内不显示**；App Store 中国区上架另需 App 备案，走接入服务商通道。
- 诊断日志绝不写用户内容（短信原文、取件码、地址、电话、设备 UUID 都不行）。

---

## 10. 接手第一步 checklist

1. `git status` 确认干净；`grep CURRENT_PROJECT_VERSION` 确认是 312。
2. 装一次真机包：`bash tools/install-device.sh`，跑一遍主流程（收码 → 列表 → 标记已取 → 小组件）。
3. 按 §6 P0 把 ASC 三件人工事做掉，然后提交审核。
4. 需要改代码时：先跑 §8 的三个自检脚本记下基线，改完再跑一遍对比。
5. 任何要发布的事（bump / archive / upload / 挂群组）都先问主人。

---

## 11. 文档地图

| 文档 | 内容 |
|---|---|
| `AGENTS.md` | 工程纪律全文（硬规则、路径、构建、字号、图标、里程碑） |
| `产品与商业模式规格_v1.md` | 定位、免费/付费边界 |
| `快递短信解析规格_V803.md` | 解析规则与优先级链 |
| `短信语料库_v1.md` | 全量回归语料（514 段） |
| `iPhone Duo 官方设计规范笔记_v1.md` | Duo 官方口径（侧栏 = 设计意图、reservedRegions…） |
| `App备案准备清单_v1.md` | 备案材料 |
| `.workbuddy/memory/*.md` | 逐日踩坑记录（按日期，**改模块前值得翻**） |
| `Allude/Allude/Views/VersionHistoryView.swift` |  App 内「版本历史」（对外文案的最新口径） |
