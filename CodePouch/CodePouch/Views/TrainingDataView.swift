import SwiftUI

// MARK: ============================================================================
// 设置 › 帮助与反馈 › 帮助改进拾码（2026-11-05 主人 A+B 方案）
//
// 用户手动提供短信样本 → 存本地 → 用户主动导出（分享 / 邮件）给开发者，
// 开发者在 Mac 上重训分类器，发新版本。
//
// 🔴 页面顶部**强制提醒**：导出内容包含哪些、不包含哪些，用户看过再操作。
// ============================================================================

struct TrainingDataView: View {
    @State private var samples: [TrainingSample] = []
    @State private var showComposer = false
    @State private var showClearConfirm = false
    @State private var pendingMail = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                noticeCard
                addCard
                listCard
                exportCard
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("帮助改进拾码")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { samples = TrainingSampleStore.load() }
        .sheet(isPresented: $showComposer) {
            TrainingSampleComposer { text, label, code, address, note in
                _ = TrainingSampleStore.add(text: text, label: label, code: code,
                                            address: address, note: note)
                samples = TrainingSampleStore.load()
                DiagnosticsLog.record("training", "sample added total=\(samples.count)")
            }
        }
        .sheet(isPresented: $pendingMail) {
            MailComposeView(
                subject: "拾码 · 训练样本（\(samples.count) 条）",
                body: "开发者你好，附件是我手动提供的短信样本，用于改进识别。\n\n"
                    + "说明：样本由我手动添加，手机号/身份证/邮箱已脱敏。",
                attachment: ("codepouch-training.jsonl", TrainingSampleStore.exportData())
            ) { pendingMail = false }
        }
        .destructiveConfirm(
            isPresented: $showClearConfirm,
            title: "清空训练样本",
            message: "样本只存在这台手机上，清空后无法恢复。"
        ) {
            TrainingSampleStore.clear()
            samples = []
        }
    }

    // MARK: 强制提醒

    private var noticeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.pendingTint)
                Text("导出前请先看这一段")
                    .font(AppTheme.TypeScale.rowTitleMedium)
            }
            Text("· 导出内容 = 你手动添加的短信样本 + App 诊断日志，仅此两项。\n"
                 + "· 训练样本由你主动提供并授权使用；手机号、身份证、邮箱会自动脱敏。\n"
                 + "· 不含：你的全部取件记录、位置、通讯录、相册、设备码、账号信息。\n"
                 + "· App 不会自动上传：只有你点「导出」或「邮件发送」时，数据才离开这台手机。")
                .font(AppTheme.TypeScale.note)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: 添加

    private var addCard: some View {
        VStack(spacing: 0) {
            Button { showComposer = true } label: {
                SettingsRow(symbol: "plus.circle.fill", title: "添加一条样本",
                            subtitle: "从已有短信里挑，或手动输入", showsChevron: false,
                            tint: AppTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .cardSurface()
    }

    // MARK: 列表

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已添加 \(samples.count) 条")
                    .font(AppTheme.TypeScale.rowTitleMedium)
                Spacer(minLength: 0)
                if !samples.isEmpty {
                    Button("清空") { showClearConfirm = true }
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(AppTheme.pendingTint)
                        .buttonStyle(.plain)
                }
            }
            if samples.isEmpty {
                Text("还没有样本。添加后可以导出给开发者，用于提升识别准确率。")
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(samples) { sample in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(sample.label == "pickup" ? "快递" : "非快递")
                                .font(AppTheme.TypeScale.badge)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(AppTheme.accent.opacity(0.14)))
                                .foregroundStyle(AppTheme.accent)
                            if let code = sample.code, !code.isEmpty {
                                Text("码 \(code)").font(AppTheme.TypeScale.badge)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button {
                                TrainingSampleStore.delete(id: sample.id)
                                samples = TrainingSampleStore.load()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(sample.text)
                            .font(AppTheme.TypeScale.note)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                    if sample.id != samples.last?.id { SettingsDivider() }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: 导出

    private var exportCard: some View {
        VStack(spacing: 0) {
            ShareLink(item: TrainingExportFile.url()) {
                SettingsRow(symbol: "square.and.arrow.up.fill", title: "导出样本（分享）",
                            subtitle: "可发微信、AirDrop、存文件 App", showsChevron: false,
                            tint: AppTheme.sky)
            }
            .buttonStyle(.plain)
            .disabled(samples.isEmpty)

            SettingsDivider()

            Button { pendingMail = true } label: {
                SettingsRow(symbol: "envelope.fill", title: "用邮件发送",
                            subtitle: "附件为样本文件", showsChevron: false,
                            tint: AppTheme.doneTint)
            }
            .buttonStyle(.plain)
            .disabled(samples.isEmpty)
        }
        .cardSurface()
    }
}

// MARK: 分享用的临时文件

enum TrainingExportFile {
    /// 写到缓存目录，交给系统分享（微信 / AirDrop / 文件 App 都能收）
    static func url() -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("codepouch-training.jsonl")
        try? TrainingSampleStore.exportData().write(to: url, options: .atomic)
        return url
    }
}

// MARK: 添加样本（解析结果即时可见、可改）

struct TrainingSampleComposer: View {
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var label = "pickup"
    @State private var code = ""
    @State private var address = ""
    @State private var note = ""
    @State private var showPicker = false
    /// 解析结果（按下「解析」或选完短信后填）
    @State private var parsed: ParsedFields?

    let onSave: (String, String, String?, String?, String?) -> Void

    struct ParsedFields {
        var isPickup: Bool
        var code: String
        var address: String
        var courier: String
        var station: String
        var shelf: String
        var locker: String
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("短信原文") {
                    TextEditor(text: $text)
                        .frame(minHeight: 110)
                        .font(AppTheme.TypeScale.body)
                    Button {
                        runParse()
                    } label: {
                        Label("解析这条短信", systemImage: "sparkle.magnifyingglass")
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 6)
                }

                Section("从已有短信挑选") {
                    Button {
                        showPicker = true
                    } label: {
                        HStack {
                            Text("打开取件卡片列表")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if let parsed {
                    Section {
                        if parsed.isPickup {
                            parsedRow("判定", "快递短信")
                            parsedRow("快递公司", parsed.courier.isEmpty ? "未识别" : parsed.courier)
                            parsedRow("取件码", parsed.code.isEmpty ? "未识别" : parsed.code)
                            parsedRow("地址", parsed.address.isEmpty ? "未识别" : parsed.address)
                            if !parsed.shelf.isEmpty { parsedRow("货架", parsed.shelf) }
                            if !parsed.locker.isEmpty { parsedRow("柜位", parsed.locker) }
                            if !parsed.station.isEmpty { parsedRow("驿站", parsed.station) }
                        } else {
                            parsedRow("判定", "不是取件短信（内容里没有可用的取件凭证）")
                        }
                    } header: {
                        Text("拾码的解析结果")
                    } footer: {
                        Text("下面是拾码自己解析出来的值。可以在「标注」里直接改成正确的，导出时会带上你改的版本。")
                    }
                    if parsed.isPickup {
                        Section {
                            Button {
                                code = parsed.code
                                address = parsed.address
                                label = "pickup"
                            } label: {
                                Label("用解析结果填充下方标注", systemImage: "arrow.down.doc")
                            }
                        }
                    }
                }

                Section("标注（可修改）") {
                    Picker("这是快递短信吗", selection: $label) {
                        Text("是（取件通知）").tag("pickup")
                        Text("不是").tag("other")
                    }
                    .pickerStyle(.segmented)
                    TextField("正确取件码（可空）", text: $code)
                        .textInputAutocapitalization(.never)
                    TextField("正确地址（可空）", text: $address)
                    TextField("备注（可空）", text: $note)
                }

                Section {
                    Text("手机号、身份证、邮箱会自动脱敏。若原文含姓名，请自行改成「张三」这类占位。")
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("添加样本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(text, label, code, address, note)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 6)
                }
            }
            .sheet(isPresented: $showPicker) {
                TrainingRecordPickerView { record in
                    text = record.rawMessage
                    runParse()
                    showPicker = false
                }
            }
        }
    }

    private func parsedRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(AppTheme.TypeScale.body)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(AppTheme.TypeScale.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func runParse() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { parsed = nil; return }
        guard let result = PickupParser.parse(trimmed) else {
            parsed = ParsedFields(isPickup: false, code: "", address: "",
                                  courier: "", station: "", shelf: "", locker: "")
            return
        }
        let station = StationDirectory.shared.matchedName(in: [trimmed]) ?? ""
        parsed = ParsedFields(isPickup: true,
                              code: result.value,
                              address: result.address,
                              courier: result.courier.isEmpty ? result.company : result.courier,
                              station: station,
                              shelf: result.shelf,
                              locker: result.locker)
    }
}

// MARK: 取件卡片列表（整屏挑选）

struct TrainingRecordPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let onPick: (PickupRecord) -> Void

    /// 按收信时间倒序（最新的在最上面），与列表页口径一致
    private var records: [PickupRecord] {
        let sorted = PickupStore.shared.records.sorted { $0.receivedAt > $1.receivedAt }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.rawMessage.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if records.isEmpty {
                    Text("还没有取件记录。")
                        .foregroundStyle(.secondary)
                }
                ForEach(records) { record in
                    Button {
                        onPick(record)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(record.courierDisplay ?? record.company)
                                    .font(AppTheme.TypeScale.rowTitleMedium)
                                Text(record.code)
                                    .font(AppTheme.TypeScale.body.weight(.semibold))
                                    .monospaced()
                                Spacer(minLength: 0)
                                Text(record.isPickedUp ? "已取" : "待取")
                                    .font(AppTheme.TypeScale.badge)
                                    .foregroundStyle(.secondary)
                            }
                            if !record.address.isEmpty {
                                Text(record.address)
                                    .font(AppTheme.TypeScale.note)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Text(record.rawMessage)
                                .font(AppTheme.TypeScale.note)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "搜索短信内容")
            .navigationTitle("选择一条短信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
