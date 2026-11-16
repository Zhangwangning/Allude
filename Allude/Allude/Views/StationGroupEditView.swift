import SwiftUI
import PhotosUI

// MARK: - 驿站组编辑页（2026-11-17 主人）
//
// 一个「驿站组」就是一个**全新的驿站**：有自己的名称、图标、位置。
// 三项各自独立，可以自定义，也可以「只从某一个成员继承」——
// 继承是**动态引用**（成员换图 / 换位置，组立刻跟着变），不是复制一份快照。
//
// 成员关系挂的是成员**驿站 ID**（`NZYZ…` / `DZYYZ…`），所以成员改名不会断链。
// 一个成员只能进一个组：选一个已在别组里的成员时，会明确提示「将从原组移出」。

struct StationGroupEditView: View {

    enum Mode: Equatable {
        case create
        /// 编辑已有组：传组 ID（`FZYD…`），不传名字 —— 名字可以改，ID 不会变
        case edit(String)
    }

    /// 图标来源三档
    enum IconMode: String, CaseIterable, Identifiable {
        case fallback
        case custom
        case inherit

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fallback: "名称首字"
            case .custom:   "自定义图片"
            case .inherit:  "继承成员"
            }
        }
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var station = StationDirectory.shared
    @ObservedObject private var locationStore = StationLocationStore.shared

    @State private var name: String
    @State private var selectedMemberIDs: Set<String>
    @State private var iconMode: IconMode
    @State private var iconData: Data?
    @State private var iconInheritMemberID: String?
    @State private var locationInheritMemberID: String?
    @State private var pickerSelection: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _selectedMemberIDs = State(initialValue: [])
            _iconMode = State(initialValue: .fallback)
            _iconInheritMemberID = State(initialValue: nil)
            _locationInheritMemberID = State(initialValue: nil)

        case .edit(let id):
            let group = StationGroupStore.group(id: id)
            _name = State(initialValue: group?.name ?? "")
            _selectedMemberIDs = State(initialValue: Set(group?.memberIDs ?? []))
            _iconInheritMemberID = State(initialValue: group?.iconInheritMemberID)
            _locationInheritMemberID = State(initialValue: group?.locationInheritMemberID)

            let inherited = group?.iconInheritMemberID != nil
            let customData = group.flatMap { StationDirectory.shared.iconData(for: $0.id) }
            _iconData = State(initialValue: customData)
            _iconMode = State(initialValue: inherited ? .inherit : (customData != nil ? .custom : .fallback))
        }
    }

    // MARK: 基础

    private var groupID: String? {
        if case .edit(let id) = mode { return id }
        return nil
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// **已保存**的组名（位置表的 key 用它 —— 编辑页里改了名还没保存时，
    /// 不能拿新名字去写位置，否则会多出一条孤儿记录）
    private var savedGroup: StationGroup? {
        guard let groupID else { return nil }
        return StationGroupStore.group(id: groupID)
    }

    private var canEditLocation: Bool {
        savedGroup != nil && trimmedName == savedGroup?.name
    }

    private var allCandidates: [(id: String, name: String)] {
        station.allNames.compactMap { name in
            guard let id = StationIdentity.id(for: name) else { return nil }
            return (id, name)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                nameCard
                iconCard
                locationCard
                memberCard

                if let errorMessage {
                    Text(errorMessage.L)
                        .font(.caption)
                        .foregroundStyle(AppTheme.pendingTint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                Text("组是独立的一个驿站：待取 / 已取页只显示组名，卡面副名仍保留「组名/成员原名」。解散组后成员会原地恢复独立显示，历史记录不受影响。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)

                if groupID != nil {
                    deleteButton
                }
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(groupID == nil ? "新建驿站组" : "编辑驿站组")
        .navigationBarTitleDisplayMode(.inline)
        .cloaksTabBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { save() }
                    .fontWeight(.semibold)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .photosPicker(isPresented: Binding(
            get: { pickerSelection != nil },
            set: { if !$0 { pickerSelection = nil } }
        ), selection: $pickerSelection, matching: .images, photoLibrary: .shared())
        .task(id: pickerSelection) {
            guard let item = pickerSelection else { return }
            if let data = try? await item.loadTransferable(type: Data.self) {
                iconData = data
                iconMode = .custom
            }
            pickerSelection = nil
        }
        .alert("解散这个驿站组？", isPresented: $showDeleteConfirm) {
            Button("解散", role: .destructive) { deleteGroup() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("成员会恢复成独立驿站，历史记录与取件状态都不受影响。组自己的图标与位置会被清除。")
        }
    }

    // MARK: 名称

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("组名")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            TextField("如「恒大御府驿站」", text: $name)
                .font(.system(size: 16))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Text("不能与内置驿站、自定义驿站或其它组同名。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: 图标

    private var iconCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                iconPreview
                VStack(alignment: .leading, spacing: 4) {
                    Text("图标")
                        .font(AppTheme.TypeScale.bodyMedium)
                    Text(iconSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Picker("", selection: $iconMode) {
                ForEach(IconMode.allCases) { mode in
                    Text(mode.title.L).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: iconMode) { _, newValue in
                if newValue != .inherit { iconInheritMemberID = nil }
            }

            switch iconMode {
            case .fallback:
                Text("用组名首字自动生成，随名称实时变化。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .custom:
                PhotosPicker(selection: $pickerSelection, matching: .images, photoLibrary: .shared()) {
                    Label("从相册选择图片", systemImage: "photo.badge.plus")
                        .font(AppTheme.TypeScale.bodyMedium)
                }
                .buttonStyle(.bordered)

            case .inherit:
                inheritPicker(selection: $iconInheritMemberID,
                              hint: "选一个成员，组就跟着它换图标；成员换了图，组立刻跟着变。")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    @ViewBuilder
    private var iconPreview: some View {
        let corner: CGFloat = 54 * 0.29
        if iconMode == .custom, let iconData, let image = UIImage(data: iconData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        } else if iconMode == .inherit,
                  let memberID = iconInheritMemberID,
                  let memberName = StationIdentity.name(for: memberID) {
            StationLogo(name: memberName, size: 54, showsShadow: false)
        } else if !trimmedName.isEmpty {
            CourierLogo(company: trimmedName, size: 54, showsShadow: false)
        } else {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(AppTheme.violet.opacity(0.12))
                .frame(width: 54, height: 54)
                .overlay {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.violet)
                }
        }
    }

    private var iconSummary: String {
        switch iconMode {
        case .fallback:
            return "按组名首字生成"
        case .custom:
            return iconData == nil ? "还没选图片，保存后仍按首字兜底" : "使用你选的图片"
        case .inherit:
            guard let memberID = iconInheritMemberID,
                  let memberName = StationIdentity.name(for: memberID) else {
                return "还没选成员"
            }
            return "继承「\(memberName)」的图标"
        }
    }

    // MARK: 位置

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.violet)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("位置与到达提醒")
                        .font(AppTheme.TypeScale.bodyMedium)
                    Text(locationSummary)
                        .font(AppTheme.TypeScale.note)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if let savedName = savedGroup?.name {
                NavigationLink {
                    StationLocationEditor(stationName: savedName)
                } label: {
                    HStack {
                        Text(locationInheritMemberID == nil
                             ? "设置组自己的位置"
                             : "组的位置正在继承成员，点此改用组自己的位置")
                            .font(AppTheme.TypeScale.body)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(AppTheme.TypeScale.rowSubtitle.weight(.semibold))
                            .foregroundStyle(.quaternary)
                    }
                }
                .buttonStyle(.plain)
            }

            inheritPicker(selection: $locationInheritMemberID,
                          hint: "到达提醒只会为组监一个围栏；选「不使用继承」则用组自己的位置。",
                          allowsNone: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var locationSummary: String {
        if let memberID = locationInheritMemberID,
           let memberName = StationIdentity.name(for: memberID) {
            return "继承「\(memberName)」的位置"
        }
        guard canEditLocation, let savedName = savedGroup?.name else {
            if savedGroup == nil {
                return "保存组名后即可设置位置。"
            }
            return "组名改过还没保存 —— 先保存，再设置位置。"
        }
        guard let location = locationStore.location(for: savedName) else {
            return "未设置。设好后，到店时若有该组的待取件会提醒你。"
        }
        return location.enabled ? "已设置并启用到达提醒" : "已设置位置，未启用到达提醒"
    }

    // MARK: 成员

    private var memberCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("成员驿站")
                    .font(AppTheme.TypeScale.bodyMedium)
                Text("\(selectedMemberIDs.count)")
                    .font(AppTheme.TypeScale.note)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }

            Text("选中的驿站会从待取 / 已取页收进这个组。一个驿站只能在一个组里。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVStack(spacing: 0) {
                ForEach(allCandidates, id: \.id) { candidate in
                    Button {
                        toggle(candidate.id)
                    } label: {
                        memberRow(candidate)
                    }
                    .buttonStyle(.plain)

                    if candidate.id != allCandidates.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func memberRow(_ candidate: (id: String, name: String)) -> some View {
        HStack(spacing: 12) {
            StationLogo(name: candidate.name, size: 30, showsShadow: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name.L)
                    .font(AppTheme.TypeScale.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let other = occupiedGroupName(candidate.id) {
                    // 老大第 2 条：只能进一个组，再选进新组要明说「将从原组移出」
                    Text("在「\(other)」里，选中后会移出")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.violet)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Image(systemName: selectedMemberIDs.contains(candidate.id)
                  ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 19))
                .foregroundStyle(selectedMemberIDs.contains(candidate.id)
                                 ? AppTheme.accent : Color.secondary.opacity(0.35))
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
    }

    private func toggle(_ memberID: String) {
        if selectedMemberIDs.contains(memberID) {
            selectedMemberIDs.remove(memberID)
        } else {
            selectedMemberIDs.insert(memberID)
        }
    }

    /// 这个成员现在归在哪个别的组里
    private func occupiedGroupName(_ memberID: String) -> String? {
        for group in StationGroupStore.all() where group.id != groupID {
            if group.memberIDs.contains(memberID) { return group.name }
        }
        return nil
    }

    // MARK: 继承选择器

    @ViewBuilder
    private func inheritPicker(selection: Binding<String?>,
                               hint: String,
                               allowsNone: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                if allowsNone {
                    Button("不使用继承") { selection.wrappedValue = nil }
                }
                // 只列当前组里的成员：继承一个不属于本组的驿站没有意义，
                // 而且成员一旦被移出组，这里就该跟着失效
                ForEach(Array(selectedMemberIDs), id: \.self) { memberID in
                    if let memberName = StationIdentity.name(for: memberID) {
                        Button(memberName) { selection.wrappedValue = memberID }
                    }
                }
            } label: {
                HStack {
                    Text(selection.wrappedValue
                         .flatMap { StationIdentity.name(for: $0) } ?? "选择成员")
                        .font(AppTheme.TypeScale.body)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .disabled(selectedMemberIDs.isEmpty)

            Text(selectedMemberIDs.isEmpty ? "先在下面选成员，再从成员里挑一个继承来源。" : hint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 删除

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            Text("解散驿站组")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.10),
                            in: .rect(cornerRadius: AppTheme.innerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func deleteGroup() {
        guard let groupID else { return }
        StationGroupStore.delete(id: groupID)
        dismiss()
    }

    // MARK: 保存

    private func save() {
        guard !trimmedName.isEmpty else {
            errorMessage = "组名不能为空"
            return
        }
        guard StationGroupStore.isValidGroupName(trimmedName,
                                                excluding: groupID,
                                                builtinAndCustom: station.allNames) else {
            errorMessage = "「\(trimmedName)」与内置驿站、自定义驿站或已有驿站组重复，换一个名字。"
            return
        }

        let members = Array(selectedMemberIDs)
        let inheritIcon = iconMode == .inherit ? iconInheritMemberID : nil
        let inheritLocation = locationInheritMemberID

        if let groupID, var group = StationGroupStore.group(id: groupID) {
            let oldName = group.name
            group.name = trimmedName
            group.memberIDs = members
            group.iconInheritMemberID = inheritIcon
            group.locationInheritMemberID = inheritLocation
            StationGroupStore.update(group)

            // 位置表以名字为 key（与自定义驿站同一套迁移口径）。
            // 组名不进 `StationIdentity` 表 —— 组关系挂的是成员 ID，组本身不需要名字映射。
            if oldName != trimmedName {
                locationStore.rename(from: oldName, to: trimmedName)
            }

            switch iconMode {
            case .custom:
                if let iconData { station.setIcon(iconData, for: groupID) }
            case .fallback, .inherit:
                station.clearIcon(for: groupID)
            }
        } else {
            guard let created = StationGroupStore.create(name: trimmedName,
                                                         memberIDs: members,
                                                         iconInheritMemberID: inheritIcon,
                                                         locationInheritMemberID: inheritLocation) else {
                errorMessage = "创建失败，请换个名字再试。"
                return
            }
            if iconMode == .custom, let iconData {
                station.setIcon(iconData, for: created.id)
            }
        }

        StationGroupStore.invalidateCache()
        dismiss()
    }
}
