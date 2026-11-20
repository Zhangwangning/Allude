# Allude

[English](README.md) · **简体中文**

iOS 取件码收纳 App。**数据只在本机，不联网、不上传、不需要注册。**

App Store：上架准备中。源码就是本仓库，自行编译即可核对它到底有没有联网。

---

## 这是什么

把快递短信里的取件码抠出来，按取件地点归好，桌面小组件与实时活动能直接看到。

解析以规则为主：四套独立正则 + 优先级链，语料来自真实短信，回归基线可复跑。
规则没捞到某个字段时，由 Apple 端侧智能补一刀把结果补完整——**只填空、不覆盖**；
端侧智能不可用时自动退回纯规则，功能不受影响。

- SwiftUI，iOS 17 起。纯 Xcode 工程，**零第三方依赖、零 SPM 包**
- 唯一网络行为：StoreKit（只连 Apple），以及可选开启的「同步到**你自己的** iCloud」
- 没有开发者服务器，没有第三方 SDK，没有 API Key

## 怎么编

```bash
cd Allude
xcodebuild -project Allude.xcodeproj -scheme Allude \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/allude-verify build \
  CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS="-disable-sandbox"
```

`-disable-sandbox` 是给宏插件（`swift-plugin-server`）留子进程用的，不是修代码。
被沙箱包住时会抛一批**假错误**（典型是 `SwipeActionRow.swift` 里的 `'self' is immutable`），
那是工具链问题。

## 仓库里有什么（开发过程）

| 文件 | 内容 |
|---|---|
| `AGENTS.md` | 项目指令：硬规则、目录结构、字号档位、图标规范、发版链路、各模块口径 |
| `交接说明_dsh.md` | 完整交接文档：现状实测、三层目录、按重要度排的文件地图、已知问题 |
| `交接说明_workbuddy.md` | 更早期的一版交接记录 |
| `快递短信解析规格_V803.md` | 解析器规格：优先级链、三层误判闸门、字段口径 |
| `短信语料库_v1.md` | 514 段真实短信语料（已脱敏为各类运单形态） |
| `iPhone Duo 适配规范_v1.md`、`iPhone Duo 官方设计规范笔记_v1.md` | 折叠屏设计口径与官方 Tech Talks 笔记 |
| `产品与商业模式规格_v1.md` | 产品定位与功能边界 |
| `.workbuddy/memory/*.md` | 逐日开发记录：踩过的坑、当天的决策与理由 |
| `tools/` | 自检脚本：解析回归、驿站匹配、品牌表、去重、OCR 管线、单元断言 |

每个目录的 `main.swift` 文件头写了完整编译命令，例如：

```bash
# 解析回归（全量库，基线：识别 193/514、地址 192/514）
swiftc -O -o /tmp/parser-regression \
  Allude/Allude/Models/PickupParser.swift tools/parser-regression/main.swift && \
/tmp/parser-regression 短信语料库_v1.md
```

## 仓库里不放什么

- **不放 IPA**，不放构建产物（`build/`、`DerivedData/`）、不放描述文件
- **不放签名私钥**（`tools/license-gen/private-key.pem` 已在 `.gitignore`）
- 不放其他 App 的二进制产物

上架分发包只有一条路：Xcode Archive → App Store Connect。

## 署名

极客ZHANG · zhang_wangning@126.com

第三方标识（快递公司 / 取件点图标）只用于标识取件来源，版权归各品牌方，
不表示授权或合作。
