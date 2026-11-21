# 标签

- 来源：https://developer.apple.com/cn/design/human-interface-guidelines/labels
- 抓取：2026-11-21，正文取自 Apple 文档 JSON（同上路径 + `.json`）
- 说明：官方原文，除本头注未改写。

---

标签是一段可供用户阅读的静态文本，通常可以拷贝，但不能编辑。

标签用于在界面各处、按钮、菜单项和视图中显示文本，以帮助用户了解当前上下文和接下来可执行的操作。

术语标签指可在各处显示的不可编辑文本。例如：

- 在按钮内，标签通常用于说明按钮的功能，如“编辑”、“取消”或“发送”。

- 在许多列表内，标签可描述每个项目，通常还配有符号或图像。

- 在视图内，标签可能会介绍控制或描述用户可在该视图中执行的常见操作或任务，以提供更多上下文。

> 为显示不可编辑的文本，SwiftUI 定义了两个组件： Label 和 Text。

以下指南可帮助你使用标签来显示文本。在某些情况下，特定组件（如buttons、menus以及lists-and-tables）的指南中包括使用文本的额外建议。

## 最佳实践

使用标签显示用户无需编辑的少量文本。如果需要让用户编辑少量文本，请使用text-fields。如果需要显示大量文本，并且可选择让用户编辑，请使用text-views。

首选系统字体。标签可显示纯文本或样式文本，还默认支持动态字体（可用时）。如果调整标签样式或使用自定义字体，请确保文本保持清晰可读。

使用系统提供的标签颜色来传达相对重要性。系统定义了四种标签颜色，它们的外观各不相同，可帮助你从视觉上为文本赋予不同级别的重要性。有关更多指南，请参阅color。

| 系统颜色 | 使用示例 | iOS、iPadOS、Apple tvOS、visionOS | macOS |
| 标签 | 主要信息 | label | labelColor |
| 二级标签 | 副标题或补充文本 | secondaryLabel | secondaryLabelColor |
| 三级标签 | 描述不可用项目或行为的文本 | tertiaryLabel | tertiaryLabelColor |
| 四级标签 | 水印文本 | quaternaryLabel | quaternaryLabelColor |

让有用的标签文本可选择。如果标签包含有用的信息（如错误信息、位置或 IP 地址），请考虑让用户选择这些信息以拷贝到其他位置。

## 平台考量因素

无针对 iOS、iPadOS、Apple tvOS 或 visionOS 的额外考量因素。

### macOS

> 若要在标签中显示不可编辑文本，请使用 NSTextField 的 isEditable 属性。

### watchOS

日期和时间文本组件（如下方左图所示）显示当前日期和/或当前时间。你可以将日期文本组件配置为使用各种格式、历法和时区。倒数计时器文本组件（如下方右图所示）显示倒计时或正计时的精确计时器。你可以将计时器文本组件配置为以各种格式显示其计时值。

使用系统提供的日期和计时器文本组件时，watchOS 会自动调整标签的呈现方式以适合可用空间。系统也无需 App 进一步输入即可更新内容。

考虑在复杂功能中使用日期和计时器组件。有关设计指南，请参阅complications；有关开发者指南，请参阅 Text。

## 资源

#### 相关内容

text-fields

text-views

#### 开发者文档

Label — SwiftUI

Text — SwiftUI

UILabel — UIKit

NSTextField — AppKit

## 更改日志

| 日期 | 更改内容 |
| 2023 年 6 月 5 日 | 更新了指南以反映 watchOS 10 中的变化。 |
