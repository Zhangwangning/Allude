# 组合框

- 来源：https://developer.apple.com/cn/design/human-interface-guidelines/combo-boxes
- 抓取：2026-11-21，正文取自 Apple 文档 JSON（同上路径 + `.json`）
- 说明：官方原文，除本头注未改写。

---

组合框将文本栏和下拉式按钮组合在一个控制中。

用户可以将自定义值输入到栏位中，也可以点按按钮从预定义值列表中进行选择。用户输入自定义值时，该值不会添加到选项列表中。

## 最佳实践

使用列表中有意义的默认值填充栏位。虽然栏位默认可以为空，但最好让默认值引用隐藏选项。默认值不必是列表中的第一项。

使用介绍性标签以让用户知道所期待的项目类型。一般来说，标签采用标题式大写，并以冒号结尾。相关指南，请参阅labels。

提供相关选项。用户期望能够输入自定义值，也喜欢从最有可能的选项列表中进行选择带来的便利。

确保列表项的宽度不会超过文本栏。如果项目太宽，文本栏可能会将其截断，导致用户难以阅读。

有关指南，请参阅text-fields和pull-down-buttons。

## 平台考量因素

在 iOS、iPadOS、Apple tvOS、visionOS 或 watchOS 中不受支持。

## 资源

#### 相关内容

text-fields

pull-down-buttons

#### 开发者文档

NSComboBox — AppKit
