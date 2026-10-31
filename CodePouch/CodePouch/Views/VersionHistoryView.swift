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
        Entry(version: "0.3.1", date: "2026-10-31", theme: "免费下载 + 订阅解锁，凭证输入下线", isCurrent: true, highlights: [
            "App 免费下载。完整版改为内购三档：终身 ¥28 一次买断（推荐）、每年 ¥9、每月 ¥1；价格以 App Store 显示为准，换机可「恢复购买」",
            "设置页顶部新增 PRO 横幅；订阅页一屏看完：三档横排比较、解锁清单、主行动键与恢复购买",
            "订阅页底部可直接打开隐私政策与使用条款，订阅的自动续期规则写在购买键上方",
            "删除「粘贴凭证」那套解锁方式：从未对外售卖，没有需要兼容的历史买家",
            "「关于」里移除设备 UUID —— 凭证体系下线后它没有用途了",
            "内购状态写入本机权益快照，桌面小组件与实时活动同步解锁，无需打开主 App 也生效",
        ]),
        Entry(version: "0.2.8", date: "2026-10-30", theme: "免费档边界收口，实时活动预览改为真实渲染", highlights: [
            "免费档边界落定：列表同屏 3 条；桌面小组件只开放「小 / 中」两种尺寸，且最多看到 3 条待取",
            "超出条数的提示条改为满圆角胶囊，与上方卡片拉开层次",
            "签名凭证页改用与「通知提醒」等设置页同一套版式；激活结果改成弹窗，必须点「确认」才消失",
            "设置里的实时活动预览改为在 App 内真实渲染，不再是截图：换一条待办、条数变化都会跟着变",
            "预览配了浅色 / 深色两套真机机模（锁屏与主屏幕各一），深色下不再拿浅色壁纸凑数",
            "灵动岛外圈描边与取件码同色，粗细固定、强度随壁纸亮度自动在 0.45–0.75 之间取值",
            "预览切换改为连续形变：灵动岛在展开与折叠之间缩放变形；锁屏卡片是另一个对象，就地浮出，不从岛上滑下来",
        ]),
        Entry(version: "0.2.7", date: "2026-10-30", theme: "更名拾码 CodePouch，重复短信只更新时间", highlights: [
            "品牌更名：中文「拾码」、英文「CodePouch」，图标与界面文案同步更新",
            "重复短信不再新增卡片：同一个码再收到时只刷新时间，详情页「添加时间」逐条记下每次通知时刻（标签样式、最新在上）",
            "列表分组与排序改用「最后一次通知」的时间，卡片写几点就归到哪一天",
            "列表卡、详情卡、添加预览卡、小组件、锁屏卡的取色统一：图标取第一行第一个字段，卡面与取件码取该图标的主题色",
            "快递公司名称归一到标准名（「申通」存为「申通快递」），列表、详情、编辑态、小组件全链路一致",
            "柜位不再重复「柜」字：短信写「快递柜A3」就显示 A3",
            "解析补充「请凭6309取件」这类 4 位纯数字取件码",
            "详情页取件地址过长时换行完整显示，不再用省略号截断",
            "存量数据自动回填：柜位格式、公司标准名、缺失字段一并补齐，同时清理重复记录与无效取件码",
            "通知标题只显示取件码本身；识别到快递柜或货架时紧跟其后",
        ]),
        Entry(version: "0.2.6", date: "2026-10-28", theme: "拾码只认取件码，锁屏换成原生液态玻璃", highlights: [
            "全面取消取件码类型区分：取件码、运单号、尾号一律按取件码呈现，界面不再出现类别标签，统计页也不再按类别拆分",
            "统计页删除「凭证类别」，把「取件效率」上移到频率之后 —— 结论在前、明细在后",
            "锁屏实时活动改用系统原生液态玻璃（Liquid Glass），取件码保留品牌色并加描影，正文白字描影保证任何壁纸上都读得清",
            "通知标题只显示取件码本身；识别到快递柜或货架时，紧跟在码后面显示",
            "桌面小组件的取件码颜色与 App 完全一致（跟承运方走），不再因平台不同而变色",
            "解析增强：精确格口（02-23格口）、第 N 箱（15箱）、地址重复词折叠、签收状态不再被当成地址",
            "快递公司名称归一到标准名：「申通」存为「申通快递」，列表、详情、编辑、小组件全链路一致",
            "详情页取件地址过长时换行完整显示，不再用省略号截断",
            "详情页取件码颜色与顶部卡片统一，「妈妈驿站发的、圆通承运」这类记录不再一页两色",
            "设置页实时活动预览图更新为最新真机效果（紧凑 / 展开 / 锁屏三态）",
        ]),
        Entry(version: "0.2.5", date: "2026-10-27", theme: "小组件改版与解析同步 V8.0.3", highlights: [
            "小尺寸小组件改为一次显示 4 条纯取件码，字号统一；中/大尺寸取件码后紧跟快递柜 / 货架",
            "小组件设置页：「显示内容」改为五个开关（完整信息 / 地址 / 快递公司 / 驿站 / 快递柜），完整信息与其余互斥",
            "效果预览去掉外层白卡片，小组件直接浮在页面上，并补描边与阴影，底边不再与背景融为一体",
            "快递公司识别修复：「乐苑圆通超市」这类店名不再被当成承运方，超市 / 便利店 / 驿站代收均正确",
            "解析规则同步快捷指令 V8.0.3：支持 4 位纯数字取件码、包裹 + 4 位、冒号 + 引号等写法",
            "新增快递柜格口识别（2号柜 / 12-34格口 / 柜A12），与货架号分开存储与显示",
            "设置页「快递管理」拆分为「快递公司」与「驿站管理」两个入口",
            "筛选菜单精简：只保留最近收到 / 最早收到 / 按快递公司，按公司时列表真正按承运方归类",
            "分享面板在常规 iPhone 上重构：卡片居中、操作按钮回到底部横排，面板圆角跟随机型屏幕圆角",
            "标签栏固定显示，不再随列表滚动收缩",
        ]),
        Entry(version: "0.2.4", date: "2026-10-25", theme: "折叠屏适配与全量缺陷修复", highlights: [
            "iPhone Duo 适配：内屏展开改为左侧列表 / 右侧常驻详情的平行视图，左右等宽分列",
            "统计页与设置页同步支持分栏；设置页采用 iPad 式「侧栏分组 + 右侧内容」布局",
            "分享面板重做：卡片按可用宽高自适应放大、右侧竖排液态玻璃操作钮，面板四角贴合 D 型屏",
            "详情页编辑保存修复：此前保存不生效（编辑后数据未落库），现已正常写回",
            "货架号识别修复：短信里的「货架号：5-12」「3号货架」等写法现在能正确解析",
            "实时活动修复：全新安装时锁屏与灵动岛不出卡的问题已解决",
            "删空记录后重启不再回填示例数据；深色模式分享面板层次恢复正常",
            "标记已取连点两条不再出现「假已取」卡住；通知点击可直接打开对应记录",
            "地图导航修复：驿站 / 超市类地址改用 POI 搜索定位，不再一律显示「无法解析该地址」",
        ]),
        Entry(version: "0.2.3", date: "2026-10-20", theme: "详情页重构与卡片一致性", highlights: [
            "详情页顶部卡主名口径修正：快递公司优先于短信平台（「圆通快递 | 拼多多」），与首页卡完全一致",
            "取件码强调色跟随图标主题色（承运快递公司），不再用短信平台色，图标与码同色",
            "入库时长移到卡片右上角，已取件不再显示（与首页卡同口径）",
            "「取件平台」标签改名「短信平台」，一眼区分发信平台与承运快递",
            "详情页复制按钮移除，改为长按取件码唤起菜单",
            "详情页顶部卡补全取件地址、货架号，信息量与首页卡对齐",
        ]),
        Entry(version: "0.2.2", date: "2026-10-19", theme: "待取卡布局 v2 与已取页同步", highlights: [
            "待取卡图标下沉进取件码行、缩小至 26pt 与码视觉同高，文字左缘与图标齐平",
            "勾选「已取」回归到取件码行右端，点按直接切换取件状态",
            "已取页卡片同步为待取页 v2 布局，去掉左侧独立勾选列",
            "取件码末四位品牌色强调、长码整卡宽度显示，长码不再被截断",
        ]),
        Entry(version: "0.2.1", date: "2026-10-14", theme: "四标签信息架构与全功能开放", highlights: [
            "信息架构重排：待取 / 已取 / 统计 / 设置 四个标签，各司其职",
            "设置中心化：原「我的」面板整体重构进「设置」标签页，顶栏头像入口退役",
            "全功能开放：VIP/会员体系整体退役，记录数量与全部能力不再有任何限制",
            "首次安装引导：三页上手教程（认识拾码 → 配置自动化 → 开始使用），设置页可重看",
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
            "快捷指令自动化引导：收到快递短信自动写入拾码",
        ]),
    ]

    var body: some View {
        // 🔴 2026-10-25：底色改用 ZStack 独立铺一层 ——
        // 原先 `.background(...)` 挂在 ScrollView 上，在分栏 detail 列里撑不满，
        // 露出 NavigationStack 的默认白底，表现为「右栏整片白、左栏浅灰」。
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro
                    timeline
                }
                .padding(.horizontal, AppTheme.hInset)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("版本历史")
        .navigationBarTitleDisplayMode(.inline)
        .cloaksTabBar()
        // 隐藏入口：命中后推凭证页，返回即回到版本历史，不留任何标记

    }

    // MARK: 页首

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("拾码 CodePouch")
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
