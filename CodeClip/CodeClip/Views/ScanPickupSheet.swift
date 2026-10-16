import SwiftUI
import PhotosUI
import UIKit
import Vision

// MARK: ============================================================================
// 扫描添加
//
// 两条入口，同一个出口：
//   · 扫一扫  —— 相机识别二维码 / 一维码（驿站小票、快递柜屏幕、面单条码）
//   · 相册识别 —— 对图片做中文 OCR（短信截图、取件小票照片）
//
// 无论哪条路径，拿到的都是「一段文本」，随后统一交给 PickupParser —— 与快捷指令
// 自动化、手动粘贴完全同一条链路。扫描出来的内容若本身就是一串取件码
// （柜机二维码常如此），解析必然落空，此时降级为「直接当作取件码」。
// ============================================================================

enum ScanMode: String, CaseIterable, Identifiable {
    case camera = "扫一扫"
    case photo = "相册识别"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .camera: "qrcode.viewfinder"
        case .photo: "photo.on.rectangle.angled"
        }
    }
}

/// 确认页上的一条**可编辑草稿**。
///
/// 识别结果一旦落成草稿，就与人手输入同等对待 —— 后续入库不再经过正则，
/// 否则用户改过的字会被重新解析覆盖（见 `PickupStore.commitEdited`）。
/// `rawText` 保留该条所在的原文片段，记录详情页仍能回看来源短信/截图。
struct ScanDraft: Identifiable, Equatable {
    let id = UUID()
    var kind: PickupKind
    var value: String
    var company: String
    var address: String
    var rawText: String
}

final class ScanPickupModel: ObservableObject {
    @Published var mode: ScanMode = .camera

    /// 识别到的原始文本（非空即进入「确认」态）
    @Published var captured: String?
    /// 识别失败的中性提示
    @Published var errorMessage: String?
    @Published var isRecognizing = false
    /// 多图批量识别：相册一次可选中多张（2026-09-23）
    @Published var pickedItems: [PhotosPickerItem] = []
    /// 本轮识别一共处理了几张图（用于文案「已识别 N 张图」；1 张时不显示）
    @Published var photoCount = 0
    @Published var addedMessage: String?
    /// 强制重建相机控制器，用于「重新扫描」
    @Published var scannerToken = UUID()

    /// 确认页的可编辑草稿（每个字段都能当场改）
    @Published var drafts: [ScanDraft] = []

    /// 预置状态（仅供命令行截图验证注入，生产路径不传）
    init(seed: String = "", mode: ScanMode = .camera) {
        self.mode = mode
        if !seed.isEmpty {
            captured = seed
            rebuildDrafts()
        }
    }

    /// 识别结果。**可能是多条** —— 一张截图里常有 2–4 条短信，
    /// 一张面单照片也可能同时拍到两个码。
    var parsedList: [PickupParseResult] {
        guard let captured, !captured.isEmpty else { return [] }
        // 走 OCR 专用入口：OCR 的换行是视觉折行，会切断定长 lookbehind 锚点；
        // 该入口同时负责「一次多条」的切段。
        return PickupParser.parseAll(captured, ocrSource: true).map(\.normalized)
    }

    /// 从解析结果重建草稿。**只在「刚识别完」时调用** —— 确认页上用户
    /// 正在改的字不能被任何一次重算冲掉，所以它不挂在 computed 属性上。
    func rebuildDrafts() {
        drafts = parsedList.map {
            ScanDraft(kind: $0.kind,
                      value: $0.value,
                      company: $0.company,
                      address: $0.address,
                      rawText: $0.rawText)
        }
    }

    /// 待入库的结果：以草稿为准，用户没动过的字段原样保留。
    var editedResults: [PickupParseResult] {
        drafts.map {
            PickupParseResult(kind: $0.kind,
                              value: $0.value.trimmingCharacters(in: .whitespacesAndNewlines),
                              company: $0.company.trimmingCharacters(in: .whitespacesAndNewlines),
                              address: $0.address.trimmingCharacters(in: .whitespacesAndNewlines),
                              rawText: $0.rawText)
        }
    }

    /// 有没有识别到东西（判空口径从 `parsedList` 换成草稿，因为后者才是真相）
    var hasResult: Bool { !drafts.isEmpty }

    /// 识别到的那串内容本身是否像一个可直接使用的取件码
    var looksLikeBareCode: Bool {
        guard let captured else { return false }
        let t = captured.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...48).contains(t.count), !t.contains("\n") else { return false }
        guard t.rangeOfCharacter(from: .whitespaces) == nil else { return false }
        let punctuation = CharacterSet(charactersIn: "。，,、；;！!？?")
        return t.rangeOfCharacter(from: punctuation) == nil
    }

    func reset() {
        captured = nil
        errorMessage = nil
        addedMessage = nil
        photoCount = 0
        drafts = []
        scannerToken = UUID()
    }
}

struct ScanPickupSheet: View {
    @EnvironmentObject private var store: PickupStore
    @StateObject private var model: ScanPickupModel

    let onClose: () -> Void
    let onAdded: (IngestOutcome) -> Void

    /// 相册一次最多选几张。取件场景一趟十几件是极少数的极端情况，
    /// 9 张足够覆盖「一次帮家人取几件」；再多则识别耗时与确认页长度都失控。
    static let photoLimit = 9

    init(initialCaptured: String = "",
         initialMode: ScanMode = .camera,
         onClose: @escaping () -> Void,
         onAdded: @escaping (IngestOutcome) -> Void) {
        _model = StateObject(wrappedValue: ScanPickupModel(seed: initialCaptured,
                                                           mode: initialMode))
        self.onClose = onClose
        self.onAdded = onAdded
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.addedMessage != nil {
                    successBanner
                } else if model.captured != nil {
                    reviewPane
                } else {
                    modePicker
                        .padding(.horizontal, AppTheme.hInset)
                        .padding(.top, 10)
                        .padding(.bottom, 12)

                    Group {
                        switch model.mode {
                        case .camera: cameraPane
                        case .photo: photoPane
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("扫描添加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(model.captured == nil ? "取消" : "重来") {
                        if model.captured == nil { onClose() } else { withAnimation(.snappy) { model.reset() } }
                    }
                }
            }
            .onChange(of: model.pickedItems) { _, items in
                guard !items.isEmpty else { return }
                recognize(items)
            }
        }
    }

    // MARK: 模式切换

    private var modePicker: some View {
        Picker("识别方式", selection: $model.mode) {
            ForEach(ScanMode.allCases) { mode in
                Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: 扫一扫

    @ViewBuilder
    private var cameraPane: some View {
        switch ScannerAvailability.current() {
        case .ready:
            ZStack {
                CameraScannerView(onScan: handleCaptured)
                    .id(model.scannerToken)

                ScannerReticle()
                    .allowsHitTesting(false)

                VStack {
                    Spacer()
                    Text("对准取件码二维码或快递面单条码")
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.5), in: .capsule)
                        .padding(.bottom, 26)
                }
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

        case .denied:
            fallbackCard(
                symbol: "camera.metering.unknown",
                tint: AppTheme.amber,
                title: "没有相机权限",
                detail: "在「设置 → 隐私与安全性 → 相机」中允许码夹使用相机，然后重新进入本页。",
                primary: ("去设置", openSettings)
            )

        case .unsupported:
            fallbackCard(
                symbol: "iphone.slash",
                tint: AppTheme.sky,
                title: "当前设备不支持相机扫码",
                detail: "模拟器没有摄像头。可以改用「相册识别」，或在真机上扫码。",
                primary: ("改用相册识别", { withAnimation(.snappy) { model.mode = .photo } })
            )
        }
    }

    private func fallbackCard(symbol: String, tint: Color, title: String,
                              detail: String, primary: (String, () -> Void)) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 20)

            IconBadge(symbol: symbol, tint: tint, size: 56)

            Text(title)
                .font(.headline)

            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
                .fixedSize(horizontal: false, vertical: true)

            Button(primary.0, action: primary.1)
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(AppTheme.accent, in: .capsule)
                .foregroundStyle(.white)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 相册识别

    private var photoPane: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)

            IconBadge(symbol: "text.viewfinder", tint: AppTheme.violet, size: 56)

            Text("从图片里读文字")
                .font(.headline)

            Text("短信截图、取件小票、快递面单照片都可以，会自动识别其中的取件码与地址。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
                .fixedSize(horizontal: false, vertical: true)

            PhotosPicker(selection: $model.pickedItems,
                         maxSelectionCount: Self.photoLimit,
                         matching: .images) {
                Label("选择图片", systemImage: "photo.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(AppTheme.accent, in: .capsule)
                    .foregroundStyle(.white)
            }

            Text("可一次选多张，最多 \(Self.photoLimit) 张")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if model.isRecognizing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在识别…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let error = model.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.pendingTint)
                    .padding(.horizontal, 30)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 确认态

    private var reviewPane: some View {
        ScrollView {
            VStack(spacing: 14) {
                rawCard

                if model.hasResult {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.doneTint)
                            Text(resultSummary)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Text("可直接修改")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        ForEach(model.drafts.indices, id: \.self) { index in
                            EditableParseCard(
                                draft: $model.drafts[index],
                                index: model.drafts.count > 1 ? index + 1 : nil,
                                // `_ =` 是必要的：`withAnimation` 会把闭包的返回值
                                // （这里是 `remove(at:)` 吐出的那条草稿）原样传出来，
                                // 不显式丢弃就会报 "result of call is unused"。
                                onDelete: model.drafts.count > 1
                                    ? { _ = withAnimation(.snappy) { model.drafts.remove(at: index) } }
                                    : nil
                            )
                        }
                    }
                } else if model.looksLikeBareCode {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            IconBadge(symbol: "lightbulb.fill", tint: AppTheme.pendingTint, size: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("识别到的是一个单独的码")
                                    .font(.subheadline.weight(.semibold))
                                Text("扫出来的内容本身就是取件码，直接加进待取件列表即可。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface()

                        primaryButton(title: "作为取件码添加", tint: AppTheme.pendingTint) {
                            finish(with: store.addManual(code: model.captured ?? ""))
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        IconBadge(symbol: "exclamationmark.triangle.fill", tint: AppTheme.amber, size: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("没识别到取件信息")
                                .font(.subheadline.weight(.semibold))
                            Text("这段内容里没有取件码、运单号或尾号。可以换个角度重扫，或用「添加」手动粘贴短信全文。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
                }

                if model.hasResult {
                    // 走结构化入口：用户在卡上改过的字必须原样落库，
                    // 不能再拿原文跑一遍正则（那会把改动覆盖回去）
                    primaryButton(title: model.drafts.count > 1
                                  ? "全部添加 · \(model.drafts.count) 条"
                                  : "添加",
                                  tint: AppTheme.accent) {
                        finish(with: store.commitEdited(model.editedResults))
                    }
                }

                Button {
                    withAnimation(.snappy) { model.reset() }
                } label: {
                    Text("重新识别")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemGroupedBackground), in: .capsule)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 14)
            .padding(.bottom, 26)
        }
    }

    /// 确认区标题。多图时把「几张图」也讲清楚 —— 否则用户看到一长串条目，
    /// 不知道它们是从几张图里来的，也无从判断是不是漏识别了某一张。
    private var resultSummary: String {
        let count = model.drafts.count
        if model.photoCount > 1 { return "已识别 \(count) 条 · 来自 \(model.photoCount) 张图" }
        return count > 1 ? "已识别 \(count) 条" : "已识别"
    }

    private var rawCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: model.mode == .camera ? "qrcode" : "doc.text.magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text(model.mode == .camera ? "扫描到的内容" : "识别出的文字")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(model.captured ?? "")
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func primaryButton(title: String, tint: Color,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(tint, in: .capsule)
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var successBanner: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.doneTint)
            Text(model.addedMessage ?? "")
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 动作

    private func handleCaptured(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation(.snappy) {
            model.captured = trimmed
            model.errorMessage = trimmed.isEmpty ? "没有读到内容，请再试一次" : nil
            model.photoCount = 1
            if !trimmed.isEmpty { model.rebuildDrafts() }
        }
    }

    /// 多图批量识别（2026-09-23）。
    ///
    /// 逐张串行 OCR 后**拼成一段文本**，再整体走一次 `parseAll` —— 而不是
    /// 每张图各自解析、各自弹一次确认页：用户一次圈了 5 张图，应该看到
    /// 一张合并后的确认清单；逐张确认就是 5 次交互，比逐张选图还累。
    ///
    /// 串行而非并发：Vision 是 CPU 密集的同步调用，同时跑多张只会互相抢核，
    /// 总耗时基本不变，峰值内存却按张数翻倍（一张截图解码后可达数十 MB）。
    private func recognize(_ items: [PhotosPickerItem]) {
        model.isRecognizing = true
        model.errorMessage = nil

        Task { @MainActor in
            defer {
                model.isRecognizing = false
                model.pickedItems = []
            }

            var texts: [String] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { continue }

                // OCR 是 CPU 密集的同步调用，放到后台（UIImage 本身即 Sendable）
                let text = await Task.detached(priority: .userInitiated) {
                    PickupOCR.recognize(image)
                }.value

                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { texts.append(trimmed) }
            }

            guard !texts.isEmpty else {
                model.errorMessage = items.count > 1
                    ? "这 \(items.count) 张图里都没读出文字，换更清晰的试试"
                    : "这张图里没读出文字，换一张更清晰的试试"
                return
            }

            let merged = texts.joined(separator: "\n")
            withAnimation(.snappy) {
                model.photoCount = texts.count
                model.captured = merged
                model.rebuildDrafts()
            }
        }
    }

    private func finish(with outcome: IngestOutcome) {
        onAdded(outcome)

        // 文案统一取 `outcome.dialog` —— App 内所有入口（粘贴 / 扫码 / 相册）
        // 共用同一口径，不会出现"这个入口说 3 条、那个入口说 5 条"这种两套说法。
        withAnimation(.snappy) { model.addedMessage = outcome.dialog }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_050_000_000)
            onClose()
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - 可编辑识别结果卡

/// 与 `ParsePreviewCard` 的分工：这张**每个字段都能当场改**。
///
/// 为什么必须可编辑（2026-09-23）：OCR 认错一个字符（`8`↔`B`、`0`↔`O`、
/// `l`↔`1`）在取件现场是致命的 —— 报一个错码比没识别更糟，用户白跑一趟。
/// 而原版确认页只能看，发现错了唯一出路是整张重拍，多数人会直接放弃这条路。
///
/// 与 `AddPickupSheet` 里那张只读卡的区别：那边是「手动输入后确认」，字是
/// 用户自己打的，不需要再改；这边是「机器识别后确认」，出错概率高，必须给
/// 一条修的路。
///
/// 三个几何约定：取件码单独一行且字号最大（最常改的就是它）、其余字段
/// 统一「40pt 标签 + 淡色填充输入框」，与二级设置页的输入行同一种手感。
struct EditableParseCard: View {
    @Binding var draft: ScanDraft
    /// 一次识别多条时在卡头显示序号，单条时为 nil（不占位）
    var index: Int? = nil
    /// 只有多条时才给删除入口 —— 单条删掉等于什么都没识别到，
    /// 那种情况用户要的是「重新识别」，而不是留下一个空确认页。
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            DashedDivider()
                .padding(.vertical, 11)

            codeRow
            kindRow
            inputRow(label: "平台", placeholder: "快递公司", text: $draft.company)
            inputRow(label: "地址", placeholder: "未识别到", text: $draft.address)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(tint: draft.kind.tint)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let index {
                Text("\(index)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(draft.kind.tint, in: .circle)
            }

            // 平台名一改，图标跟着换 —— 这是"我改对了"最直接的反馈
            CourierLogo(company: draft.company, size: 22)

            KindTag(kind: draft.kind)

            Spacer(minLength: 8)

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var codeRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("取件码")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            TextField("取件码", text: $draft.value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospaced()
                .foregroundStyle(draft.kind.tint)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
        }
        .padding(.bottom, 10)
    }

    private var kindRow: some View {
        HStack(spacing: 10) {
            rowLabel("类别")

            Menu {
                Picker("类别", selection: $draft.kind) {
                    ForEach(PickupKind.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(draft.kind.label)
                        .font(.system(size: 14))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: .capsule)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 6)
    }

    private func inputRow(label: String, placeholder: String,
                          text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            rowLabel(label)

            TextField(placeholder, text: text)
                .font(.system(size: 14))
                .autocorrectionDisabled()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
        }
        .padding(.bottom, 6)
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .frame(width: 40, alignment: .leading)
    }
}

// MARK: - 取景框

/// 四角取景框。不做「扫描线动画」——那类装饰会持续重绘，
/// 而扫码本身是秒级动作，视觉噪音大于信息量。
struct ScannerReticle: View {
    private let side: CGFloat = 232
    private let corner: CGFloat = 34
    private let lineWidth: CGFloat = 3.5

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                Corner()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: corner, height: corner)
                    .rotationEffect(.degrees(Double(index) * 90))
                    .offset(x: index == 0 || index == 3 ? -(side - corner) / 2 : (side - corner) / 2,
                            y: index == 0 || index == 1 ? -(side - corner) / 2 : (side - corner) / 2)
            }
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.35), radius: 6)
    }

    /// 左上角直角的两条边
    private struct Corner: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            return path
        }
    }
}

// MARK: - 中文 OCR

enum PickupOCR {
    /// 对一张图片做文字识别，按视觉上的「从上到下」顺序拼成多行文本。
    ///
    /// 同步实现（调用方负责放到后台线程）：`perform` 的同步版本返回后
    /// `request.results` 即已就绪，比走 completion handler + continuation
    /// 少一层并发状态，也不会出现「perform 抛错导致 continuation 永不 resume」。
    static func recognize(_ image: UIImage) -> String {
        guard let cgImage = image.cgImage else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        // 取件码是数字串，语言纠正会把它「纠」成看似合理的词，必须关闭
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        guard let observations = request.results else { return "" }

        return observations
            // Vision 坐标系原点在左下角，midY 越大越靠上
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
