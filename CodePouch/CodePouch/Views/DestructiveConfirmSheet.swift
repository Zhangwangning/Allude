import SwiftUI

// MARK: ============================================================================
// 破坏性操作的二次确认弹窗（2026-11-01 主人）
//
// 为什么不是 alert、也不是新页面：
//   · alert —— 里面放不了输入框校验，两下点完就删，拦不住手快的人；
//   · 新页面 —— 为了删几条记录把人推到另一个界面，太重。
// 所以做成**盖在当前页面上的居中弹窗**：蒙层下方仍是列表，随机四位数就在弹窗里输。
//
// 这个 App 的数据只在本机，删了 App 内无法恢复，清空类动作值得多这一步。
// ============================================================================

private struct DestructiveConfirmModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let confirmLabel: String
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                DestructiveConfirmDialog(title: title,
                                         message: message,
                                         confirmLabel: confirmLabel,
                                         isPresented: $isPresented,
                                         onConfirm: onConfirm)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: isPresented)
    }
}

extension View {
    /// 破坏性确认弹窗（随机四位数字，输对了才激活删除）
    func destructiveConfirm(isPresented: Binding<Bool>,
                            title: String,
                            message: String,
                            confirmLabel: String = "清空",
                            onConfirm: @escaping () -> Void) -> some View {
        modifier(DestructiveConfirmModifier(isPresented: isPresented,
                                           title: title,
                                           message: message,
                                           confirmLabel: confirmLabel,
                                           onConfirm: onConfirm))
    }
}

struct DestructiveConfirmDialog: View {
    let title: String
    let message: String
    let confirmLabel: String
    @Binding var isPresented: Bool
    let onConfirm: () -> Void

    @State private var code = ""
    @State private var input = ""
    @FocusState private var focused: Bool

    private var matched: Bool { input == code }

    var body: some View {
        ZStack {
            // 蒙层：点空白处取消
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 14) {
                Text(title)
                    .font(AppTheme.TypeScale.rowTitle.weight(.semibold))

                Text(message)
                    .font(AppTheme.TypeScale.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // 随机四位数字：每次弹出重新生成，避免记住上次的数字闭眼输
                Text(code)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .tracking(6)
                    .foregroundStyle(AppTheme.todayTint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppTheme.todayTint.opacity(0.10),
                                in: .rect(cornerRadius: 10, style: .continuous))
                    .textSelection(.enabled)

                TextField("照上方数字输入", text: $input)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground),
                                in: .rect(cornerRadius: 10, style: .continuous))
                    .onChange(of: input) { _, new in
                        let digits = new.filter(\.isNumber)
                        input = String(digits.prefix(4))
                    }

                HStack(spacing: 10) {
                    Button {
                        isPresented = false
                    } label: {
                        Text("取消")
                            .font(AppTheme.TypeScale.body)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color(.tertiarySystemFill), in: .capsule)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onConfirm()
                        isPresented = false
                    } label: {
                        Text(confirmLabel)
                            .font(AppTheme.TypeScale.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(matched ? Color.red : Color(.tertiarySystemFill), in: .capsule)
                            .foregroundStyle(matched ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!matched)
                }
                .padding(.top, 2)
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: .rect(cornerRadius: 20, style: .continuous))
            // 键盘弹出时往上抬，别被挡住
            .padding(.bottom, focused ? 180 : 0)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            code = String(format: "%04d", Int.random(in: 1000...9999))
            focused = true
            if ProcessInfo.processInfo.environment["CONFIRM_MATCH"] == "1" {
                input = code
            }
        }
    }
}
