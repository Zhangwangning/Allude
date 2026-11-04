import SwiftUI
import UIKit

// MARK: ============================================================================
// 手动添加取件信息
//
// 设计原则：手动添加与快捷指令自动化**共用同一个解析入口**
// （PickupParser → PickupStore.ingest），因此同一套去重指纹、同一套类别判定，
// 不会出现「自动收的能去重、手动加的不能」这类两套逻辑的问题。
//
// 只有在「整段文本解析不出任何凭证」时才降级：把那串输入直接当作取件码写入。
// 这条兜底是必要的 —— 用户手上可能只有一个码，没有短信原文。
// ============================================================================

final class AddPickupModel: ObservableObject {
    @Published var text: String = "" {
        didSet { reparse() }
    }

    /// 实时解析结果（输入即算）。**可能是多条** ——
    /// 从短信 App 多选复制一次粘进来，常常就是好几行。
    @Published private(set) var parsedList: [PickupParseResult] = []

    /// 首条结果（供「只关心有没有识别到」的场景，如按钮可用性判断）
    var parsed: PickupParseResult? { parsedList.first }

    /// 添加成功后的收尾态：显示绿色反馈再自动关闭
    @Published var addedMessage: String?

    /// 预填内容（仅供命令行截图验证注入，生产路径不传）
    init(seed: String = "") {
        // init 中的赋值不触发 didSet，需显式解析一次
        text = seed
        reparse()
    }

    private func reparse() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 走 OCR 专用入口：短信原文本身可能带换行（在「取件码」与数字之间断行），
        // 会切断定长 lookbehind 锚点。该入口同时负责「一次多条」的切段。
        parsedList = trimmed.isEmpty
            ? []
            : PickupParser.parseAll(trimmed, ocrSource: true).map(\.normalized)
    }

    var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasInput: Bool { !trimmed.isEmpty }

    /// 输入只有一行且不含空白/中文时，才认为「可以当作一个纯码」
    var looksLikeBareCode: Bool {
        let t = trimmed
        guard (1...48).contains(t.count) else { return false }
        guard !t.contains("\n") else { return false }
        guard t.rangeOfCharacter(from: .whitespaces) == nil else { return false }
        // 纯码里不该出现空格或句读，否则更像是被截断的短信
        let punctuation = CharacterSet(charactersIn: "。，,、；;！!？?")
        return t.rangeOfCharacter(from: punctuation) == nil
    }

    func pasteFromClipboard() {
        if let value = UIPasteboard.general.string, !value.isEmpty { text = value }
    }

    func clear() { text = "" }
}

struct AddPickupSheet: View {
    @EnvironmentObject private var store: PickupStore
    @StateObject private var model: AddPickupModel

    /// 关闭回调（由父视图控制呈现状态，避免依赖 dismiss 环境值）
    let onClose: () -> Void
    /// 添加成功后的回调，用于让列表把新条目显现出来
    let onAdded: (IngestOutcome) -> Void

    init(initialText: String = "",
         onClose: @escaping () -> Void,
         onAdded: @escaping (IngestOutcome) -> Void) {
        _model = StateObject(wrappedValue: AddPickupModel(seed: initialText))
        self.onClose = onClose
        self.onAdded = onAdded
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let message = model.addedMessage {
                        successBanner(message)
                    } else {
                        inputCard
                        resultSection
                    }
                }
                .padding(.horizontal, AppTheme.hInset)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("添加取件信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消", action: onClose)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加") { submit() }
                        .fontWeight(.semibold)
                        .disabled(!model.hasInput || model.addedMessage != nil)
                }
            }
        }
    }

    // MARK: 输入区

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text("粘贴短信内容")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if model.hasInput {
                    Text("\(model.trimmed.count) 字")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.text)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 132)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                if model.text.isEmpty {
                    Text("把整条快递短信粘贴进来，自动识别取件码、快递平台与取件地址。")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .background(Color(.secondarySystemGroupedBackground),
                        in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.separator.opacity(0.5), lineWidth: 0.5)
            }

            HStack(spacing: 10) {
                smallButton(title: "粘贴", symbol: "doc.on.clipboard",
                            enabled: UIPasteboard.general.hasStrings) {
                    model.pasteFromClipboard()
                }
                smallButton(title: "清空", symbol: "xmark.circle",
                            enabled: model.hasInput) {
                    model.clear()
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func smallButton(title: String, symbol: String,
                             enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AppTheme.accent.opacity(enabled ? 0.13 : 0.05), in: .capsule)
                .foregroundStyle(enabled ? AppTheme.accent : Color.secondary.opacity(0.6))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: 解析结果 / 引导

    @ViewBuilder
    private var resultSection: some View {
        if !model.hasInput {
            hintCard(symbol: "wand.and.sparkles", tint: AppTheme.sky,
                     title: "会自动识别",
                     detail: "取件码 / 运单号 / 尾号 / 特殊取件码四类凭证，以及平台、快递公司与取件地址 —— 识别不出的字段留空。识别不了的短信不会写入。")
        } else if !model.parsedList.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.doneTint)
                    Text(model.parsedList.count > 1
                         ? "已识别 \(model.parsedList.count) 条"
                         : "已识别")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                // 多条时逐张列出，添加前能核对到每一条
                ForEach(Array(model.parsedList.enumerated()), id: \.offset) { index, parsed in
                    ParsePreviewCard(parsed: parsed,
                                     index: model.parsedList.count > 1 ? index + 1 : nil)
                }
            }
        } else if model.looksLikeBareCode {
            VStack(alignment: .leading, spacing: 12) {
                hintCard(symbol: "lightbulb.fill", tint: AppTheme.pendingTint,
                         title: "没有短信可解析",
                         detail: "看起来这串内容本身就是一个取件码。可以直接把它加进待取件列表。")

                Button {
                    submitBareCode()
                } label: {
                    Label("作为取件码添加", systemImage: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(AppTheme.pendingTint, in: .capsule)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        } else {
            hintCard(symbol: "exclamationmark.triangle.fill", tint: AppTheme.amber,
                     title: "没识别到取件信息",
                     detail: "请确认粘贴的是**快递短信全文**。若只想记录一个取件码，单独输入那一串码即可。")
        }
    }

    private func hintCard(symbol: String, tint: Color,
                          title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: symbol, tint: tint, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(title.L)
                    .font(.subheadline.weight(.semibold))
                Text(detail.richText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func successBanner(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.doneTint)
                .padding(.top, 36)

            Text(message.L)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 提交

    private func submit() {
        guard model.hasInput else { return }
        var outcome = store.ingestOCR(model.trimmed)

        // 🔴 解析器一条都没认出来时，兜底把整段输入当取件码（2026-10-25 审查修）。
        // 以前这里只走 `ingestOCR`：用户手输「A128」这种短信正则认不出、但明显是
        // 取件码的内容，点右上「添加」会弹**绿色对勾** +「没识别到取件信息，已忽略」，
        // 1 秒后自动关闭、什么都没存 —— 成功视觉配失败结果，而且「添加」是这个页面
        // 最顺手的主按钮。页面下方本来就有「作为取件码添加」的兜底按钮，主按钮更该兜住。
        // 🔴 2026-10-30 修：只有「解析器一条都没认出来」且「输入确实像一个裸码」
        //    才走兜底。原来的判断是 `outcome.added.isEmpty` —— 而 2026-10-30 起
        //    同码重复短信**不再新建**（只更新时间），`added` 同样是空，
        //    于是「粘贴一条已经存在的短信」会被当成裸码，把**整段短信原文**
        //    塞进取件码字段，列表里出现「手动添加 / 快递超市 / 您的圆通快递包裹已…」
        //    这种垃圾记录（真机实证）。
        let recognized = !PickupParser.parseAll(model.trimmed, ocrSource: true).isEmpty
        if !recognized, model.looksLikeBareCode {
            outcome = store.addManual(code: model.trimmed)
        }

        finish(with: outcome)
    }

    /// 兜底路径：把输入直接当作一个取件码
    private func submitBareCode() {
        let outcome = store.addManual(code: model.trimmed)
        finish(with: outcome)
    }

    private func finish(with outcome: IngestOutcome) {
        onAdded(outcome)

        // 文案统一取 `outcome.dialog` —— App 内所有入口（粘贴 / 扫码 / 相册）
        // 共用同一口径，不会出现"这个入口说 3 条、那个入口说 5 条"这种两套说法。
        withAnimation(.snappy) { model.addedMessage = outcome.dialog }

        // 短暂展示结果后自动收尾，不需要用户再点一次
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_050_000_000)
            onClose()
        }
    }
}

// MARK: - 解析结果预览（添加页与扫描页共用）

/// 把 `PickupParseResult` 的**全部字段**摊平成一张可核对的卡。
/// 用户点「添加」之前能一眼确认「是不是识别成了我要的东西」——
/// 这比添加完再去列表里翻找要可靠得多。
///
/// 🔴 字段口径（2026-10-30 主人修订）：预览卡只列**核对得上的四项** ——
///    取件码 / 平台 / 快递公司 / 地址。
///    运单号、尾号**不再单独成行**：绝大多数短信里这两个字段是空的，
///    留着就是两行空占位；即便有值，主凭证位已经显示了真正要核对的那串码。
///    数据本身照旧解析并入库，需要时在详情页查看（`RecordDetailView` 仍保留这两项）。
///    **识别不出的字段留空**，不写「未识别到」也不编造。
///
/// 🔴 2026-10-28 主人：「拾码内再不区分取件码信息的类型」——
///    删掉「类别」行与类别标签，主凭证一律叫取件码（不再写「运单号 / 尾号 / 特殊码」）；
///    配色也从「类型色」改成**品牌色**，与列表卡同一套取色逻辑。
struct ParsePreviewCard: View {
    let parsed: PickupParseResult
    /// 一次识别多条时在卡头显示序号，单条时为 nil（不占位）
    var index: Int? = nil

    /// 主凭证 —— 不论解析时走的是哪条公式，到界面上一律叫「取件码」
    private var code: String { parsed.value }
    /// 快递公司（2026-09-23 主人定）：与平台一边没匹配到就保持相同。
    /// 解析层已互填归一，这里再兜底一次，防 OCR 之外的路径漏网。
    private var courier: String { parsed.courier.isEmpty ? parsed.company : parsed.courier }

    /// 卡头命名 —— **与待取卡同一套 `PickupNaming`**（2026-10-30 主人：
    /// 「预览卡也要和卡片取色规则一致」）。
    /// 以前这里直接显示短信平台，于是「【欢猫驿站】圆通快递…」预览成一张绿卡，
    /// 保存进列表却变成紫卡（列表主名是快递公司），同一个码两种颜色。
    private var naming: PickupNaming {
        PickupNaming(courier: courier, platform: parsed.company, station: nil)
    }

    /// 配色 = **图标主题色**，即第一行第一个字段（快递公司优先）的颜色
    private var tint: Color { CourierBrand.color(for: naming.iconSource) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let index {
                    Text("\(index)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(tint, in: .circle)
                }

                CourierLogo(company: naming.iconSource, size: 22)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(naming.primary.L)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        if let secondary = naming.secondary {
                            Text("| \(secondary)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 8)

                Text(parsed.value.L)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospaced()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(tint)
            }

            DashedDivider()
                .padding(.vertical, 11)

            field(label: "取件码", value: code, mono: true, tint: tint)
            field(label: "平台", value: parsed.company, mono: false, tint: .secondary)
            field(label: "快递公司", value: courier, mono: false, tint: .secondary)
            field(label: "地址", value: parsed.address, mono: false, tint: .secondary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(tint: tint)
    }

    @ViewBuilder
    private func field(label: String, value: String,
                       mono: Bool, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label.L)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(width: 58, alignment: .leading)

            Text(value.L)
                .font(.system(size: 13, weight: mono ? .semibold : .regular,
                              design: mono ? .rounded : .default))
                .monospaced(mono)
                .foregroundStyle(tint)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}
