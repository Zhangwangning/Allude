import SwiftUI

// MARK: ============================================================================
// 免费版功能门禁（2026-11-07 主人定义）
//
// 口径：
//   · 受限功能**不隐藏**，用户点得到；
//   · 点了弹「此功能为拾码 Pro 版功能，请订阅后使用」；
//   · 免费用户可以选「仅预览效果」—— 设置页能看效果，但**实际不生效**；
//   · 付费（`PickupStore.isPro`）后一切照旧。
// ============================================================================

struct ProPrompt: Identifiable {
    let id = UUID()
    /// 触发的是哪个功能（只用于无障碍与日志，不进弹窗正文）
    let feature: String
    /// 用户选择「仅预览效果」时执行：只改界面状态，不落库、不排通知
    let preview: () -> Void
}

enum PremiumGate {
    static let title = "拾码 Pro 功能"
    static let message = "此功能为拾码 Pro 版功能，请订阅后使用。"
}

extension View {
    /// 挂上「Pro 功能」提示 + 订阅页。
    ///
    /// 免费用户点受限控件 → 弹窗；「去订阅」打开 `FullVersionView`，
    /// 「仅预览效果」执行 `ProPrompt.preview`（界面变、但不生效）。
    func proGate(prompt: Binding<ProPrompt?>,
                 showSubscription: Binding<Bool>) -> some View {
        self
            .alert(PremiumGate.title, isPresented: Binding(
                get: { prompt.wrappedValue != nil },
                set: { if !$0 { prompt.wrappedValue = nil } }
            ), presenting: prompt.wrappedValue) { item in
                Button("去订阅") {
                    DiagnosticsLog.record("pro", "gate-promoted feature=\(item.feature)")
                    prompt.wrappedValue = nil
                    showSubscription.wrappedValue = true
                }
                Button("仅预览效果") {
                    DiagnosticsLog.record("pro", "gate-preview feature=\(item.feature)")
                    prompt.wrappedValue = nil
                    item.preview()
                }
                Button("取消", role: .cancel) { prompt.wrappedValue = nil }
            } message: { _ in
                Text(PremiumGate.message)
            }
            .sheet(isPresented: showSubscription) {
                NavigationStack { FullVersionView() }
            }
    }
}
