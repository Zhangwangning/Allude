# 图像视图

- 来源：https://developer.apple.com/cn/design/human-interface-guidelines/image-views
- 抓取：2026-11-21，正文取自 Apple 文档 JSON（同上路径 + `.json`）
- 说明：官方原文，除本头注未改写。

---

图像视图在透明或不透明背景上显示单张图像（某些情况下显示图像的动态序列）。

在图像视图内，你可以拉伸、缩放图像，调整图像大小以适合，或者将图像固定到特定位置。图像视图通常不可交互。

## 最佳实践

在主要用途是仅显示图像时使用图像视图。在你可能想要使用交互式图像这种少数情况下，请配置系统提供的buttons来显示图像，而非将按钮行为添加到图像视图。

如果想在你的界面中显示图标，请考虑使用符号或界面图标，而非图像视图。sf-symbols提供大量精简的矢量图，可使用各种颜色和不透明度进行渲染。icons（也称为图形或模板图像）通常是位图图像，其中的非透明像素可接收颜色。符号和界面图标都可使用用户选取的强调色。

## 内容

图像视图可包含各种格式（如 PNG、JPEG 和 PDF）的丰富图像数据。有关更多指导，请参阅images。

在图像上叠加文本时请小心。在图像上合成文本可能会同时降低图像的清晰度和文本的可读性。为帮助改进结果，请确保文本和图像之间形成合理对比，并设法使文本对象突出显示，如添加文本阴影或背景层。

致力于为动态序列中的所有图像使用一致的大小。预缩放图像以适合视图时，系统不需要执行任何缩放操作。在系统必须进行缩放的情况下，当所有图像的大小和形状都相同时效果通常最佳。

## 平台考量因素

无针对 iOS 或 iPadOS 的额外考量因素。

### macOS

如果你的 App 需要可编辑的图像视图，请使用图像池。image-wells是支持拷贝、粘贴、拖移和使用 Delete 键清除其内容的图像视图。

使用图像按钮而非图像视图来制作可点按的图像。buttons#Image-buttons包含图像或图标，显示在视图中并且会瞬时发起 App 特定的操作。

### Apple tvOS

许多 Apple tvOS 图像组合了带有透明度的多个层，以带来深度感。有关指南，请参阅images#Layered-images。

### visionOS

visionOS App 中的窗口及游戏可使用图像视图显示 2D 和立体图像以及空间照片。如果 App 使用 RealityKit，你还可以在图像视图之外将任意类型的图像显示在 3D 内容旁边，或者从现有 2D 图像生成空间场景。有关设计指南，请参阅images#visionOS；有关开发者指南，请参阅 ImagePresentationComponent。

有关在窗口或视体中呈现其他 3D 内容的指南，请参阅windows#visionOS。

### watchOS

尽可能使用 SwiftUI 创建动画。你也可以根据需要使用 WatchKit 为图像元素内的图像序列添加动画。有关开发者指南，请参阅 WKImageAnimatable。

## 资源

#### 相关内容

images

image-wells

buttons#Image-buttons

sf-symbols

#### 开发者文档

Image — SwiftUI

UIImageView — UIKit

NSImageView — AppKit

#### 视频

- doc://com.apple.documentation/videos/play/wwdc2023/10181
- doc://com.apple.documentation/videos/play/wwdc2021/10021

## 更改日志

| 日期 | 更改内容 |
| 2023 年 6 月 21 日 | 更新以包括针对 visionOS 的指南。 |
