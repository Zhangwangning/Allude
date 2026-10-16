import SwiftUI
import UIKit

// MARK: ============================================================================
// 取件码分享卡片（#51）
//
// 主人指定：分享出去的是**一张卡片图片**，不是链接 —— 收到的人一眼看到
// 平台、取件码、地址，不需要点开任何东西。落地方式：
//   · `PickupShareCard` 用固定浅色版式画卡（分享图固定浅色，无论收发双方
//     各自的外观设置，白底黑字在聊天流里都可读）；
//   · `ImageRenderer` 按 3x 渲染成 UIImage；
//   · 分享面板统一为 `SharePreviewSheet`（**先看图，再分享**）—— 长按菜单、
//     详情页工具栏、多选分享三个入口共用同一个面板，口径完全一致；
//     面板里的「更多分享」再交系统（UIActivityViewController）给微信 / QQ /
//     抖音 / 支付宝，分享的是图片本体，渠道不受本 App 控制。
//   · ⚠️ 面板**必须挂在页面层**，不能挂进长按浮层：菜单一收，条件渲染的浮层
//     连同其中的呈现者一起销毁，面板根本弹不出来（踩坑记录见 CardMenu.swift）。
//
// 多码分享（2026-09-23 主人定，当晚修订）：
//   · 列表页进入多选模式，可一次分享多条 —— 一张图上多个取件码；
//   · **版式取舍**：多码卡不再逐条铺全部信息，每行 = 图标 + 快递公司 +
//     取件码 + **该条自己的地址** —— 分享的多条不一定在同一个地方，
//     地址必须跟着各自的记录走，不能用第一条的糊弄全部（主人指认）；
//   · **上限 12 行**：选了超过 12 条时，相同快递公司（含驿站）聚合成一行，
//     取件码只显示该组第一条，公司名后标「×N」（地址取组首的）；
//     聚合后仍超过 12 组的极端情况，多余的在卡尾用一行「另有 N 件未列出」交代；
//   · 单条版式与多码版式是**同一 struct 的两个分支** —— 渲染管线、
//     固定浅色、署名行完全共用，只有中段不同。
//
// 渲染细节：
//   · 卡内**不用语义色**（.primary / .secondary）—— ImageRenderer 的环境
//     不可控，语义色会随渲染环境漂移；全部显式定色；
//   · CourierLogo 的官方图标来自 Assets，ImageRenderer 可正常画出。
// ============================================================================

/// 多码分享卡上的一行：组首记录 + 该快递公司的件数（单条组 count = 1）。
struct PickupShareLine: Identifiable {
    let record: PickupRecord
    let count: Int
    var id: UUID { record.id }
}

/// 分享卡版式（固定浅色，脱离环境）。
struct PickupShareCard: View {
    let records: [PickupRecord]

    /// 单条分享（详情页 / 长按菜单的原入口）
    init(record: PickupRecord) { self.records = [record] }
    /// 多条分享（多选模式）
    init(records: [PickupRecord]) { self.records = records }

    /// 多码卡的行数上限：超过即触发同司聚合（2026-09-23 主人定：6 → 12）
    static let maxLines = 12

    private var tint: Color { records.first?.brandColor ?? Color(hex: 0x0B63F3) }
    private var isSingle: Bool { records.count <= 1 }

    var body: some View {
        if isSingle {
            singleCard
        } else {
            multiCard
        }
    }

    // MARK: 单条版式（390×500，保持不变）

    private var singleRecord: PickupRecord { records[0] }

    @ViewBuilder
    private var singleCard: some View {
        let record = singleRecord
        VStack(alignment: .leading, spacing: 0) {
            // 顶部：品牌身份行
            HStack(spacing: 12) {
                CourierLogo(company: record.company, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.company)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x1C1C1E))

                    Text(record.kind.label)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.14), in: .capsule)
                        .foregroundStyle(tint)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 30)

            // 中部：取件码是唯一主角
            VStack(alignment: .leading, spacing: 10) {
                record.emphasizedCodeText(tint: tint)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospaced()
                    .minimumScaleFactor(0.35)
                    .lineLimit(1)

                if !record.address.isEmpty {
                    Text(record.address)
                        .font(.system(size: 15))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .foregroundStyle(Color(hex: 0x6E6E73))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            shareFooter
        }
        .padding(.horizontal, 28)
        .frame(width: 390, height: 500, alignment: .top)
        .background { shareBackground }
    }

    // MARK: 多码版式（宽 390，高度随行数）

    /// 2–12 条：逐条一行；>12 条：同快递公司聚合，组首码 + ×N。
    private var lines: [PickupShareLine] {
        if records.count <= Self.maxLines {
            return records.map { PickupShareLine(record: $0, count: 1) }
        }
        // 按快递公司（含驿站）聚合，保持首次出现顺序，组首 = 第一条的取件码
        var order: [String] = []
        var firsts: [String: PickupRecord] = [:]
        var counts: [String: Int] = [:]
        for record in records {
            if firsts[record.company] == nil {
                order.append(record.company)
                firsts[record.company] = record
            }
            counts[record.company, default: 0] += 1
        }
        return order.prefix(Self.maxLines).compactMap { key in
            firsts[key].map { PickupShareLine(record: $0, count: counts[key] ?? 1) }
        }
    }

    /// 聚合截断后没能上卡的件数（仅 >12 条且分组数 >12 时 >0）
    private var omittedCount: Int {
        guard records.count > Self.maxLines else { return 0 }
        let shown = lines.reduce(0) { $0 + $1.count }
        return records.count - shown
    }

    @ViewBuilder
    private var multiCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            multiHead
            multiLines
            shareFooter
                .padding(.top, 12)
        }
        .padding(.horizontal, 28)
        .frame(width: 390, height: multiCardHeight, alignment: .top)
        .background { shareBackground }
    }

    /// 多码卡总高：头部 28+44 + 间距 12 + 行区（码行 50 / 带地址行 69）
    /// + 省略行 26 + 页脚 56。地址行按**实际有地址的条数**累加。
    private var multiCardHeight: CGFloat {
        let lineList = lines
        let addressRows = lineList.filter { !$0.record.address.isEmpty }.count
        let rowsHeight = lineList.count * 50 + addressRows * 19
        let omittedRow: Int = omittedCount > 0 ? 26 : 0
        return CGFloat(28 + 44 + 12 + rowsHeight + omittedRow + 12 + 18 + 26)
    }

    /// 卡头：件数。地址不在这里 —— 多条不一定同地，地址跟各自的行走（主人指认）。
    /// 图标用**软件图标**（AppMark），不是第一家快递 —— 多条来自不同快递时，
    /// 抬头摆任何一家的图标都误导（2026-09-23 主人指认）。
    private var multiHead: some View {
        HStack(spacing: 12) {
            AppMarkIcon(size: 40)

            Text("待取 \(records.count) 件")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color(hex: 0x1C1C1E))

            Spacer(minLength: 0)
        }
        .padding(.top, 28)
    }

    /// 行区：每行 = 图标 + 公司 +（×N）+ 码；聚合截断后补省略行
    private var multiLines: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                if index > 0 {
                    Rectangle()
                        .fill(Color(hex: 0x1C1C1E).opacity(0.08))
                        .frame(height: 0.5)
                }
                lineRow(line)
            }

            if omittedCount > 0 {
                Text("另有 \(omittedCount) 件未列出")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0x8E8E93))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }
        .padding(.top, 14)
    }

    /// 多码卡上的一行：码行 + 该条**自己的地址**（空则不画）。
    /// 取件码用**该行自己**的品牌色 —— 行与行颜色不同，扫一眼就能对上「哪行是哪家」。
    /// 聚合行（×N）地址取组首的：同公司大概率同驿站，属于聚合本来就接受的取舍。
    private func lineRow(_ line: PickupShareLine) -> some View {
        let tint = line.record.brandColor
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                CourierLogo(company: line.record.company, size: 22)

                Text(line.record.company)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(Color(hex: 0x1C1C1E))

                if line.count > 1 {
                    Text("×\(line.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(tint, in: .capsule)
                }

                Spacer(minLength: 8)

                line.record.emphasizedCodeText(tint: tint)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospaced()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }

            let address = line.record.address.trimmingCharacters(in: .whitespaces)
            if !address.isEmpty {
                Text(address)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Color(hex: 0x8E8E93))
                    .padding(.leading, 32)   // 与公司名对齐（图标 22 + 间距 10）
            }
        }
        .padding(.vertical, 10.5)
    }

    // MARK: 共用部件

    /// 底部：来源署名 + 时间（单条显示记录时间，多条显示渲染时刻）
    private var shareFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            Text("码夹 CodeClip · 待取件")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x8E8E93))

            Spacer(minLength: 0)

            Text((records.first?.receivedAt ?? Date())
                .formatted(.dateTime.month().day().hour().minute()))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Color(hex: 0xAEAEB2))
        }
        .padding(.bottom, 26)
    }

    /// 白底 + 顶部品牌色氛围渐变（与 App / 小组件同一口径）
    private var shareBackground: some View {
        ZStack(alignment: .top) {
            Color.white
            LinearGradient(colors: [tint.opacity(0.12), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 140)
        }
    }
}

// MARK: - 分享预览面板（单条 / 多条共用）

/// 分享图渲染：**弹出面板那一刻才渲染**（选中集随时在变，预渲染没有意义）。
@MainActor
private final class SharePreviewModel: ObservableObject {
    let image: UIImage?
    /// 非 nil 时在预览页之上再弹系统分享面板（App 列表由系统给出）
    @Published var showActivity = false
    /// 保存 / 拷贝完成后的短暂勾选反馈
    @Published var saved = false
    @Published var copied = false
    private var resetTask: Task<Void, Never>?

    init(records: [PickupRecord]) {
        let renderer = ImageRenderer(content: PickupShareCard(records: records))
        renderer.scale = 3
        self.image = renderer.uiImage
    }

    /// 勾选态 1.4s 后回弹
    func resetFlagsLater() {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            self?.saved = false
            self?.copied = false
        }
    }
}

/// 分享预览面板（2026-09-24 主人定）：**先看图，再分享** ——
/// 上半是渲染好的分享卡大图预览，底部一行快捷操作：
/// 保存图片 / 拷贝图片 / 更多分享。
/// 微信、QQ 等第三方 App 的图标行在「更多分享」的系统面板里 ——
/// iOS 不允许自绘直跳其它 App 带图分享，应用列表只能由系统给出。
///
/// **单条与多条共用**：单条传 `[record]`（走单条版式），多条传选中集（走多码版式），
/// 两个入口的分享体验因此完全一致。
///
/// ⚠️ 它必须挂在**页面**上，不能挂进长按浮层：面板的呈现者要比菜单活得久 ——
/// 长按菜单收起时会连同浮层一起被摘掉，挂在其内的呈现者（曾经的 `ShareLink`）
/// 会因锚点消失而根本弹不出来（踩坑记录见 `CardMenu.swift`）。
struct SharePreviewSheet: View {
    @StateObject private var model: SharePreviewModel
    @Environment(\.dismiss) private var dismiss

    init(records: [PickupRecord]) {
        _model = StateObject(wrappedValue: SharePreviewModel(records: records))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let image = model.image {
                    ScrollView {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
                            .padding(.horizontal, 28)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    // 渲染失败不该静默 —— 页面底色占位，面板仍可关闭
                    Color(.systemGroupedBackground)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("分享取件码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { quickActions }
            .sheet(isPresented: $model.showActivity) {
                if let image = model.image {
                    ActivityShareSheet(activityItems: [image])
                }
            }
        }
    }

    /// 底部快捷行：保存 / 拷贝 / 更多分享。动作完成图标短暂变绿勾。
    private var quickActions: some View {
        HStack(spacing: 12) {
            if let image = model.image {
                QuickShareAction(icon: model.saved ? "checkmark" : "square.and.arrow.down",
                                 title: model.saved ? "已保存" : "保存图片",
                                 highlight: model.saved) {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    model.saved = true
                    model.resetFlagsLater()
                }
                QuickShareAction(icon: model.copied ? "checkmark" : "doc.on.doc",
                                 title: model.copied ? "已拷贝" : "拷贝图片",
                                 highlight: model.copied) {
                    UIPasteboard.general.image = image
                    model.copied = true
                    model.resetFlagsLater()
                }
            }
            QuickShareAction(icon: "square.and.arrow.up", title: "更多分享",
                             highlight: false) {
                model.showActivity = true
            }
        }
        .padding(.horizontal, AppTheme.hInset)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

/// 快捷分享按钮：竖排圆底图标 + 文字，横向均分。
/// 取件码分享与车票分享共用（internal，跨文件复用）。
struct QuickShareAction: View {
    let icon: String
    let title: String
    let highlight: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(highlight ? Color.green.opacity(0.15)
                                          : Color(.secondarySystemGroupedBackground),
                                in: Circle())
                    .foregroundStyle(highlight ? Color.green : Color.primary)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// 系统分享面板的 SwiftUI 包装（分享预览面板的「更多分享」用）。
struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
