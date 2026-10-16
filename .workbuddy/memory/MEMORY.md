# CodeClip 项目长期笔记

## 构建命令（Xcode-beta 沙箱缺陷，必须带 -disable-sandbox）
```
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcrun xcodebuild -project CodeClip.xcodeproj -scheme CodeClip \
  -destination 'generic/platform=iOS Simulator' build \
  CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS="-disable-sandbox"
```
- 根因：swift-plugin-server 在 sandbox-exec 里加载不了宏库，所有 Swift 宏（@State/@Observable…）报 "malformed response"。缺 `-disable-sandbox` 必挂，与 SDK/代码无关。
- 新产物在默认 DerivedData（~/Library/Developer/Xcode/DerivedData/CodeClip-hjjfrsammlsrcbbzlysabufspvva/Build/Products/Debug-iphonesimulator/）；`build-sim/` 下是旧包，勿装。

## 模拟器（simctl 必须用绝对路径）
- `xcrun simctl` 报找不到 simctl（beta 包装脚本解析缺陷），用 `/Applications/Xcode-beta.app/Contents/Developer/usr/bin/simctl`。
- 常用设备：iPhone 16 Pro (iOS 27.0)，UDID `281DCBD3-D8CC-4262-A82A-1BFDD6FED586`。
- 截图脚手架：`SIMCTL_CHILD_SCREEN=<name> SIMCTL_CHILD_SKIP_ONBOARDING=1 simctl launch <udid> com.jikezhang.codeclip`，支持 SCREEN 值见 CodeClipApp.swift 主 switch（含 smsLibrary / stationNames；已取页是 `pickedUp`，`history`/`stats` 现在都指向统计页）。
- 🔴 **simctl launch 传环境变量必须带 `SIMCTL_CHILD_` 前缀**：直接 `VAR=x` 不透传给 app 进程（simctl 会剥掉前缀后注入 App 侧读的无前缀名）；曾漏前缀白跑一轮截图。`--console` 会持续跟随 stdout 不退出，管道 grep 会被 SIGTERM，别用。
- 🔴 截图必加 `SIMCTL_CHILD_SKIP_PERM=1`：重装后系统通知授权弹窗每次冷启动必弹且**点不掉**（simctl 无点击、osascript 权限违例），`PickupListView.onAppear` 的 SKIP_PERM 开关是验收截图的唯一干净解法。
- `simctl privacy grant notifications` 不支持（Operation not permitted）。
- 其他常用脚手架：`SIMCTL_CHILD_EDIT=1`（详情页直接进编辑态）、`SIMCTL_CHILD_DETAIL_MATCH=<码子串>`（按取件码定位记录，找不到会回落 RootView）、`SIMCTL_CHILD_SEED=<短信>`+`SCREEN=ingest`（注入记录，落盘可复用于后续 detail 截图）、`SIMCTL_CHILD_GALLERY_ANCHOR=<分类rawValue>`（快递管理页滚到指定分类，如「驿站 / 代收平台」「智能快递柜」）。
- 回落 RootView 冷启动首帧慢，截图 sleep ≥4s，否则白屏误判。

## 卡片行 1 格式（2026-10-14 定稿）
- `CourierLogo(主名) 主名 [| 取件平台]` + 时间；无类别标签（KindTag）；图标在行首不在地址前；地址行只留地址+货架号。待取/已取两页同款。
- 主名优先级：courier（快递公司）> StationDirectory 驿站名匹配 > company（平台）；`titleSecondary` = 主名≠平台时才显示「| 平台」。
- `Models/StationDirectory.swift`：ObservableObject 单例，内置 29 个取自 CourierBrand 的 station/locker 类目；自定义存 UserDefaults `station.customNames`；`matchedName(in:)` 对 address+rawMessage 做最长关键词包含匹配；卡片挂 @ObservedObject 即时刷新。管理入口已并入「快递管理」页（原 StationNamesView 已删）。

## 详情页字段口径（2026-10-15 主人指正后定稿）
- 🔴 **快递驿站 ≠ 取件地址**（主人原话：「取件地址是取件地址，快递驿站是固定的驿站或者商铺」）。历史上「快递驿站」标签误绑 address 字段，已拆分：
  - 「取件地址」= `record.address`（解析器从「到XX取」提取，可编辑补填）；
  - 「快递驿站」= `matchedName(in: [address, rawMessage])` 实时匹配值，**只读不可手改、不落库**；只读态匹配不到整行隐藏，编辑态显「未识别」弱化占位。
  - 门店名（如韵达加盟店「林成驾校店」）千变万化不进固定词表，匹配不到即无驿站，卡片走 courier 兜底，属规则行为。
- 顺序：取件码 → 取件平台 → 快递公司 → 快递驿站 → 取件地址 → 货架号 → 运单号 → 尾号 → 添加时间。
- **编辑态所有字段恒显**（主人 10-15 13:27 定）：`editableBlock` 显示条件 = `required || 有值 || 编辑态`；运单号/尾号仍只读（10-14 口径），空值编辑态显「未识别」占位。

## 快递管理页（2026-10-14，原「支持的快递」改名）
- `CourierGalleryView` = 品牌画廊 + 驿站分类网格首位特殊格。**顶部列表/FAB 已撤**（主人 23:52 定稿：融进网格）。
- 驿站分类网格顺序：第一格「添加驿站」= 圆角矩形（54pt，accent 淡底 0.12）+ 中心 26pt 十字 → 自定义驿站格（CourierLogo 兜底图标，点按弹删除确认）→ 内置品牌。计数 = 内置+自定义。
- 🔴 LazyVGrid 格子**必须与 brandCell 同构**（VStack：54pt 方块 + overlay + 26pt 双行文字位）；复杂版式（ZStack 嵌套/offset 角标/虚线 overlay/contentShape）会让 ideal size 算错、整格跳过不渲染。
- SCREEN 脚手架：`courierGallery`。预置自定义名验证：`simctl spawn <udid> defaults write com.jikezhang.codeclip station.customNames -array "名字"`。
- 2026-10-15 补 4 个官方图标 asset（均 640×640 入 Assets.xcassets/Brands/ 并在 CourierBrand.swift 挂 asset 字段）：喵站 brand-miaozhan、多多代收点 brand-duoduodaishou、韵达快递超市 brand-yundakuaichaoshi、收件宝 brand-shoujianbao。⚠️ 主人给的 `取件宝.JPEG` 实为「收件宝」条目（文件名口误，图与品牌均为收件宝）。

## 地图导航（2026-10-14 方案 B，免费）
- `Views/AddressMapCard.swift`：详情页取件码卡下方，MapKit 迷你预览（150pt）+「导航」玻璃钮；点地址/地图/钮同链路：CLGeocoder 地理编码 → 有坐标 `MKMapItem.openInMaps(walking)`，失败兜底 `maps.apple.com/?q=`。Apple 禁止第三方内嵌实时导航，跳系统地图是唯一免费路。
- 短信库入口已下线（`SmsLibraryView.swift` 删除，Model 层 `SmsLibrary.swift` 保留服务 SampleData 预置）；语料已落盘项目根 `短信语料库_v1.md`（449 段/175 命中/274 拒/60 去重基线，PickupParser 回归测试用）。



## 短信库（SmsLibrary）
- 单一数据源：`Models/SmsLibrary.swift` 内嵌真实短信语料，同时服务「短信库」页展示 + SampleData 首装预置（60 条去重取件记录：175 命中 / 449 段 / 274 非取件正确拒绝）。
- 生成脚本 `/tmp/gen_smslib.py`（语料源 `/tmp/sms_raw.txt`，注意 /tmp 重启会清）。
- Swift 踩坑：Xcode-beta 对多行 raw string `#"..."#` 有编译 bug，用普通多行 `"""..."""`（收尾独占一行）；`Color.quaternary` 在该 SDK 返回 `some ShapeStyle`，不能与 `Color` 混三元；iOS 27 SDK 的 `UIColor.tertiaryLabelColor` 已更名 `tertiaryLabel`。
