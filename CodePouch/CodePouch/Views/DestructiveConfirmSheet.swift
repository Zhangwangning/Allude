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
    /// 输错时给一句红字提示（不弹二级弹窗，免得叠两层）
    @State private var wrong = false
    @FocusState private var focused: Bool

    private var matched: Bool { input == code }

    /// 版式照系统 alert 走（2026-11-01 主人给的参考图）：
    /// 标题居中、说明文字里带【随机数】、输入框占位符就是那串数字、底部两个并排按钮。
    /// 「清空」**常亮红色**，点下去才校验：输对就执行，输错给红字提示并换一个新数字。
    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .multilineTextAlignment(.center)

                    Text("\(message)\n请输入【\(code)】来执行此次操作")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 14)

                TextField(code, text: $input)
                    .font(.system(size: 16))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 12)
                    .background(Color(.tertiarySystemFill),
                                in: .rect(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 16)
                    .onChange(of: input) { _, new in
                        let digits = new.filter(\.isNumber)
                        input = String(digits.prefix(4))
                        if wrong { wrong = false }
                    }

                if wrong {
                    Text("数字不正确，请重新输入")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(.top, 6)
                        .transition(.opacity)
                }

                HStack(spacing: 0) {
                    Button {
                        isPresented = false
                    } label: {
                        Text("取消")
                            .font(.system(size: 17))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                    Divider().frame(height: 44)

                    // 按钮**常亮**（2026-11-01 主人）：输不对删不掉，没必要先灰着。
                    // 点下去时校验，错了给红字提示并换一个新数字。
                    Button {
                        guard matched else {
                            withAnimation(.snappy(duration: 0.2)) { wrong = true }
                            input = ""
                            code = String(format: "%04d", Int.random(in: 1000...9999))
                            return
                        }
                        onConfirm()
                        isPresented = false
                    } label: {
                        Text(confirmLabel)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 16)
                .overlay(alignment: .top) {
                    Divider()
                }
            }
            .frame(maxWidth: 280)
            .background(.regularMaterial,
                        in: .rect(cornerRadius: 16, style: .continuous))
            // 键盘弹出时往上抬，别被挡住
            .padding(.bottom, focused ? 200 : 0)
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
