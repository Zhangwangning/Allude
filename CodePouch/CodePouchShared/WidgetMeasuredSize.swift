import SwiftUI
import WidgetKit

// MARK: - 小组件真实尺寸记录（2026-11-08）
//
// 背景：Apple 的桌面小组件尺寸是**按屏宽比例**算的（没有公开的 pt 表），
// 所以设置页里的「效果预览」想和真机一致，只能问系统要。
// 这个文件做两件事：
//   1. 小组件进程里用 `WidgetSizeProbe` 量出当前尺寸，写进 App Group；
//   2. 设置页读回这份尺寸画预览；没有记录时才退回按屏宽等比估算。

enum WidgetMeasuredSize {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: PickupStorage.appGroupID) ?? .standard
    }

    private static func key(_ family: String) -> String { "codeclip.widgetSize.\(family)" }

    /// 记录一次实测尺寸（单位 pt）
    static func record(_ size: CGSize, family: String) {
        guard size.width > 1, size.height > 1 else { return }
        defaults.set([Double(size.width), Double(size.height)], forKey: key(family))
    }

    /// 读回实测尺寸；没有记录返回 nil
    static func load(family: String) -> CGSize? {
        guard let pair = defaults.array(forKey: key(family)) as? [Double], pair.count == 2 else {
            return nil
        }
        return CGSize(width: pair[0], height: pair[1])
    }
}

/// 静默探针：不画任何东西，只把系统给的尺寸记下来。
/// 不设 hit-testing，不影响小组件交互。
struct WidgetSizeProbe: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    WidgetMeasuredSize.record(proxy.size,
                                              family: WidgetPageSize.key(family))
                }
                .onChange(of: proxy.size) { _, newValue in
                    WidgetMeasuredSize.record(newValue,
                                              family: WidgetPageSize.key(family))
                }
        }
        .allowsHitTesting(false)
    }
}
