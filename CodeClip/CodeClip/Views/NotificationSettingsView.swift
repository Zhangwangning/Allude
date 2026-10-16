import SwiftUI
import UserNotifications

// MARK: ============================================================================
// 通知提醒（我的 › 设置 › 二级页）
//
// 回答两个问题：
//   1. **东西来了要说一声** —— 入库通知，开关一拨立即生效；
//   2. **东西放久了要催一下** —— 取件提醒，分两类：
//      · **定期**：每天固定时间看一眼还有几件没取（与单条记录无关）；
//      · **不定期**：某条入库 N 小时还没取，单独催一次（与单条记录绑定）。
//
// ⚠️ 全页沿用工程口径：`ObservableObject` + `@StateObject`，不用 `@State` 宏。
// ============================================================================

final class ReminderSettingsModel: ObservableObject {
    /// 入库通知开关（App 内）
    @Published var isEnabled = PickupNotifier.isEnabled
    /// 系统通知权限。与 App 内开关可能不一致，分开显示（静默失效的经典坑）。
    @Published var authStatus: UNAuthorizationStatus = .notDetermined

    @Published var dailyEnabled = PickupNotifier.isDailyReminderEnabled
    /// DatePicker 只吃 `Date` —— 用「今天」垫底、只取时分的桥接值。
    @Published var dailyTime: Date
    @Published var pendingEnabled = PickupNotifier.isPendingReminderEnabled
    @Published var pendingHours = PickupNotifier.pendingReminderHours

    init() {
        dailyTime = Self.bridge(hour: PickupNotifier.dailyReminderHour,
                                minute: PickupNotifier.dailyReminderMinute)
    }

    private static func bridge(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
    }

    func refresh() {
        isEnabled = PickupNotifier.isEnabled
        dailyEnabled = PickupNotifier.isDailyReminderEnabled
        pendingEnabled = PickupNotifier.isPendingReminderEnabled
        PickupNotifier.queryAuthorizationStatus { [weak self] status in
            self?.authStatus = status
        }
    }

    func setEnabled(_ value: Bool) {
        PickupNotifier.isEnabled = value
        if value { PickupNotifier.requestAuthorizationIfNeeded() }
        refresh()
    }

    func setDailyEnabled(_ value: Bool) {
        PickupNotifier.isDailyReminderEnabled = value
        dailyEnabled = value
        PickupNotifier.rescheduleDailyReminder()
    }

    func setDailyTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        PickupNotifier.dailyReminderHour = components.hour ?? 20
        PickupNotifier.dailyReminderMinute = components.minute ?? 0
        dailyTime = date
        PickupNotifier.rescheduleDailyReminder()
    }

    func setPendingEnabled(_ value: Bool) {
        PickupNotifier.isPendingReminderEnabled = value
        pendingEnabled = value
        PickupNotifier.rescheduleAllPendingReminders()
    }

    func setPendingHours(_ value: Int) {
        PickupNotifier.pendingReminderHours = value
        pendingHours = value
        PickupNotifier.rescheduleAllPendingReminders()
    }
}

// MARK: - 页面

struct NotificationSettingsView: View {
    @EnvironmentObject private var store: PickupStore
    @StateObject private var model = ReminderSettingsModel()

    /// 不定期提醒的可选等待时长（小时）。
    private let hourOptions = [3, 6, 12, 24, 48]

    var body: some View {
        ScrollView {
            // 组间距 24：iOS 设置页的分组留白比卡内行距大得多，
            // 分组标题 + 卡 + 卡外说明构成一个"块"，块与块之间必须能一眼断开。
            VStack(spacing: 24) {
                toggleSection
                dailySection
                pendingSection
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 14)
            .padding(.bottom, 60)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("通知提醒")
        .cloaksTabBar()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.refresh() }
    }

    // MARK: 入库通知

    private var toggleSection: some View {
        // 第一组也带组标题：三组（入库通知 / 定期 / 不定期）节奏一致，
        // 否则顶上一块无标题的卡会像是从上一页漏下来的。
        SettingsGroup(title: "入库通知",
                      note: "取件信息入库后弹一条通知：标题是取件码，下面是平台与地址。") {
            SettingsPlainRow(title: "添加后发送通知") {
                Toggle("", isOn: Binding(get: { model.isEnabled },
                                         set: { model.setEnabled($0) }))
                    .labelsHidden()
                    .tint(AppTheme.doneTint)
            }

            // 🔴 App 内开关开着、系统权限却是关的 —— 静默失效要摆在脸上。
            if model.isEnabled && model.authStatus == .denied {
                SettingsDivider(style: .plain)
                systemDeniedHint
            }
        }
    }

    private var systemDeniedHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.pendingTint)

            VStack(alignment: .leading, spacing: 3) {
                Text("系统的「通知」权限被关掉了")
                    .font(.caption.weight(.medium))
                Text("上面这个开关开着也不会弹。需要到系统设置里把「码夹」的通知打开。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("去开启") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: 定期提醒

    private var dailySection: some View {
        SettingsGroup(title: "取件提醒 · 定期",
                      note: "每天固定时间数一遍待取件，有没取的才响；全部取完不会打扰。") {
            SettingsPlainRow(title: "每天定时提醒") {
                Toggle("", isOn: Binding(get: { model.dailyEnabled },
                                         set: { model.setDailyEnabled($0) }))
                    .labelsHidden()
                    .tint(AppTheme.doneTint)
            }

            if model.dailyEnabled {
                SettingsDivider(style: .plain)

                SettingsPlainRow(title: "提醒时间") {
                    DatePicker("",
                               selection: Binding(get: { model.dailyTime },
                                                  set: { model.setDailyTime($0) }),
                               displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
            }
        }
    }

    // MARK: 不定期提醒

    private var pendingSection: some View {
        SettingsGroup(title: "取件提醒 · 不定期",
                      note: "入库超过设定时长还没取，单独催一次；取走或删除后自动撤回。") {
            SettingsPlainRow(title: "超时未取提醒") {
                Toggle("", isOn: Binding(get: { model.pendingEnabled },
                                         set: { model.setPendingEnabled($0) }))
                    .labelsHidden()
                    .tint(AppTheme.doneTint)
            }

            if model.pendingEnabled {
                SettingsDivider(style: .plain)

                SettingsPlainRow(title: "等待时长") {
                    // 5 档固定时长：自由输入会把「37 小时」这类值排进
                    // UNTimeIntervalNotificationTrigger，数字对用户毫无意义。
                    //
                    // 用 `Menu` + 自绘值标签（而不是 `Picker(.menu)`）：
                    // 菜单样式的 Picker 在行内可压缩，会把「24 小时」折成两行
                    // —— 真机上就是主人看到的"时间错位"。
                    Menu {
                        ForEach(hourOptions, id: \.self) { hours in
                            Button {
                                model.setPendingHours(hours)
                            } label: {
                                if hours == model.pendingHours {
                                    Label("\(hours) 小时", systemImage: "checkmark")
                                } else {
                                    Text("\(hours) 小时")
                                }
                            }
                        }
                    } label: {
                        SettingsValueLabel(text: "\(model.pendingHours) 小时")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
