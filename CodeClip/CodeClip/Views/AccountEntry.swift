import SwiftUI
import UIKit

// MARK: ============================================================================
// 账户入口（右上角圆形头像）
//
// 2026-09-22 定调：**底部导航栏不设「我的」页**（三格留给「待取 / 浏览 / 统计」），
// 「我的」改由**右上角一枚独立的圆形头像**进入 —— 这是 iOS 自己的做法
// （App Store、音乐、播客右上角都是这么一块），账户这类「与当前内容无关、
// 低频、个人化」的入口本来就不该占用一个常驻标签位。
//
// 🔴 **头像必须是独立的圆，不能并进旁边那组按钮的玻璃胶囊**（2026-09-22 主人指出）：
//    iOS 26 起，导航栏里同一 placement 的多个 item 会被**合并进同一块
//    Liquid Glass 胶囊**。只要头像还在那块胶囊里，它看起来就是「第四个功能按钮」，
//    而不是「我」。两处改动一起才能拆开：
//      ① `ToolbarSpacer(.fixed, placement: .topBarTrailing)` —— 在头像与页面
//         自己的按钮之间插一个**分组间隔**，把它切成两块独立玻璃；
//      ② `.sharedBackgroundVisibility(.hidden)` —— 头像这块不画系统玻璃，
//         背景改由 `AccountAvatar` 自己画一枚半透明圆环（见该视图 body ⑤）。
//    只做②不做①无效：同一组内的 item 共享一个背景，"不参与"没有可退的地方。
//
// 进入方式也从 sheet 改成了 **push**：面板右上角原本挂着一个 X，
// 与 App 里其他页「左上角返回」的规则不一致 —— 统一成导航推入后，
// 返回按钮自然长在左上角，且能按住右滑返回。
//
// 🔴 **2026-09-23 重做**：原先这里的「账户」是第三方登录态的附属品
//    （`signedInProvider` / `boundProviders` / 手机号 / 密码…），现在整套登录已删除，
//    账户回归成**纯本机的档案**（名字 + 头像，可多枚），
//    真值存在 `LocalAccountStore`（见 LocalAccounts.swift），
//    本文件只剩两件事：**一个读写门面** + **一个头像视图**。
// ============================================================================

// MARK: - 账户门面

/// 对当前账户的读写门面。
///
/// 存在的理由：UI 各处只关心"**我现在叫什么、头像长什么样**"，
/// 不该每处都写 `LocalAccountStore.shared.current.xxx`；也不该让视图层
/// 知道迁移、文件路径这些事。
///
/// ⚠️ 这是**静态门面**，自己没有发布机制。需要"改了就重画"的地方
/// （头像视图、账户卡）请直接订阅 `LocalAccountStore.shared`。
enum AccountProfile {
    private static var store: LocalAccountStore { .shared }

    /// 当前账户名
    static var nickname: String {
        get { store.current.name }
        set { store.renameCurrent(to: newValue) }
    }

    /// 当前账户的头像款式。
    /// 🔴 取不出来时回落到 `fallback`（历史上删过款式的用户会遇到）。
    static var avatarStyle: AccountAvatarStyle {
        get { store.current.avatar }
        set { store.setAvatar(newValue) }
    }

    /// 当前账户上传的自定义头像；没上传过时 nil。
    static var customAvatarImage: UIImage? {
        store.customAvatarImage(for: store.current.id)
    }

    /// 存入从相册选的图（落盘 + 自动切到「自定义」款）。
    @discardableResult
    static func saveCustomAvatar(_ data: Data) -> Bool {
        store.saveCustomAvatar(data)
    }
}

// MARK: - 头像

/// 圆形头像。两种形态：
///   · `.custom` —— 用户上传的照片（没有照片时是相机占位）；
///   · 其余 —— 内置几何头像（`CartoonAvatar`，全代码绘制）。
///
/// 🔴 订阅 `LocalAccountStore`：改名或换头像后，导航栏、账户卡、选择格
///    会在同一帧一起重画 —— 不再依赖手写的 `bump()` 回调逐个通知。
struct AccountAvatar: View {
    @ObservedObject private var store = LocalAccountStore.shared

    var size: CGFloat = 30

    /// 指定款式渲染（选择格里逐个预览用）。
    /// nil = 读账户保存的款式。
    var style: AccountAvatarStyle? = nil

    /// 指定图片（刚选完还没走完落盘流程时用）。
    /// nil = 读磁盘上已保存的那张。
    var customImage: UIImage? = nil

    /// 是否**自己画**外环底板。
    ///
    /// 🔴 导航栏里必须传 `false`：那里由**系统 Liquid Glass** 画整块玻璃，
    ///    我们再画一层就是玻璃叠玻璃（而且实测还会把 item 整个吞掉，
    ///    见 `body` 注释）。此时本视图只贡献「38pt 头像 + 3pt 透明留白」，
    ///    留白处露出的正是系统那块玻璃。
    ///
    /// ⚠️ 普通页面（账户卡 / 账户列表 / 选择格）没有系统玻璃可借，保持 `true`。
    var ownRing: Bool = true

    private var resolved: AccountAvatarStyle {
        style ?? store.current.avatar
    }

    private var resolvedImage: UIImage? {
        customImage ?? store.customAvatarImage(for: store.current.id)
    }

    /// 🔴 **两层结构：玻璃外环 + 内嵌头像**（2026-09-23 主人照参考图要求，
    ///    2026-09-23 晚改材质）。
    ///
    /// 以前是"头像直接等于外接圆"，三种形态各画各的圆 —— 卡通头像自带底圆、
    /// 首字是渐变圆、照片是裁出来的圆，边缘质感各不相同，摆在导航栏里像三个
    /// 不同来源的图标。现在统一成：**外层永远是一枚外环**（`size` 由调用方给），
    /// 头像按 `size - 2 × ring` 渲染后裁圆嵌进去。三种形态从此共用同一个轮廓。
    ///
    /// 🔴 **外环 = 半透明玻璃感（自画），不是系统玻璃**（2026-09-23 主人三轮反馈定稿）。
    ///
    /// 演进过程（都是 @3x 截图逐像素实测，不是推断）：
    /// ```
    ///  ① Circle().fill(Color(.secondarySystemGroupedBackground))
    ///     浅色 #FFFFFF / 深色 #1C1C1E —— 不透明确色。
    ///     实测 y=83.5pt：外环 rgb(255,255,255)，而隔壁按钮胶囊
    ///     rgb(242,242,247)～(247,247,252)（半透明、几乎透出页面底）。
    ///     → 一行上两种材质，主人："怎么感觉一圈白的"。
    ///
    ///  ② .glassEffect(.regular, in: .circle)
    ///     🔴 toolbar item 里**整个前景被吞掉**：头像矩形
    ///     （x342…386pt / y62…105pt，17028 px）一个卡通色像素都没有，
    ///     只剩 #F0F0F5～#F7F7FB 的玻璃噪点。
    ///     同一个组件在普通页面（「我的」账户卡）渲染完全正常 → 是宿主的问题。
    ///
    ///  ③ .ultraThinMaterial —— 同样需要 backdrop 采样，**整个 item 连渲染都没有**
    ///     （三页扫描棕熊色 0.00%，那片区域只剩页面底色 #F2F2F7）。
    ///     → 主人："头像边框看不见了，液态玻璃的质感完全没有了"。
    ///
    ///  ④ 撤掉 `.sharedBackgroundVisibility(.hidden)`，让**系统**给这块画玻璃
    ///     → 系统玻璃出来了，但形状是 **50 宽 × 44 高的横向胶囊**（非正圆）
    ///     （主人："头像是个正圆啊，你这太要命了"）。
    ///     ⚠️ 当时还误判成"盖住头像"—— 那条结论**已作废**：取样判据用的是
    ///        "棕熊色"，而主人此时已把头像换成照片，所以扫不到是正常的，
    ///        头像其实一直在（见 ⑥ 之后的正解）。
    ///
    ///  ⑤ 自画 + 半透明（`Circle().fill(...).opacity(0.45)`）
    ///     → **仍是一圈实色**。红色探针给出决定性证据：把环临时换成
    ///     `Color.red.opacity(0.45)`，出图 rgb(247,157,162) —— 与
    ///     `0.45×(255,59,48) + 0.55×(242,242,247)` 逐通道吻合（247 / 159 / 157），
    ///     说明**环确实是这行代码画的、透明度也确实生效**；
    ///     但换成 `Color(.secondarySystemGroupedBackground)` 量到的却是
    ///     **不透明 `#FFFFFF`**。加上 ⑤ 之前"环其实一直叠在系统玻璃上"，
    ///     结论很明确：**自己画环这条路走不通**（要么实色、要么和系统玻璃叠两层）。
    ///
    ///  ⑥ **定稿（主人给的思路）：借系统的玻璃，靠"内容收窄"把它变正圆。**
    ///     · `ring = 0` —— 本视图**不画任何底板**，只出「正圆头像」；
    ///     · 工具栏那枚内容取 **38pt**（不是 44）—— 系统玻璃 = 内容宽 + 每边约 3pt，
    ///       于是正好 **44 × 44 的正圆**，那 3pt 就是系统玻璃自己露出的环；
    ///     · 不写 `.sharedBackgroundVisibility(.hidden)`，玻璃才是系统的。
    ///
    /// 🔴 **结论（省得下次再试）**：
    ///    · 需要 backdrop 采样的材质（`glassEffect` / `Material`）在 toolbar item
    ///      里**一律不可用** —— 吞前景 / 整个 item 不渲染；
    ///    · 自己画环 —— 只能是不透明确色（浅色底上就是"一圈白"）；
    ///    · **想在工具栏拿到液态玻璃，唯一的路是让系统画**，再通过
    ///      **调内容尺寸**去控制那块玻璃的形状（宽 = 内容宽 + 6，高恒 44）。
    var body: some View {
        core
            .frame(width: size, height: size)
            // 统一在这里裁圆：`scaledToFill` 会把照片撑出 frame，
            // 不裁的话方图会顶着四个角露在圆外。
            .clipShape(.circle)
    }

    /// 头像内容本身（不含底板）。所有分支都按 `inner` 尺寸画。
    @ViewBuilder
    private var core: some View {
        switch resolved {
        case .custom:
            if let image = resolvedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                AvatarUploadPlaceholder(size: inner)
            }

        default:
            CartoonAvatar(style: resolved, size: inner)
        }
    }

    // MARK: 尺寸

    /// 🔴 **外环已取消**（2026-09-23 晚，主人第五轮反馈）。
    ///
    /// 曾经是 2pt（size<44）/ 3pt（≥44）的实色白环。但实测证明：
    /// 在工具栏那个宿主里，**只要我们自己画环，出来的就一定是不透明确色**
    /// （见 `body` 注释的探针结果），浅色底上就是"一圈白"；
    /// 而借系统的玻璃又会变成非正圆胶囊。两头都不成立，索性不要环 ——
    /// 头像直接裁成正圆撑满 `size`，与左侧按钮胶囊等高、边缘干净。
    private var ring: CGFloat { 0 }

    /// 头像内容直径（= 外径 − 两侧环宽）。
    private var inner: CGFloat { size - ring * 2 }
}

extension AccountAvatar {
    /// 导航栏里那枚头像的外径。
    ///
    /// 🔴 **必须等于工具栏胶囊的高度（44pt）**（2026-09-23 主人要求）。
    ///
    /// 原因：系统把同一 placement 的多个 item 合成一块 Liquid Glass 胶囊，
    /// 那块胶囊的高度由系统定为 **44pt**；而头像是自定义视图，尺寸完全由 `size`
    /// 决定。原来写 30pt，于是并排看时头像**比旁边的胶囊矮 14pt** ——
    /// 视觉上不成一组，也显得"没对齐"。
    ///
    /// 实测（@3x 截图，402×874pt 设备，同为导航栏中线）：
    /// ```
    ///   胶囊   y 62…105pt   高 44pt   中心 83.5
    ///   头像   y  69…98pt   高 30pt   中心 83.5   ← 同心，只是矮
    ///   头像横向 x 349…378pt（30pt）· 外环 2pt · 内容 26pt
    /// ```
    /// 两者本来就是垂直居中的，唯一的问题就是直径小；改成 44pt 后外轮廓齐平，
    /// 同心关系由系统维持，无需手工偏移。
    ///
    /// ⚠️ 44 ≥ 44 会让 `ring` 落到 3pt 档（内容直径 38pt）—— 这是刻意的：
    ///    外径放大而内径不动的话，会变成一圈厚环的「甜甜圈」。
    ///    导航栏里这 3pt 就是那圈半透明外环的宽度。
    static let toolbarSize: CGFloat = 44

    /// 导航栏里**头像内容**的直径。
    ///
    /// 🔴 38 = 44 − 2 × 3：系统给这块 item 的外层玻璃 = 内容宽 + 每边约 3pt，
    ///    所以内容取 38 时系统那枚玻璃正好是 **44 × 44 的正圆**（与工具栏胶囊等高）。
    ///    详见 `AccountAvatarToolbarItem`。
    static let avatarSize: CGFloat = 38
}

// MARK: - 2026-10-14 退役说明
//
// 顶栏头像入口（AccountAvatarToolbarItem / accountToolbar / ProfilePushScaffold）
// 已随「我的」面板重构进设置页（第 4 个标签）整体退役 —— 头像组件本体
// （AccountAvatar / AccountAvatarStyle）保留，设置页的账户卡仍在使用。
