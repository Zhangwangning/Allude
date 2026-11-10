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
        // 超时未取提醒属于Allude Pro：非 Pro 一律落回关闭态
        let allowed = value && EntitlementSnapshot.licensedPro
        PickupNotifier.isPendingReminderEnabled = allowed
        pendingEnabled = allowed
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
    /// 非 Pro 点「超时未取提醒」时直接弹订阅页（不显示任何加锁标志）
    @State private var showPaywall = false

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
        .navigationTitle("通知")
        .sheet(isPresented: $showPaywall) {
            NavigationStack { FullVersionView() }
        }
        .cloaksTabBar()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.refresh()
            // 截图脚手架 `HOURS_MENU=1`：把「等待时长」选单直接打开。
            // 命令行点不出 popover，没有这个入口就只能靠肉眼在真机上验。
            guard ProcessInfo.processInfo.environment["HOURS_MENU"] == "1" else { return }
            model.setPendingEnabled(true)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                showHoursMenu = true
            }
        }
    }

    // MARK: 入库通知

    private var toggleSection: some View {
        // 第一组也带组标题：三组（入库通知 / 定期 / 不定期）节奏一致，
        // 否则顶上一块无标题的卡会像是从上一页漏下来的。
        SettingsGroup(title: "入库通知",
                      note: "入库后弹一条：标题是取件码。") {
            SettingsPlainRow(title: "添加后发送通知") {
                Toggle("", isOn: Binding(get: { model.isEnabled },
                                         set: { model.setEnabled($0) }))
                    .labelsHidden()
                    .tint(AppTheme.accent)
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
                Text("上面这个开关开着也不会弹。需要到系统设置里把「Allude」的通知打开。")
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
        SettingsGroup(title: "提醒 · 每天固定",
                      note: "到点数一遍待取件，没取的才响。") {
            SettingsPlainRow(title: "每天定时提醒") {
                Toggle("", isOn: Binding(get: { model.dailyEnabled },
                                         set: { model.setDailyEnabled($0) }))
                    .labelsHidden()
                    .tint(AppTheme.accent)
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

    /// 等待时长的自绘菜单是否展开
    @State private var showHoursMenu = false

    /// 等待时长选单（自绘，替代系统 `Menu`）。
    ///
    /// 布局刻意与系统菜单区分开：**勾号贴最右端**、颜色用系统蓝
    /// （`Color(.systemBlue)` = Apple 蓝 #007AFF，不是 App 主色那个偏深的蓝）。
    /// 未选中行不放占位图形 —— `Spacer` 已经把文字顶到左边，勾的有无不影响对齐。
    private var hoursMenu: some View {
        VStack(spacing: 0) {
            ForEach(hourOptions, id: \.self) { hours in
                Button {
                    model.setPendingHours(hours)
                    showHoursMenu = false
                } label: {
                    HStack(spacing: 12) {
                        Text("\(hours) 小时")
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 20)

                        if hours == model.pendingHours {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(.systemBlue))
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(width: 168, height: 42)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: 不定期提醒

    private var pendingSection: some View {
        SettingsGroup(title: "提醒 · 超时未取",
                      note: "超过设定时长还没取就催一次，取走后自动撤回。") {
            SettingsPlainRow(title: "超时未取提醒") {
                // 🔴 2026-11-08 主人：**不显示任何加锁标志**；
                //    非 Pro 点一下开关 = 直接弹订阅页（不先翻转开关再回弹）。
                if EntitlementSnapshot.licensedPro {
                    Toggle("", isOn: Binding(get: { model.pendingEnabled },
                                             set: { model.setPendingEnabled($0) }))
                        .labelsHidden()
                        .tint(AppTheme.accent)
                } else {
                    // 用 overlay 接管点击：ZStack 里放 `Color.clear` 会撑宽，
                    // 把开关挤到行中间（2026-11-08 主人：开关怎么乱跑）。
                    Toggle("", isOn: .constant(false))
                        .labelsHidden()
                        .tint(AppTheme.accent)
                        .allowsHitTesting(false)
                        .overlay {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { showPaywall = true }
                                .accessibilityLabel("超时未取提醒")
                                .accessibilityHint("需要Allude Pro")
                        }
                }
            }

            if model.pendingEnabled {
                SettingsDivider(style: .plain)

                SettingsPlainRow(title: "等待时长") {
                    // 5 档固定时长：自由输入会把「37 小时」这类值排进
                    // UNTimeIntervalNotificationTrigger，数字对用户毫无意义。
                    //
                    // 🔴 **不再用系统 `Menu`**（2026-10-27 主人：「把这个对号继续做成 Apple 蓝，
                    // 位置再向右侧移动一些」）。系统 Menu 的行由 UIKit 渲染：
                    //   · 行内文字颜色被强制成 label 色，`foregroundStyle` 一律无效；
                    //   · `Label(_, systemImage:)` 的图标恒排**最左**，既不能右对齐也不能改色。
                    // 上一版用字符 "✓" 拼在时间后面，只是绕开了"图标跑最左"，
                    // 颜色与位置仍然动不了。所以这里换成自绘 popover：
                    // 行 = 文字 + Spacer + SF Symbol 勾，勾在最右端且可指定颜色。
                    // `.presentationCompactAdaptation(.popover)` 让它在小屏也保持气泡形态，
                    // 而不是被降级成底部 sheet。
                    Button {
                        showHoursMenu = true
                    } label: {
                        SettingsValueLabel(text: "\(model.pendingHours) 小时")
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showHoursMenu, arrowEdge: .top) {
                        hoursMenu
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }
        }
    }
}
