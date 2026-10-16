#!/bin/zsh
# ============================================================================
# 主题 / 布局验证：创建真实窗口 → 量化测量 → 抓真实渲染出图 → 审计
#
#   ./verify/run.sh              输出到 /tmp/ccui-verify
#   CC_VERIFY_OUT=~/tmp/x ./verify/run.sh
#
# 什么时候该跑：改完任何 UI（间距 / 颜色 / 卡片 / 新控件）之后。
# AppKit 的长度分配在缺约束时会给「能跑但难看」的结果，看代码判断不出来。
#
# 注意：入口文件必须叫 main.swift —— Swift 只允许 main.swift 里写顶层代码。
# ============================================================================

set -e
cd "$(dirname "$0")/.."

OUT="${CC_VERIFY_OUT:-/tmp/ccui-verify}"
mkdir -p "$OUT"

echo "▸ 编译验证器"
# 显式列源文件：排除 Src/main.swift（那是 App 入口，含另一个顶层 main）
xcrun swiftc -swift-version 5 -framework AppKit -framework CryptoKit \
  Src/Theme.swift Src/LicenseCore.swift Src/Pages.swift Src/SignPanel.swift Src/MainWindow.swift Src/MainMenu.swift \
  verify/theme/main.swift -o "$OUT/themecheck"

echo "▸ 运行"
CC_VERIFY_OUT="$OUT" "$OUT/themecheck"

echo
echo "▸ 产出："
ls -1 "$OUT"/*.png 2>/dev/null | sed 's/^/  /'
