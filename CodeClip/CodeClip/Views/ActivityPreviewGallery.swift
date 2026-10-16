import SwiftUI

// MARK: ============================================================================
// 实时活动预览（App 内 · 真实渲染）
//
// 背景：锁屏卡片与灵动岛**都无法脚本化截图** —— 锁屏要真的把设备锁上，
// 灵动岛只在带灵动岛的机型上由系统绘制。唯一能拿到「真实渲染证据」的办法，
// 与桌面小组件（`WidgetPreviewGallery.swift`）同一套：在 App 内用**同一份视图代码**
// （`CodeClipShared/PickupActivityAttributes.swift`）按各形态的约束渲染一次。
//
// 因此这里不是手工复刻：锁屏卡片与灵动岛四块区域引用的都是共享层那几个
// `ActivityLockScreenCard` / `IslandExpandedContent` / `IslandCompact*` / `IslandMinimal`
// 结构体本身，改版式两处一起变，预览不会与真机漂移。
//
// ⚠️ 唯一「模拟」的成分是外框：锁屏的卡片材质与灵动岛的黑洞形状由系统绘制，
//    这里用等尺寸的外壳近似，只为观察内容的排布与截断。
//
// 入口：`SCREEN=activity`（命令行验收截图）。
// ⚠️ 本文件不得使用 SwiftUI 宏（#Preview / @State），原因见 DesignSystem.swift 顶部。
// ============================================================================

// MARK: - 外框

/// 锁屏 / 通知中心里的活动卡片外壳。
///
/// 真实卡片 = 系统给的圆角 + 半透明材质，再由活动自己的
/// `.activityBackgroundTint(...)` 叠一层品牌色。这里把同一套叠加顺序复现一次：
/// 材质在下、品牌色（opacity 0.10）在上 —— 顺序反了颜色会脏。
struct ActivityCardShell: View {
    let tint: Color
    let content: AnyView

    init(tint: Color, @ViewBuilder content: () -> some View) {
        self.tint = tint
        self.content = AnyView(content())
    }

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(tint.opacity(0.10))
                    }
            }
            .allowsHitTesting(false)
    }
}

/// 灵动岛外壳。
///
/// 🔴 **几何按 Apple HIG 官方尺寸**（2026-09-23 修正）：
/// ```
///                        Compact leading / trailing      Minimal          Expanded
///   393x852 (17 Pro)         52.33 x 36.67 pt         36.67–45 x 36.67     371 x 84–160
///   430x932 (17 Pro Max)     62.33 x 36.67 pt         36.67–45 x 36.67     408 x 84–160
///
///   紧凑态整岛宽：17 Pro **230** / 17 Pro Max **250**
///   （= 单侧 × 2 + 挖孔 125.34，两档机型的挖孔宽度相同）
/// ```
/// 旧版预览把紧凑态画成「148pt 的一个连续黑框、里面 leading 与 trailing 并排」——
/// 两处都错：**总宽差了一倍**，而且真机上 leading / trailing 是被 TrueDepth 挖孔
/// **隔开的两块独立画布**，不是一条横条里的左右两端。于是"预览宽松、真机发挤"，
/// 这就是主人说的"真机截图与模拟器对比相差很大"。
///
/// 预览一律取 **393x852（17 Pro）** 这一档，不按机型分流：它的单侧更窄（52.33 < 62.33），
/// 预览偏保守 —— 与"预览别比真机更好看"的既定口径一致。
struct IslandShell: View {

    enum Style {
        /// 展开态：整岛宽度（官方 371 / 408）
        case expanded(width: CGFloat)
        /// 紧凑态：两翼 + 挖孔（官方 230 = 52.33 × 2 + 125.34）
        case compact
        /// 最小态：只有约 45×36.67pt 可画
        case minimal

        /// 紧凑态单侧可画宽度（393x852 档）
        static let compactSide: CGFloat = 52.33
        /// 单侧可画高度（两个形态共用）
        static let contentHeight: CGFloat = 36.67
        /// TrueDepth 挖孔的宽度
        static let punchHole: CGFloat = 125.34

        var cornerRadius: CGFloat {
            switch self {
            case .expanded: 44
            // 紧凑/最小态是**居中的胶囊**（两端半圆），半径 = 高/2。
            // 之前写的 22 是猜的；按 36.67 的内容高 + 上下各 3.17 的岛体余量 = 43，
            // 半径取 21.5。
            case .compact, .minimal: 21.5
            }
        }

        /// 外壳总宽（= 真机整岛宽，黑框包含在内）。
        var width: CGFloat {
            switch self {
            case .expanded(let w): w
            case .compact: Self.compactSide * 2 + Self.punchHole
            case .minimal: 44
            }
        }

        /// 外壳总高。展开态由内容撑开，另两种形态高度固定。
        var height: CGFloat? {
            switch self {
            case .expanded: nil
            case .compact, .minimal: 43
            }
        }
    }

    let style: Style
    let content: AnyView
    /// 真机岛外圈有一圈 `keylineTint`（品牌色细线）。预览壳复现它：
    /// 🔴 必须用 `islandTint` 亮化后的品牌色 —— 顺丰的纯黑主色描边
    /// 贴着黑色壳 + 暗黑页面就是隐形的（2026-09-24 主人真机指认）。
    var keyline: Color?

    init(_ style: Style, keyline: Color? = nil, @ViewBuilder content: () -> some View) {
        self.style = style
        self.keyline = keyline
        self.content = AnyView(content())
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            // 外框宽度 = 真机整岛宽度。顺序不能反：frame 在 padding 之前会让总宽超出。
            // 紧凑/最小态**连高度一起定死**，宽度才是有意义的对照 ——
            // 否则外壳会跟着内容缩，量出来的"余量"全是假的。
            .frame(width: style.width, height: style.height, alignment: .center)
            // 灵动岛恒为黑色挖孔：不跟随 App 外观，深色下也是这块黑，
            // 所以这里写死 .black 而不是语义色。
            .background(Color.black, in: .rect(cornerRadius: style.cornerRadius, style: .continuous))
            // 暗黑页面底也是黑的，黑壳直接融进去 —— 画一圈真机同款的
            // keyline 描边把岛的轮廓勾出来（浅色下多这一圈也自然）。
            .overlay {
                if let keyline {
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .strokeBorder(keyline, lineWidth: 1)
                }
            }
            // 同时把外观锁成深色 —— 岛内是黑底，品牌图标要取它在深色下的那一档。
            .environment(\.colorScheme, .dark)
            .allowsHitTesting(false)
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .expanded: 16
        // 🔴 紧凑态左右各留 **7pt**（2026-09-23 从主人真机截图逐像素量得：
        //    系统给紧凑态内容的前边距 ≈ 7.3pt，不是 0）。之前写 0 的理由
        //    （"官方可画宽从岛边缘算起"）导致预览里图标**整个贴在胶囊左缘**、
        //    左角被帽形圆角压住 —— 主人："超出灵动岛紧凑显示区域了"。
        //    预览要复现的是"系统边距之后的内容区"，所以这 7pt 必须给。
        case .compact: 7
        case .minimal: 12
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .expanded: 14
        case .compact: 3.17
        case .minimal: 3.17
        }
    }
}

// MARK: - 预览页

struct ActivityPreviewGallery: View {
    @EnvironmentObject private var store: PickupStore

    /// 真实待办里的前三条。
    private var realItems: [PickupActivityAttributes.Item] {
        store.pending.prefix(3).map { record in
            PickupActivityAttributes.Item(
                id: record.id.uuidString,
                company: record.company,
                code: record.code,
                kindLabel: record.kind.label,
                address: record.address,
                tint: CourierBrand.info(for: record.company).from
            )
        }
    }

    /// 预览数据。
    ///
    /// 真实待办不足两条时退回固定样本 ——「还有 N 条」这条分支恰恰是版式最容易出问题的
    /// 地方（平台名 + 计数 + 类别标签三方抢宽度），不能因为库里刚好只有一条就看不到它。
    ///
    /// ⚠️ 计数取 `items.count` 本身，**不虚构**成 3 条：预览一旦报假数就不能当验收依据
    /// （初版就犯了这错，显示「还有 2 条」而库里实际只有 1 条）。
    private static let sampleItems: [PickupActivityAttributes.Item] = [
        .init(id: "preview-1", company: "顺丰速运", code: "8-2-4031",
              kindLabel: "取件码", address: "丰巢智能柜 · 望京SOHO T1 大堂", tint: 0x000000),
        .init(id: "preview-2", company: "蜜雪冰城", code: "A128",
              kindLabel: "取餐码", address: "望京SOHO T2 1层", tint: 0xE4002B),
    ]

    private var items: [PickupActivityAttributes.Item] {
        realItems.count >= 2 ? realItems : Self.sampleItems
    }

    private var usingSample: Bool { realItems.count < 2 }

    /// 带「还有 N 条」的状态：卡面只画一条，其余用计数交代
    private var multiState: PickupActivityAttributes.ContentState {
        .init(item: items[0], pendingCount: items.count)
    }

    /// 单条状态：不出现计数文案，用来对照两种排布
    private var singleState: PickupActivityAttributes.ContentState {
        .init(item: items[1], pendingCount: 1)
    }

    /// 灵动岛展开用的状态：只画**最近一条**的完整信息，条数交给右上角计数。
    ///
    /// 计数用 `max(items.count, 3)`：多条时的计数样式（一位数）与单条一致，
    /// 预览取 3 是为了让右上角的两位数以内的排布也能被看到。
    private var islandState: PickupActivityAttributes.ContentState {
        .init(item: items[0], pendingCount: max(items.count, 3))
    }

    // 🔴 预览壳上所有品牌色一律走 `islandTint` 亮度插值 —— 与真机锁屏卡
    //    / 岛的亮化口径一致；原始品牌色（顺丰纯黑）在暗色页面上全部隐形。
    private var accent: Color { islandTint(multiState.item.tint) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if usingSample {
                    // 数据来源必须写在脸上：否则对着一张样本数据的截图
                    // 没法判断"这到底是不是我库里那条"。
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                        Text("真实待办不足 2 条，本页用样本数据演示「多条」分支")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                activityToggleSection
                lockScreenSection
                if DeviceProfile.hasDynamicIsland {
                    expandedSection
                    compactSection
                } else {
                    // 无灵动岛机型（iPhone 13 系列及更早）：系统只会显示锁屏卡片，
                    // 岛形态的预览没有意义 —— 收起来，并把口径讲清楚。
                    HStack(spacing: 6) {
                        Image(systemName: "iphone.gen3")
                        Text("当前设备没有灵动岛，实时活动将以锁屏卡片呈现")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("实时活动")
        .cloaksTabBar()
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 锁屏

    private var lockScreenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("锁屏卡片", note: "多条待办时取最新一条，其余用计数交代")

            ActivityCardShell(tint: accent) {
                ActivityLockScreenCard(state: multiState)
            }

            ActivityCardShell(tint: islandTint(singleState.item.tint)) {
                ActivityLockScreenCard(state: singleState)
            }
        }
    }

    // MARK: 灵动岛 · 展开

    private var expandedSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            label("灵动岛 · 展开", note: "长按 / 有第二个活动时展开，可画面积最大；只画最近一条待办，条数看右上角")

            // 与 `PickupLiveActivity` 的 dynamicIsland 分支同一份内容：只挂 bottom 区。
            //
            // 只有一种版式了：无论几条待办都画**最近一条**（站点名与取件码同源），
            // 「恰好 2 条并排两个码」的分支已删 —— 那样顶部的站点名只能对上其中一条。
            expandedCase("多条待办 · 站点名与取件码同源，条数看右上角", state: islandState)        }
    }

    private func expandedCase(_ caption: String,
                              state: PickupActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)

            IslandShell(.expanded(width: 371), keyline: accent) {
                IslandExpandedContent(state: state)
            }
        }
    }

    // MARK: 灵动岛 · 紧凑与最小

    private var compactSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("灵动岛 · 紧凑与最小",
                  note: "左 App 图标 + 右「待取 N」（同时有两个活动时退化为紧凑态）；三个以上只剩最小态，只画 App 图标")

            HStack(spacing: 14) {
                // 🔴 紧凑态外壳不再带 `width:` 参数（旧版 148pt 是错的，见 IslandShell 注释）：
                //    官方整岛宽 = 单侧 52.33 × 2 + 挖孔 125.34 = **230pt**，由壳自己算。
                IslandShell(.compact, keyline: accent) {
                    HStack(spacing: 8) {
                        IslandCompactLeading(state: multiState)
                        Spacer(minLength: 4)
                        IslandCompactTrailing(state: multiState)
                    }
                }

                IslandShell(.minimal, keyline: accent) {
                    IslandMinimal(state: multiState)
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: 总开关

    /// 🔴 总开关（2026-09-23 主人要求）。
    ///
    /// 存储在 **App Group**（`LiveActivitySetting`），理由见该类型注释：
    /// 桌面小组件的勾选意图在**扩展进程**里直接调 `PickupActivityController.sync`，
    /// 那条路径不经本页，开关只存 App 的 standard defaults 就会被勾选"复活"。
    ///
    /// 切换后立即 `sync` 一次：
    ///   · 关 → 控制器第 0 道门当场收掉正在跑的活动；
    ///   · 开 → 按当前待办立刻补起一张卡，不用等下一次数据变动。
    private var activityToggleSection: some View {
        SettingsGroup(title: "总开关",
                      note: "在锁屏与灵动岛上显示最新待取的取件码。关闭后立刻收掉卡片，重新打开后自动恢复。") {
            SettingsPlainRow(title: "显示实时活动") {
                Toggle("", isOn: Binding(
                    get: { LiveActivitySetting.isEnabled },
                    set: { on in
                        LiveActivitySetting.isEnabled = on
                        PickupActivityController.sync(pending: store.pending)
                    }))
                    .labelsHidden()
                    .tint(AppTheme.doneTint)
            }
        }
    }

    // MARK: 小节标题

    private func label(_ title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
