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
    /// 新建组时的位置草稿（老大：创建时就能加定位，默认当前位置）
    @State private var draftCoordinate: CLLocationCoordinate2D?
    @State private var showLocationPicker = false

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
        .sheet(isPresented: $showLocationPicker) {
            NavigationStack {
                StationLocationPicker(coordinate: $draftCoordinate,
                                      stationName: trimmedName)
            }
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

    // MARK: 图标（2026-11-17 老大：原来那版「不好」，重做）

    /// 旧版是「一行摘要 + 三段分段控件 + 随模式换内容」：分段控件只有文字，
    /// 选之前完全看不出图标长什么样；继承又用下拉菜单，只能看名字不能看图。
    ///
    /// 现在改成三格**带缩略图**的来源选择：每一格直接画出「选它之后组会长什么样」，
    /// 选中格用紫色描边 + 淡底；下面的补充区只在需要时出现（已选的摘要里已说明的
    /// 就不再重复一遍文字）。
    private var iconCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                iconPreview
                VStack(alignment: .leading, spacing: 3) {
                    Text("图标")
                        .font(AppTheme.TypeScale.bodyMedium)
                    Text(iconSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                ForEach(IconMode.allCases) { mode in
                    iconSourceTile(mode)
                }
            }

            switch iconMode {
            case .fallback:
                // 摘要已写「按组名首字生成」，这里不再重复一句话
                EmptyView()

            case .custom:
                PhotosPicker(selection: $pickerSelection, matching: .images, photoLibrary: .shared()) {
                    Label(iconData == nil ? "从相册选择图片" : "换一张图片",
                          systemImage: "photo.badge.plus")
                        .font(AppTheme.TypeScale.bodyMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.violet.opacity(0.10),
                                    in: .rect(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

            case .inherit:
                memberStrip(selected: $iconInheritMemberID,
                            noneTitle: nil,
                            emptyHint: "先在下面「成员驿站」里选几个成员，再回来挑一个继承来源。")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// 一格来源：缩略图 + 名称，选中即切换。
    private func iconSourceTile(_ mode: IconMode) -> some View {
        let selected = iconMode == mode
        return Button {
            withAnimation(.snappy(duration: 0.18)) { iconMode = mode }
            if mode != .inherit { iconInheritMemberID = nil }
        } label: {
            VStack(spacing: 7) {
                iconTileThumbnail(mode)
                    .frame(height: 36)
                Text(mode.title.L)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? AppTheme.violet : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selected ? AppTheme.violet.opacity(0.10) : Color(.tertiarySystemFill),
                        in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? AppTheme.violet.opacity(0.55) : .clear,
                                  lineWidth: 1.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func iconTileThumbnail(_ mode: IconMode) -> some View {
        switch mode {
        case .fallback:
            // 换成实际首字预览：空名时用一个「驿」占位，让人知道这里会出字
            CourierLogo(company: trimmedName.isEmpty ? "驿" : trimmedName,
                        size: 34, showsShadow: false)
        case .custom:
            if let iconData, let image = UIImage(data: iconData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                placeholderThumb(systemName: "photo")
            }
        case .inherit:
            if let memberID = iconInheritMemberID,
               let memberName = StationIdentity.name(for: memberID) {
                StationLogo(name: memberName, size: 34, showsShadow: false)
            } else {
                placeholderThumb(systemName: "square.stack.3d.up.fill")
            }
        }
    }

    private func placeholderThumb(systemName: String) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AppTheme.violet.opacity(0.12))
            .frame(width: 34, height: 34)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.violet)
            }
    }

    @ViewBuilder
    private var iconPreview: some View {
        let corner: CGFloat = 64 * 0.29
        if iconMode == .custom, let iconData, let image = UIImage(data: iconData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(.primary.opacity(0.10), lineWidth: 0.5)
                }
        } else if iconMode == .inherit,
                  let memberID = iconInheritMemberID,
                  let memberName = StationIdentity.name(for: memberID) {
            StationLogo(name: memberName, size: 64, showsShadow: false)
        } else if iconMode == .custom {
            // 选了「自定义图片」但还没挑图：竖图占位，别后退到首字，免得自相矛盾
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(AppTheme.violet.opacity(0.12))
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(AppTheme.violet)
                }
        } else {
            // 与「名称首字」小格同一预览口径：空名时也用「驿」示意会出什么字
            CourierLogo(company: trimmedName.isEmpty ? "驿" : trimmedName,
                        size: 64, showsShadow: false)
        }
    }

    private var iconSummary: String {
        switch iconMode {
        case .fallback:
            return trimmedName.isEmpty ? "按组名首字生成" : "按「\(trimmedName)」首字生成"
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

    // MARK: 位置（2026-11-17 老大：这里只管定位，不提到达提醒）
    //
    // 两种来源，主操作永远是「在地图上选」——老大要「手动选择，直接点地图」：
    //   · 已保存的组 → 推入 `StationLocationEditor`（读写位置表，还能调半径）；
    //   · 还没保存（新建）→ 弹出草稿选择器，创建时一起落盘，不用先存再设。

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.violet)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("位置")
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
                    locationActionRow(hasLocation: locationStore.location(for: savedName) != nil)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    // 手动选点 = 改用自己的位置，继承自然失效
                    locationInheritMemberID = nil
                })
            } else {
                Button {
                    locationInheritMemberID = nil
                    showLocationPicker = true
                } label: {
                    locationActionRow(hasLocation: draftCoordinate != nil)
                }
                .buttonStyle(.plain)
            }

            if !memberCandidates.isEmpty {
                Divider().opacity(0.6)

                HStack(spacing: 6) {
                    Text("或直接沿用成员的位置")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if locationInheritMemberID != nil {
                        Button("改用自己的位置") {
                            locationInheritMemberID = nil
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.violet)
                    }
                }

                memberStrip(selected: $locationInheritMemberID,
                            noneTitle: nil,
                            emptyHint: nil)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func locationActionRow(hasLocation: Bool) -> some View {
        HStack {
            Text(hasLocation ? "在地图上重新选位置" : "在地图上选择位置")
                .font(AppTheme.TypeScale.body)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(AppTheme.TypeScale.rowSubtitle.weight(.semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(AppTheme.violet.opacity(0.10),
                    in: .rect(cornerRadius: 12, style: .continuous))
        .contentShape(.rect)
    }

    private var locationSummary: String {
        if let memberID = locationInheritMemberID,
           let memberName = StationIdentity.name(for: memberID) {
            return "沿用「\(memberName)」的位置"
        }
        if let savedName = savedGroup?.name,
           let loc = locationStore.location(for: savedName) {
            return String(format: "已设置 %.5f, %.5f", loc.latitude, loc.longitude)
        }
        if let c = draftCoordinate {
            return String(format: "已选 %.5f, %.5f", c.latitude, c.longitude)
        }
        return "未设置"
    }

    // MARK: 成员选择（图标继承 / 位置沿用 共用）

    /// 组里成员的图标横条：点一下 = 选中它当继承来源。
    ///
    /// 🔴 用横条代替下拉菜单的原因：下拉里只有文字，看不出图标/相对位置；
    ///    横条一眼能看到每个成员长什么样，点选也少一次弹出。
    @ViewBuilder
    private func memberStrip(selected: Binding<String?>,
                             noneTitle: String?,
                             emptyHint: String?) -> some View {
        if memberCandidates.isEmpty {
            if let emptyHint {
                Text(emptyHint.L)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if let noneTitle {
                        chip(title: noneTitle,
                             systemImage: "slash.circle",
                             isSelected: selected.wrappedValue == nil, hasLogo: false) {
                            selected.wrappedValue = nil
                        }
                    }
                    ForEach(memberCandidates, id: \.id) { member in
                        chip(title: member.name,
                             systemImage: nil,
                             isSelected: selected.wrappedValue == member.id,
                             hasLogo: true) {
                            selected.wrappedValue = member.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func chip(title: String,
                      systemImage: String?,
                      isSelected: Bool,
                      hasLogo: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                if hasLogo {
                    StationLogo(name: title, size: 40, showsShadow: false)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: systemImage ?? "slash.circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                }

                Text(title.L)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AppTheme.violet : Color.secondary)
                    .lineLimit(1)
                    .frame(width: 52)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(isSelected ? AppTheme.violet.opacity(0.10) : .clear,
                        in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.violet.opacity(0.55) : .clear,
                                  lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }

    /// 组内成员（按名字排序，保证横条顺序稳定）
    private var memberCandidates: [(id: String, name: String)] {
        selectedMemberIDs.compactMap { id -> (id: String, name: String)? in
            guard let name = StationIdentity.name(for: id) else { return nil }
            return (id, name)
        }
        .sorted { $0.name < $1.name }
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
            // 新建时顺手选的位置：挂到组名上（沿用成员位置时不需要，组自己不落点）
            if inheritLocation == nil, let c = draftCoordinate {
                locationStore.set(StationLocation(latitude: c.latitude,
                                                  longitude: c.longitude,
                                                  radius: StationLocation.defaultRadius,
                                                  enabled: true),
                                  for: created.name)
            }
        }

        StationGroupStore.invalidateCache()
        dismiss()
    }
}
