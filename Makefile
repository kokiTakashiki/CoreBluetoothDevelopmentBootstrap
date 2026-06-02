# ============================================================
# DESIGN-001 環境構築 Makefile
# Core Bluetooth 検証環境を冪等に構築する自動化レイヤ
#
# 設計方針:
#   - 各ターゲットは状態検査つきの冪等な単位として定義する。
#   - 依存グラフにより必要最小限の実行に限定する。
#   - 失敗時は副作用を残さず即停止し、再実行で回復可能な状態を保つ。
#
# 対象: Apple Silicon Mac。Xcode / iOS 実機署名は対象外。
# ============================================================

# --- シェル設定 ---------------------------------------------
# 1 レシピを 1 シェルで実行し、いずれかのコマンド失敗で即停止する。
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:

# ============================================================
# 変数（コマンドライン引数での上書きを許容。未指定時は安全側の既定値）
# ============================================================

# nRF Connect SDK のバージョン固定。バージョン不整合に起因するビルド失敗を防ぐ。
NCS_VERSION ?= v2.6.1

# ビルド対象ボード。
BOARD ?= nrf52840dk_nrf52840

# NCS のインストールルートとサンプル / ビルドディレクトリ。
NCS_BASE   ?= $(HOME)/ncs/$(NCS_VERSION)
SAMPLE_DIR ?= $(NCS_BASE)/nrf/samples/bluetooth/peripheral_uart
BUILD_DIR  ?= $(CURDIR)/build

# nrfutil 本体（公式 arm64 ネイティブバイナリ）。
# Homebrew cask(nrfutil) は deprecated かつ macOS Gatekeeper チェックに失敗し、
# 壊れた symlink を残すため使わない。Nordic 公式の配布物を直接取得する。
NRFUTIL_BIN ?= $(shell brew --prefix 2>/dev/null)/bin/nrfutil
NRFUTIL_URL ?= https://files.nordicsemi.com/ui/api/v1/download?repoKey=swtools&path=external/nrfutil/executables/aarch64-apple-darwin/nrfutil&isNativeBrowsing=false

# Sniffer ファームウェア（dongle 書き込み用 hex）と extcap プラグインのソース。
# nRF Sniffer 配布物のバージョンに追随する。
SNIFFER_PKG_DIR    ?= $(HOME)/nrf_sniffer_for_bluetooth_le
SNIFFER_HEX        ?= $(SNIFFER_PKG_DIR)/hex/sniffer_nrf52840dongle_nrf52840_*.hex
SNIFFER_EXTCAP_SRC ?= $(SNIFFER_PKG_DIR)/extcap

# extcap プラグインの配置先。macOS のユーザー領域パスを既定とする。
WIRESHARK_EXTCAP_DIR ?= $(HOME)/.local/lib/wireshark/extcap

# 書き込み対象シリアルポート。未指定時は flash 系ターゲットで自動検出を試み、
# 複数検出時はエラーで停止する。
SERIAL_PORT ?=

# ============================================================
# 既定ゴール: help（先頭に配置）
# 素の `make` は副作用を持たない help を表示する。導入・ビルド・実機書き込みを
# 伴う setup は明示的に `make setup` と打たせ、誤実行の事故を防ぐ。
# ============================================================
.DEFAULT_GOAL := help

help: ## このヘルプ（ターゲット一覧）を表示
	@echo "使い方: make <target>  (例: make setup)"
	@echo ""
	@echo "ターゲット:"
	@grep -E '^[a-zA-Z][a-zA-Z0-9_-]*:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ============================================================
# setup : 環境構築から検証までを一括実行（明示呼び出し）
# 依存先がすべて冪等なため再実行も冪等。
# ============================================================
setup: check-os install-tools build-firmware verify ## 前提確認→導入→ビルド→検証を一括実行
	@echo ""
	@echo "==> setup 完了: 環境構築から検証まで一括実行しました。"

# ============================================================
# check-os : 実行環境の前提確認（読み取り専用 / 本質的に冪等）
# ============================================================
check-os: ## 実行環境の前提確認（arm64 / Homebrew）
	@if [ "$$(uname -m)" != "arm64" ]; then \
		echo "ERROR(check-os): Apple Silicon (arm64) が必要です。検出: $$(uname -m)" >&2; \
		exit 1; \
	fi
	@if ! command -v brew >/dev/null 2>&1; then \
		echo "ERROR(check-os): Homebrew が見つかりません。https://brew.sh を参照してください。" >&2; \
		exit 1; \
	fi
	@echo "==> check-os: OK (arm64 / Homebrew あり)"

# ============================================================
# install-tools : 各ツールを導入（導入前に存在検査し、未導入のもののみ導入）
#   nRF Connect SDK Toolchain / nrfutil / Wireshark / Python 依存(west)
# ============================================================
install-tools: check-os ## ツール導入（nrfutil/NCS/west/Wireshark）
	@echo "==> install-tools: 導入状況を検査します"
	# --- nrfutil 本体（公式 arm64 バイナリ。判定は --version の終了コードで行う）---
	@if nrfutil --version >/dev/null 2>&1; then \
		echo "    [skip] nrfutil は導入済み ($$(nrfutil --version 2>/dev/null | head -1))"; \
	else \
		echo "    [install] nrfutil (Nordic 公式 arm64 ネイティブバイナリ)"; \
		tmp="$$(mktemp)"; \
		curl -fL -o "$$tmp" "$(NRFUTIL_URL)"; \
		chmod +x "$$tmp"; \
		xattr -d com.apple.quarantine "$$tmp" 2>/dev/null || true; \
		mv "$$tmp" "$(NRFUTIL_BIN)"; \
		nrfutil --version; \
	fi
	# --- nrfutil サブコマンド: toolchain-manager / device（install は冪等）---
	@if nrfutil toolchain-manager --help >/dev/null 2>&1; then \
		echo "    [skip] nrfutil toolchain-manager / device は導入済み"; \
	else \
		echo "    [install] nrfutil コマンド (toolchain-manager / device)"; \
		nrfutil install toolchain-manager; \
		nrfutil install device; \
	fi
	# --- nRF Connect SDK Toolchain（NCS_VERSION で固定）---
	@if nrfutil toolchain-manager list 2>/dev/null | grep -q "$(NCS_VERSION)"; then \
		echo "    [ok] NCS Toolchain $(NCS_VERSION)"; \
	else \
		echo "    [install] NCS Toolchain $(NCS_VERSION)"; \
		nrfutil toolchain-manager install --ncs-version $(NCS_VERSION); \
	fi
	# --- Python 依存: west ---
	@if command -v west >/dev/null 2>&1; then \
		echo "    [skip] west は導入済み"; \
	else \
		echo "    [install] west (pip)"; \
		python3 -m pip install --user west; \
	fi
	# --- Wireshark ---
	@if brew list --cask wireshark >/dev/null 2>&1 || command -v tshark >/dev/null 2>&1; then \
		echo "    [skip] Wireshark は導入済み"; \
	else \
		echo "    [install] Wireshark"; \
		brew install --cask wireshark; \
	fi
	# --- nRF Connect for Desktop（Toolchain Manager GUI / 任意）---
	@if brew list --cask nrf-connect >/dev/null 2>&1; then \
		echo "    [skip] nRF Connect for Desktop は導入済み"; \
	else \
		echo "    [install] nRF Connect for Desktop"; \
		brew install --cask nrf-connect; \
	fi
	@echo "==> install-tools: 完了"

# ============================================================
# install-sniffer : nRF Sniffer の extcap プラグインを配置
#   配置元と配置先の shasum を比較し、一致時は再配置しない（冪等）
# ============================================================
install-sniffer: install-tools ## nRF Sniffer の extcap プラグインを配置
	@echo "==> install-sniffer: extcap プラグインを配置します"
	@if [ ! -d "$(SNIFFER_EXTCAP_SRC)" ]; then \
		echo "ERROR(install-sniffer): Sniffer extcap ソースが見つかりません: $(SNIFFER_EXTCAP_SRC)" >&2; \
		echo "  SNIFFER_PKG_DIR を nRF Sniffer 配布物の展開先に設定してください。" >&2; \
		exit 1; \
	fi
	@mkdir -p "$(WIRESHARK_EXTCAP_DIR)"
	@changed=0; \
	for src in "$(SNIFFER_EXTCAP_SRC)"/*; do \
		[ -e "$$src" ] || continue; \
		name="$$(basename "$$src")"; \
		dst="$(WIRESHARK_EXTCAP_DIR)/$$name"; \
		src_h="$$(shasum "$$src" | awk '{print $$1}')"; \
		dst_h="$$([ -f "$$dst" ] && shasum "$$dst" | awk '{print $$1}' || echo none)"; \
		if [ "$$src_h" = "$$dst_h" ]; then \
			echo "    [skip] $$name (ハッシュ一致)"; \
		else \
			echo "    [copy] $$name"; \
			cp "$$src" "$$dst"; \
			chmod +x "$$dst" 2>/dev/null || true; \
			changed=1; \
		fi; \
	done; \
	echo "==> install-sniffer: 完了 (更新 $$changed 件)"

# ============================================================
# build-firmware : peripheral_uart をビルド
#   west build のインクリメンタル機構に委ねる（ソース未変更時は再コンパイルなし）
# ============================================================
build-firmware: install-tools ## peripheral_uart をビルド
	@echo "==> build-firmware: $(BOARD) 向けに $(SAMPLE_DIR) をビルドします"
	@if [ ! -d "$(SAMPLE_DIR)" ]; then \
		echo "ERROR(build-firmware): サンプルが見つかりません: $(SAMPLE_DIR)" >&2; \
		echo "  NCS_VERSION=$(NCS_VERSION) のインストール先を確認してください。" >&2; \
		exit 1; \
	fi
	# nrfutil toolchain-manager の環境内で west build を実行する。
	# west は未変更ソースを再コンパイルしないため、再実行は冪等に近い。
	@nrfutil toolchain-manager launch --ncs-version $(NCS_VERSION) -- \
		west build -b $(BOARD) "$(SAMPLE_DIR)" --build-dir "$(BUILD_DIR)"
	@echo "==> build-firmware: 完了 ($(BUILD_DIR))"

# ============================================================
# flash-dk : ビルド済みファームウェアを開発キットへ書き込む
#   接続中の DK(J-Link) を検出し、未接続時は明示エラーで停止
#   同一ファームウェアの再書き込みは結果状態を変えないため実質冪等
# ============================================================
flash-dk: build-firmware ## 開発キットへ書き込み（要 DK 接続）
	@echo "==> flash-dk: 開発キットへ書き込みます"
	@if ! command -v nrfjprog >/dev/null 2>&1; then \
		echo "ERROR(flash-dk): nrfjprog が見つかりません（nRF Command Line Tools を導入してください）" >&2; \
		exit 1; \
	fi
	@ids="$$(nrfjprog --ids 2>/dev/null || true)"; \
	if [ -z "$$ids" ]; then \
		echo "ERROR(flash-dk): 接続中の開発キット(J-Link)が検出できません。USB 接続を確認してください。" >&2; \
		exit 1; \
	fi; \
	echo "    検出した J-Link: $$ids"
	@nrfutil toolchain-manager launch --ncs-version $(NCS_VERSION) -- \
		west flash --build-dir "$(BUILD_DIR)"
	@echo "==> flash-dk: 完了"

# ============================================================
# flash-sniffer-dongle : USB ドングルへ Sniffer FW を書き込む
#   Open Bootloader 経由の DFU を用いる
#   同一ファームウェアの再書き込みは結果を変えない（実質冪等）
# ============================================================
flash-sniffer-dongle: install-sniffer ## ドングルへ Sniffer FW を書き込み（要ドングル）
	@echo "==> flash-sniffer-dongle: ドングルへ Sniffer FW を書き込みます"
	@hex="$$(ls $(SNIFFER_HEX) 2>/dev/null | head -n1 || true)"; \
	if [ -z "$$hex" ]; then \
		echo "ERROR(flash-sniffer-dongle): Sniffer hex が見つかりません: $(SNIFFER_HEX)" >&2; \
		exit 1; \
	fi; \
	port="$(SERIAL_PORT)"; \
	if [ -z "$$port" ]; then \
		found="$$(ls /dev/tty.usbmodem* 2>/dev/null || true)"; \
		n="$$(printf '%s\n' $$found | grep -c . || true)"; \
		if [ "$$n" -eq 0 ]; then \
			echo "ERROR(flash-sniffer-dongle): ドングルのシリアルポートが検出できません。" >&2; \
			echo "  Open Bootloader を有効にして接続するか、SERIAL_PORT= を明示してください。" >&2; \
			exit 1; \
		elif [ "$$n" -gt 1 ]; then \
			echo "ERROR(flash-sniffer-dongle): シリアルポートが複数検出されました。SERIAL_PORT= を明示してください:" >&2; \
			printf '    %s\n' $$found >&2; \
			exit 1; \
		fi; \
		port="$$found"; \
	fi; \
	echo "    対象ポート: $$port / hex: $$hex"; \
	nrfutil pkg generate --hw-version 52 --sd-req 0x00 \
		--application "$$hex" --application-version 1 "$(BUILD_DIR)/sniffer_dfu.zip"; \
	nrfutil dfu usb-serial -pkg "$(BUILD_DIR)/sniffer_dfu.zip" -p "$$port"
	@echo "==> flash-sniffer-dongle: 完了"

# ============================================================
# verify : 構築結果を検査（読み取り専用 / 状態を変更しない）
#   - DK が BLE Peripheral として広告しているか
#   - Wireshark に Sniffer インタフェースが出現しているか
# ============================================================
verify: flash-dk flash-sniffer-dongle ## 広告 / Sniffer インタフェースの検査
	@echo "==> verify: 構築結果を検査します"
	# 注: macOS 標準の make 3.81 は .ONESHELL 非対応のため、レシピ行をまたいだ
	# 変数共有はできない。検査全体を 1 つのシェルチェーンに閉じて状態を持たせる。
	@ok=1; \
	if command -v tshark >/dev/null 2>&1 && tshark -D 2>/dev/null | grep -qi "sniffer"; then \
		echo "    [ok] Wireshark に Sniffer インタフェースが出現"; \
		iface="$$(tshark -D 2>/dev/null | grep -i sniffer | head -n1 | sed -E 's/^[0-9]+\. ([^ ]+).*/\1/')"; \
		if timeout 8 tshark -i "$$iface" -a duration:6 -c 1 >/dev/null 2>&1; then \
			echo "    [ok] DK の BLE 広告（または BLE トラフィック）を検出"; \
		else \
			echo "    [warn] 広告を検出できませんでした。DK が起動・広告中か、flash-dk を確認してください。" >&2; \
			ok=0; \
		fi; \
	else \
		echo "    [NG] Sniffer インタフェースが見つかりません（install-sniffer / flash-sniffer-dongle を再実行）" >&2; \
		ok=0; \
	fi; \
	if [ "$$ok" -ne 1 ]; then \
		echo "==> verify: 一部の検査に失敗しました。" >&2; \
		exit 1; \
	fi; \
	echo "==> verify: すべての検査に合格"

# ============================================================
# clean : ビルド成果物を削除（対象不在でも rm -f により正常終了）
#   導入済みツールやファームウェア書き込み状態には干渉しない
# ============================================================
clean: ## ビルド成果物を削除
	@echo "==> clean: ビルド成果物を削除します ($(BUILD_DIR))"
	@rm -rf "$(BUILD_DIR)"
	@echo "==> clean: 完了"

# ============================================================
# .PHONY 指定（同名ファイルの有無に挙動を左右されないようにする）
# ============================================================
.PHONY: help setup check-os install-tools install-sniffer build-firmware \
        flash-dk flash-sniffer-dongle verify clean
