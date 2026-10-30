# 拾码 CodePouch — 项目指令

iOS 取件码收纳 App。核心承诺：**数据只在本机，不联网、不上传、不需要注册**。
SwiftUI + iOS 27 SDK，纯 Xcode 工程，零第三方依赖、零 SPM 包。

商业模式：**买断制**。离线签名凭证按设备绑定，本地验签解锁全功能。

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

### 3. 凭证枚举只增不删

`LicenseService` / `MembershipPlan` 里**删掉任何一个 case**，已售出的凭证会在
`JSONDecoder` 解码时失败 → 被判 `malformed` → 用户当场掉回免费档。

`monthly` / `yearly` 就是为此保留的：**只读兼容，不再签发**，统一映射到 `.trial`。

### 4. 签名私钥绝不入库

`tools/license-gen/private-key.pem` 已在 `.gitignore`。
它一旦进仓库（哪怕私有仓），整套买断制作废——谁拿到都能自己签。

### 5. 其它纪律

- **clean build 必须 0 warning**，弃用 API 当场迁移，不留 `@available` 兜底。
- **不要提交构建产物**：`build/`、`build-sim/`、`DerivedData/` 已忽略。
- **App 内不出现价格**。卖什么、多少钱都在店外说；App 只说「已解锁 / 未解锁」。
- **App 内不做销售催促、不做防盗宣示**。

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
`license`（签名凭证页）、`scan` / `scanPhoto`、`share`、`pickedUp`、`stats`、
`detail`、`detailPicked`、`notify`、`gallery`。

环境变量必须带 **`SIMCTL_CHILD_`** 前缀。截图建议同时注入
`SIMCTL_CHILD_SKIP_PERM=1`、`SIMCTL_CHILD_SKIP_ONBOARDING=1`，冷启动等 6–8 秒。

真机回归基准模拟器：iPhone 16 Pro `272DD31C-D94F-46B4-9CC7-974A61439777`。
**目前只做 iPhone 直板机**，iPad / Duo 的宽屏适配暂不维护。

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

# 签发 / 验签凭证
python3 tools/license-gen/issue-openssl.py --service lifetime --device <32位HEX>
python3 tools/license-gen/issue-openssl.py --check "<凭证>"
```

---

## 提交规范

署名 `极客ZHANG <zhang_wangning@126.com>`。提交信息用中文，
前缀 `feat:` / `fix:` / `refactor:` / `style:` / `docs:` / `chore:`。

远端：`https://github.com/Zhangwangning/CodePouch`（私有）。
