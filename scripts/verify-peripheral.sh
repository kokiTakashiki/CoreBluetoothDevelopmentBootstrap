#!/usr/bin/env bash
# ============================================================
# verify-peripheral.sh — peripheral_uart の往復(上り/下り)を対話誘導で検証する。
#
# device 操作（ポート識別・送信・受信）は submodule の uart-* ターゲットへ委譲し、
# ここは「実行コマンドを見せて y/N」「受信内容の表示」という UX だけを担う
# （DESIGN-001 D-12 と同じ分担: device 操作は submodule、誘導は親）。
#
# 非対話（CI 等、stdin が tty でない）では全スキップして正常終了する（D-9）。
#
# 往復の仕組み: peripheral_uart は BLE(NUS) と DK の UART を橋渡しするだけ。
#   上り = Mac から DK シリアルへ world 送信 → iPhone の TX 通知に world。
#   下り = iPhone から RX へ てすと を Write → DK シリアルに てすと。
# ============================================================
set -uo pipefail

SUB="${1:?usage: verify-peripheral.sh <submodule-dir>}"
RUN() { make --no-print-directory -C "$SUB" "$@"; }

# 非対話なら検査をスキップ（機械では人間操作前提の往復を回せない）
if [ ! -t 0 ]; then
	echo "    [非対話] verify-peripheral の往復検査をスキップします"
	exit 0
fi

# y で真。それ以外（N・空・EOF）は偽。
ask() {
	local a
	printf '%s [yN] ' "$1"
	read -r a || return 1
	[ "$a" = y ] || [ "$a" = Y ]
}

# ---- ポート識別（submodule へ委譲）----
PORT="$(RUN uart-port)" || { echo "ERROR: DK シリアル(VCOM)の識別に失敗しました。USB 接続を確認してください。" >&2; exit 1; }
echo "識別した DK シリアル: $PORT"

# ---- 上り検査 (Peripheral -> Central) ----
echo
echo "[1/2] 上り検査: Mac から DK シリアルへ world を送信します。"
echo "      先に iPhone の nRF Connect で TX(6E400003) の Notify を ON にしておき、"
echo "      送信後に TX 通知へ world が出れば上り OK です。"
if ask "実行しますか？（make -C $SUB uart-send UART_MSG=world）"; then
	RUN uart-send UART_MSG=world
else
	echo "終了します。"
	exit 0
fi

# ---- 下り検査 (Central -> Peripheral) ----
# 取りこぼし防止のため、書き込みを促す前にキャプチャを開始しておく。
TMP="$(mktemp -t verify-peripheral)"
cleanup() {
	kill "${CAP_PID:-}" 2>/dev/null || true
	local h
	h=$(lsof -t "$PORT" 2>/dev/null || true)
	[ -n "$h" ] && kill $h 2>/dev/null || true
}
RUN uart-capture UART_SECS=180 >"$TMP" 2>/dev/null &
CAP_PID=$!

echo
echo "[2/2] 下り検査: iPhone の nRF Connect で RX(6E400002) へ てすと を Write してください。"
if ask "書き込みが完了したら y（終了は N）"; then
	:
else
	cleanup
	wait "$CAP_PID" 2>/dev/null || true
	rm -f "$TMP"
	echo "終了します。"
	exit 0
fi

# キャプチャ停止・ポート解放
cleanup
wait "$CAP_PID" 2>/dev/null || true

# ---- 受信内容の表示 ----
echo
if ask "DK のシリアルが受信した内容を表示しますか？（cat ${TMP} を整形）"; then
	echo "=== 受信(テキスト) ==="
	tr -d '\r' <"$TMP"
	echo
	echo "=== 受信(hex) ==="
	xxd "$TMP"
	if [ -s "$TMP" ]; then
		echo "→ てすと（UTF-8: e3 81 a6 e3 81 99 e3 81 a8）が見えれば下り OK です。"
	else
		echo "→ 受信なし。iPhone から RX(6E400002) へ Write したか、TX/接続状態、"
		echo "   別 VCOM の可能性（UART_PORT=/dev/cu.xxx で上書き可）を確認してください。"
	fi
else
	echo "終了します。"
fi
rm -f "$TMP"
