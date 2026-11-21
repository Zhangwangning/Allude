# 针对 iOS 设计

- 来源：https://developer.apple.com/cn/design/human-interface-guidelines/designing-for-ios
- 抓取：2026-11-21，正文取自 Apple 文档 JSON（同上路径 + `.json`）
- 说明：官方原文，除本头注未改写。

---

用户依赖 iPhone 随时随地保持联系、玩游戏、观看媒体、完成各种任务和追踪个人数据。

当你着手为 iOS 设计 App 或游戏时，首先要了解以下区分 iOS 使用体验的基本设备特征和模式。利用这些特征和模式来指导你的设计决策，可以帮助你制作出 iPhone 用户喜爱的 App 或游戏。

显示屏。iPhone 配备高分辨率的中等大小显示屏。

人体工程学。用户通常用单手或双手握住 iPhone 进行交互，并根据需要在横屏和竖屏间切换。与设备交互时的视距往往不会超过 30 到 60 厘米（1 到 2 英尺）。

输入。多点触控gestures、virtual-keyboards和siri控制可让用户随时执行各种操作和完成有意义的任务。此外，用户通常想让 App 使用他们的privacy和来自设备gyro-and-accelerometer的输入，可能还想参与spatial-interactions。

App 交互。用户有时只花一两分钟来检查日程或社交媒体更新、追踪数据或发信息，而有时也会花一个小时或更长时间浏览网页、玩游戏或欣赏媒体。用户通常会同时打开多个 App，并喜欢在 App 间频繁切换。

系统功能。iOS 提供了一些功能，帮助用户以熟悉且一致的方式与系统和 App 交互。

- widgets

- home-screen-quick-actions

- searching

- siri#Shortcuts-and-suggestions

- activity-views

## 最佳实践

出色的 iPhone 使用体验整合了用户最看重的平台和设备功能。为使你的设计让 iOS 用户感到自在，请优先考虑以下方法来整合这些特性和功能。

- 限制屏幕控制的数量，同时让用户以最少的交互来发现次要细节和操作，从而专注于主要任务和内容。

- 无缝适配外观变化，如设备方向、深色模式和动态字体，让用户选择最适合他们的配置。

- 支持与用户通常手持设备的方式相适应的交互。例如，将控制放在显示屏中间或底部区域时，用户往往可以更轻易地触及，因此让用户可轻扫返回或在列表行中发起操作显得尤为重要。

- 在用户允许的情况下，整合可通过平台功能获取的信息，无需用户输入数据，以增强使用体验。例如，你可能会接受付款，通过生物识别认证提供安全性，或者提供使用设备位置的功能。

## 资源

#### 相关内容

#ios-apps

#### 开发者文档

#### 视频

- doc://com.apple.documentation/videos/play/wwdc2025/219
- doc://com.apple.documentation/videos/play/wwdc2025/356
