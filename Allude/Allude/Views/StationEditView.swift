import SwiftUI
import PhotosUI

// MARK: - 自定义驿站编辑页（2026-10-15 主人定稿）
//
// 添加与编辑合并为同一页面：
//   · 名称必填，图标**可选** —— 不换图标则按名称首字自动生成（CourierLogo 兜底）；
//   · 图标来源不限（系统相册任意图片），保存后统一按圆角矩形呈现；
//   · 编辑模式可改名、可换图、可删除；内置驿站没有这个入口（只读）。

struct StationEditView: View {

    enum Mode: Equatable {
        case add
        case edit(String)   // 原名称
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var station = StationDirectory.shared
    /// 位置摘要要跟着设置页的改动即时刷新（2026-11-16 到达提醒）
    @ObservedObject private var locationStore = StationLocationStore.shared

    @State private var name: String
    /// 图标原始数据：编辑态预填当前图标；添加态为 nil（未选）
    @State private var iconData: Data?
    /// 本次是否真的换过图（决定保存时是否写盘，避免无变化也重存）
    @State private var iconChanged = false
    @State private var pickerSelection: PhotosPickerItem?
    @State private var showPicker = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showDeleteConfirm = false

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            _name = State(initialValue: "")
            _iconData = State(initialValue: nil)
        case .edit(let original):
            _name = State(initialValue: original)
            _iconData = State(initialValue: StationDirectory.shared.iconData(for: original))
        }
    }

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var originalName: String? {
        if case .edit(let name) = mode { return name }
        return nil
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool { !trimmedName.isEmpty }

    private var corner: CGFloat { 96 * 0.29 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                iconCard
                nameCard

                // 自定义驿站：添加完点格子进来，就能设位置；
                // 内置驿站走网格里的同一个编辑页，不必经过这里。
                if isEdit {
                    locationCard
                }

                Text(isEdit
                     ? "改名后，卡片会自动按新名称从短信里识别。留空图标则显示名称首字。"
                     : "不添加图标时，卡片与网格里会按名称首字自动生成图标。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                if isEdit {
                    deleteButton
                }
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(isEdit ? "编辑驿站" : "添加驿站")
        .navigationBarTitleDisplayMode(.inline)
        .cloaksTabBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerSelection,
                      matching: .images, photoLibrary: .shared())
        .task(id: pickerSelection) {
            guard let item = pickerSelection else { return }
            if let data = try? await item.loadTransferable(type: Data.self) {
                iconData = data
                iconChanged = true
            }
            pickerSelection = nil
        }
        .alert("无法保存", isPresented: $showError) {
            Button("好", role: .cancel) { }
        } message: {
            Text(errorMessage.L)
        }
        .alert(isEdit ? "删除这个驿站？" : "放弃添加？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                if let original = originalName { station.remove(named: original) }
                dismiss()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text(isEdit
                 ? "删除后，卡片将不再自动标注「\(originalName ?? "")」。"
                 : "当前编辑的内容不会被保存。")
        }
    }

    // MARK: 图标卡（点预览即换图）

    private var iconCard: some View {
        VStack(spacing: 14) {
            // 点预览图直接弹系统相册；角标提示「可更换」
            PhotosPicker(selection: $pickerSelection, matching: .images, photoLibrary: .shared()) {
                preview
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(AppTheme.accent, in: .circle)
                            .offset(x: 8, y: 8)
                    }
            }
            .buttonStyle(.plain)

            Text("点按图标从相册选择（可选）")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    /// 预览优先级：已选新图 > 当前名称兜底首字（首字实时跟着输入变）
    @ViewBuilder
    private var preview: some View {
        if let data = iconData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(.primary.opacity(0.10), lineWidth: 0.5)
                }
        } else if !trimmedName.isEmpty {
            CourierLogo(company: trimmedName, size: 96)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(AppTheme.accent.opacity(0.12))
                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(width: 96, height: 96)
        }
    }

    // MARK: 名称卡

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("驿站名称")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            TextField("如「XX 便利店代收」", text: $name)
                .font(.system(size: 16))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    // MARK: 位置与到达提醒（仅编辑态）

    /// 内置 / 自定义共用 `StationLocationEditor`；这里只做入口与状态摘要。
    private var locationCard: some View {
        NavigationLink {
            StationLocationEditor(stationName: originalName ?? "")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.violet)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("位置与到达提醒")
                        .font(AppTheme.TypeScale.bodyMedium)
                        .foregroundStyle(.primary)
                    Text(locationSummary)
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(AppTheme.TypeScale.rowSubtitle.weight(.semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(.plain)
    }

    private var locationSummary: String {
        guard let original = originalName,
              let loc = locationStore.location(for: original) else {
            return "未设置。设好后，到店时若有该驿站的待取件会提醒你。"
        }
        return loc.enabled ? "已设置并启用到达提醒" : "已设置位置，未启用到达提醒"
    }

    // MARK: 删除（仅编辑态）

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            Text("删除驿站")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.10),
                            in: .rect(cornerRadius: AppTheme.innerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: 保存

    private func save() {
        guard !trimmedName.isEmpty else {
            errorMessage = "名称不能为空"
            showError = true
            return
        }

        if let original = originalName {
            // 编辑：先改名（重名会失败并提示），再按新名存图
            if trimmedName != original {
                guard station.rename(original, to: trimmedName) else {
                    errorMessage = "名称与内置或已有驿站重复"
                    showError = true
                    return
                }
            }
            if iconChanged, let data = iconData {
                station.setIcon(data, for: trimmedName)
            }
        } else {
            // 添加：先建名，再存图
            guard station.add(trimmedName) else {
                errorMessage = "名称与内置或已有驿站重复"
                showError = true
                return
            }
            if let data = iconData {
                station.setIcon(data, for: trimmedName)
            }
        }
        dismiss()
    }
}

// MARK: - 添加驿站 · 居中弹窗（2026-11-08 主人定）

/// 参考系统 alert 版式：半透明蒙层 + 居中玻璃卡，两个胶囊按钮（取消 / 保存）。
/// 原来「添加驿站」是推入的独立页面，主人要求改成弹窗，不再切换页面。
struct StationAddDialog: View {
    var onDismiss: () -> Void

    @ObservedObject private var station = StationDirectory.shared

    @State private var name = ""
    @State private var iconData: Data?
    @State private var pickerSelection: PhotosPickerItem?
    @State private var errorMessage: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("添加驿站")
                .font(AppTheme.TypeScale.rowTitle.weight(.semibold))
                .padding(.top, 4)

            // 图标（可选）：点一下从相册挑，没选就按名称首字自动生成
            PhotosPicker(selection: $pickerSelection, matching: .images, photoLibrary: .shared()) {
                iconPreview
            }
            .buttonStyle(.plain)

            TextField("驿站名称，如「XX 便利店代收」", text: $name)
                .font(AppTheme.TypeScale.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let errorMessage {
                Text(errorMessage.L)
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(AppTheme.pendingTint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                dialogButton("取消", filled: false) { onDismiss() }
                dialogButton("保存", filled: true) { save() }
                    .disabled(trimmedName.isEmpty)
                    .opacity(trimmedName.isEmpty ? 0.5 : 1)
            }
        }
        .padding(20)
        .frame(maxWidth: 320)
        // 🔴 弹窗要**读得清**：玻璃太透会透出后面的品牌图标。
        //    用系统厚材质打底 + 细描边 + 阴影，观感与系统 alert 一致。
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .padding(.horizontal, 28)
        .task(id: pickerSelection) {
            guard let item = pickerSelection else { return }
            if let data = try? await item.loadTransferable(type: Data.self) {
                iconData = data
            }
            pickerSelection = nil
        }
    }

    @ViewBuilder
    private var iconPreview: some View {
        ZStack {
            if let iconData, let image = UIImage(data: iconData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else if !trimmedName.isEmpty {
                CourierLogo(company: trimmedName, size: 84)
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: 84, height: 84)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(5)
                .background(AppTheme.accent, in: .circle)
                .offset(x: 6, y: 6)
        }
        .accessibilityLabel("选择图标")
    }

    private func dialogButton(_ title: String,
                              filled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.TypeScale.body.weight(.semibold))
                .foregroundStyle(filled ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .appGlass(.capsule,
                          tint: filled ? AppTheme.accent : nil,
                          interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        guard station.add(trimmedName) else {
            errorMessage = "名称与内置或已有驿站重复"
            return
        }
        if let iconData { station.setIcon(iconData, for: trimmedName) }
        onDismiss()
    }
}
