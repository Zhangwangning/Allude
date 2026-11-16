import Foundation
import CoreLocation
import UserNotifications
import SwiftUI

extension Notification.Name {
    static let stationLocationAuthDidChange = Notification.Name("allude.stationLocationAuthDidChange")
}

// MARK: - 到达提醒 · 地理围栏（2026-11-16 主人：实验室功能）
//
// 口径：
//   · 只在**用户主动打开「到达提醒」**且为 Allude Pro 时才申请「始终允许」定位；
//   · 只监视为数不多的驿站圆形区域（系统上限 20 个），不连续取位置、不记轨迹；
//   · 进入区域时读本机共享文件，**该驿站还有待取件才推通知**，没件不打扰；
//   · 位置只用于系统地理围栏判断，全部在本机，不上传、不联网。
//
// ⚠️ 实验性：系统围栏有延迟、低电量 / 无网络 / 定位精度差时可能不触发，
//    界面上必须如实说明（见 NotificationSettingsView 的实验室分组）。

final class StationLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = StationLocationService()

    private static let regionPrefix = "allude.station."
    private static let arrivalEnabledKey = "allude.arrivalReminderEnabled"
    private static let lastArrivalKeyPrefix = "allude.arrival.last."
    /// 同一驿站 30 分钟内不重复打扰（系统 didEnterRegion 偶尔会连发）
    private static let arrivalCooldown: TimeInterval = 30 * 60

    private let manager = CLLocationManager()
    /// 「用当前位置」的一次性定位回调
    private var oneShot: ((CLLocationCoordinate2D?) -> Void)?

    /// 到达提醒开关（实验室 + Allude Pro）。
    static var isArrivalReminderEnabled: Bool {
        get { UserDefaults.standard.object(forKey: arrivalEnabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: arrivalEnabledKey) }
    }

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    /// App 启动时调一次。
    /// 🔴 系统围栏事件能在 App 被杀之后重新把进程拉起来，只有启动即建好
    ///    manager + delegate 才收得到；靠页面懒加载会漏掉后台那一次。
    func bootstrap() {
        authorizationStatus = manager.authorizationStatus
        syncRegions()
    }

    // MARK: 权限

    func setArrivalEnabled(_ enabled: Bool) {
        Self.isArrivalReminderEnabled = enabled
        if enabled { requestAlwaysAuthorization() }
        syncRegions()
    }

    func requestAlwaysAuthorization() {
        // 截图脚手架：与通知权限同一套口径 —— 命令行点不掉系统授权弹窗，
        // 有 SCREEN / SKIP_PERM 时一律不弹，否则整页截图会被糊住。
        let env = ProcessInfo.processInfo.environment
        guard env["SKIP_PERM"] == nil, env["SCREEN"] == nil else { return }
        guard CLLocationManager.locationServicesEnabled() else { return }
        switch manager.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            // 已是 WhenInUse 时再申请一次 = 升级为 Always
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    /// 编辑页「用当前位置」：只要 WhenInUse 就够，不碰 Always。
    func requestCurrentCoordinate(_ completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        oneShot = completion
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            finishOneShot(nil)
        }
    }

    private func finishOneShot(_ coordinate: CLLocationCoordinate2D?) {
        let callback = oneShot
        oneShot = nil
        DispatchQueue.main.async { callback?(coordinate) }
    }

    // MARK: 围栏重排

    /// 按「开关 + 权益 + 权限 + 已启用驿站位置」重排监控区域。
    /// iOS 同时最多 20 个区域；超出按名称排序取前 20（界面会提示上限）。
    func syncRegions() {
        for region in manager.monitoredRegions where region.identifier.hasPrefix(Self.regionPrefix) {
            manager.stopMonitoring(for: region)
        }
        // 🔴 老大 2026-11-16 补充：到达提醒是 Allude Pro 功能。
        //    降级 / 权益过期 / 关开关 / 权限不是 Always，一律把围栏全撤干净。
        guard EntitlementSnapshot.licensedPro,
              Self.isArrivalReminderEnabled,
              manager.authorizationStatus == .authorizedAlways else { return }

        let store = StationLocationStore.shared
        for name in store.enabledNames.prefix(20) {
            guard let loc = store.location(for: name) else { continue }
            let maxRadius = manager.maximumRegionMonitoringDistance
            let radius = min(max(loc.radius, 100), maxRadius > 0 ? maxRadius : loc.radius)
            let region = CLCircularRegion(center: loc.coordinate,
                                          radius: radius,
                                          identifier: Self.regionPrefix + name)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async {
            self.authorizationStatus = status
            NotificationCenter.default.post(name: .stationLocationAuthDidChange, object: nil)
        }
        // 编辑页那次一次性定位，等授权下来再发
        if oneShot != nil {
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                finishOneShot(nil)
            default:
                break
            }
        }
        syncRegions()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard oneShot != nil else { return }
        finishOneShot(locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard oneShot != nil else { return }
        finishOneShot(nil)
    }

    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        // 刚启动监控时人若已经在区域内，系统不保证补发 didEnterRegion；
        // 主动查一次状态，避免「站在驿站里开了功能却一声不响」。
        guard let circular = region as? CLCircularRegion else { return }
        manager.requestState(for: circular)
    }

    func locationManager(_ manager: CLLocationManager,
                         didDetermineState state: CLRegionState,
                         for region: CLRegion) {
        guard state == .inside, region.identifier.hasPrefix(Self.regionPrefix) else { return }
        notifyArrival(for: String(region.identifier.dropFirst(Self.regionPrefix.count)))
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix(Self.regionPrefix) else { return }
        notifyArrival(for: String(region.identifier.dropFirst(Self.regionPrefix.count)))
    }

    // MARK: 到达通知

    private func notifyArrival(for stationName: String) {
        guard EntitlementSnapshot.licensedPro, Self.isArrivalReminderEnabled else { return }

        let defaults = UserDefaults.standard
        let key = Self.lastArrivalKeyPrefix + stationName
        let now = Date().timeIntervalSince1970
        guard now - defaults.double(forKey: key) > Self.arrivalCooldown else { return }

        let pending = PickupStorage.load().filter { !$0.isPickedUp }
        let hits = pending.filter { Self.matches($0, stationName: stationName) }
        // 老大要求：**存在该驿站的待取件信息**才推，没件不打扰
        guard !hits.isEmpty else { return }
        defaults.set(now, forKey: key)

        let content = UNMutableNotificationContent()
        content.title = "到 \(stationName) 了，有 \(hits.count) 件待取"
        // 空字段不凑行：这里只列最多 3 个取件码，用户到店看码就够
        content.body = hits.prefix(3).map(\.code).joined(separator: " · ")
        content.sound = .default
        content.threadIdentifier = PickupNotifier.threadID
        content.userInfo = ["kind": "arrival", "station": stationName]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "com.jikezhang.allude.arrival.\(UUID().uuidString)",
                                  content: content,
                                  trigger: nil))
    }

    /// 一条记录是否属于这个驿站。
    /// 模型复核的覆盖值优先，其次走驿站名匹配（含用户自定义名），
    /// 最后用平台 / 地址做包含兜底 —— 有些短信只在地址里写了驿站名。
    private static func matches(_ record: PickupRecord, stationName: String) -> Bool {
        if record.stationOverride == stationName { return true }
        if StationDirectory.shared.matchedName(in: [record.rawMessage]) == stationName { return true }
        return record.company.localizedCaseInsensitiveContains(stationName)
            || record.address.localizedCaseInsensitiveContains(stationName)
    }
}
