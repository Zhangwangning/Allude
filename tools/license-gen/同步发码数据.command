#!/bin/zsh
# ============================================================================
# 码夹 · 发码工具 —— 数据同步（双击运行）
#
# 【为什么需要这个脚本】
#
#   本仓库位于 /Volumes/<外挂卷>，该卷受 macOS「可移除宗卷」门禁保护。
#   实测（macOS 27.2 / 外挂 APFS 卷）：由 Finder 双击启动的 App 读该卷上的文件，
#   stat() 会 0ms 返回 true，但紧接着的 open() 会在内核里**永久挂起**，因为系统
#   要弹授权框 —— 而那个授权框在多屏布局下会弹到副屏（副屏在主屏左侧、x 为负），
#   副屏没接时完全看不见。结果就是「App 一打开就永久卡死」。
#
#   终端持有磁盘访问权限，所以由终端来做跨卷读写，App 只读写本机容器：
#       本机容器：~/Library/Application Support/CodeClipIssuer/
#
# 【本脚本做两件事】
#   ① 容器里没有私钥时，从本目录导入 private-key.pem
#   ② 台账取「行数多」的一方为准，双向补齐（App 签的新单在容器里，需要带回仓库）
#
# 用法：双击本文件即可。已存在的台账不会被覆盖成更少的内容。
# ============================================================================

set -u
cd "$(dirname "$0")"

SRC_DIR="$(pwd)"
DEST="$HOME/Library/Application Support/CodeClipIssuer"
KEY="private-key.pem"
LEDGER="issued-ledger.md"

mkdir -p "$DEST"

echo "码夹 · 发码工具 —— 数据同步"
echo "======================================================"
echo "仓库目录：$SRC_DIR"
echo "本机容器：$DEST"
echo

# ── ① 私钥：只进不退（容器里已有就不动，避免误覆盖）
if [ -f "$DEST/$KEY" ]; then
    echo "  ✓ 私钥已在本机容器（跳过导入）"
elif [ -f "$SRC_DIR/$KEY" ]; then
    cp -f "$SRC_DIR/$KEY" "$DEST/$KEY"
    echo "  ✓ 已导入私钥 → $(wc -c < "$DEST/$KEY" | tr -d ' ') 字节"
else
    echo "  ✗ 找不到 $KEY（既不在容器也不在本目录）"
fi

# ── ② 台账：按「已签发条数」比较，多的一方为准
count_rows() {
    [ -f "$1" ] || { echo 0; return }
    # 台账表格行形如 "| 0001 | 2026-09-24 21:48 | 月付 …"
    grep -c -E '^\| *[0-9]+ *\|' "$1" 2>/dev/null || echo 0
}

SRC_ROWS=$(count_rows "$SRC_DIR/$LEDGER")
DEST_ROWS=$(count_rows "$DEST/$LEDGER")

echo "  · 仓库台账：$SRC_ROWS 条"
echo "  · 容器台账：$DEST_ROWS 条"

if [ "$DEST_ROWS" -gt "$SRC_ROWS" ]; then
    cp -f "$DEST/$LEDGER" "$SRC_DIR/$LEDGER"
    echo "  ✓ 容器较新 → 已写回仓库（$DEST_ROWS 条）"
elif [ "$SRC_ROWS" -gt "$DEST_ROWS" ]; then
    cp -f "$SRC_DIR/$LEDGER" "$DEST/$LEDGER"
    echo "  ✓ 仓库较新 → 已同步到容器（$SRC_ROWS 条）"
elif [ "$SRC_ROWS" -eq 0 ] && [ "$DEST_ROWS" -eq 0 ]; then
    echo "  · 两边都没有记录，无需同步"
else
    echo "  · 两边条数一致（$SRC_ROWS 条），无需同步"
fi

echo
if [ -f "$DEST/$KEY" ]; then
    echo "✓ 完成。可以直接双击「发码.app」使用。"
else
    echo "✗ 容器里仍没有私钥，App 无法签发 —— 请确认 $KEY 与本脚本在同一目录。"
fi
echo
echo "（本窗口可以直接关闭）"
