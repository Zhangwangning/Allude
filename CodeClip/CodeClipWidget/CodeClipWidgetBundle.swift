import WidgetKit
import SwiftUI

// MARK: - 小组件扩展入口
//
// 单一 @main 入口。快递取件码小组件独立注册。
//
// 实时活动（锁屏卡片 + 灵动岛）也注册在这里 —— Live Activity 的 UI 必须
// 由 widget extension 提供，不能放在宿主 App 内。

@main
struct CodeClipWidgetBundle: WidgetBundle {
    var body: some Widget {
        PickupWidget()
        PickupLiveActivity()
    }
}
