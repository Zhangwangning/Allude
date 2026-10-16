import SwiftUI

// MARK: ============================================================================
// 版本历史（「我的 › 关于 › 版本」点开的二级页）
//
// 2026-09-24 主人要求：把从 0 到现在的开发历程按版本总结，点版本号进来能看
// 每个版本的成果。纯静态展示页 —— 没有任何状态、没有任何动作，零 @State。
//
// 版式 = 时间线：左侧一条竖线串起各版本节点，当前版本（列表首项）用主题色
// 圆点 + 「当前版本」徽章高亮，历史版本灰点。每个版本一张卡：
//   版本号（大字等宽）· 日期 · 主题一句话 · 成果条目列表。
//
// 🔴 本页文案是**工作产出**，口径与对外承诺一致：
//   · 不出现「主人」等对话称呼；
//   · 不写内测阶段的功能许诺，只写已经落地的成果。
// ============================================================================

struct VersionHistoryView: View {
    private struct Entry: Identifiable {
        let id = UUID()
        let version: String
        let date: String
        let theme: String
        /// 是否为当前发行版本（首项恒 true）
        var isCurrent: Bool = false
        let highlights: [String]
    }

    private let entries: [Entry] = [
        Entry(version: "0.2.1", date: "2026-10-14", theme: "四标签信息架构与全功能开放", isCurrent: true, highlights: [
            "信息架构重排：待取 / 已取 / 统计 / 设置 四个标签，各司其职",
            "设置中心化：原「我的」面板整体重构进「设置」标签页，顶栏头像入口退役",
            "全功能开放：VIP/会员体系整体退役，记录数量与全部能力不再有任何限制",
            "首次安装引导：三页上手教程（认识码夹 → 配置自动化 → 开始使用），设置页可重看",
            "新增反馈入口：邮件直达开发者，邮箱自动附带版本号",
            "电子纪念票功能移除，产品聚焦取件码一件事",
        ]),
        Entry(version: "0.2.0", date: "2026-10-13", theme: "设计语言 v2", highlights: [
            "全局设计 token 升级：卡片圆角 20→22pt，大圆角配软投影的 iOS 27 质感",
            "待取页统计卡升级为 Hero 仪表盘大卡：46pt 渐变大数字主视觉",
            "通用车票卡票券化：撕票线 + 两侧打孔的纸质票视觉母语",
            "分组标题升级：主标题 + 彩色数量徽标胶囊",
        ]),
        Entry(version: "0.1.9", date: "2026-10-13", theme: "末四位高亮与小组件货架号", highlights: [
            "取件码末四位高亮：放大 + 品牌色强调，长码一眼锁定报码位",
            "高亮覆盖 9 个展示面：列表卡、详情页、分享卡、小组件、灵动岛、锁屏",
            "货架号进小组件二级行，排序在地址之前",
        ]),
        Entry(version: "0.1.8", date: "2026-10-12", theme: "驿站归类与货架号", highlights: [
            "按驿站归类视图：待取件按取件地点聚拢，到店场景一次取完",
            "货架号字段全链路：解析 → 落库 → 卡片 → 详情 → 小组件",
            "批量标记已取 + 撤销：多选一次完成，误触 5 秒内可回滚",
            "时间流 / 按驿站切换选择本地持久化",
        ]),
        Entry(version: "0.1.7", date: "2026-10-11", theme: "纪念票交互统一", highlights: [
            "全 App 左滑 / 右滑统一为 List + 原生 swipeActions，弃用手势自绘",
            "纪念票手动出行状态：自动判断之外可手动指定待出行 / 已出行",
            "票夹改纵向平铺卡片流，分组标题保留状态区分",
        ]),
        Entry(version: "0.1.6", date: "2026-10-10", theme: "长按景深菜单", highlights: [
            "长按卡片：整个界面后退虚化，卡片浮起 + 菜单贴卡弹出",
            "菜单动作齐备：复制 / 分享 / 编辑 / 删除，替代系统 contextMenu",
            "支持点空白处收起与滚动关闭",
        ]),
        Entry(version: "0.1.5", date: "2026-10-08", theme: "统计并入浏览页", highlights: [
            "独立统计页与浏览页合并：总览三格 + 五张习惯分析卡一页看完",
            "取件频率 / 时段 / 各快递 / 凭证类别 / 取件效率 五维分析",
            "截图脚手架体系建成：环境变量直达任意页面与状态",
        ]),
        Entry(version: "0.1.4", date: "2026-09-28", theme: "电子纪念票", highlights: [
            "纪念票上线：火车 / 高铁 / 飞机 / 汽车 / 轮船 五类票面",
            "铁路票复刻三代实体票面（磁介质 / 软纸票），一比一还原",
            "分享输出真实票面长图",
            "（该功能已于 0.2.1 移除，产品聚焦取件码）",
        ]),
        Entry(version: "0.1.3", date: "2026-09-24", theme: "多选分享与暗黑适配", highlights: [
            "多选分享：勾选多条出一张分享图，图上最多 12 个取件码",
            "多码分享卡逐行带各自驿站地址，超限自动按快递公司聚合（×N 徽标）",
            "分享改「先看图再分享」：大图预览 + 保存图片 / 拷贝图片 / 更多分享",
            "顶栏新增「选择」按钮，一键进入多选模式",
            "暗黑模式全面修复：品牌色统一亮度插值，锁屏卡取件码深色背景可读",
        ]),
        Entry(version: "0.1.2", date: "2026-09-23", theme: "解析引擎与账户二版", highlights: [
            "解析引擎全字段扩展：快递公司 / 运单号 / 尾号，识别不出留空不摆占位",
            "多码链拆分：一条短信含多个取件码时自动拆成多条记录",
            "地址误锚修正：黑名单过滤「派送 / 派件」等动词，说明文字不再混入地址",
            "扫描确认卡可编辑 + 多图批量识别（一次最多 9 张）",
            "账户体系二版：单账户本机档案（无登录、无联网）",
            "中文本地化：拷贝 / 粘贴等系统编辑菜单跟随手机语言",
        ]),
        Entry(version: "0.1.1", date: "2026-09-23", theme: "实时活动与真机交付", highlights: [
            "实时活动总开关：详情页顶部一键启停，关闭后灵动岛与锁屏卡立刻收起",
            "真机部署链路打通：构建、安装、拉起全程命令行",
            "真机灵动岛图标发灰修复：资源按展示尺寸三档重制 + 原色渲染声明",
            "标签栏定稿：回归系统原生液态玻璃 TabView，二级页滑出动画由原生视图驱动",
            "界面底色修正：页面浅灰 + 卡片白，七个页面统一对齐 iOS 分组规范",
        ]),
        Entry(version: "0.1.0", date: "2026-09-22", theme: "初版 Demo", highlights: [
            "核心框架：待取 / 已取 / 统计三页 + 详情页，底部标签导航",
            "添加取件信息：手动粘贴解析 + 相机扫描快递面单 OCR",
            "短信解析引擎：提取取件码 / 运单号 / 尾号 / 地址，40+ 快递品牌自动识别配色",
            "桌面小组件（取件 / 取餐）+ 灵动岛 / 锁屏实时卡片",
            "快捷指令自动化引导：收到快递短信自动写入码夹",
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                intro
                timeline
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("版本历史")
        .navigationBarTitleDisplayMode(.inline)
        .cloaksTabBar()
    }

    // MARK: 页首

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("码夹 CodeClip")
                .font(.system(size: 17, weight: .semibold))
            Text("从第一行代码到现在的每一步。取件数据始终只在本机流转，不上传任何服务器。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: 时间线
    //
    // 结构 = 每个版本一行（左轨道 + 右卡片），行间不设间距 —— 卡片自身的
    // bottom padding 负责拉开卡片距离，这样轨道的竖线能**连续贯穿**：
    //   · 首行：13pt 空白（对齐卡内标题行）→ 圆点 → 竖线延伸到行底；
    //   · 中间行：竖线接上来 → 圆点 → 竖线继续；
    //   · 末行：竖线接上来 → 圆点收尾。
    private var timeline: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                HStack(alignment: .top, spacing: 14) {
                    track(for: entry, at: index, isLast: index == entries.count - 1)

                    entryCard(entry)
                        .padding(.bottom, index == entries.count - 1 ? 0 : 16)
                }
            }
        }
    }

    /// 左轨道：宽 16pt，圆点落在卡内标题的视觉中心高度（顶 13pt + 圆点半径）。
    private func track(for entry: Entry, at index: Int, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            if index > 0 {
                Rectangle()
                    .fill(trackColor)
                    .frame(width: 1.5, height: 13)
            } else {
                Color.clear.frame(height: 13)
            }

            Circle()
                .fill(entry.isCurrent ? AppTheme.accent : Color(.tertiaryLabel).opacity(0.6))
                .frame(width: entry.isCurrent ? 12 : 8,
                       height: entry.isCurrent ? 12 : 8)
                .overlay {
                    if entry.isCurrent {
                        Circle()
                            .stroke(AppTheme.accent.opacity(0.25), lineWidth: 4)
                    }
                }

            if !isLast {
                Rectangle()
                    .fill(trackColor)
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 16)
    }

    private var trackColor: Color { Color(.tertiaryLabel).opacity(0.25) }

    private func entryCard(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.version)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.isCurrent ? AppTheme.accent : .primary)

                if entry.isCurrent {
                    Text("当前版本")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppTheme.accent.opacity(0.14), in: .capsule)
                        .foregroundStyle(AppTheme.accent)
                }

                Spacer(minLength: 8)

                Text(entry.date)
                    .font(.system(size: 12, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            Text(entry.theme)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(entry.highlights, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(entry.isCurrent ? AppTheme.accent : Color(.tertiaryLabel))
                            .frame(width: 4, height: 4)
                            .padding(.top, 6)

                        Text(item)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.82))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
