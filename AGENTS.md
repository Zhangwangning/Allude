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
iPhone 直板机已完工（0.3.3）；**iPhone Duo 折叠屏适配已开工**，规矩见「里程碑」一节。iPad 暂不维护。

---

## 字号（设置类界面统一标准）

全 App 的设置/教程/二级页**只用 `AppTheme.TypeScale` 里的档位**，不要再写
`.system(size: 11.5)` 这类随手值。起因：2026-11-01 主人指出"教程字号太小、
设置里大大小小随意来"，盘出来 9–24 之间散着 18 种字号（含 10.5 / 11.5 / 12.5）。

| 档位 | 字号 | 用途 |
|---|---|---|
| `rowTitle` | 17 | 行标题、行尾值（对齐系统设置） |
| `rowSubtitle` | 13 | 行副标题、分区说明 |
| `body` | 15 | 教程步骤说明、卡片内长文 |
| `section` | 13 | 分区标题 |
| `note` | 12 | 注解、页脚、卡片下小字 |
| `badge` | 11 semibold | 徽章、角标 |

需要强调时**只加 weight，不加字号**（`AppTheme.TypeScale.body.weight(.semibold)`）。

例外只有两类，它们不是"字号"，是图形尺寸：chevron / 锁图标（12–13pt）、
等宽码（设备 UUID、凭证输入框，15/13pt 等宽）—— 改它们等于改图形比例，别动。

---

## App 图标切换

八套内置图标，**默认是第 3 套「取件袋」**；设置 › App 图标可切换（版式同快递公司页的网格）。

- 主图标：`Assets.xcassets/AppIcon.appiconset`（1024，**不能有透明通道、不能自带圆角**）。
- 另外七套是 alternate icon，由 **真实 `CodePouch/Info.plist`** 里的
  `CFBundleAlternateIcons` 声明（`Icon01`…`Icon08`，跳过默认的 Icon03），
  文件是 bundle 根目录的 `IconNN@2x.png`(120) / `@3x.png`(180)。
- 图源自 512 满幅方图，**不再裁切**（早期那批是白底圆角，裁过角）。
  ⚠️ 工程已改为 `GENERATE_INFOPLIST_FILE = NO` + `INFOPLIST_FILE = Info.plist`，
  增删 Info.plist 键要改那个真实文件，`INFOPLIST_KEY_*` 不再生效。
- 选择状态存 **App Group**（`codeclip.appIcon`）：灵动岛/锁屏由小组件进程渲染，
  读不到 App 偏好。三张图在 App 与 Widget **两个**资源目录里各有一份。
- `AppMarkIcon`（灵动岛/锁屏）、关于页顶部都读同一份选择。
- 🔴 **给灵动岛用的图片资源，`Contents.json` 必须写两样**，否则折叠态会渲染成
  一个纯色方块（2026-11-01 真机修复）：
  ```json
  "properties": { "template-rendering-intent": "original" },
  "images": [ 1x(60) / 2x(120) / 3x(180) 三档 ]
  ```
  WidgetKit 的 accented 渲染管线会把"没声明渲染意图的图"当模板涂成单色，
  方形图标被涂完就是一个灰方块；只给 1x 一张也会踩到。旧的 `AppMark.imageset`
  一直带着这两样，所以当年没暴露 —— 新加资源要照抄这个规格。
- ⚠️ `setAlternateIconName` 在 `App.init()` 里调用太早（场景未连、连回调都不给），
  必须在视图出现之后调用。
- 截图验收：`SCREEN=appicon` 看选择页，`APP_ICON=envelope|cards|hand` 强制切换；
  切完**必须重启 SpringBoard** 才看得到主屏图标变化（`simctl spawn <udid> killall SpringBoard`）。

---

---

## 来源与第三方标识（对外口径，改文案前先看）

App 内「关于 › 声明与免责」（`StatementView`）是唯一的对外表述来源，四段：

1. **来源**：拾码 CodePouch 由极客ZHANG 独立开发，衍生自开发者本人制作的
   「快递取件码」快捷指令；App 把那套取码逻辑搬进原生应用，没有第二个来源。
2. **技术**：全部 Apple 官方工具与框架（Xcode / Swift / SwiftUI / WidgetKit /
   ActivityKit / StoreKit），零第三方依赖、零第三方 SDK。
3. **关于借鉴**：产品形态、交互、视觉均自设计，未借鉴未抄袭其他应用；
   解析规则来自真实短信整理与回归测试，语料与基线可复核。
4. **第三方标识**：快递公司/驿站图标只用于**标识取件来源**，版权归各品牌方；
   不表示授权或合作；权利人异议即移除。侵权联系邮箱同「联系方式」。

🔴 修改这四段时保持事实准确：
- 不要再写"参考了某 App"之类的话（与第 3 条冲突）；
- 品牌图标只能出现在「快递公司 / 驿站管理」这类标识场景，别拿去做宣传图。

## 里程碑：iPhone 直板机 v0.3.3（2026-11-01）

直板机（iPhone 16 Pro 及其同类）的功能与视觉验收到此**全部完成**，基线是
`0.3.3 (58)`。当前涵盖：

取码与列表 · 桌面小组件（小/中）· 灵动岛与锁屏实时活动 · 统计 · 搜索与排序 ·
截图收件 · 通知提醒 · 快递公司与驿站管理 · 使用教程 · 诊断日志 · 反馈邮件 ·
八套 App 图标 · 权益与订阅页 · 声明与免责 · 联系方式 · 首启同意与引导 ·
破坏性操作的随机数确认。

### 🔴 从这里开始做 iPhone Duo，**不得影响直板机**

规矩（违反即回退）：

1. **只增不改**：Duo 的版式、断点、状态**新增**文件或分支，不改直板机现用的
   布局代码与常量。确需共用一处，先在直板机上跑一遍回归。
2. **调用点判设备**，不在视图内部到处塞 `if foldable`：尺寸判定集中在
   `DeviceClass`（新建），视图只读它的结果。
3. **直板机回归清单**（每次改完 Duo 都要过）：
   - `SCREEN=settings / help / about / consent / contact / appicon / widgets` 截图；
   - 首启同意 → 引导 → 进列表，全流程一次；
   - 待取/已取列表条数仍是 4，卡片配色与取件码字号不变；
   - 桌面小组件小/中尺寸正常，灵动岛折叠态图标正常（真机）；
   - `bash tools/install-device.sh` 装机后 `devicectl` 核对版本号。
4. **版本号不混**：Duo 的实验性改动不跟着直板机一起发，合并前确认直板机构建 0 warning。

## iPhone Duo 模拟器（2026-11-01 首次装机）

- 设备类型：`com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`
- UDID：`C1B11E62-C700-4065-BFAE-E65D2BA42071`（iOS 27.2）
- 两个显示：`--display=1` 是**折叠态外屏**（1398×2034，约 466×678pt），
  `--display=3` 是展开态内屏（2007×2853）。折叠时内屏是黑的。
- 截图必须带 `--display=`：不带参数会报 `Invalid argument`。
- ⚠️ **`simctl` 没有 fold/unfold 命令**，展开态只能在模拟器菜单里手动切；
  命令行验收先按折叠态做，展开态靠 `CODEPOUCH_DEVICE=duo` 脚手架 + 人工截图校对。

### 🔴 官方设计规范（2026-11-01 查证，优先于一切猜测）

完整笔记在 **`iPhone Duo 官方设计规范笔记_v1.md`**，来源是 Apple 三场 Tech Talks：
[Prepare your app](https://developer.apple.com/videos/play/tech-talks/111461/) ·
[Design for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111466/) ·
[Strike a pose](https://developer.apple.com/videos/play/tech-talks/111463/)。

三条最容易搞错的官方口径：

1. **侧边竖排标签栏是设计意图，不是 bug。**
   官方："position your toolbars, tab bars and controls along the side"。
   ⚠️ 我在 0.3.3 把它记成"问题"，**已撤回**。
2. **只为两种 size class 设计**（外屏 compact / 内屏 regular），
   内屏**不遵循 supportedInterfaceOrientations**，布局只看 size class。
3. **折痕与摄像头是「保留区域」**，有 API 可查，不要写死像素：
   `proxy.reservedRegions(kind: .division / .occlusion)`（iOS 27.1+）。

### 折叠态首装实测（0.3.3）真正要改的

1. ~~标签栏变右侧竖排~~ → **符合官方意图，不改**。
2. **单列列表被拉宽**：官方要求 regular 宽度下用两列或分栏，这条要做。
3. ✅ 已改：自绘面板改用 `reservedRegions(kind: .occlusion)` 拿摄像头区域
   （不再写死 84pt）。⚠️ 但 `ConcentricRectangle` 在根 overlay 里会裁成直角
   （容器没有 cornerConfiguration），圆角仍按屏幕半径显式算。

### 已修：外屏「分享取件码」面板（0.3.3 build 59）

`SharePreviewSheet` 现在按**窗口高度**分流：`< 720pt` 走紧凑版式（直板机 ≥ 850pt，
永远不进这个分支）。紧凑态做了四件事：

1. 面板尺寸改从**窗口**读（`Self.windowSize`）——原来用 GeometryReader，
   在被 `ignoresSafeArea` 的层级里仍报"安全区内"尺寸，Duo 上面板少掉上下两条。
2. **隐藏系统状态栏**（`.statusBarHidden(compact)`）：Duo 外屏的状态栏时间画在
   面板内部右上角，正压「完成」胶囊上。
3. 顶栏左右留白让到面板大圆角之内（`corner * 0.86`），「完成」不再被弧线切掉。
4. 卡片收窄（左右 40）并下移 12pt，两侧与顶部留出呼吸。
5. 🔴 **按真实安全区内缩**（2026-11-01 主人："右侧是摄像头和 dock，遮挡了"）：
   Duo 外屏实测 `window=466x678 inset t=0 l=0 r=84 b=34` ——
   右侧 84pt 是摄像头/dock 区、底部 34pt 是 Home 条。
   面板挂在 RootView 顶层且 `ignoresSafeArea`（为了盖住标签栏），
   所以必须自己把这四边补回来，否则内容会被摄像头压住。
6. 🔴 **圆角按 D 型屏分边**：铰链侧（左）16pt 小圆角、机身外缘（右）大圆角
   （`corner = displayCornerRadius − 8`），用 `UnevenRoundedRectangle`。
   四角同半径在 D 型屏上一定错位。直板机仍是统一 `RoundedRectangle`。
7. ⚠️ **底部与顶部留白要一致**（2026-11-01 主人两次指出底部间隙太大）：
   面板四边一律只留 `inset = 8`（底部**不再**额外让 34pt），
   Home 指示条由**内部按钮条**的 26pt padding 让开。
   也不要再叠加 `safeBottom + x`，那会翻倍。
8. **铰链在左、摄像头在右**（主人确认）：所以圆角是「左 16 / 右 55」，
   不要反过来。

⚠️ 直板机的分享面板**没有改**（`compact == false` 走原参数），截图对比过。

## 首次启动（同意条款 → 引导）

2026-11-01 主人要求：首启**必须先读并同意《使用条款》《隐私政策》**，再看使用教程。

顺序（`RootTabModel` 控制，两个都是 fullScreenCover，不叠加）：
1. `LegalConsentView`：条款链接（`LegalDocumentView`，App 内读）+ 「我已阅读并同意」
   勾选 + 「同意并继续」（未勾选置灰）+ 「不同意」（弹说明）。
2. 同意后写 `legal.consent.v1`，接着进 `OnboardingView`（三页速览），
   完成写 `onboarding.completed.v1`。

这一页还有一条**必须写清**的事：数据只在本机，
**卸载 App 或删除记录后 App 内无法恢复**（没有云端备份、没有回收站）。
文案在 `LegalConsentView.dataNotice`，别弱化成"请注意"。

同理，「清空已取件记录」在 2026-11-01 前是**直接删、没有确认**的。
现在要先过一道**随机四位数字**：弹窗里显示一个随机数，用户照着输入，
输对了「清空」才变红可点（`DestructiveConfirmDialog` + `.destructiveConfirm(...)`）。
- 🔴 是**盖在当前页上的居中弹窗**（版式照系统 alert），不是新页面。
- 「清空」**常亮红色**，点下去才校验：输对就删；输错给一行红字、清空输入、
  并换一个新数字（2026-11-01 主人："按钮常亮也行，反正输不对删不掉"）。
- 数字每次弹出/每次输错都重新生成，防止记住上一轮闭眼输。
- 截图验收：
  · `SCREEN=confirmClear` —— 纯色底上的弹窗（只看版式，**背景一定是空的，不代表真机**）；
  · `CONFIRM_DEMO=1` —— 在真实列表上自动亮起弹窗，这才是用户看到的样子。
  · `CONFIRM_MATCH=1` —— 预填正确数字。
- 蒙层用 `Color.black.opacity(0.20)`：再深就把后面的卡片压没了
  （2026-11-01 主人要求"后面的列表卡片内容要显示"）。

截图验收：`SCREEN=consent`；不带 `SKIP_ONBOARDING` 冷启动可看真实首次流程。

## 联系方式页（`ContactView`）

2026-11-01 第二版口径（主人定的）：

- 每行显示**平台名 + 账号名**，不显示那串 ID（`zwn1652503532` 对用户没有意义）。
  邮箱例外：地址本身就是账号，保留 `zhang_wangning@126.com`。
- 行尾动作写明白：`复制邮箱` / `去小红书` / `去抖音`。
- **不展示二维码**。小红书 `https://xhslink.cn/o/7EXKCLCJzB0`、
  抖音 `https://v.douyin.com/jUUUICs4WuY/` 点击直接跳主页（打不开会提示）。
- 微信公众号**无法跳转**：`weixin://` 只能打开微信本体，公众号二维码里是微信私有
  ticket，第三方拼不出来。所以**只放那一张横幅图**（`QRWeChatBanner`），
  不加卡片边框、不加标题、不加微信图标（2026-11-01 主人：图里信息已完整）。
  图下那句话是**引导反馈**（"有使用上的问题，可以在公众号后台留言"），
  不是引导关注 —— 措辞克制，别写成"欢迎关注"。
- 行首用平台官方图标（`IconMail` / `IconXiaohongshu` / `IconDouyin` / `IconWeChat`），
  `SettingsRow.imageAsset` 支持图片图标。
  ⚠️ `IconMail` 是 Apple「邮件」App 的图标，属 Apple 商标；仅在自家 App 里指代
  "发邮件"这一动作，不暗示与 Apple 的合作关系。

## 产品命名（2026-11-01 主人定）

界面上**不出现「免费版」「付费版」**这两个词，只用两个产品名：

| 档位 | 对外名称 |
|---|---|
| 未解锁 | **拾码 CodePouch** |
| 已解锁 | **拾码 Pro**（完整名 拾码 CodePouch Pro） |

小组件头部空间窄，截断提示用最短的「Pro」（配锁图标），不再写「免费版」。

额度：**同屏 4 条**（`PickupLimits.freeVisible`，App 列表与小组件同源；
2026-11-01 主人从 3 改成 4）。不再限制"每种尺寸只能加一个"——那条是文案，
WidgetKit 也不暴露实例数量，说不清就别写。

## 模拟器里看不到灵动岛（已知环境限制）

实时活动**能起来**，但**灵动岛不显示**——这是模拟器 SpringBoard 的行为，不是 App 的问题。
2026-11-01 实测取证（iPhone 16 Pro / iOS 27 模拟器）：

- App 侧三道门全过，`Activity.request` 成功：
  `converge pending=34 enabled=true pro=true auth=true` → `requested id=...`
- SpringBoard 也登记了这张活动，并创建了 compact 布局断言：
  `<activity:…com.apple.chrono.WidgetRenderer-Activities>` / `preferredLayoutMode: compact`
- 随后整个 SystemAperture 被压掉：
  `invalidation reason: SBSystemApertureCoordinator suppressionForSuppressSystemApertureCompletely`

排查过：把 App 切后台、激活 Simulator 窗口、换全新 iPhone 18 Pro Max 模拟器、
写 `SBSystemApertureSuppressCompletely` / `SBSuppressSystemApertureCompletely` 默认值 —— 均无效。

✅ 所以灵动岛相关的验收走两条路：
1. **版式/着色**：设置 › 实时活动页里的灵动岛预览（`SCREEN=activity`，配
   `ACTIVITY_PAGE=1` 落到折叠态），它用**同一套视图**渲染，能看到图标、描边、计数；
2. **真实呈现**：以真机为准（2026-11-01 主人已确认折叠态图标正常）。

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
