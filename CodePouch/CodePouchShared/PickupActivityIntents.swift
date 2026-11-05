import AppIntents
import ActivityKit
import Foundation

// MARK: ============================================================================
// 锁屏卡的「上一件 / 下一件」（2026-11-05）
//
// Live Activity 从 iOS 17 起支持交互：卡面上的 `Button(intent:)` 被点后，
// 系统会**在后台**执行这个 App Intent，不需要打开 App，也不需要解锁。
//
// 放在 shared 层：卡面视图（编译进小组件扩展）要能引用到这两个类型。
// 真正干活的数据（PickupStore）在 App target，控制器通过 `pendingProvider`
// 注入 —— 扩展进程里没有这份数据，点了就是空操作，不会崩。
// ============================================================================

/// 临时诊断：翻页 Intent 到底有没有被调用、跑在哪个进程（写 App Group，App 与扩展都能读）
enum IntentDebug {
    private static let file = "intent-debug.log"
    private static var url: URL? {
        guard let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: PickupStorage.appGroupID) else { return nil }
        return base.appendingPathComponent(file)
    }
    static func trace(_ line: String) {
        guard let url else { return }
        let text = "[\(ISO8601DateFormatter().string(from: Date()))] \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(Data(text.utf8)); try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct NextPickupIntent: AppIntent {
    static var title: LocalizedStringResource { "显示下一件待取" }
    static var description: IntentDescription {
        IntentDescription("在锁屏实时活动里切换到下一件待取快递。")
    }
    /// 后台执行：不把 App 拉到前台（点箭头只想翻页，不想跳走）
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult {
        IntentDebug.trace("next tapped; provider=\(PickupActivityController.pendingProvider != nil) "
                          + "activities=\(Activity<PickupActivityAttributes>.activities.count)")
        await PickupActivityController.cycle(offset: 1)
        return .result()
    }
}

struct PreviousPickupIntent: AppIntent {
    static var title: LocalizedStringResource { "显示上一件待取" }
    static var description: IntentDescription {
        IntentDescription("在锁屏实时活动里切换到上一件待取快递。")
    }
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult {
        IntentDebug.trace("prev tapped; provider=\(PickupActivityController.pendingProvider != nil) "
                          + "activities=\(Activity<PickupActivityAttributes>.activities.count)")
        await PickupActivityController.cycle(offset: -1)
        return .result()
    }
}
