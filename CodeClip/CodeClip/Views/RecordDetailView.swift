import SwiftUI
import UIKit

// MARK: ============================================================================
// 取件详情
//
// 版式口径（2026-09-21 重排）
// --------------------------
// · **主操作全部收进顶部一张卡**：平台 + 类别标签在左上、取件码居中、
//   复制按钮缩成纯图标放在取件码右上角、底部内嵌「标记为已取」。
//   原先落在页面底部的那颗独立大按钮已取消 —— 从列表点进来后，
//   拇指不必再跨半屏去够，取件时的动作全部在首屏完成。
//
// · **卡片底 = 品牌色磨砂玻璃**：颜色取自该品牌**官方图标**的调色板
//   （tools/extract_brand_palette.py 提取，见 BrandPalette.swift），
//   再叠一层超薄材质做磨砂。于是淘宝是橙玻璃、星巴克是绿玻璃、抖音是黑玻璃 ——
//   每家的详情页颜色都不同，扫一眼就知道自己在看哪一家。
//
// · **主操作 = 液态玻璃按钮**：`标记为已取` / `恢复为待取件` 走 `glassEffect`。
//   待取件态用 `.regular.tint(doneTint)` 染色（本页唯一主动作），
//   已取件态退成 `.regular` 中性玻璃 + `.primary` 文字（回退操作，不该抢注意力）。
//   两者都带 `.interactive()` —— 少了它按下时没有形变与高光，就只是块半透明板子。
//   详见 `actionGlass`。
//
//   ⚠️ 这与 DesignSystem.swift 顶部「内容层不用玻璃」的既有口径是有出入的：
//   那条规则针对的是「导航层与内容层争夺层级」，而此处玻璃只出现在详情页的
//   唯一一张主卡上、且被品牌色染透，属于「以材质表达品牌身份」的用法。
//   系统「降低透明度 / 增强对比度」辅助功能下，`.ultraThinMaterial` 会自动
//   退化为不透明底，可读性由系统兜底。
//
// · **信息区改「标签一行、值一行」**：值不折行（长地址靠缩字自适应）。
//   原来的左右对齐在长地址上会被挤成三四行，扫读时视线要来回横跳。
// ============================================================================

struct RecordDetailView: View {
    /// 进门时的快照。**只做两个用途**：① 仓库里暂时找不到该记录时的兜底渲染；
    /// ② 提供稳定的 `id` 供实时查询。**永远不直接参与渲染** ——
    /// 否则就是 2026-09-23 主人抓到的那个 bug：点「标记为已取」后仓库已经翻状态，
    /// 详情页却拿着值拷贝纹丝不动，像点了没反应一样。
    private let snapshot: PickupRecord

    init(record: PickupRecord) {
        self.snapshot = record
        // 草稿用进门快照打底，进编辑态时会按仓库最新值重载（见 enterEdit）
        _draft = StateObject(wrappedValue: EditRecordModel(record: record))
    }

    @EnvironmentObject private var store: PickupStore
    /// 驿站名称库（2026-10-15）：详情页「快递驿站」行实时匹配用；
    /// 订阅它，自定义驿站改名/删图后本行同帧刷新（与列表卡片同款）。
    @ObservedObject private var stationDirectory = StationDirectory.shared
    @StateObject private var feedback = CopyFeedbackModel()
    /// 分享预览面板的开关。工程约定：CLI 链路下 `@State` 宏编不过，
    /// 局部状态一律 ObservableObject 承载（见 DesignSystem.swift 顶部）。
    @StateObject private var share = DetailShareModel()
    /// 详情页**原地编辑态**开关（2026-10-14 主人定稿：不弹二级页，就在本页编辑）。
    @StateObject private var edit = DetailEditModel()
    /// 编辑态草稿（字段全部存 String，空 = 可选字段不显示）。
    /// 宏规避口径（见 DesignSystem.swift 顶部）：ObservableObject 承载。
    @StateObject private var draft: EditRecordModel

    /// 🔴 **单一事实源**：视图一律从仓库按 id **实时取**（提醒事项 / 邮件详情页的
    /// 同款做法 —— 详情页永远是数据的镜像，不持有自己的状态）。
    /// 标记已取 / 恢复待取后 `records` 发布变更，本页同帧重绘：
    /// 「已取」徽章出现、取件码划线变灰、按钮切成「恢复为待取件」。
    private var record: PickupRecord {
        store.records.first { $0.id == snapshot.id } ?? snapshot
    }

    private var brand: Color { record.brandColor }

    /// 快递公司的显示值：courier 为 nil / 空时与平台保持相同
    /// （2026-09-23 主人定：平台与快递公司一边没匹配到就互为同值）。
    private var courierDisplay: String {
        if let courier = record.courier, !courier.isEmpty { return courier }
        return record.company
    }

    /// 快递驿站名（2026-10-15）：固定驿站/商铺品牌词在短信原文 + 取件地址里
    /// 实时匹配，多个命中取最长词条；匹配不到 = 这条没有驿站（如韵达加盟
    /// 门店「林成驾校店」这类地址，不是固定驿站品牌，不进词表）。
    private var stationName: String? {
        stationDirectory.matchedName(in: [record.address, record.rawMessage])
    }

    /// 品牌官方图标的调色板；未收录的品牌回落到「品牌主色 + 它的暗色档」
    private var palette: [Color] {
        let info = CourierBrand.info(for: record.company)
        let hexes = BrandPalette.colors(forAsset: info.asset) ?? [info.from, info.to]
        return hexes.map { Color(hex: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                codeCard

                // 取件地址地图卡（2026-10-14 方案 B）：MapKit 迷你预览 +
                // 点按跳 Apple 地图步行导航。地址为空（极少数手输记录）时隐藏。
                if !record.address.trimmingCharacters(in: .whitespaces).isEmpty {
                    AddressMapCard(address: record.address)
                }

                infoCard
                rawMessageCard
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        // 🔴 状态翻转的过渡挂在**整页内容**上：标记已取 / 恢复待取的一瞬，
        //    徽章淡入、划线延伸、按钮换文案与玻璃染色同步弹簧过渡，
        //    而不是各元素各自硬跳。数据驱动（value:），不会误伤滚动等无关动画。
        .animation(.spring(response: 0.35, dampingFraction: 0.82),
                   value: record.isPickedUp)
        // 编辑态进出同样整页过渡：值行 ↔ 输入框整组换，逐元素硬跳会显得页面在抖。
        .animation(.spring(response: 0.30, dampingFraction: 0.85),
                   value: edit.isEditing)
        // 页面底 = 浅灰，卡片才是白（2026-09-23 修正）
        .background(Color(.systemGroupedBackground))
        .navigationTitle(record.company)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // #51 分享卡片：与列表长按菜单、多选分享**共用同一个面板**
                // （先看图，再分享）。🔴 不再走 `ShareLink` ——
                // 全 App 的「分享卡片」只保留一个口径，见 PickupShareCard.swift。
                Button {
                    share.showing = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("分享卡片")
            }

            // 编辑（2026-10-14 主人定稿）：**不弹二级页**，就在本页原地进入编辑态 ——
            // 信息区的值行换 TextField，「完成」统一提交（见 commitEdit）。
            ToolbarItem(placement: .topBarTrailing) {
                if edit.isEditing {
                    Button("完成") { commitEdit() }
                        .fontWeight(.semibold)
                } else {
                    Button("编辑") { enterEdit() }
                }
            }
        }
        .sheet(isPresented: $share.showing) {
            SharePreviewSheet(records: [record])
        }
        // 截图脚手架：`SIMCTL_CHILD_EDIT=1` 启动即进编辑态（原地编辑没有
        // 菜单入口可脚本化，与列表页 SELECT_MODE 同一思路）。
        .onAppear {
            if ProcessInfo.processInfo.environment["EDIT"] == "1" {
                enterEdit()
            }
        }
    }

    // MARK: 原地编辑（2026-10-14 主人定稿）

    /// 进入编辑态：草稿按**仓库最新值**重载（不是进门快照 —— 进门后可能
    /// 已标记过已取，草稿要拿当前真值打底）。
    private func enterEdit() {
        draft.load(record)
        edit.isEditing = true
    }

    /// 「完成」：草稿归一后整条提交，退出编辑态。
    ///
    /// 归一口径与添加链路一致（Models.swift `commitAll`）：
    ///   · 空串 → nil（可选字段留空 = 不显示）；
    ///   · `id` / `receivedAt` / `isPickedUp` / `pickedUpAt` / `kind` 不参与编辑
    ///     —— kind 是解析期的后台分类，详情页不展示也不让改（主人 2026-10-14 定）；
    ///   · 取件码（主凭证）必填，为空则不提交（保持在编辑态）。
    private func commitEdit() {
        guard !draft.code.trimmed.isEmpty else { return }
        let edited = PickupRecord(
            company: draft.company.trimmed,
            code: draft.code.trimmed,
            kind: record.kind,
            address: draft.address.trimmed,
            rawMessage: record.rawMessage,
            receivedAt: record.receivedAt,
            isPickedUp: record.isPickedUp,
            courier: draft.courier.trimmed.isEmpty ? nil : draft.courier.trimmed,
            waybill: draft.waybill.trimmed.isEmpty ? nil : draft.waybill.trimmed,
            tail: draft.tail.trimmed.isEmpty ? nil : draft.tail.trimmed,
            shelf: draft.shelf.trimmed.isEmpty ? nil : draft.shelf.trimmed,
            pickedUpAt: record.pickedUpAt
        )
        store.update(edited)
        edit.isEditing = false
    }

    // MARK: 顶部主卡（品牌色磨砂玻璃）

    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 行 1：平台图标 + 平台名（左上角一组） ──
            // 注：类别标签（KindTag）在详情页不展示 —— kind 只是解析期的
            // 后台分类，用户不需要知道「这条是按取件码还是运单号命中的」
            // （2026-10-14 主人定稿）。列表卡片上的标签保留。
            HStack(spacing: 8) {
                CourierLogo(company: record.company, size: 26)

                Text(record.company)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 6)

                if record.isPickedUp {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("已取")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppTheme.doneTint, in: .capsule)
                }
            }

            // ── 行 2：取件码（居中）+ 右上角复制 ──
            // 🔴 长凭证避让（2026-09-23 主人指认：15 位运单号尾部被复制按钮盖住）：
            //    光缩字号治标 —— 码区仍占满整卡宽，尾部永远钻进按钮底下。
            //    布局上让 Text 右侧空出 34pt（按钮 32pt + 2pt 间隙）才是根治；
            //    字号 46→40 再降一档，15 位长码的缩字幅度更小、更清晰。
            ZStack(alignment: .topTrailing) {
                record.emphasizedCodeText(isDone: record.isPickedUp, tint: record.brandColor)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospaced()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .strikethrough(record.isPickedUp, color: .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, 34)
                    .padding(.vertical, 18)

                copyButton
                    .padding(.top, 6)
            }

            // 分割线已去掉（2026-09-23 主人要求）：取件码区与动作按钮之间
            // 只留间距，不做任何分界 —— 玻璃卡是一个整体，中间横一道虚线
            // 反而把它切成了上下两截。

            // ── 行 3：标记为已取（原先在页面底部，现收进卡内） ──
            actionButton
        }
        .padding(AppTheme.cardPadding + 3)
        .frame(maxWidth: .infinity)
        .background { glassBackground }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 0.5)
        }
    }

    private var actionButton: some View {
        Button {
            // 触感随语义走（工程先例：CameraScanner 成功用 notification、
            // CardMenu 用 impact）：「标记为已取」是完成态 → success 震动；
            // 「恢复为待取件」是回退 → medium 轻点即可。
            if record.isPickedUp {
                store.markPending(record)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } else {
                store.markPicked(record)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } label: {
            Label(record.isPickedUp ? "恢复为待取件" : "标记为已取",
                  systemImage: record.isPickedUp
                      ? "arrow.uturn.backward" : "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(record.isPickedUp ? Color.primary : Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassEffect(actionGlass,
                             in: .rect(cornerRadius: AppTheme.innerRadius,
                                       style: .continuous))
                .contentShape(.rect(cornerRadius: AppTheme.innerRadius))
        }
        .buttonStyle(.plain)
    }

    /// 主操作按钮的液态玻璃。
    ///
    /// · **待取件 → 「标记为已取」**：`.regular.tint(doneTint.opacity(0.65))` 给玻璃**染一层薄色**。
    ///   染色后的玻璃仍是透光的（能看到底下品牌色卡背在流动），比原来的实心填充更有层次，
    ///   同时把「这是本页唯一主动作」讲清楚。
    ///   ⚠️ **tint 不能给满**：`.tint(doneTint)` 也就是 alpha=1 时，玻璃会被染成一块
    ///   不透明的墨绿，玻璃感全丢 —— 主人原话「不如已取件那个有质感」就是这个原因。
    ///   0.65 是在**真实卡背**上并排比对 0.50 / 0.65 / 0.80 三档选出来的：
    ///   0.50 绿色发灰；0.80 又回到实心感；0.65 既透出紫色卡背、上缘又有玻璃高光。
    /// · **已取件 → 「恢复为待取件」**：完全不加 tint，退成**中性玻璃**。它是个回退操作，
    ///   不该和主动作抢注意力；去掉染色后文字改 `.primary`，中性玻璃上用白字会糊。
    /// · `.interactive()` 两态都不能省 —— 少了它按下时没有形变与高光，
    ///   玻璃就只是块半透明板子，「液态」没了。
    private var actionGlass: Glass {
        record.isPickedUp
            ? .regular.interactive()
            : .regular.tint(AppTheme.doneTint.opacity(0.65)).interactive()
    }

    /// 纯图标复制按钮：去掉文字后不再和「标记为已取」抢视觉，
    /// 32pt 命中区对一个次要操作足够（HIG 建议 44pt 是针对主操作）。
    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = record.code
            feedback.flash()
        } label: {
            Image(systemName: feedback.copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(feedback.copied ? AppTheme.doneTint : brand)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: .circle)
                .overlay { Circle().strokeBorder(brand.opacity(0.30), lineWidth: 1) }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(feedback.copied ? "已复制取件码" : "复制取件码")
    }

    /// 品牌色磨砂玻璃：品牌调色板渐变（底）+ 超薄材质（面）
    private var glassBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    palette[0].opacity(0.62),
                    palette[0].opacity(0.24),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 第 2 / 3 色从另外两个角补进来，避免整卡只有一种色的单调渐变
            if palette.count > 1 {
                RadialGradient(colors: [palette[1].opacity(0.50), .clear],
                               center: .bottomTrailing,
                               startRadius: 0, endRadius: 210)
            }
            if palette.count > 2 {
                RadialGradient(colors: [palette[2].opacity(0.38), .clear],
                               center: .topTrailing,
                               startRadius: 0, endRadius: 165)
            }

            Rectangle().fill(.ultraThinMaterial)
        }
    }

    // MARK: 信息区（标签一行 / 值一行；编辑态值行换 TextField）

    /// 顺序按**取件动线**排（2026-10-14 主人定稿）：报什么码 → 去哪取 →
    /// 货架在哪 → 次要凭证 → 入库时间。「信息类别」不展示（后台分类，
    /// 见主卡行 1 注释）。
    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Divider 与字段同生共死（放进 editableBlock 内）—— 否则可选字段
            // 空值隐藏时会留下两条紧邻的分隔线。
            editableBlock(label: "取件码", value: record.code, keyPath: \.code,
                          mono: true, tint: brand, required: true)

            editableBlock(label: "取件平台", value: record.company, keyPath: \.company,
                          divider: true)

            // 只读态 courier 空 → 显示平台值（2026-09-23 定：互为同值）
            editableBlock(label: "快递公司", value: courierDisplay, keyPath: \.courier,
                          placeholder: "默认与平台相同", divider: true)

            // 快递驿站（2026-10-15 主人定稿）：与「取件地址」是两个概念 ——
            // 驿站 = 固定驿站 / 商铺品牌名（菜鸟驿站、喵站、多多代收点…），由
            // StationDirectory 从短信原文 + 地址实时匹配，不落库、不可手改。
            // 匹配不到：只读态整行隐藏；编辑态显「未识别」占位
            //（主人 10-15 定：编辑时所有字段都要显示）。
            if edit.isEditing || !(stationName ?? "").isEmpty {
                infoBlock(label: "快递驿站", value: stationName ?? "未识别",
                          tint: stationName == nil ? Color(.tertiaryLabel) : .primary,
                          divider: true)
            }

            // 取件地址 = 解析器从短信「到 XX 取」提取的具体地址
            //（如「即墨区闫家岭小区西区林成驾校店」），可手改补填。
            editableBlock(label: "取件地址", value: record.address, keyPath: \.address,
                          placeholder: "如 XX小区XX号", divider: true)

            // 货架号紧跟驿站（取件时真正用来找包裹的那串），次要凭证退后
            editableBlock(label: "货架号", value: record.shelf ?? "", keyPath: \.shelf,
                          mono: true, tint: brand, placeholder: "如 3-12", divider: true)

            // 运单号 / 尾号：解析引擎从短信自动提取，**编辑态也不提供填写**
            // （2026-10-14 主人定：手改会与短信原文脱节，只做只读核对）。
            editableBlock(label: "运单号", value: record.waybill ?? "", keyPath: \.waybill,
                          mono: true, editable: false, divider: true)

            editableBlock(label: "尾号", value: record.tail ?? "", keyPath: \.tail,
                          mono: true, editable: false, divider: true)

            // 添加时间只读：入库时刻由系统记录，不允许手改
            infoBlock(label: "添加时间", value: record.shortTime, divider: true)
        }
        .padding(.vertical, 4)
        .cardSurface()
    }

    /// 一条信息 = 标签一行 + 值一行。
    ///
    /// 值**不折行**（`lineLimit(1)` + 缩字）：长地址折成三行会把「标签—值」的配对
    /// 关系打断，反而更难读。缩到 0.72 仍放不下的极端长地址才会截断。
    private func infoBlock(label: String,
                           value: String,
                           mono: Bool = false,
                           tint: Color = .primary,
                           divider: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if divider {
                Divider().padding(.horizontal, 16)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)

                Text(value)
                    .font(.system(size: 16,
                                  weight: mono ? .semibold : .regular,
                                  design: mono ? .rounded : .default))
                    .monospaced(mono)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
    }

    /// 可编辑字段行：编辑态换 TextField（绑草稿），只读态换 Text（**传仓库实时值**，
    /// 不用草稿 —— 草稿进门时加载，标记已取后会陈旧）。
    ///
    /// 🔴 空值行为分两态：**只读态留空即整行隐藏**（可选字段没有值就不占版面）；
    ///    **编辑态常驻**并显示 placeholder（不然用户看不到有这个字段可填）。
    ///    取件码（`required`）是主凭证，两态都常驻。
    /// 🔴 `editable: false` = 编辑态也只读（运单号 / 尾号这类解析提取字段，
    ///    见 infoCard 调用处注释）。
    private func editableBlock(label: String,
                               value: String,
                               keyPath: ReferenceWritableKeyPath<EditRecordModel, String>,
                               mono: Bool = false,
                               tint: Color = .primary,
                               placeholder: String = "",
                               required: Bool = false,
                               editable: Bool = true,
                               divider: Bool = false) -> some View {
        Group {
            // 显示条件：必填（主凭证）恒显 · 有值恒显 · **编辑态全部恒显**
            //（2026-10-15 主人定：编辑时所有字段都要显示，便于用户编辑 ——
            //  可选字段空值时编辑态也要占位，不能再整行隐藏）。
            if required || !value.trimmed.isEmpty || edit.isEditing {
                VStack(alignment: .leading, spacing: 0) {
                    if divider {
                        Divider().padding(.horizontal, 16)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(label)
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)

                        if edit.isEditing && editable {
                            TextField(placeholder, text: Binding(
                                get: { draft[keyPath: keyPath] },
                                set: { draft[keyPath: keyPath] = $0 }))
                                .font(.system(size: 16,
                                              weight: mono ? .semibold : .regular,
                                              design: mono ? .rounded : .default))
                                .monospaced(mono)
                                .foregroundStyle(tint)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                        } else if value.trimmed.isEmpty {
                            // 编辑态不可编辑字段（运单号 / 尾号）的空值占位 ——
                            // 主人 2026-10-15 定：编辑时所有字段都要显示，
                            // 解析没提取到的字段显「未识别」，不留空白一行。
                            Text("未识别")
                                .font(.system(size: 16))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        } else {
                            Text(value)
                                .font(.system(size: 16,
                                              weight: mono ? .semibold : .regular,
                                              design: mono ? .rounded : .default))
                                .monospaced(mono)
                                .foregroundStyle(tint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .allowsTightening(true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }
            }
        }
    }

    // MARK: 原始短信

    private var rawMessageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(brand)
                Text("原始短信")
                    .font(.footnote.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)

            Text(record.rawMessage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

// MARK: - 局部状态

/// 详情页分享面板的开关。
///
/// 工程约定（见 DesignSystem.swift 顶部）：CLI 链路下 `@State` 等 SwiftUI 宏
/// 编不过，局部状态一律 ObservableObject + `@StateObject` 承载。
@MainActor
private final class DetailShareModel: ObservableObject {
    @Published var showing = false
}

/// 详情页原地编辑态开关（2026-10-14 主人定稿：编辑不弹二级页）。
@MainActor
final class DetailEditModel: ObservableObject {
    @Published var isEditing = false
}

// MARK: - 编辑草稿（详情页原地编辑专用）

/// 编辑态草稿：字段全部存 String（可选字段的空 = nil 在提交时归一）。
///
/// 原为二级编辑页（EditRecordView）的模型，2026-10-14 主人定稿「编辑就在
/// 详情页」后随原地编辑一并收编到这里。
final class EditRecordModel: ObservableObject {
    @Published var company = ""
    @Published var courier = ""
    @Published var address = ""
    @Published var code = ""
    @Published var waybill = ""
    @Published var tail = ""
    @Published var shelf = ""

    init(record: PickupRecord) {
        load(record)
    }

    /// 按记录装载草稿（进编辑态 / 外部刷新都走这里）。
    func load(_ record: PickupRecord) {
        company = record.company
        courier = record.courier ?? ""
        address = record.address
        code = record.code
        waybill = record.waybill ?? ""
        tail = record.tail ?? ""
        shelf = record.shelf ?? ""
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
