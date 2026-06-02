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
# setup : ソフトウェア環境構築（実機不要）
# 前提確認→ツール導入→ファームウェアビルドまでをソフト工程のみで一括実行。
# 実機への書き込み＆検証は deploy が担う（→ DL-9）。
# 依存先がすべて冪等なため再実行も冪等。
# ============================================================
setup: check-os install-tools build-firmware ## ソフトウェア環境構築（実機不要）
	@echo ""
	@echo "==> setup 完了: ソフトウェア環境構築（実機不要）を一括実行しました。"
	@echo "    実機への書き込み＆検証は 'make deploy'（要 DK＋ドングル接続）。"

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
# install-nrfutil : nrfutil 本体を導入（最も壊れやすい工程を独立化）
#   Homebrew cask は deprecated/Gatekeeper 不可で壊れた symlink を残すため使わず、
#   Nordic 公式 arm64 バイナリを直接取得する。判定は --version の終了コードで行う。
#   独立ターゲット化により CI が本工程だけを実機実行して検証できる（→ DL-6）。
# ============================================================
install-nrfutil: check-os ## nrfutil 本体を導入（公式 arm64 バイナリ）
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

# ============================================================
# install-tools : 各ツールを導入（導入前に存在検査し、未導入のもののみ導入）
#   nrfutil サブコマンド / NCS Toolchain / Wireshark / Python 依存(west)
# ============================================================
install-tools: install-nrfutil ## ツール導入（nrfutil/NCS/west/Wireshark）
	@echo "==> install-tools: 導入状況を検査します"
	# --- nrfutil サブコマンド: toolchain-manager / device（install は冪等）---
	@if nrfutil toolchain-manager --help >/dev/null 2>&1; then \
		echo "    [skip] nrfutil toolchain-manager / device は導入済み"; \
	else \
		echo "    [install] nrfutil コマンド (toolchain-manager / device)"; \
		nrfutil install toolchain-manager; \
		nrfutil install device; \
	fi
	# --- nrfutil サブコマンド: nrf5sdk-tools（pkg generate / dfu usb-serial を提供）---
	# 新 unified nrfutil 本体には pkg / dfu が無いため、ドングルの DFU 書き込みに必須（→ DL-5）。
	@if nrfutil nrf5sdk-tools --help >/dev/null 2>&1; then \
		echo "    [skip] nrfutil nrf5sdk-tools は導入済み"; \
	else \
		echo "    [install] nrfutil コマンド (nrf5sdk-tools: pkg/dfu 提供)"; \
		nrfutil install nrf5sdk-tools; \
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
		echo "  nRF Sniffer for Bluetooth LE 配布物（zip）が未展開です。" >&2; \
		echo "  対処:" >&2; \
		echo "    1) ダウンロード: https://www.nordicsemi.com/Products/Development-tools/nRF-Sniffer-for-Bluetooth-LE" >&2; \
		echo "    2) zip を展開し、その中身を SNIFFER_PKG_DIR に配置（既定: $(SNIFFER_PKG_DIR)）" >&2; \
		echo "       → 展開後に $(SNIFFER_EXTCAP_SRC) が存在する状態にする" >&2; \
		echo "    3) 別パスに置いた場合は 'make install-sniffer SNIFFER_PKG_DIR=/path/to/extracted' で指定" >&2; \
		echo "  導入手順: https://docs.nordicsemi.com/bundle/nrfutil/page/nrfutil-ble-sniffer/guides/installing_nrf_sniffer.html" >&2; \
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
# fetch-ncs : nRF Connect SDK のソースツリーを取得（west init + update）
#   install-tools が入れた nrfutil toolchain-manager 環境内で west を実行し、
#   NCS_VERSION 固定で $(NCS_BASE) に nrf/ zephyr/ samples/ 等のソースを展開する。
#   install-tools はツールチェイン（コンパイラ/Zephyr 依存）のみを入れるため、
#   ソースツリー（SAMPLE_DIR を含む）は本ターゲットが別途取得する（→ DL-7）。
#
#   コマンドは Nordic 公式の install_ncs 手順に準拠（推測コマンドではない）:
#     https://docs.nordicsemi.com/bundle/ncs-latest/page/nrf/installation/install_ncs.html
#     1) launch -- west init -m https://github.com/nrfconnect/sdk-nrf --mr <ver> <topdir>
#     2) workspace 内で west update（cd 後に実行）
#     3) west zephyr-export（Zephyr CMake パッケージを登録）
#
#   注意: west update は NCS 全リポジトリ（nrf/zephyr/mcuboot 等）を clone するため
#         数 GB のダウンロードと相応の時間を要する。CI では実行しない（dry-run のみ）。
#
#   冪等ガード: SAMPLE_DIR か west workspace($(NCS_BASE)/.west) が既にあれば何もしない。
# ============================================================
fetch-ncs: install-tools ## NCS ソースツリーを取得（west init+update / 数 GB DL）
	@echo "==> fetch-ncs: NCS ソースを取得します ($(NCS_BASE), NCS_VERSION=$(NCS_VERSION))"
	@if [ -d "$(SAMPLE_DIR)" ] || [ -d "$(NCS_BASE)/.west" ]; then \
		echo "    [skip] NCS ソース取得済み ($(NCS_BASE))"; \
	else \
		echo "    [fetch] NCS ソースを取得します（数 GB のダウンロード。時間がかかります）"; \
		mkdir -p "$(NCS_BASE)"; \
		if ! nrfutil toolchain-manager launch --ncs-version $(NCS_VERSION) -- \
			west init -m https://github.com/nrfconnect/sdk-nrf --mr $(NCS_VERSION) "$(NCS_BASE)"; then \
			echo "ERROR(fetch-ncs): west init に失敗しました（manifest 取得 / ネットワークを確認してください）。" >&2; \
			echo "  - manifest: https://github.com/nrfconnect/sdk-nrf （--mr $(NCS_VERSION) が存在するタグ/ブランチか確認）" >&2; \
			echo "  - 公式手順: https://docs.nordicsemi.com/bundle/ncs-latest/page/nrf/installation/install_ncs.html" >&2; \
			echo "  - 途中失敗時は 'rm -rf $(NCS_BASE)' で消してから再実行してください。" >&2; \
			exit 1; \
		fi; \
		if ! nrfutil toolchain-manager launch --ncs-version $(NCS_VERSION) -- \
			/bin/bash -c 'cd "$(NCS_BASE)" && west update && west zephyr-export'; then \
			echo "ERROR(fetch-ncs): west update に失敗しました（ネットワーク / リポジトリ取得を確認してください）。" >&2; \
			echo "  - 公式手順: https://docs.nordicsemi.com/bundle/ncs-latest/page/nrf/installation/install_ncs.html" >&2; \
			echo "  - 途中失敗時は workspace($(NCS_BASE)) 内で west update を再実行するか、'rm -rf $(NCS_BASE)' で消してから 'make fetch-ncs' を再実行してください。" >&2; \
			exit 1; \
		fi; \
		echo "    [done] NCS ソース取得完了 ($(NCS_BASE))"; \
	fi
	@echo "==> fetch-ncs: 完了"

# ============================================================
# build-firmware : peripheral_uart をビルド
#   west build のインクリメンタル機構に委ねる（ソース未変更時は再コンパイルなし）
#   ソースツリーは fetch-ncs が事前に取得する（依存関係で自動実行）。
# ============================================================
build-firmware: install-tools fetch-ncs ## peripheral_uart をビルド
	@echo "==> build-firmware: $(BOARD) 向けに $(SAMPLE_DIR) をビルドします"
	@if [ ! -d "$(SAMPLE_DIR)" ]; then \
		echo "ERROR(build-firmware): サンプルが見つかりません: $(SAMPLE_DIR)" >&2; \
		echo "  NCS ソースが未取得か、想定パスにありません（NCS_VERSION=$(NCS_VERSION)）。" >&2; \
		echo "  対処: 'make fetch-ncs' を実行して NCS ソースツリーを取得してください。" >&2; \
		echo "  手動取得（nrfutil toolchain-manager 環境内）:" >&2; \
		echo "    nrfutil toolchain-manager launch --ncs-version $(NCS_VERSION) -- \\" >&2; \
		echo "      west init -m https://github.com/nrfconnect/sdk-nrf --mr $(NCS_VERSION) $(NCS_BASE)" >&2; \
		echo "    cd $(NCS_BASE) && nrfutil toolchain-manager launch --ncs-version $(NCS_VERSION) -- \\" >&2; \
		echo "      /bin/bash -c 'west update && west zephyr-export'" >&2; \
		echo "  公式手順: https://docs.nordicsemi.com/bundle/ncs-latest/page/nrf/installation/install_ncs.html" >&2; \
		exit 1; \
	fi
	# nrfutil toolchain-manager の環境内で west build を実行する。
	# `west build` は west ワークスペース拡張コマンドのため、ワークスペース
	# ($(NCS_BASE)) の内側で実行する必要がある（外で実行すると
	# 「unknown command "build"」になる）。よって cd してから呼ぶ。
	# west は未変更ソースを再コンパイルしないため、再実行は冪等に近い。
	@nrfutil toolchain-manager launch --ncs-version $(NCS_VERSION) -- \
		/bin/bash -c 'cd "$(NCS_BASE)" && west build -b $(BOARD) "$(SAMPLE_DIR)" --build-dir "$(BUILD_DIR)"'
	@echo "==> build-firmware: 完了 ($(BUILD_DIR))"

# ============================================================
# flash-dk : ビルド済みファームウェアを開発キットへ書き込む
#   接続中の DK(J-Link) を検出し、未接続時は明示エラーで停止
#   同一ファームウェアの再書き込みは結果状態を変えないため実質冪等
# ============================================================
flash-dk: build-firmware ## 開発キットへ書き込み（要 DK 接続）
	@echo "==> flash-dk: 開発キットへ書き込みます"
	@if ! command -v nrfjprog >/dev/null 2>&1; then \
		echo "ERROR(flash-dk): nrfjprog が見つかりません。" >&2; \
		echo "  nrfjprog は nRF Command Line Tools に含まれます（J-Link 経由の DK 書き込みに必要）。" >&2; \
		echo "  対処: 下記からダウンロードしてインストールしてください:" >&2; \
		echo "    https://www.nordicsemi.com/Products/Development-tools/nRF-Command-Line-Tools/Download" >&2; \
		echo "  あわせて SEGGER J-Link ランタイム（JLinkARM DLL）も必要です（未導入だと" >&2; \
		echo "  'JLinkARM DLL not found' で書き込みに失敗します）。下記から入手してください:" >&2; \
		echo "    https://www.segger.com/downloads/jlink/" >&2; \
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
#   Open Bootloader 経由の DFU を用いる。手順は 2 段:
#     1) hex を署名付き DFU パッケージ(zip)へ変換（pkg generate）
#     2) zip をブートローダへシリアル転送（dfu usb-serial）
#   いずれも新 unified nrfutil の `nrf5sdk-tools` コマンドが提供する。
#   旧 pc-nrfutil の `nrfutil pkg` / `nrfutil dfu` は新 nrfutil 本体に無い（→ DL-5）。
#   ドングルは RESET ボタンで Open Bootloader(LED 赤点滅)にし /dev/tty.usbmodem* で接続する。
#   同一ファームウェアの再書き込みは結果を変えない（実質冪等）
# ============================================================
flash-sniffer-dongle: install-sniffer ## ドングルへ Sniffer FW を書き込み（要ドングル）
	@echo "==> flash-sniffer-dongle: ドングルへ Sniffer FW を書き込みます"
	@hex="$$(ls $(SNIFFER_HEX) 2>/dev/null | head -n1 || true)"; \
	if [ -z "$$hex" ]; then \
		echo "ERROR(flash-sniffer-dongle): Sniffer hex が見つかりません: $(SNIFFER_HEX)" >&2; \
		echo "  nRF Sniffer for Bluetooth LE 配布物（zip）が未展開か、SNIFFER_PKG_DIR が誤っています。" >&2; \
		echo "  対処:" >&2; \
		echo "    1) ダウンロード: https://www.nordicsemi.com/Products/Development-tools/nRF-Sniffer-for-Bluetooth-LE" >&2; \
		echo "    2) zip を展開し、その中身を SNIFFER_PKG_DIR に配置（既定: $(SNIFFER_PKG_DIR)）" >&2; \
		echo "       → 展開後に $(SNIFFER_PKG_DIR)/hex/*.hex が存在する状態にする" >&2; \
		echo "    3) 別パスに置いた場合は 'make flash-sniffer-dongle SNIFFER_PKG_DIR=/path/to/extracted' で指定" >&2; \
		echo "  導入手順: https://docs.nordicsemi.com/bundle/nrfutil/page/nrfutil-ble-sniffer/guides/installing_nrf_sniffer.html" >&2; \
		exit 1; \
	fi; \
	port="$(SERIAL_PORT)"; \
	if [ -z "$$port" ]; then \
		found="$$(ls /dev/tty.usbmodem* 2>/dev/null || true)"; \
		n="$$(printf '%s\n' $$found | grep -c . || true)"; \
		if [ "$$n" -eq 0 ]; then \
			echo "ERROR(flash-sniffer-dongle): ドングルのシリアルポートが検出できません。" >&2; \
			echo "  RESET ボタンで Open Bootloader(LED 赤点滅)にして接続するか、SERIAL_PORT= を明示してください。" >&2; \
			exit 1; \
		elif [ "$$n" -gt 1 ]; then \
			echo "ERROR(flash-sniffer-dongle): シリアルポートが複数検出されました。SERIAL_PORT= を明示してください:" >&2; \
			printf '    %s\n' $$found >&2; \
			exit 1; \
		fi; \
		port="$$found"; \
	fi; \
	echo "    対象ポート: $$port / hex: $$hex"; \
	mkdir -p "$(BUILD_DIR)"; \
	zip="$(BUILD_DIR)/sniffer_dfu.zip"; \
	rm -f "$$zip"; \
	nrfutil nrf5sdk-tools pkg generate --hw-version 52 --sd-req 0x00 \
		--application "$$hex" --application-version 1 "$$zip"; \
	nrfutil nrf5sdk-tools dfu usb-serial -pkg "$$zip" -p "$$port"
	@echo "==> flash-sniffer-dongle: 完了"

# ============================================================
# deploy : 実機へファームウェアを書き込む（要 DK＋ドングル接続）
#   書き込み（副作用あり）のみを担う。検証は読み取り専用の `verify` に分離し、
#   deploy には含めない（書き込みと検証で関心を分離する → DL-9）。
#   非並列 make では prerequisite が左→右順に実行されるため、
#   flash-dk → flash-sniffer-dongle の順に走る。
#   検証まで一括で行いたい場合は `make deploy verify` と並べて指定する。
# ============================================================
deploy: flash-dk flash-sniffer-dongle ## 実機へファームウェアを書き込む（要 DK＋ドングル接続。検証は make verify）
	@echo ""
	@echo "==> deploy 完了: 実機への書き込みを実行しました。検証は 'make verify' で行ってください。"

# ============================================================
# verify : 構築結果を検査（読み取り専用 / 状態を変更しない）
#   - DK が BLE Peripheral として広告しているか
#   - Wireshark に Sniffer インタフェースが出現しているか
#   フラッシュ済みを前提とする読み取り専用検査。書き込みは deploy が行う（→ DL-9）。
# ============================================================
verify: ## 実機へ書き込み(確認の上)→広告/Sniffer インタフェースを検査
	@# 書き込みは副作用のため [y/N] 確認を取り、y のときだけ deploy(書き込み)を実行する。
	@# 確認をフラッシュ前に出す必要があるため make 依存ではなくレシピ内でサブ実行する。
	@# 再帰に MAKE 変数ではなく literal `make` を使うのは、MAKE 変数を含む行が
	@# `make -n`(dry-run) でも実行され、確認プロンプトが誤って出てしまうのを避けるため。
	@printf "実機へファームウェアの書き込み（flash-dk / flash-sniffer-dongle）が行われます。問題ないですか？ [y/N]: "; \
	read -r ans </dev/tty 2>/dev/null || ans=""; \
	if [ "$$ans" = "y" ] || [ "$$ans" = "Y" ]; then \
		echo "==> 書き込みを実行します (make deploy)"; \
		make deploy; \
	else \
		echo "==> 書き込みをスキップし、現在の状態を検査します（書き込みは make deploy で）"; \
	fi
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
.PHONY: help setup deploy check-os install-nrfutil install-tools install-sniffer fetch-ncs build-firmware \
        flash-dk flash-sniffer-dongle verify clean
