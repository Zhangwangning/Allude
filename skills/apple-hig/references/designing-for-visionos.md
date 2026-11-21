# 针对 visionOS 设计

- 来源：https://developer.apple.com/cn/design/human-interface-guidelines/designing-for-visionos
- 抓取：2026-11-21，正文取自 Apple 文档 JSON（同上路径 + `.json`）
- 说明：官方原文，除本头注未改写。

---

用户佩戴 Apple Vision Pro 时会进入无边际的 3D 空间，在这里他们可以与你的 App 或游戏交互，同时与四周保持联系。

当你着手为 visionOS 设计 App 或游戏时，首先要了解该平台特有的基本设备特征和模式。利用这些特征和模式来指导你的设计决策，帮助你打造出富有吸引力的沉浸式体验。

空间。Apple Vision Pro 提供了无限的画布，用户可在其中查看windows、windows#visionOS-volumes和 3D 对象等虚拟内容，还可选择进入仿佛置身于不同地点的深度沉浸式体验。

沉浸。在 visionOS App 中，用户可在不同的immersive-experiences程度之间流畅转换。App 默认在共享空间中启动，在此空间中多个 App 可并排运行，用户可打开、关闭窗口以及调整窗口的位置。用户还可选择将 App 转换到全空间，在此空间中只会运行这一个 App。  在全空间 App 中，用户可查看与四周融合的 3D 内容，打开传送门以查看其他地点，或者进入另一个世界。

透视。immersive-experiences#Immersion-and-passthrough提供了来自设备外部相机的实时视频，帮助用户在与虚拟内容交互的同时还可看到其实际四周。用户想看到更多或更少的四周时，可使用digital-crown控制透视量。

空间音频。Apple Vision Pro 结合听觉和视觉感知技术来为用户四周的声波特征建模，可自动使音频在其空间中听起来自然。App 从用户处获得访问其四周信息的许可后，可微调playing-audio#visionOS以使自定义体验更加身临其境。

眼睛和手。一般而言，用户通过用eyes注视虚拟对象并使用轻点等非直接gestures#visionOS将其激活来执行大部分操作。用户还可以使用单指轻触等直接手势来与虚拟对象交互。

人体工程学。佩戴 Apple Vision Pro 时，用户完全依赖设备相机来看到真实和虚拟的一切事物，因此保持视觉舒适性至关重要。为帮助保持舒适，系统会自动相对于佩戴者的头部放置内容，无论用户的身高如何或者是坐着、站着还是躺着。visionOS 会将内容带到用户眼前（而非让用户移动来触及内容），因此用户可在保持静止不动的状态下与 App 和游戏交互。

无障碍。Apple Vision Pro 支持“旁白”、“切换控制”、“停留控制”、“引导式访问”、“头控指针”等许多accessibility技术，因此用户可使用适合自己的交互方式。与所有平台一样，在 visionOS 中，系统提供的用户界面组件默认内建无障碍支持，系统框架也为你提供了增强 App 或游戏中无障碍的方式。

> 为 Apple Vision Pro 构建 App 时，请务必考虑设备的独有特征及其空间计算环境，并特别注意用户的安全；有关这些特征的更多详细信息，请参阅apple-vision-pro。例如，在驾车或操控重型机械时不应使用 Apple Vision Pro。在阳台、街道、楼梯或其他潜在危险地点附近移动时，也不应使用该设备。请注意，Apple Vision Pro 仅供年满 13 岁的用户群体佩戴和使用。

## 最佳实践

优秀的 visionOS App 和游戏会让用户觉得容易上手且十分熟悉，同时其中的优美内容、扩展功能和引人入胜的冒险会为用户带来沉浸其中的非凡体验。

积极采用 Apple Vision Pro 的独特功能。充分利用空间、空间音频和沉浸来让你的体验身临其境，同时以让用户在设备上感到轻松自然的方式集成透视和通过眼睛和手进行的空间输入。

设计呈现 App 中最独特时刻的方式时，考虑不同的沉浸类型。你可以在以用户界面为中心的窗口式环境、全沉浸式环境或介于两者之间的某种环境中呈现体验。为 App 中的每个关键时刻找到最适合的最低沉浸程度，不要假设每个时刻都需要完全沉浸。

为以用户界面为中心的受限体验使用窗口。若要帮助用户执行标准任务，首选在空间中使用显示为平面并包含熟悉控制的标准windows#visionOS。在 visionOS 中，用户可将窗口重新放置在想要的任何位置，且系统的spatial-layout#Scale可帮助保持窗口内容无论远近都清晰易读。

优先考虑舒适性。若要帮助用户在与 App 或游戏交互时保持舒适和身体放松，请记住以下基本原则。

- 在用户的spatial-layout#Field-of-view内显示内容，并相对其头部放置。避免将内容放在用户必须转头或改变姿势才能进行交互的位置。

- 避免显示眼花缭乱、不和谐、过快或缺少静止参考系的motion#visionOS。

- 支持gestures#visionOS，让用户的手放在大腿或身侧时也能与 App 交互。

- 如果支持直接手势，请确保交互式内容不会距离过远，并且用户无需长时间与其交互。

- 用户处于全immersive-experiences中时，避免鼓励其过多移动。

帮助用户与他人共享活动。当你使用shareplay#visionOS支持共享活动时，用户可查看其他参与者的空间自影像，感觉就像大家都相聚在相同空间中一样。

## 资源

#### 相关内容

#visionos-apps

#### 开发者文档

creating-your-first-visionos-app

#### 视频

- doc://com.apple.documentation/videos/play/wwdc2024/10096
- doc://com.apple.documentation/videos/play/wwdc2024/10086
- doc://com.apple.documentation/videos/play/wwdc2023/10072

## 更改日志

| 日期 | 更改内容 |
| 2024 年 2 月 2 日 | 包括了《Apple Vision Pro 使用手册》链接。 |
| 2023 年 9 月 12 日 | 更新了介绍插图。 |
| 2023 年 6 月 21 日 | 新页面。 |
