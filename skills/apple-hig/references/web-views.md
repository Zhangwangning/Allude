# 网页视图

- 来源：https://developer.apple.com/cn/design/human-interface-guidelines/web-views
- 抓取：2026-11-21，正文取自 Apple 文档 JSON（同上路径 + `.json`）
- 说明：官方原文，除本头注未改写。

---

网页视图可直接在你的 App 内加载和显示丰富的网页内容，例如嵌入的 HTML 和网站。

例如，“邮件”使用网页视图显示邮件中的 HTML 内容。

## 最佳实践

适时支持向前和向后导航。网页视图支持向前和向后导航，但此行为默认不可用。如果用户有可能使用你的网页视图访问多个页面，请允许向前和向后导航，并提供用于发起此类功能的对应控制。

避免使用网页视图来构建网页浏览器。你可以使用网页视图让用户在不离开 App 环境的情况下短暂访问网站，但 Safari 浏览器仍是用户浏览网页的主要方式。不提倡多此一举地尝试在你的 App 中复制 Safari 浏览器的功能。

## 平台考量因素

无针对 iOS、iPadOS、macOS 或 visionOS 的额外考量因素。在 Apple tvOS 或 watchOS 中不受支持。

## 资源

#### 相关内容

#### 开发者文档

WKWebView — WebKit

#### 视频

- doc://com.apple.documentation/videos/play/wwdc2021/10032
