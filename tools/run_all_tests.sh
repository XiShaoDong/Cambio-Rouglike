#!/usr/bin/env bash
# 一键跑全量 headless 回归测试（含双实例网络测试 + 网络条件注入测试）。
#
# 用法：
#   tools/run_all_tests.sh                  # 全量
#   tools/run_all_tests.sh --quick          # 只跑单进程核心回归，跳过双实例/网络注入
#
# 环境变量：
#   GODOT=/path/to/Godot   覆盖 Godot 可执行路径（默认 macOS 安装路径）
#
# 退出码：全过 0；有失败 1。

set -u
cd "$(dirname "$0")/.." || exit 1

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
QUICK=0
for a in "$@"; do
	case "$a" in
		--quick) QUICK=1 ;;
		*) echo "未知参数: $a"; exit 2 ;;
	esac
done

PASS=0; FAIL=0
FAILED=()
TMP="$(mktemp -d)"

say() { printf '%s\n' "$*"; }

# 单进程测试：<label> <scene.tscn> [额外参数...]
run_single() {
	local label="$1"; shift
	local out
	out="$("$GODOT" --headless --path . "$@" 2>&1)"
	local rc=$?
	local result
	result="$(printf '%s\n' "$out" | grep -E "RESULT|PASS|FAIL" | tail -1)"
	if [ $rc -eq 0 ]; then
		PASS=$((PASS+1)); say "PASS  $label  $result"
	else
		FAIL=$((FAIL+1)); FAILED+=("$label"); say "FAIL  $label  $result"
		printf '%s\n' "$out" | grep -E "SCRIPT ERROR|Parse Error|printerr|VERIFY.*FAIL|ERROR" | head -6 | sed 's/^/        /'
	fi
}

# 双实例测试：<label> <scene.tscn> <host参数> <client参数>
run_dual() {
	local label="$1"; local scene="$2"; local host_args="$3"; local client_args="$4"
	local logbase="${label//\//_}"
	"$GODOT" --headless --path . "$scene" -- $host_args > "$TMP/$logbase.host.log" 2>&1 &
	local hp=$!
	sleep 1
	"$GODOT" --headless --path . "$scene" -- $client_args > "$TMP/$logbase.client.log" 2>&1
	local crc=$?
	wait $hp; local hrc=$?
	if [ $hrc -eq 0 ] && [ $crc -eq 0 ]; then
		PASS=$((PASS+1)); say "PASS  $label  (host+client)"
	else
		FAIL=$((FAIL+1)); FAILED+=("$label")
		say "FAIL  $label  (host=$hrc client=$crc)"
		grep -E "VERIFY.*FAIL|SCRIPT ERROR|Parse Error" "$TMP/$logbase.host.log" "$TMP/$logbase.client.log" | head -6 | sed 's/^/        /'
	fi
}

say "== 编译检查 =="
if ! "$GODOT" --headless --path . --quit-after 5 > "$TMP/compile.log" 2>&1; then
	say "FAIL  编译检查"
	grep -E "SCRIPT ERROR|Parse Error" "$TMP/compile.log" | head -6 | sed 's/^/        /'
	exit 1
fi
PASS=$((PASS+1)); say "PASS  编译检查（无脚本错误）"

say "== 单进程核心回归 =="
run_single "protocol"   res://tests/verify_protocol.tscn
run_single "swap"       res://tests/verify_swap.tscn
run_single "duel"       res://tests/verify_duel.tscn
run_single "reconnect"  res://tests/verify_reconnect.tscn
run_single "kongbaya"   res://tests/verify_kongbaya.tscn
run_single "settlement" res://tests/verify_settlement.tscn
run_single "series"     res://tests/verify_series.tscn
run_single "economy"    res://tests/verify_economy.tscn
run_single "hint"       res://tests/verify_hint.tscn

if [ "$QUICK" -eq 1 ]; then
	say ""
	say "== 结果：$PASS 过 / $FAIL 败 =="
	[ "$FAIL" -eq 0 ] && exit 0 || exit 1
fi

say "== 双实例网络测试 =="
run_dual "net"  res://tests/verify_net.tscn   "-role host"   "-role client"

say "== 网络条件注入测试（ProxyRelay UDP 中继）=="
for S in baseline latency loss jitter; do
	run_dual "proxy/$S" res://tests/verify_proxy.tscn "-role host -scenario $S" "-role client -scenario $S"
done
run_dual "proxy/reconnect" res://tests/verify_proxy.tscn "-role host -scenario baseline -mode reconnect" "-role client -scenario baseline -mode reconnect"

say ""
say "== 汇总：$PASS 过 / $FAIL 败 =="
if [ "$FAIL" -gt 0 ]; then
	say "失败项："
	for f in "${FAILED[@]}"; do say "  - $f"; done
	exit 1
fi
exit 0