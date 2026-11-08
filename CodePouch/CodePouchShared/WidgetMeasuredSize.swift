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
    ///
    /// 🔴 2026-11-08：加合理性门槛。小组件的真实宽高都在 140–400pt 之间，
    /// 探针如果在别的容器里量到一条行、一个角标（几十 pt），写进去会让设置页
    /// 那张预览被压扁、内容叠在一起。宁可不要这条记录。
    static func record(_ size: CGSize, family: String) {
        guard size.width >= 120, size.height >= 120 else { return }
        defaults.set([Double(size.width), Double(size.height)], forKey: key(family))
    }

    /// 读回实测尺寸；没有记录、或与 `expected` 差得太离谱时返回 nil。
    ///
    /// 校验的意义：历史版本可能写进过脏数据（量到的是行/角标而不是整块），
    /// 一次脏数据就会让预览长期错位。超出 ±25% 就当没有。
    static func load(family: String, expected: CGSize) -> CGSize? {
        guard let pair = defaults.array(forKey: key(family)) as? [Double], pair.count == 2 else {
            return nil
        }
        let size = CGSize(width: pair[0], height: pair[1])
        guard expected.width > 0, expected.height > 0 else { return nil }
        let dw = abs(size.width - expected.width) / expected.width
        let dh = abs(size.height - expected.height) / expected.height
        guard dw <= 0.25, dh <= 0.25 else { return nil }
        return size
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
