import Foundation
import UIKit
import UserNotifications

// MARK: ============================================================================
// 通知的前台呈现策略
//
// **前台一律不弹横幅**：App 就在眼前、列表实时更新了，再叠一条横幅是重复打扰
// （添加成功的反馈在 App 内已经有浮层提示）。真正需要横幅的是**后台**场景 ——
// 快捷指令自动化 / 截图动作被系统静默拉起时，用户正在别的 App 里。
//
// ⚠️ 与 `PickupNotifier` 分开放的原因：那边刻意不 import UIKit，好让
// `tools/notify-check/` 能在 macOS 上直接编译它做文案断言。UIApplication 只在这里用。
//
// ⚠️ 必须尽早 `install()`（见 `CodeClipApp.init`）：自动化触发时 App 是被系统
// **静默拉起**的，若 delegate 还没挂上，`willPresent` 不会被回调，前台抑制就失效了。
// ============================================================================

final class PickupNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {

    static let shared = PickupNotificationPresenter()

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler:
                                   @escaping (UNNotificationPresentationOptions) -> Void) {
        // applicationState 必须在主线程读
        DispatchQueue.main.async {
            let isForeground = UIApplication.shared.applicationState == .active
            completionHandler(isForeground ? [] : [.banner, .sound, .list])
        }
    }

    /// 用户点了通知 → 把 `recordID` 交给 `NotificationRouter`，由视图去打开详情
    /// （2026-10-25 补：此前只有 `willPresent`，`recordID` 写了却没人读）。
    ///
    /// 异步版本：iOS 15+ 若实现了 `didReceive ... async`，系统优先走它，
    /// 不必再写 completionHandler 那版。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info["recordID"] as? String,
              let id = UUID(uuidString: raw) else { return }
        await MainActor.run { NotificationRouter.shared.pendingRecordID = id }
    }
}
