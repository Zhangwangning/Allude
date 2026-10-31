import SwiftUI

// MARK: ============================================================================
// 使用教程（2026-10-14 合并定稿，主人：两个设置入口合成一个，内容优化去重）
//
// 由原「自动化设置」（AutomationGuideView，5 步配置详解）与
// 「引导教程」（首启引导回放）合并而来：
//   · 原「引导教程」三页里与本页重复的自动化概要已并入「短信自动入库」；
//   · 原引导的「认识拾码」三点收编为第一节；
//   · 原「搜不到动作」「运行横幅」两条提示分别归位到所属章节。
// 入口：设置 › 使用教程；首启引导第 2 页「查看完整配置教程」也进这里。
// ============================================================================

struct UsageGuideView: View {
    private struct Step: Identifiable {
        let id = UUID()
        let index: Int
        let title: String
        let detail: String
        /// 关键步骤：数字圈改用强调色，提醒这一步不做整套就白搭
        var isKey: Bool = false
    }

    /// 短信自动化五步（与快捷指令 App 的实际界面逐项对过）。
    private let automationSteps: [Step] = [
        Step(index: 1, title: "打开「快捷指令」App",
             detail: "切到底部「自动化」标签页，点右上角「+」新建一个。"),

        Step(index: 2, title: "触发条件选「信息」",
             detail: "在「当」一栏里把触发类型设为「信息」。"),

        Step(index: 3, title: "条件改成「信息内容 · 包含 · 关键词」",
             detail: "左侧默认是「**发件人**」，**必须手动改成「信息内容」**；中间选「包含」，右侧填**一个**快递短信里几乎必现的词。\n\n最省事的是「**【**」——快递短信几乎都以【平台名】开头。但这不是唯一写法：填「**快递**」「**包裹**」「**取件**」同样能筛出来，按你常收到的短信来定。\n\n只填一个词即可，填多了反而容易漏。",
             isKey: true),

        Step(index: 4, title: "关闭「运行前询问」",
             detail: "**开着的话每收到一条短信都要手动点一次确认**，自动化等于没做。新建时把它关掉；新系统里这一项显示为打开「**立即运行**」。"),

        Step(index: 5, title: "添加动作「添加到拾码」",
             detail: "在动作搜索框输入「拾码」，选「**添加到拾码**」；「短信内容」一栏选「**快捷指令输入**」——自动化触发时它就是刚收到的那条短信。",
             isKey: true),
    ]

    /// 截屏收件四步（手动快捷指令，不是自动化）。
    ///
    /// 自动化只能监听「收到短信」。微信群转发的取件通知、快递 App 的推送、驿站发来的
    /// 聊天截图 —— 这些都没有可监听的系统事件，用户手上唯一能做的动作就是「截屏」。
    private let screenshotSteps: [(String, String)] = [
        ("新建一条快捷指令", "切到「**快捷指令**」标签页（不是「自动化」），点右上角「+」。"),
        ("第一个动作：截屏", "搜索「**截屏**」拖进来，它会截下当前屏幕。"),
        ("第二个动作：识别取件截图", "搜索「**拾码**」，选「**识别取件截图**」；「截图」一栏会自动接上一步的输出，不用手动挑。"),
        ("（可选）放到随手能按的地方", "长按这条快捷指令 → 分享 →「添加到主屏幕」；或到「设置 › 辅助功能 › 触控 › 轻点背面」绑成双击。"),
    ]

    /// 认识拾码三点（原首启引导欢迎页收编）。
    private let introPoints: [(String, String, Color, String)] = [
        ("bubble.left.and.text.bubble.right.fill", "自动收码", AppTheme.accent,
         "配合快捷指令，快递短信一到取件码自动进「待取」"),
        ("platter.filled.top.iphone", "灵动岛常显", AppTheme.violet,
         "最新取件码挂在灵动岛与锁屏，到驿站抬手即见"),
        ("hand.raised.fill", "只在本机", AppTheme.doneTint,
         "无账号、无联网，取件数据不出这台手机"),
    ]

    var body: some View {
        // 🔴 2026-10-25：同 VersionHistoryView —— 底色用 ZStack 独立铺，
        // 不再依赖 ScrollView 上的 `.background`（分栏 detail 列里撑不满会露白）。
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    introSection
                    automationSection
                    screenshotSection
                    verifySection
                }
                .padding(.horizontal, AppTheme.hInset)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("使用教程")
        .navigationBarTitleDisplayMode(.inline)
        .cloaksTabBar()
    }

    // MARK: 一、认识拾码

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "认识拾码")

            VStack(spacing: 0) {
                ForEach(Array(introPoints.enumerated()), id: \.offset) { position, point in
                    if position > 0 { SettingsDivider() }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: point.0)
                            .font(AppTheme.TypeScale.rowTitle.weight(.semibold))
                            .foregroundStyle(point.2)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.1)
                                .font(AppTheme.TypeScale.rowTitle.weight(.semibold))
                            Text(point.3)
                                .font(AppTheme.TypeScale.body)
                                .foregroundStyle(.secondary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }
            }
            .cardSurface()
        }
    }

    // MARK: 二、短信自动入库（自动化）

    private var automationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "短信自动入库")

            stepList(automationSteps)

            // 🔴 2026-11-01 主人：别让用户以为"没有【的短信 App 处理不了"。
            //    【 只是自动化的筛选条件，App 本身不依赖它。
            infoCard(symbol: "text.alignleft", tint: AppTheme.doneTint,
                     title: "条件里的关键词可以换",
                     detail: "「**【**」不是硬性要求，只是最省事的写法——快递短信几乎都以【平台名】开头。换成「**快递**」「**包裹**」「**取件**」这些词同样能筛出来，按你常收到的短信挑一个即可。\n\n**短信里没有【也一样能处理**：它只是自动化的筛选条件，不是解析前提。手动粘贴、截图识别都不受影响，解析器看的是取件码与地址的写法，不看有没有方括号。")

            // 第 5 步的常见卡点直接跟在这一节后面
            infoCard(symbol: "questionmark.circle.fill", tint: AppTheme.sky,
                     title: "搜不到「拾码」这个动作？",
                     detail: "先在手机上**打开一次拾码**再回快捷指令搜索。iOS 需要 App 至少运行过一次，才会把它提供的动作索引到动作库。")
        }
    }

    // MARK: 三、截屏收件（手动）

    private var screenshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "截屏收件")

            VStack(alignment: .leading, spacing: 12) {
                Text("自动化只能监听「收到短信」。微信群转发的取件通知、快递 App 的推送、驿站发来的聊天截图 —— 这些都没有可监听的系统事件，这时用一条**手动快捷指令**：截屏 → 一键收纳。".richText)
                    .font(AppTheme.TypeScale.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(screenshotSteps.enumerated()), id: \.offset) { position, item in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(position + 1)")
                                .font(AppTheme.TypeScale.badge)
                                .frame(width: 20, height: 20)
                                .background(AppTheme.sky.opacity(0.15), in: .circle)
                                .foregroundStyle(AppTheme.sky)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.0)
                                    .font(AppTheme.TypeScale.note.weight(.medium))
                                Text(item.1.richText)
                                    .font(AppTheme.TypeScale.note)
                                    .foregroundStyle(.tertiary)
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }

                Text("截图里没有取件信息（比如截了个聊天记录、截了个网页）就**什么都不会写入**，「待取」不会被污染。".richText)
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(.tertiary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    // MARK: 四、配好之后

    private var verifySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "配好之后")

            infoCard(symbol: "checkmark.seal.fill", tint: AppTheme.doneTint,
                     title: "怎么验证配置生效",
                     detail: "让家人或同事给你发一条带取件码的快递短信试试。自动化运行几秒后切回拾码，「待取」里会多出一条；桌面小组件也会同步刷新，同时你会收到一条通知（标题就是取件码，下面是平台与地址）。若没反应，多半是第 3 步的条件没切到「信息内容」。")

            infoCard(symbol: "lightbulb.fill", tint: AppTheme.pendingTint,
                     title: "小提示",
                     detail: "自动化每次运行时，系统会弹出「正在运行」的横幅提示，这是 iOS 的系统行为、无法关闭。它不影响识别，只是说明它在工作。")
        }
    }

    // MARK: 步骤列表（数字圈 + 关键徽标）

    private func stepList(_ steps: [Step]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { position, step in
                if position > 0 {
                    Divider().padding(.leading, 58)
                }

                HStack(alignment: .top, spacing: 14) {
                    Text("\(step.index)")
                        .font(AppTheme.TypeScale.noteStrong)
                        .frame(width: 26, height: 26)
                        .background((step.isKey ? AppTheme.pendingTint : AppTheme.accent).opacity(0.15),
                                    in: .circle)
                        .foregroundStyle(step.isKey ? AppTheme.pendingTint : AppTheme.accent)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(step.title)
                                .font(AppTheme.TypeScale.bodyMedium)

                            if step.isKey {
                                Text("关键")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(AppTheme.pendingTint.opacity(0.16), in: .capsule)
                                    .foregroundStyle(AppTheme.pendingTint)
                            }
                        }

                        Text(step.detail.richText)
                            .font(AppTheme.TypeScale.note)
                            .foregroundStyle(.tertiary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
            }
        }
        .cardSurface()
    }

    // MARK: 信息卡

    private func infoCard(symbol: String, tint: Color,
                          title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(AppTheme.TypeScale.note)
                    .foregroundStyle(tint)
                Text(title)
                    .font(AppTheme.TypeScale.body.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)

            Text(detail.richText)
                .font(AppTheme.TypeScale.body)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
