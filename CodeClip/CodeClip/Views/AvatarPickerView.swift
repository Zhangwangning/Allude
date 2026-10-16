import SwiftUI
import PhotosUI

// MARK: ============================================================================
// 更换头像（「账户」页的下级页，2026-09-23 深夜二版）
//
// 主人要求：账户详情页不摆一屏头像格，"自定义头像的在点击更换头像时才显示
//（做个下级页面）"—— 资料页只留一个「更换头像」入口，宫格全部收进这里。
//
// 结构：
//   · 第一格 = **自定义**（系统选图器 `PhotosPicker`，不申请相册权限；
//     选完即落盘并切换到自定义款 —— 头像属于"我看到它变了才算数"的东西）；
//   · 其余 11 格 = 内置几何头像，**点一下立即生效**（无确认步骤）；
//   · 选中格描主题色环（描在头像外侧 3pt，不压头像边缘）。
//
// ⚠️ 视图里**没有一个 @State**：选图器选中项与失败提示都挂在共享的
//    `AccountDetailModel` 上 —— 本机 Xcode 27 beta 命令行编译链路对新文件
//    的 SwiftUI 宏（@State）返回 malformed response（红线坑），一律绕开。
//
// 🔴 这是「我的」分支的下级页：必须挂 `.cloaksTabBar()`（标签栏保持收起）。
// ============================================================================

struct AvatarPickerView: View {
    /// 与账户详情页**共享同一份草稿**：在这里选的头像，详情页顶部大头像
    /// 实时跟着变（关闭本页回详情页，右上角「保存」仍要确认名称改动）。
    ///
    /// ⚠️ 用 `@ObservedObject` 接住外层的 model —— 草稿只有一份真值。
    @ObservedObject var model: AccountDetailModel

    /// 选择格里的图直接从磁盘读（详情页的草稿流程不经过这里）。
    @ObservedObject private var store = LocalAccountStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                grid

                Text("「自定义」从相册挑一张 —— 走系统选图器，**不申请相册权限**，App 只拿到你选中的那一张。其余头像由 App 内置绘制，全程不联网。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineSpacing(2)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppTheme.hInset)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("更换头像")
        .navigationBarTitleDisplayMode(.inline)
        .cloaksTabBar()
        // 选图器回传：值变了才触发，处理完 model 会把它置回 nil。
        .onChange(of: model.pickedPhoto) { _, item in
            guard let item else { return }
            model.handlePickedPhoto(item)
        }
        .alert("这张图读不出来", isPresented: $model.photoFailed) {
            Button("好", role: .cancel) { }
        } message: {
            Text("换个格式（JPG / PNG / HEIC）再试一次。")
        }
    }

    /// 12 格宫格：自定义 + 11 款内置，4 列正好铺满三行。
    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                  spacing: 14) {
            ForEach(AccountAvatarStyle.allCases) { style in
                if style == .custom {
                    PhotosPicker(selection: $model.pickedPhoto,
                                 matching: .images,
                                 photoLibrary: .shared()) {
                        cellLabel(.custom, isSelected: model.avatar == .custom)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        model.avatar = style
                    } label: {
                        cellLabel(style, isSelected: model.avatar == style)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .cardSurface()
    }

    /// 格子外观：56pt 圆（头像 50 + 外侧 3pt 空隙描选中环）+ 款名。
    private func cellLabel(_ style: AccountAvatarStyle,
                           isSelected: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                // 选中环描在头像**外侧**留 3pt 空隙（不是压在头像边缘），
                // 否则深色底头像会和蓝环糊在一起。
                Circle()
                    .strokeBorder(isSelected ? AppTheme.accent : Color.clear,
                                  lineWidth: 2.5)
                    .frame(width: 56, height: 56)

                AccountAvatar(size: 50, style: style)
            }

            Text(style.title)
                .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AppTheme.accent : .secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
    }
}
