# 拾码 CodePouch — 项目指令

iOS 取件码收纳 App。核心承诺：**数据只在本机，不联网、不上传、不需要注册**。
SwiftUI + iOS 27 SDK，纯 Xcode 工程，零第三方依赖、零 SPM 包。

商业模式：**免费下载 + 订阅解锁**（参照 Infuse），三档同一权益：
`com.jikezhang.codeclip.pro.monthly`（¥1/月）、`.yearly`（¥9/年）、
`.lifetime`（¥28，非消耗型买断，**主推**）。走 StoreKit 2，价格一律取 `Product.displayPrice`。
订阅会过期 → 权益快照必须写 `expiresAt`，否则小组件会一直按完整版渲染。

> 隐私政策与使用条款有**三份副本要同步**：GitHub Pages（`Zhangwangning/codepouch-legal`，
> App Store 表单填这个地址）、Gitee 镜像（`zhang_wangning/codepouch-legal`，国内可访问），
> 以及 App 内打包的 `CodePouch/Legal/{privacy,terms}.html`（WKWebView 离线读，不跳浏览器）。
> 改文档必须三处一起改，否则用户看到的和商店页面写的会不一致。

> 托管地址：
> 地址集中写在 `CodePouch/Models/LegalLinks.swift`。这三个 URL 已经要填进
> App Store Connect 的审核表单 —— **不要改**，确需更换必须先让旧地址 301 过去。

> ⚠️ **未上架期间的激活入口**：设置 › 激活（`ActivationView`）。设备码打码显示、可复制；
> 凭证由 `tools/license-gen` 签发，绑定设备码，本机离线验签。
> 🔴 **正式上架前必须移除或改成内购** —— 用 license key 解锁完整功能是 App Review 3.1.1 的靶子。

> 旧的「离线签名凭证 / 绑定设备」体系已于 2026-10-31 停用（从未对外售卖）。
> `LicenseVerifier` / `license-gen` 工具**仍在**，只为读得懂老快照里的 `license` 字段；
> 界面上已经没有粘贴凭证的入口，别再把它加回来（那是 App Store 3.1.1 的靶子）。

---

## 硬规则（违反会出事故）

### 1. 构建带上 `-disable-sandbox`

这个参数是**防沙箱，不是修代码**。宏插件（`FoundationModelsMacros`）要让
`swift-plugin-server` 拉起一个子进程；**只要 xcodebuild 本身被沙箱包住**
（agent 运行时 / CI / Xcode 的 User Script Sandboxing），子进程起不来，就会报
`could not be found` / `swift-plugin-server produced malformed response`，
并连带抛出一堆**假错误**（典型是 `SwipeActionRow.swift` 里的 `'self' is immutable`）。

**那是工具链问题，不是代码问题。** 不要为了让这些报错消失去改业务代码 ——
先确认构建进程是不是被沙箱包着，把参数补上重跑一次。

> 2026-10-30 实测，别被两种情形搞混：在**普通 shell** 里（不经 agent 沙箱）
> 不带宽也照样 0 warning 构建通过，产物二进制与带宽版本 sha 完全相同。
> 所以「没带宽却过了」不代表这条规则错了，只代表这次没被沙箱包住；
> 反过来「带宽了还报假错误」才是真正需要排查的信号。

### 2. 这四项内部标识绝不能改

| 项 | 值 | 改了会怎样 |
|---|---|---|
| App Bundle ID | `com.jikezhang.codeclip` | 数据容器换新，用户记录全丢 |
| Widget Bundle ID | `com.jikezhang.codeclip.CodeClipWidget` | 系统判成新扩展，小组件需全部重加 |
| App Group | `group.com.jikezhang.codeclip` | 主 App 与小组件的数据通道断 |
| Widget `kind` | `CodeClipPickupWidget` | 已添加的桌面小组件失配 |

这些是用户看不见的内部标识。对外名称是「拾码 CodePouch」，对外显示名改 `CFBundleDisplayName` 即可。

### 3. 权益枚举只增不删

`MembershipPlan` 里**删掉任何一个 case**，老快照会在 `JSONDecoder` 解码时失败 →
被判 `malformed` → 用户当场掉回免费版。权益快照（`entitlement.json`）里新增字段
一律 `decodeIfPresent` 给默认值，否则一次解码失败就是静默降级。

`monthly` / `yearly` 就是为此保留的：**只读兼容，不再签发**，统一映射到 `.trial`。

### 4. 签名私钥绝不入库

`tools/license-gen/private-key.pem` 已在 `.gitignore`。
它一旦进仓库（哪怕私有仓），整套买断制作废——谁拿到都能自己签。

### 5. 其它纪律

- **clean build 必须 0 warning**，弃用 API 当场迁移，不留 `@available` 兜底。
- **不要提交构建产物**：`build/`、`build-sim/`、`DerivedData/` 已忽略。
- **价格只能来自 StoreKit**：内购（`PurchaseStore`，订阅 + 买断三档）必须展示
  `Product.displayPrice`，不要写死「¥18」—— 上架定价改了代码就对不上。
  除此之外不做销售催促、不做防盗宣示。


---

## 路径结构（三层同名，别数错）

```
CodePouch/                    ← 仓库根（.git 在这里）
└── CodePouch/                ← 工程根
    ├── CodePouch.xcodeproj
    ├── CodePouch/            ← App 源码（Views / Models）
    ├── CodePouchShared/      ← App 与小组件共用的代码
    ├── CodePouchWidget/      ← 小组件扩展
    ├── Config/               ← entitlements
    └── tools/
```

仓库根下另有 `tools/`（构建、安装、签发、自检脚本）与若干规格 `.md`。

---

## 构建与运行

```bash
cd CodePouch
xcodebuild -project CodePouch.xcodeproj -scheme CodePouch \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/codepouch-verify build \
  CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS="-disable-sandbox"
```

真机安装：`bash tools/install-device.sh`
（自动探测 Team、构建、用 devicectl 装机。免费 Personal Team 签名，描述文件 7 天过期，到期重跑续签。）

---

## 怎么验证 UI（重要：命令行点不了屏幕）

本机没有 idb / applesimutils，AppleScript 驱动模拟器会被辅助功能权限拒绝
（`-10004 权限违例`）。**所有面板类界面都靠 `SCREEN` 环境变量直渲**：

```bash
xcrun simctl launch <UDID> com.jikezhang.codeclip   # 需先 SIMCTL_CHILD_SCREEN=xxx
xcrun simctl io <UDID> screenshot /tmp/x.png
```

常用 `SCREEN` 值：
`settings`（设置页，配 `SETTINGS_ANCHOR=about` 滚到底）、`add`（添加面板，配 `SEED=<短信>`）、
`license`（完整版/订阅页）、`scan` / `scanPhoto`、`share`、`pickedUp`、`stats`、
`detail`、`detailPicked`、`notify`、`gallery`、`activation`（激活页）、
`help`（帮助与反馈）、`about`（关于）、`legal`（隐私政策页）。

🔴 **装完先核对版本号再截图**：`simctl install` 与 `terminate` 是异步的，
旧进程没死就 `launch`，会**静默沿用旧进程**——截到的是上一版界面，
看起来像"改的代码没生效"。2026-10-31 因此误判过一次选中态。
```bash
xcrun simctl terminate UDID com.jikezhang.codeclip; sleep 4
xcrun simctl install UDID …/CodePouch.app; sleep 2
xcrun simctl terminate UDID com.jikezhang.codeclip; sleep 4
# 确认装上去的是新构建，再 launch + 截图
```

环境变量必须带 **`SIMCTL_CHILD_`** 前缀。截图建议同时注入
`SIMCTL_CHILD_SKIP_PERM=1`、`SIMCTL_CHILD_SKIP_ONBOARDING=1`，冷启动等 6–8 秒。

真机回归基准模拟器：iPhone 16 Pro `272DD31C-D94F-46B4-9CC7-974A61439777`。
**目前只做 iPhone 直板机**，iPad / Duo 的宽屏适配暂不维护。

---

## App 图标切换

三套内置图标（经典 / 信封 / 卡券），设置 › App 图标可切换。

- 主图标：`Assets.xcassets/AppIcon.appiconset`（1024，**不能有透明通道、不能自带圆角**）。
- 另外两套是 alternate icon，由 **真实 `CodePouch/Info.plist`** 里的
  `CFBundleAlternateIcons` 声明（`IconEnvelope` / `IconCards`），
  文件是 bundle 根目录的 `IconEnvelope@2x.png`(120) / `@3x.png`(180)。
  ⚠️ 工程已改为 `GENERATE_INFOPLIST_FILE = NO` + `INFOPLIST_FILE = Info.plist`，
  增删 Info.plist 键要改那个真实文件，`INFOPLIST_KEY_*` 不再生效。
- 选择状态存 **App Group**（`codeclip.appIcon`）：灵动岛/锁屏由小组件进程渲染，
  读不到 App 偏好。三张图在 App 与 Widget **两个**资源目录里各有一份。
- `AppMarkIcon`（灵动岛/锁屏）、关于页顶部都读同一份选择。
- ⚠️ `setAlternateIconName` 在 `App.init()` 里调用太早（场景未连、连回调都不给），
  必须在视图出现之后调用。
- 截图验收：`SCREEN=appicon` 看选择页，`APP_ICON=envelope|cards|hand` 强制切换；
  切完**必须重启 SpringBoard** 才看得到主屏图标变化（`simctl spawn <udid> killall SpringBoard`）。

---

## 诊断日志（反馈用）

`DiagnosticsLog` 在 `Application Support/Diagnostics/log.txt` 滚动记录（上限 256 KB，
超过滚成 `log.1.txt`，只留一代）。用户点「反馈 › 发送邮件反馈」时，日志作为
`codepouch-log.txt` **附件**随邮件发出（走 `MFMailComposeViewController`，
`mailto:` 带不了附件）；用户可关闭「附带诊断日志」开关。

🔴 **日志绝不记录用户内容**：不写短信原文、取件码、地址、电话、设备 UUID。
只写"发生了什么"：版本、系统、解析长度与条数、错误码、耗时、权益档位。
这是本 App 唯一会离开设备的数据，写日志前先问一句"这句能不能给外人看"。

⚠️ 模拟器里 `canSendMail()` 为假，只能验证到"复制邮箱兜底"分支；
带附件的编辑器必须在真机上验。

---

## 数据安全红线

`enforceStorageLimit()` **只在 `ingest()`（收到新短信解析入库）时触发**，
按免费档 50 条 FIFO 淘汰最旧的；启动时不会删。

改任何与权益、限额、存储相关的逻辑前，先确认：**会不会让已在用的用户掉数据**。
这个 App 的价值全在"用户攒了几个月的那堆取件记录"。

---

## 既有领域约定（改之前先看）

- **字段口径**：一条短信里多个取件码 → 拆成多张卡（`parseAll` 的 `codeChainParts`），
  但链式段必须与首段同形（`codeShape` 指纹），否则会把柜位号误判成第二条。
- **主名口径**：`titlePrimary = courier ?? company`，驿站不进主名位。
- **解析器**：四套独立正则 + 优先级链（code → waybill → tail → special）。
  **新增正则必须注册进 `regexes` 预编译表**，否则 `firstMatch` 恒 nil 且不报错。
- **颜色**：卡面用品牌色，取件码恒用 `iconBrand`（`CourierBrand.color(for: titleIconSource)`）。
- 更细的历史决策见 `.workbuddy/memory/MEMORY.md` 与按日期的日志（同目录），
  那是逐轮迭代积累的踩坑记录，改动相关模块前值得一读。

---

## 自检脚本

```bash
# 短信解析回归 —— **必须传语料路径**，省略会直接报「读不到语料文件」并 exit 1。
# 精选库（64 条，基线：识别 64 / 地址 60），语料在**仓库外**，换机器可能不存在
swiftc -O -o /tmp/parser-regression \
  CodePouch/CodePouch/Models/PickupParser.swift \
  tools/parser-regression/main.swift && \
/tmp/parser-regression "/Volumes/ZWN/Downloads/Project/shortcuts-toolkit-master/快递取件码短信库.md"

# 全量库（514 段，基线：识别 192 / 地址 189），语料就在仓库根，长期可用
/tmp/parser-regression 短信语料库_v1.md

# 驿站匹配自检（精选 63 条 + 对抗样本 14 条，逐条比对「这条应该判成哪个驿站」）
# ⚠️ 必须用**绝对路径**编译：工具靠 #filePath 推自己的目录找语料，
#    用相对路径编译后换工作目录运行会报「读不到 cases.txt」。
swiftc -O -o /tmp/station-check \
  "$PWD/CodePouch/CodePouchShared/CourierBrand.swift" \
  "$PWD/CodePouch/CodePouchShared/BrandPalette.swift" \
  "$PWD/tools/station-check/main.swift" && /tmp/station-check
# 退出码 0 = 全符合基线；1 = 有差异并逐条打印。
# 🔴 改匹配规则时不要为了让它是绿的而改基线文件 —— 先确认每处变化都符合预期。
# 🔴 自由文本匹配**只用 name + aliases，不用 key**：key 是给用户改名归一化用的短名
#    （中邮/菜鸟/兔喜…），拿去扫正文会把「中邮大厦」「熊猫便利超市」判成驿站。
#    某条短信确实只写短名时，把那个写法补成该条目的 alias，不要放 key 回循环。

# 品牌表 + 资源落盘自检（必须用绝对路径编译，它靠 #filePath 推仓库根）
swiftc -O -o /tmp/brand-check \
  "$PWD/CodePouch/CodePouchShared/CourierBrand.swift" \
  "$PWD/CodePouch/CodePouchShared/BrandPalette.swift" \
  "$PWD/tools/brand-check/main.swift" && /tmp/brand-check
# 这条目前会 exit 1。2 项失败是**既有业务差异**，不是回归，别去「修」：
#   ① 「某某冷门驿站」期望映射到「快递驿站」；
#   ② 品牌表多挂 5 个未登记资产（brand-duoduodaishou / miaozhan /
#     shoujianbao / tiantian / yundakuaichaoshi）。
# 除这两项外必须全 ✓；要让脚本变绿，改的是期望值，不是品牌表。

# 签发 / 验签凭证（未上架期间给测试者发凭证用）
python3 tools/license-gen/issue-openssl.py --plan 7d       --device <32位HEX>
python3 tools/license-gen/issue-openssl.py --plan 30d      --device <码>
python3 tools/license-gen/issue-openssl.py --plan 180d     --device <码>
python3 tools/license-gen/issue-openssl.py --plan 1y       --device <码>
python3 tools/license-gen/issue-openssl.py --plan forever  --device <码>
# 也认 --plan 7天 / 30天 / 半年 / 一年 / 永久；旧写法 --service trial --days N 仍可用。
# 限时凭证靠 payload 里的 `e`（到期时间）在**读侧**降级：过期即 free，App 与小组件同口径。

python3 tools/license-gen/issue-openssl.py --check "<凭证>"
```

---

## 提交规范

署名 `极客ZHANG <zhang_wangning@126.com>`。提交信息用中文，
前缀 `feat:` / `fix:` / `refactor:` / `style:` / `docs:` / `chore:`。

远端：`https://github.com/Zhangwangning/CodePouch`（私有）。
