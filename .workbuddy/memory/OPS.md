# Allude 操作手册（发版 / 真机 / 取证 / 内购）

## 真机安装（Debug，唯一能验灵动岛的路）
```
DEST='platform=iOS,id=00008140-001138A92E01801C'   # iPhone 16 Pro（桌面名被改成「Huawei Mate XT」）
xcodebuild -project Allude.xcodeproj -scheme Allude -destination "$DEST" \
  -derivedDataPath /tmp/allude-device -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration OTHER_SWIFT_FLAGS="-disable-sandbox" build
```
- 团队 `8499X3S9X8` automatic signing。模拟器 `CODE_SIGNING_ALLOWED=NO` 的包**没有 App Group**。
- 移开模型构建出的包**缺 `.mlmodelc` 且残留 `.bak`**：
  `xcrun coremlc compile <in> <outdir>`（**位置参数**，没有 `--output-dir`）→ `rm` 掉 `.bak`
  → `cp -R` 进 `Allude.app/` → **必须重签**，先 appex 后 App：
  ```
  codesign -d --entitlements :- Allude.app 2>&1 | sed -n '/<?xml/,$p' > /tmp/ent.plist
  ID="2728A60C4902F4F2EF87F8A9B02564C87172B59E"   # Apple Development: zhang_wangning@126.com (K2FQFHU46Z)
  codesign -f -s "$ID" --entitlements /tmp/ent_widget.plist --timestamp=none Allude.app/PlugIns/AlludeWidget.appex
  codesign -f -s "$ID" --entitlements /tmp/ent_app.plist    --timestamp=none Allude.app
  ```
  **必须用导出的** entitlements：裸 `Config/*.entitlements` 缺 `application-identifier` /
  `team-identifier` / `get-task-allow`，装了起不来。
- `devicectl device install app --device <id> <path>`；
  `devicectl device process launch --terminate-existing -e '{"SCREEN":"…"}'`；
  `--console` 可抓 stdout（`[allude-iap]` 等日志）；`process terminate --pid <pid>`（**只吃 pid**）；
  `devicectl device capture screenshot --device <id> --destination p.png`。
- 真机读写：`devicectl device info files|copy from|copy to --domain-type appGroupDataContainer
  --domain-identifier group.com.jikezhang.allude`。真机启动会从 iCloud 同步，种子数据可能被覆盖。
- ⚠️ 装 Debug 包会**覆盖 TestFlight 正式版**（同 bundle id），要回正式版得从 TestFlight 重装。

## 模拟器取证
- 无 idb/applesimutils，AppleScript 被拒（-10004）→ 面板靠
  `SIMCTL_CHILD_SCREEN=xxx xcrun simctl launch <dev> com.jikezhang.allude`
  （**前缀形式**；写在 bundle id 后面会被当 argv 丢弃）。
- `simctl launch` 必须 `--terminate-running-process`；装完先核对 `CFBundleVersion` 再截图。
- 常用直达入口（`BuildFlags.scaffoldsEnabled`，仅 Debug）：`history|stats|browse`、`settings|profile`、
  `appicon`、`license`（= `FullVersionView` 付费页）、`legal`、`stationGroups`、`share`、`aiCheck`。
  付费页另有 `PAYWALL_ANCHOR=bottom` 落到页底。
- 模拟器 ID 会变，`xcrun simctl list devices` 现查。折叠屏（iPhone Duo）截图必须 `--display=1`。
- 性能：`xctrace record --template 'Time Profiler' --attach <pid> --time-limit 18s`，
  导出 xpath `/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]`；
  XML 里 frame/thread 是 id 定义 + ref 引用，必须建表再解析。`Animation Hitches` 模拟器不支持。
  DEBUG 探针：`PERF_LOG=1`（PerfProbe，写 Documents/perf.log）、`PERF_FPS=1`（FrameMonitor）。

## 内购（2026-11-21 实测定论）
- 商品：`…pro.lifetime`（非消耗，基准地 CHN，手动价 1 档）+ `…pro.annual`（订阅组 `22565648`）。
  `displayedPlans = [.lifetime, .yearly]`，月度已下架。
- 🔴 **真机价格不显示 = 商品在 ASC 未过审，不是代码问题**。真机实测日志
  `[allude-iap] storefront=CHN products=(empty)` —— StoreKit 连上了，但一个商品都不返回。
  ASC 状态：lifetime `READY_TO_SUBMIT`、annual `CREATED`（都没进过审核）。
- 模拟器里显示 `$0.99` 是**占位价**，不能当「商品可用」的证据（本地 `Allude.storekit` 写的是
  9.99 / 1.99，ASC 是 CNY，都对不上 0.99）。
- 修复路径：把两个内购挂进提交单随版本一起送审 → 过审后 StoreKit 才返回商品。
  1.0.0 现为 REJECTED（2.1），得先在 Resolution Center 回复。
- API：`/v1/subscriptionGroups` 对当前 Key **403**；annual 状态从
  `/v1/apps/{aid}/inAppPurchases`（legacy）读；价格走
  `/v1/inAppPurchasePriceSchedules/{id}/manualPrices?include=territory`。
- 代码侧：`Product.displayPrice` 是系统按 storefront 格式化好的串，**不许写死金额**；
  取不到商品时 `price(for:)` 返 nil → 按钮「暂时无法购买」+「重新获取商品信息」重试入口。

## TestFlight 发版（全命令行）
- 🔴 `-exportArchive` **本机不可用**（无 GUI 时 `ITunesSoftwareService` 起不来），别试。
- 分发证书 `P76B23FF7S`（2027-11-15）。🔴 **profile 别用 Xcode 本地缓存**
  （`~/Library/Developer/Xcode/UserData/Provisioning Profiles/` 里那两个是 `Apple Distribution:`
  证书签的，本机只有 `iPhone Distribution: Wangnjng Zhang (8499X3S9X8)` → altool 报 90179）。
  ✅ 用 ASC 上 2027-11-15 到期的：App `7H29P7MJ8Q`(313) / `QWXC4A3745`(322)、
  Widget `4F62FDJ8K2`(313) / `43ADL489RJ`(322)；`python3 tools/asc-profiles.py --list` 现查，
  `GET /v1/profiles/{id}` 的 `profileContent`(base64) 下载。⚠️ 别用 `bids["data"][0]`（第一个是 Widget）。
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
- 停测旧构建：`python3 tools/asc-expire-old-builds.py --below N [--apply]`（`PATCH /v1/builds/{id}`
  `{expired:true}`；Apple 语义是「停止测试」不是删除）。

## ASC 现状（2026-11-21 19:16）
- 构建 **328** 已上传 VALID（19:16，`b49a57ce`），挂「Allude公测」（组
  `c90099fc-1862-4b2a-8f48-a7537111fe45`），测试内容 645 字，Beta 审核 submitted。
  327（`6e1a8b57`）/ 326 / 325 保留可用。
- 文案改名（2026-11-21 19:08 走 API 改完并回读确认）：1.0.0 版本描述 4 处
  `Allude` → `Codelumi`（**没动** `allude-legal` 两个 URL）；内购 lifetime 本地化
  「Allude Pro 永久 / 订阅可永久使用Allude Pro」→「Codelumi Pro 永久 / 一次买断，永久使用 Codelumi Pro」。
  App 级名称已是 `Codelumi`，`CFBundleDisplayName` 已是 `Codelumi`，法务 HTML 全是 Codelumi；
  版本历史 0.2.7 那条「英文名 Allude」是**史实保留**，别改。
- 1.0.0 目前 `PREPARE_FOR_SUBMISSION`（不是之前记的 REJECTED），已绑 build 327。
  老大 2026-11-21 19:10 决定：**先不提交审核**。
- 🔴 **API Key 权限差异（2026-11-21 定论）**：`34Z43R5SGY`（DSH）只有「App 管理」→
  `/v1/subscriptions`、`/v1/subscriptionGroups` 全 403；`T359K7F6U3`（workbuddy）是「管理」→
  订阅接口都能读能改。用法：`ASC_KEY_ID=T359K7F6U3 python3 …`（脚本 `make_token` 认这个环境变量）。
  私钥 `~/.appstoreconnect/private_keys/AuthKey_T359K7F6U3.p8`。
- 🔴 legacy `/v1/apps/{aid}/inAppPurchases` 报的 annual `state=CREATED` **是假的**；
  真状态要用 Admin Key 查 `/v1/subscriptionGroups/22565648/subscriptions` → `READY_TO_SUBMIT`。
- 两个内购的审核截图都已存在，元数据齐全，**唯一缺的就是挂进提交单送审**。
- 仍需人工在网页做的三件：Resolution Center 回 2.1 六项、App 合规页、
  「协议、税务和银行业务」里的付费应用协议（未生效会让**所有**内购返回空）。
- **324 及以下全部停测**（324/322/321/320/319/318 六个 `expired=true`）。
- **1.0.0 = REJECTED，2.1 Information Needed**（2026-11-16），`releaseType=SCHEDULED`；
  提交单 `1c1857ec…` 实测 COMPLETE，仍绑 build 309。审核备注 `reviewDetail 2de42837…` 只有
  128 字符，须补 6 项（真机录屏/用途受众/设置功能/外部服务/地区差异/受监管）。
