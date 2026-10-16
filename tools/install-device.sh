#!/bin/bash
#
# 码夹 CodeClip · 真机安装脚本（免费 Personal Team 自动签名路径）
#
# 背景：免费 Apple ID 签名的描述文件只有 **7 天**有效期，到期后 App 图标点不开，
#       重跑本脚本即可续签，无需打开 Xcode 图形界面。
#
# 用法：
#   tools/install-device.sh                    # 标准安装（含 App Group）
#   tools/install-device.sh --check            # 只体检，不构建
#   tools/install-device.sh --no-appgroup      # 降级：临时摘掉 App Group 再装
#   tools/install-device.sh --restore          # 恢复被摘掉的 App Group
#   tools/install-device.sh --team ABCD123456  # 手动指定 Team ID（默认自动探测）
#
# 前置（这三步必须先在图形界面完成，脚本无法代劳）：
#   1) Xcode → Settings → Accounts 登录 Apple ID（Team 栏应显示「xxx (Personal Team)」）
#   2) iPhone → 设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启确认
#   3) iPhone 数据线连 Mac，弹窗点「信任此电脑」并输锁屏密码
#
# 说明：App Group（group.com.jikezhang.codeclip）是小组件共享数据的通道。
#       免费账号通常签不下来该能力，此时用 --no-appgroup 装：App 本体功能完整，
#       仅小组件读不到数据（PickupStorage 已做回落，不会崩）。
#       拿到付费账号后执行 --restore 并重装即可恢复小组件。

set -euo pipefail

DEV_UDID="${DEV_UDID:-00008140-001138A92E01801C}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$SCRIPT_DIR/../CodeClip"
PROJ="$PROJ_ROOT/CodeClip.xcodeproj"
CFG_DIR="$PROJ_ROOT/Config"
DD="/tmp/codeclip-device"
BUNDLE_ID="com.jikezhang.codeclip"
SCHEME="CodeClip"

# 🔴 Xcode 27 beta 下 `xcrun` 不把 devicectl 暴露为可查找工具（xcrun --find 会报
#    "unable to find utility"），但二进制实际存在于 Developer/usr/bin/。
#    若直接 `xcrun devicectl` 会被 xcrun 当场判失败，安装步骤永远到不了。
#    这里先 xcrun 探测，失败则回退到已知的 beta 完整路径。
DEVICECTL="$(xcrun --find devicectl 2>/dev/null || true)"
[[ -z "$DEVICECTL" ]] && DEVICECTL="$(ls /Applications/Xcode-beta.app/Contents/Developer/usr/bin/devicectl 2>/dev/null || true)"
[[ -n "$DEVICECTL" ]] || die "找不到 devicectl（Xcode 27 下 xcrun 不暴露该工具，且 beta 路径缺失）"

C_OK="\033[32m"; C_WARN="\033[33m"; C_ERR="\033[31m"; C_DIM="\033[2m"; C_OFF="\033[0m"
say()  { printf "%b\n" "$1"; }
ok()   { printf "${C_OK}✓${C_OFF} %s\n" "$1"; }
warn() { printf "${C_WARN}!${C_OFF} %s\n" "$1"; }
die()  { printf "${C_ERR}✗${C_OFF} %s\n" "$1" >&2; exit 1; }

MODE="install"
TEAM=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)      MODE="check"; shift ;;
    --no-appgroup) MODE="no-appgroup"; shift ;;
    --restore)    MODE="restore"; shift ;;
    --team)       TEAM="${2:-}"; shift 2 ;;
    -h|--help)    sed -n '2,26p' "$0"; exit 0 ;;
    *)            die "未知参数：$1（用 --help 查看用法）" ;;
  esac
done

# ── 1. 恢复 App Group ────────────────────────────────────────────────
if [[ "$MODE" == "restore" ]]; then
  restored=0
  for f in "$CFG_DIR"/CodeClip.entitlements "$CFG_DIR"/CodeClipWidget.entitlements; do
    if [[ -f "$f.appgroup-backup" ]]; then
      mv -f "$f.appgroup-backup" "$f"
      ok "已恢复 $(basename "$f")"
      restored=$((restored + 1))
    fi
  done
  [[ $restored -eq 0 ]] && warn "没有找到备份（可能当前已是含 App Group 的状态）"
  say ""
  say "现在重跑 ${C_DIM}$0${C_OFF} 即可带 App Group 安装（需付费账号签名）。"
  exit 0
fi

# ── 2. 摘掉 App Group ────────────────────────────────────────────────
if [[ "$MODE" == "no-appgroup" ]]; then
  for f in "$CFG_DIR"/CodeClip.entitlements "$CFG_DIR"/CodeClipWidget.entitlements; do
    [[ -f "$f.appgroup-backup" ]] || cp -p "$f" "$f.appgroup-backup"
    cat > "$f" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
PLIST
    ok "已摘除 App Group：$(basename "$f")（原文件备份为 .appgroup-backup）"
  done
  warn "小组件本次将读不到数据；App 本体会自动回落到自身容器，功能完整。"
  say ""
fi

# ── 3. 体检 ──────────────────────────────────────────────────────────
say "── 环境体检 ──────────────────────────────────────"
xcodebuild -version 2>/dev/null | head -1 | sed 's/^/  Xcode：/'

if [[ -z "$TEAM" ]]; then
  # 来源 1：工程里已经写好的值（例如主人在 Xcode 图形界面手动选过 Team）
  #   必须用 sed 一次性取出 `=` 之后的部分。
  #   🔴 早期版本写成 `grep -oE 'DEVELOPMENT_TEAM = [A-Z0-9]{10}' | head -1 | grep -oE '[A-Z0-9]{10}'`，
  #      第二步的宽松匹配会把键名 "DEVELOPMENT" 也切出前 10 位，TEAM 变成
  #      "DEVELOPMEN\nSW725KU49U" 两行 —— 带这种值去构建必然签名失败。
  TEAM="$(sed -n 's/.*DEVELOPMENT_TEAM = \([A-Z0-9]\{10\}\).*/\1/p' "$PROJ/project.pbxproj" 2>/dev/null \
          | head -1 || true)"
fi
if [[ -z "$TEAM" ]]; then
  # 来源 2：Xcode 已登录账号中的团队列表（先锁到 teamID 键，再取值，避免抓到无关的 10 位串）
  TEAM="$(defaults read com.apple.dt.Xcode IDEProvisioningTeams 2>/dev/null \
          | grep -oE 'teamID = "[A-Z0-9]{10}"|teamID = [A-Z0-9]{10}' | head -1 \
          | grep -oE '[A-Z0-9]{10}' || true)"
fi
if [[ -z "$TEAM" ]]; then
  # 来源 3：钥匙串里 Apple Development 证书的 Team（即括号内那 10 位，也等于证书 OU）
  TEAM="$(security find-identity -v -p codesigning 2>/dev/null \
          | grep -oE '\([A-Z0-9]{10}\)' | head -1 | tr -d '()' || true)"
fi
# 🔴 校验：必须是单行 10 位大写字母数字。挡住多行、空值、以及被键名污染的脏值。
if [[ -n "$TEAM" ]] && ! [[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]]; then
  warn "自动探测到的 Team ID 非法（$(printf '%s' "$TEAM" | tr '\n' '|')），已丢弃"
  TEAM=""
fi
if [[ -z "$TEAM" ]]; then
  die "取不到 Team ID。请二选一：
    A) 在 Xcode 里打开工程 → 选 CodeClip target → Signing & Capabilities
       → Team 下拉选「<你的名字> (Personal Team)」，CodeClipWidget target 也选一遍；
    B) 重跑本脚本并加 --team XXXXXXXXXX（Team ID 可在 Xcode 账号页查到）。"
fi
ok "Team ID：$TEAM"

if [[ "$MODE" == "check" ]]; then
  security find-identity -v -p codesigning 2>/dev/null | sed 's/^/  /'
  exit 0
fi

# ── 4. 写入 Team ID ──────────────────────────────────────────────────
PBX="$PROJ/project.pbxproj"
perl -0pi -e 's/^\t*DEVELOPMENT_TEAM = [^;]*;\n//mg' "$PBX"
perl -0pi -e "s/(CODE_SIGN_STYLE = Automatic;)/\$1\n\t\t\t\tDEVELOPMENT_TEAM = $TEAM;/g" "$PBX"
cnt="$(grep -c 'DEVELOPMENT_TEAM' "$PBX" || true)"
ok "已写入 DEVELOPMENT_TEAM（$cnt 处配置）"

# ── 5. 构建 ──────────────────────────────────────────────────────────
say ""
say "── 构建（首次会联网生成证书与描述文件，稍慢）─────────"
set +e
xcodebuild -project "$PROJ" \
           -scheme "$SCHEME" \
           -configuration Debug \
           -destination "id=$DEV_UDID" \
           -derivedDataPath "$DD" \
           -allowProvisioningUpdates \
           build 2>&1 | tee /tmp/codeclip-device-build.log | \
  grep -E "error:|warning:|CodeSign|BUILD SUCCEEDED|BUILD FAILED|No profiles|doesn't include" || true
rc=${PIPESTATUS[0]}
set -e

if [[ $rc -ne 0 ]]; then
  say ""
  if grep -q "application-groups" /tmp/codeclip-device-build.log; then
    warn "签名被 App Group 拦下 —— 这正是免费账号的已知限制。"
    say ""
    say "  解决办法：改用降级模式重装"
    say "    ${C_DIM}$0 --no-appgroup${C_OFF}"
    say ""
  elif grep -qi "developer mode" /tmp/codeclip-device-build.log; then
    warn "iPhone 尚未开启开发者模式。"
    say "  设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启 → 确认"
    say ""
  else
    warn "构建失败，完整日志：/tmp/codeclip-device-build.log"
    say "  常见原因：Apple ID 未登录 / 描述文件额度用尽（免费账号 7 天 10 个 App ID）"
    say ""
  fi
  exit $rc
fi
ok "构建成功"

# ── 6. 安装到真机 ────────────────────────────────────────────────────
APP="$(find "$DD/Build/Products/Debug-iphoneos" -maxdepth 1 -name "$SCHEME.app" | head -1)"
[[ -n "$APP" ]] || die "找不到构建产物 $SCHEME.app"

say ""
say "── 安装到 iPhone ────────────────────────────────"
"$DEVICECTL" device install app --device "$DEV_UDID" "$APP"

say ""
ok "安装完成。首次打开若提示「不受信任的开发者」："
# 🔴 必须写 ${TEAM}：`$TEAM」` 会把中文右引号的首字节算进变量名，
#    在 `set -u` 下报 "TEAM<乱码>: unbound variable" 并以非 0 退出 ——
#    安装其实已经成功，但脚本尾部中断会让续签时误判为失败。
say "  iPhone → 设置 → 通用 → VPN 与设备管理 → 信任「${TEAM}」"

if [[ "$MODE" != "no-appgroup" ]]; then
  say ""
  warn "当前描述文件 7 天后过期，届时重跑本脚本续签即可。"
fi
