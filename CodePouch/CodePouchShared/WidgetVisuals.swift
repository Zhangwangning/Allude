import SwiftUI
import AppIntents
import WidgetKit

// MARK: ============================================================================
// 小组件可视层（App 与小组件扩展共同编译）
//
// 为什么放在共享层而不是 Widget target：
//   桌面小组件在模拟器上无法脚本化添加，唯一的「真实渲染证据」是在 App 内用
//   **同一份视图代码**按小组件尺寸渲染一次。放在共享层后，设置页里的「小组件预览」
//   也不用手写副本 —— 之前 SettingsView 里那个 MediumWidgetPreview 就是手工复刻，
//   两份代码一旦漂移就会出现「设置页看着好好的、桌面却不一样」的假象。
//
// 版式口径（2026-09-21 定稿）：
//   · **不放快递平台图标** —— 行首图标占宽约 41pt，去掉后全部让给取件码与地址；
//   · **取件码是唯一主角** —— 每行只有两级信息：取件码（大字）→ 平台｜地址（小字）；
//   · **行首圆形勾选框** —— 与 App 内 CompleteButton 同源，可直接在桌面点掉。
//
// ⚠️ 本文件不得使用 SwiftUI 宏（#Preview / @State），原因见 DesignSystem.swift 顶部。
// ============================================================================

// MARK: - 停用态（已删除 · 2026-09-23）
//
// 这里原有 `WidgetDisabledContent`：用户在「设置 › 桌面小组件」关掉总开关后
// 桌面显示的「小组件已关闭」占位版式。总开关已被主人判定为无意义并整体删除
// （理由见 `PickupStorage.swift` 顶部同名注释），没有"关闭"这个状态了，
// 因此这块版式也一并退场 —— 保留它就是留一段永远画不到的死代码。

// MARK: - 圆形勾选框（可点击）

/// 小组件里的「标记已取」按钮。
///
/// 与 App 内 CompleteButton 的差别：
///   · 尺寸压缩到 21~22pt（小组件行高只有约 40pt）；
///   · 点击后由 `TogglePickupIntent` 直接写 App Group，不打开 App。
///
/// 小组件只展示「待取件」，因此 isDone 目前恒为 false（空心圆环）；
/// 参数保留是为了付费版大尺寸展示已取记录时可以直接复用。
struct WidgetCheckCircle: View {
    let isDone: Bool
    let tint: Color
    let recordID: String
    var size: CGFloat = 21

    var body: some View {
        Button(intent: TogglePickupIntent(recordID: recordID)) {
            ZStack {
                Circle()
                    .strokeBorder(isDone ? tint : Color.secondary.opacity(0.55),
                                  lineWidth: max(1.6, size * 0.085))
                    .frame(width: size, height: size)

                if isDone {
                    Circle()
                        .fill(tint)
                        .frame(width: size, height: size)

                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            // 点击热区：圈本身只有 21pt，可点面积太小；
            // 扩到 32pt 仍在本行高预算内，且不改变视觉尺寸。
            .frame(width: 32, height: 32)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDone ? "已取件，轻点可恢复为待取件" : "标记为已取件")
    }
}

// MARK: - 细分隔线

/// 不用系统 `Divider()`：它会随环境 tint 变色，在小组件里与 App 内的分隔线观感不一致。
struct WidgetHairline: View {
    var body: some View {
        Rectangle()
            .fill(.separator.opacity(0.5))
            .frame(height: 0.5)
    }
}

// MARK: - 翻页控件（上下翻动查看）
//
// 为什么不是「滑动」：小组件**不支持原生滚动** —— 已对 iOS 27 SDK 的 WidgetKit /
// SwiftUI 接口逐一核实（无任何滚动相关 API），Apple 在 Meet WidgetKit 里也明确说
// List / ScrollView 在小组件内不滚动。真机表现是内容被裁掉、手指划不动。
//
// 可行且真能用的机制只有 iOS 17+ 的可交互小组件：两个 `Button(intent:)` 改页码、
// 重画时间线。用户按住上/下箭头即可逐页翻看，效果等同「上下翻动」。
//
// 页码写进 App Group（见 `WidgetPaging`），因此翻页不唤醒主 App 也能持久。

struct WidgetPager: View {
    let page: Int
    let pageCount: Int
    let familyKey: String

    var body: some View {
        HStack(spacing: 0) {
            chevron("chevron.up", delta: -1, label: "上一页")

            Text("\(page + 1)/\(pageCount)")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 1)

            chevron("chevron.down", delta: 1, label: "下一页")
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.14), in: .capsule)
    }

    private func chevron(_ symbol: String, delta: Int, label: String) -> some View {
        Button(intent: WidgetPageIntent(familyKey: familyKey,
                                        delta: delta)) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.secondary)
                // 箭头本身只有 9pt，可点面积扩到 18×16 —— 小组件上的手指精度更差，
                // 视觉尺寸不变但命中率翻倍。
                .frame(width: 18, height: 16)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - 翻页意图（写页码 + 重画）

/// 小组件内的上/下翻页动作。
///
/// ⚠️ `familyKey` / `delta` 必须是 `@Parameter`：
/// `Button(intent:)` 会被系统**归档成一个实例标识**再在扩展进程里还原，
/// 只有 `@Parameter` 标注的属性会进归档。写成普通存储属性会在还原后变成默认值 ——
/// 表现就是「点了没反应」或「永远停在第一页」。
struct WidgetPageIntent: AppIntent {
    static var title: LocalizedStringResource { "翻页" }

    /// 与 `TogglePickupIntent` 同一口径：小组件内部指令，不进快捷指令 / 聚焦列表
    static var isDiscoverable: Bool { false }

    /// 纯后台：翻页绝不把 App 拉到前台
    /// 🔴 部署目标降到 iOS 18：`IntentModes`（含 `.background`）是 iOS 26 新增。
    ///    改用等价的 `openAppWhenRun = false`（iOS 16 起可用）：后台执行、不拉起 App。
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "尺寸")
    var familyKey: String

    @Parameter(title: "方向")
    var delta: Int

    init() {}

    init(familyKey: String, delta: Int) {
        self.familyKey = familyKey
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        // 与 `WidgetSnapshot.load()` 同一口径：翻页可及的最大条数也要按档位裁，
        // 否则免费用户在免费档上能翻到第 4 条以后（列表里根本没有那些条目）。
        let isPro = EntitlementSnapshot.licensedPro
        let cap = isPro ? PickupLimits.widgetListCap : PickupLimits.freeVisible

        // 现数一遍页数，不复用可视层传进来的值：翻页意图可能在任何时刻被唤醒，
        // 期间用户可能已经取走几件，用旧页数会翻到空白页。
        let count = min(PickupStorage.load()
            .filter { !$0.isPickedUp }
            .count, cap)
        let size = WidgetPageSize.rowCount(family: familyKey)
        let pageCount = max(1, Int(ceil(Double(count) / Double(size))))

        let current = WidgetPaging.page(family: familyKey)
        // 首尾**环形**相接：翻到最后再往下回到第 1 页。
        // 比「禁用按钮」少两个状态要渲染，也避免用户以为小组件卡住了。
        let next = ((current + delta) % pageCount + pageCount) % pageCount
        WidgetPaging.setPage(next, family: familyKey)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - 分页列表内容（中 / 大 / 超大尺寸共用）
//
// 三个尺寸只有「一页几行」不同，版式完全一致 —— 所以是同一个视图 + 一个 pageSize，
// 不是三份会各自漂移的副本。

struct WidgetPagedContent: View {
    let snapshot: WidgetSnapshot
    let pageSize: Int
    let familyKey: String
    /// 二级信息行显示哪几项（"我的 › 桌面小组件 › 显示内容"）。
    /// 默认 `.full` = 改版前的版式，免费版就是这样。
    var options: WidgetDisplayOptions = .full

    private var pageCount: Int { snapshot.pageCount(pageSize: pageSize) }
    private var current: Int {
        snapshot.clampedPage(WidgetPaging.page(family: familyKey),
                             pageSize: pageSize)
    }
    private var rows: [PickupRecord] { snapshot.pageItems(current, pageSize: pageSize) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 7)

            WidgetHairline()

            // 🔴 2026-10-28 主人：「数据少的时候仍然不能改变字号、行间距」。
            //
            // 原先是 `.frame(maxHeight: .infinity)` —— 行高按**剩余高度均分**：
            // 满页 8 条时每行 36pt，只有 2 条时每行会被拉到 140pt，
            // 进来一看就像「字变大了、行距变松了」，与满页完全是两种观感。
            //
            // 现在改成**行高恒定 = 满页时的行高**（可用高度 ÷ 每页条数），
            // 数据不足一页时多出来的空间留在底部，任何行数下字号与行距都一致。
            GeometryReader { geo in
                // 🔴 2026-11-08 修「内容重叠」：
                //    行高来自「可用高度 ÷ 每页条数」，高度不够时它会小于一行的自然高度，
                //    而 `.frame(height:)` **不会裁剪**内容 —— 第一行的第二行文字就压到了
                //    第二行上，看起来像串行。三处一起兜住：
                //      · 行高设下限（够放码 + 一行副标题），
                //      · 每行 `.clipped()`，任何溢出都截在本行内，
                //      · 外层随后由卡片 clipShape 兜底。
                let rawRowHeight = geo.size.height / CGFloat(max(pageSize, 1))
                let rowHeight = max(rawRowHeight, 28)
                VStack(spacing: 0) {
                    ForEach(rows) { record in
                        WidgetPickupRow(record: record, options: options)
                            .frame(height: rowHeight, alignment: .top)
                            .clipped()
                    }
                    // 不足一页时补空槽：向用户传达「就这些了」，而不是「还没加载完」。
                    ForEach(0 ..< snapshot.placeholderRows(page: current, pageSize: pageSize),
                            id: \.self) { _ in
                        WidgetPlaceholderRow()
                            .frame(height: rowHeight, alignment: .top)
                            .clipped()
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 头部：分类标题 + 真实总数 +（Pro 截断提示 / 今日已取）+ 翻页控件。
    ///
    /// 「Pro」与「今日已取」互斥显示：被截断时说明「为什么只看到这几条」
    /// 远比今天的成绩重要，两者同排会把头部挤到换行。
    /// 🔴 文案不带「免费版」「付费版」—— 对外只有「拾码 CodePouch」与「拾码 Pro」
    ///    （2026-11-01 主人）。组部件里空间紧，这里用最短的「Pro」。
    private var header: some View {
        HStack(spacing: 6) {
            Text("待取件")
                .font(.system(size: 13, weight: .semibold))

            Text("\(snapshot.pendingTotal)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.pendingTint)

            Spacer(minLength: 0)

            if snapshot.isTruncated {
                freeBadge
            } else if snapshot.pickedTodayCount > 0 {
                todayChip
            }

            if pageCount > 1 {
                WidgetPager(page: current,
                            pageCount: pageCount,
                            familyKey: familyKey)
            }
        }
    }

    private var freeBadge: some View {
        HStack(spacing: 2.5) {
            Image(systemName: "lock.fill")
                .font(.system(size: 8.5, weight: .bold))
            Text("Pro")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(AppTheme.todayTint)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var todayChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
            Text("今日已取 \(snapshot.pickedTodayCount)")
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(AppTheme.doneTint)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - 小尺寸内容（3-4 条纯取件码）

/// 小尺寸（158×158）的专用版式。
///
/// 🔴 **2026-10-27 主人定稿**：「小尺寸……就显示重要信息，取件码就行」
///    + 「一次性显示三到四个取件码信息就行」。
/// 也就是：**每条只留取件码**（不显示公司 / 驿站 / 地址 / 类型标签），
/// 但**条数要够**——只放一条等于浪费了这块地方，用户还得回 App 里看别的。
///
/// 高度预算（158 − 上下 16 padding = 126pt）：
///   头部 20 + 分隔线 6 + 上间距 6 + 4 行（21×4 + 3 间距×3 = 93）= 125pt，刚好放满。
/// 超过 4 条时不画「+N」提示 —— 头部右侧就是待取总数，用户能看出还有更多。
struct WidgetSmallContent: View {
    let snapshot: WidgetSnapshot
    /// 显示项。这里**不用**它决定显示哪些字段（小尺寸恒只画取件码），
    /// 保留参数是为了与其他尺寸的调用签名一致，将来若要加"柜位"再用。
    var options: WidgetDisplayOptions = .full

    /// 最多 4 条：再挤字号就要掉到 15pt 以下，长码（15 位运单号）会糊成一团。
    private static let maxRows = 4

    private var visible: [PickupRecord] {
        Array(snapshot.items.prefix(Self.maxRows))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("待取件")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Text("\(snapshot.pendingTotal)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.pendingTint)
            }

            WidgetHairline()
                .padding(.top, 5)

            VStack(spacing: 3) {
                ForEach(visible) { record in
                    HStack(spacing: 6) {
                        // 勾选圈缩到 16pt：4 行只有 21pt 行高，再大就溢出了。
                        // 仍可直接点（WidgetCheckCircle 自带 AppIntent 按钮），
                        // 只是这里的热区偏小 —— 真要勾取建议点开 App，这一页主要是"看码"。
                        WidgetCheckCircle(isDone: false,
                                          tint: record.codeColor,
                                          recordID: record.id.uuidString,
                                          size: 16)

                        record.emphasizedCodeText(tint: record.codeColor)
                            // 🔴 四行**字号完全统一**（2026-10-27 主人：「字体大小都保持一致」）。
                            //    不做按码长缩放、也不做 minimumScaleFactor：
                            //    取件码是 AttributedString，缩放对富文本本来就不生效，
                            //    而"短码 17pt / 长码 11pt"混排更难看 —— 一屏四种大小，
                            //    像没做完的列表。统一 15pt（2026-10-27 主人：「稍微小一点，
                            //    有点大了」——之前 17pt 四行贴得很满），真放不下的长码走尾部省略号。
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospaced()
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 0)
                    }
                    .frame(height: 21)
                }
            }
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - 单行（中尺寸）

struct WidgetPickupRow: View {
    let record: PickupRecord
    /// 二级信息行的显示项。`.full` = 平台｜地址（改版前版式）。
    var options: WidgetDisplayOptions = .full

    var body: some View {
        HStack(spacing: 8) {
            // 行首圆形勾选框：与 App 内 CompleteButton 同款视觉，可直接点
            WidgetCheckCircle(isDone: false,
                              tint: record.codeColor,
                              recordID: record.id.uuidString,
                              size: 21)

            VStack(alignment: .leading, spacing: 2) {
                // 第一行：取件码（主角）+ 柜位 + 必要的类别标签
                HStack(spacing: 5) {
                    record.emphasizedCodeText(tint: record.codeColor)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospaced()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    // 柜位 / 货架（2026-10-27 主人）：有就显示，没有就空着。
                    // 它是到柜那一刻要用的信息，紧跟取件码最省眼动。
                    if let spot = record.widgetLockerLabel(options) {
                        Text(spot.L)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    // 🔴 类型标签全部去掉（2026-10-27 主人：「运单号、尾号、特殊码也不要了，
                    // 是哪个类型对用户没啥意义」）。小组件里这行的宽度要全留给
                    // 取件码和柜位，标签占位不划算；类型信息在详情页仍可查。
                }

                // 第二行：按显示设置拼（可能是「平台｜地址」「只有平台」「整行不画」）。
                // 取件码那行不动 —— 它不参与配置。
                if let subtitle = record.widgetSubtitle(options) {
                    Text(subtitle.L)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 4)

            Text(record.clockTime.L)
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

// MARK: - 空槽（保持行高稳定）

struct WidgetPlaceholderRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .strokeBorder(.quaternary, lineWidth: 1.6)
                .frame(width: 21, height: 21)
                .frame(width: 32, height: 32)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.quaternary)
                .frame(width: 78, height: 9)

            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 空态

struct WidgetEmptyContent: View {
    let pickedTodayCount: Int
    var compact: Bool = false

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(AppTheme.doneTint.opacity(0.15))
                    .frame(width: compact ? 34 : 42, height: compact ? 34 : 42)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: compact ? 18 : 22))
                    .foregroundStyle(AppTheme.doneTint)
            }

            Text("暂无待取件")
                .font(.system(size: compact ? 12.5 : 13.5, weight: .semibold))

            if !compact {
                // 有成绩先报成绩，没有才铺引导语 —— 空态里最想知道的是「之前那些怎么样了」。
                Text(pickedTodayCount > 0
                     ? "今天已取 \(pickedTodayCount) 件"
                     : "收到取件短信后会自动出现在这里")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 勾选意图（桌面直接标记「已取」）
//
// 用途：小组件每行取件码前的圆形勾选框是一个可点击按钮，点击即把该条标记为已取，
// 不需要打开 App —— iOS 17+ 允许小组件内的 Button(intent:) 直接执行 AppIntent。
//
// 架构说明：本条是「小组件只读」原则的**唯一例外**。理由是该操作不产生新数据、
// 不跑正则、只翻转一个既有字段，并且用户预期桌面上的勾选框与 App 内行为一致
// （点不动会被当成故障）。写回的仍是 App Group 共享 JSON，与主 App 同一份。
//
// ⚠️ 主 App 侧配套：小组件改文件时主 App 可能正在后台持有内存副本，
//    因此 CodeClipApp 在回到前台（scenePhase == .active）时会重新读盘，
//    避免出现「桌面已勾、App 里还没勾」的两份状态。

struct TogglePickupIntent: AppIntent {
    static var title: LocalizedStringResource { "标记取件状态" }

    /// 不出现在「快捷指令 / 聚焦」的意图列表里：这是小组件内部指令，
    /// 用户手动编排快捷指令时看到「标记取件状态」只会造成困惑。
    static var isDiscoverable: Bool { false }

    /// 只支持后台执行：点勾选框只是翻一个字段，绝不把 App 拉到前台。
    /// 🔴 部署目标降到 iOS 18：`IntentModes`（含 `.background`）是 iOS 26 新增。
    ///    改用等价的 `openAppWhenRun = false`（iOS 16 起可用）：后台执行、不拉起 App。
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "记录 ID")
    var recordID: String

    init() {}

    init(recordID: String) {
        self.recordID = recordID
    }

    func perform() async throws -> some IntentResult {
        var all = PickupStorage.load()
        guard let index = all.firstIndex(where: { $0.id.uuidString == recordID }) else {
            return .result()
        }
        all[index].isPickedUp.toggle()
        // 时间戳与状态成对改（口径同 App 侧 `PickupStore.setPicked`）：
        // 桌面上点的这一下同样是真实的取件时刻，统计页要认它。
        all[index].pickedUpAt = all[index].isPickedUp
            ? (all[index].pickedUpAt ?? Date())
            : nil
        PickupStorage.save(all)
        // 立即重画，否则要等系统下一个刷新周期才看到勾选结果
        WidgetCenter.shared.reloadAllTimelines()
        // 锁屏实时活动必须同步跟上：这个意图跑的进程**不一定是 App**
        // （点小组件上的勾选框时是扩展进程），App 的 store 根本不会醒，
        // 所以这里直接推一次 —— 否则锁屏会一直挂着那条已经被取走的码。
        PickupActivityController.sync(pending: all.filter { !$0.isPickedUp })
        return .result()
    }
}

// MARK: - 预览 / 占位用示例数据
//
// 服务于四处：小组件坑位（placeholder）、小组件图库预览、App 内预览页的兜底、
// 以及三类新分类小组件的图库预览。放在共享层是因为 App target 也要用它。

extension WidgetSnapshot {
    /// 示例数据。**14 条**：既够「竖版超大」铺满一页（14 行/页），
    /// 又超过其它尺寸的一页（中 3 / 大 6），翻页控件也能被看到。
    /// 前两条压测两个极端 —— 最长凭证（15 位运单号）与最长标签（「特殊取件码」）
    /// 同时出现时仍要能单行排下。
    static var samples: [PickupRecord] {
        let now = Date()
        /// `locker` / `shelf` 是有意给值的（2026-10-27）：
        /// 设置页新增了「显示快递柜/货架」开关，示例数据若全是空的，
        /// 用户打开这个开关会看不出任何变化 —— 预览要能证明开关有用。
        /// 第 1 条演示柜口、第 5 条演示货架（驿站场景没有柜，走货架兜底）。
        func record(_ company: String, _ code: String, _ kind: PickupKind,
                    _ address: String, _ minutesAgo: Int,
                    message: String = "",
                    shelf: String? = nil, locker: String? = nil) -> PickupRecord {
            PickupRecord(company: company, code: code, kind: kind, address: address,
                         rawMessage: message.isEmpty ? "【\(company)】取件码 \(code)" : message,
                         receivedAt: now.addingTimeInterval(-Double(minutesAgo) * 60),
                         shelf: shelf, locker: locker)
        }

        return [
            record("兔喜生活", "C-4082", .code, "恒大御府南门西侧3栋104号", 26,
                   locker: "2号柜"),
            // 第 2 条刻意让「短信平台」与「驿站」不同（韵达发的件放在菜鸟驿站）：
            // 这样预览里能同时看到「韵达快递｜菜鸟驿站｜地址」三段，
            // 证明公司 / 驿站 / 地址是三个独立字段，不是同一个值换皮。
            record("韵达快递", "313105790279994", .waybill, "馨月湖小区南门兴裕隆超市", 95,
                   message: "【韵达快递】您的包裹已到菜鸟驿站，运单号313105790279994，请凭取件码领取"),
            record("申通快递", "3-7-12", .special, "馨月湖小区北门申通驿站", 130),
            record("菜鸟驿站", "6602", .tail, "恒大御府东门菜鸟驿站", 185),
            record("中通快递", "78-2-3051", .code, "馨月湖小区西门中通超市", 240,
                   shelf: "12-3"),
            record("顺丰速运", "SF1357902468", .waybill, "万寿街顺丰营业点", 310),
            record("圆通速递", "9-3-118", .code, "河西学院北门圆通妈妈驿站", 400),
            record("极兔速递", "JT9901", .code, "新墩镇便民超市", 520),
            // 下面 6 条是为「竖版超大 14 条/页」补的（2026-10-28）：
            // 一页 14 行才看得出这一档到底挤不挤，8 条永远只有半屏。
            // 公司、凭证形态（码/尾号/运单号）、柜口/货架都换着给，避免整页看起来一样。
            record("京东物流", "JD8812", .code, "恒大御府北门京东驿站", 640),
            record("中国邮政", "11185", .tail, "新墩镇邮政代办点", 760),
            record("德邦快递", "DB7745", .code, "万寿街德邦营业部", 880, shelf: "3-2"),
            record("丰巢智能柜", "HL-3021", .code, "恒大御府东门丰巢柜", 1000, locker: "8号柜"),
            record("天猫超市", "TM5540", .code, "馨月湖小区北门天猫驿站", 1180),
            record("极兔速递", "JT2088", .tail, "河西学院东门极兔驿站", 1360),
        ]
    }

    /// 预览快照（App 内「桌面小组件」页与 `SCREEN=widgets`）。
    ///
    /// 🔴 2026-10-30：**按档位裁**。免费档桌面本来就只看得到 3 条，
    ///    预览却铺 10 条还带翻页控件，等于给人看一个自己用不上的形态。
    ///    `PRO` 环境变量（`0` / `1`）可强制档位 —— 命令行没法改真实权益文件，
    ///    要靠它一次拍出「免费 / 买断」两种观感（`tools/widget-shots.sh` 用它）。
    static func preview() -> WidgetSnapshot {
        let forced = ProcessInfo.processInfo.environment["PRO"]
        let isPro = forced == "1" ? true
            : forced == "0" ? false
            : EntitlementSnapshot.licensedPro
        let visible = isPro ? samples : Array(samples.prefix(PickupLimits.freeVisible))

        return WidgetSnapshot(items: visible,
                              // 头部数字用**真实总数**，与线上口径一致：
                              // 免费档也要显示「还有 7 件」，否则会被读成"一共就 3 件"。
                              pendingTotal: samples.count,
                              pickedTodayCount: 2)
    }
}
