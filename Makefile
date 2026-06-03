# ============================================================
# Core Bluetooth（BLE）検証環境 オーケストレータ Makefile
#
# DESIGN-001（docs/DESIGN-001.md）に基づく 3 フェーズの自動化レイヤ。
#   Phase 1: 開発キット単体の動作確認（DUT を確定）
#   Phase 2: プロトコルアナライザ運用の確立（観測手段を確定）
#   Phase 3: Xcode で Central 最小実装（検証主体を確定）
#
# nRF ハード固有の工程（NCS 導入 / FW ビルド / 書き込み / Sniffer）は
# submodule external/nrf52840-ble-debug-bootstrap へ委譲する。本 Makefile は
# 「フェーズ」の語彙を被せ、子の冪等性・関心分離をそのまま継承する（D-8）。
#
# 対象ホスト: Apple Silicon Mac。Xcode ビルド / iOS 実機署名は人手（D-6）。
# ============================================================

SHELL := /bin/bash

# --- submodule（nRF52840 製 BLE デバッグ環境） ---------------
SUBMODULE_DIR ?= external/nrf52840-ble-debug-bootstrap

# --- Phase 1: blinky を子の flash-dk へ変数上書きで流す（D-5） ---
# 子 Makefile の SAMPLE_DIR / BUILD_DIR を上書きするだけで、子を無改変のまま
# blinky（Zephyr 標準サンプル）をビルド・書き込みできる。ビルド成果物は
# submodule の外（親の build/）へ出し、submodule を汚さない。
NCS_VERSION      ?= v2.6.1
NCS_BASE         ?= $(HOME)/ncs/$(NCS_VERSION)
BLINKY_SAMPLE    ?= $(NCS_BASE)/zephyr/samples/basic/blinky
BLINKY_BUILD_DIR ?= $(CURDIR)/build/blinky

# --- Phase 3: Central の足場（iOSAppTemplate を展開して履歴を切離。D-7） ---
CENTRAL_DIR  ?= central
APP_NAME     ?= BLECentralSample
TEMPLATE_URL ?= https://github.com/koki-mobile-studio/iOSAppTemplate.git

# ============================================================
# 既定ゴール: help（副作用なし）。導入・書き込みは明示ターゲットに限定する。
# ============================================================
.DEFAULT_GOAL := help

help: ## このヘルプ（ターゲット一覧）を表示
	@echo "Core Bluetooth（BLE）検証環境 — 3 フェーズ・オーケストレータ"
	@echo "使い方: make <target>  (例: make setup && make phase1)"
	@echo ""
	@echo "ターゲット:"
	@grep -E '^[a-zA-Z][a-zA-Z0-9_-]*:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

init: ## submodule（子）を取得・更新
	@git submodule update --init --recursive
	@echo "==> init: submodule 準備完了 ($(SUBMODULE_DIR))"

setup: init ## ソフトウェア環境構築（実機不要 / 子へ委譲）
	@echo "==> setup: 子の setup（NCS 導入＋ peripheral_uart ビルド）を実行します"
	$(MAKE) -C $(SUBMODULE_DIR) setup

# ============================================================
# Phase 1: 開発キット単体の動作確認
#   blinky を書き込み LED 点滅を確認 → peripheral_uart を書き込み。
#   blinky の確認を取れるよう、2 つの書き込みの間に人手確認の一時停止を挟む
#   （非対話時は自動でスキップ）。
# ============================================================
phase1: init ## Phase 1: 開発キット単体（blinky→確認→peripheral_uart）
	@echo "==> Phase 1: 開発キット単体の動作確認"
	@echo "--> [1/2] blinky を書き込みます（Nordic Getting Started）"
	$(MAKE) -C $(SUBMODULE_DIR) flash-dk SAMPLE_DIR='$(BLINKY_SAMPLE)' BUILD_DIR='$(BLINKY_BUILD_DIR)'
	@printf "DK の LED1 が点滅していることを確認してください。確認できたら Enter（中止は Ctrl-C）: "; \
		read -r _ </dev/tty 2>/dev/null || echo "（非対話: 確認をスキップして続行）"
	@echo "--> [2/2] peripheral_uart を書き込みます"
	$(MAKE) -C $(SUBMODULE_DIR) flash-dk
	@echo ""
	@echo "次の人手確認で Phase 1 を完了とします:"
	@echo "  - iPhone の nRF Connect for Mobile から 'Nordic_UART_Service'(NUS) へ接続"
	@echo "  - RX/TX で文字列が往復することを確認"

flash-blinky: init ## blinky のみ書き込み（LED 点滅確認用）
	$(MAKE) -C $(SUBMODULE_DIR) flash-dk SAMPLE_DIR='$(BLINKY_SAMPLE)' BUILD_DIR='$(BLINKY_BUILD_DIR)'

flash-peripheral: init ## peripheral_uart のみ書き込み
	$(MAKE) -C $(SUBMODULE_DIR) flash-dk

# ============================================================
# Phase 2: プロトコルアナライザ運用の確立
#   Sniffer extcap を配置し、ドングルへ Sniffer FW を書き込む。
#   ドングルの Open Bootloader 確認（[y/N]）は子の flash-sniffer-dongle が行う。
# ============================================================
phase2: init ## Phase 2: プロトコルアナライザ運用（Sniffer extcap＋FW）
	@echo "==> Phase 2: プロトコルアナライザ運用の確立"
	@echo "--> extcap プラグインを配置します"
	$(MAKE) -C $(SUBMODULE_DIR) install-sniffer
	@echo "--> ドングルへ Sniffer FW を書き込みます（Open Bootloader 確認あり）"
	$(MAKE) -C $(SUBMODULE_DIR) flash-sniffer-dongle
	@echo ""
	@echo "次の人手確認で Phase 2 を完了とします:"
	@echo "  - Wireshark のインタフェース一覧に 'nRF Sniffer for Bluetooth LE' が出現"
	@echo "  - DK↔iPhone 通信で Advertise → Connect → MTU 交渉 → GATT Discovery を観測"

# ============================================================
# Phase 3: Xcode で Central 最小実装
#   足場の生成（iOSAppTemplate 展開＋履歴切離）までを自動化し、Xcode での
#   実装・ビルド・実行は人手（D-6）。
# ============================================================
phase3: scaffold-central ## Phase 3: Xcode Central（足場生成＋手順案内）
	@echo "==> Phase 3: Xcode で Central 最小実装"
	@echo "足場     : $(CENTRAL_DIR)/$(APP_NAME)（iOSAppTemplate 由来 / git 履歴は切離済み）"
	@echo "参照実装 : $(CENTRAL_DIR)/reference/BLECentral.swift"
	@echo ""
	@echo "手順（人手）:"
	@echo "  1. $(CENTRAL_DIR)/$(APP_NAME) を Xcode で開く"
	@echo "  2. reference/BLECentral.swift を組み込み、CBCentralManager を実装"
	@echo "  3. scan→connect→discoverServices→discoverCharacteristics→readValue/setNotifyValue を実行"
	@echo "  4. 接続先は Phase 1 の peripheral_uart 搭載 DK。同じ通信を Wireshark でも観測"

scaffold-central: init ## Central の足場を生成（iOSAppTemplate 展開＋履歴切離）
	@if [ -d "$(CENTRAL_DIR)/$(APP_NAME)" ]; then \
		echo "    [skip] 足場は既にあります: $(CENTRAL_DIR)/$(APP_NAME)"; \
	else \
		echo "    [scaffold] $(TEMPLATE_URL) を $(CENTRAL_DIR)/$(APP_NAME) へ展開します"; \
		if git clone --depth 1 "$(TEMPLATE_URL)" "$(CENTRAL_DIR)/$(APP_NAME)"; then \
			rm -rf "$(CENTRAL_DIR)/$(APP_NAME)/.git"; \
			echo "    [done] git 履歴を切り離しました（degit 相当）。reference/ を組み込んでください。"; \
		else \
			echo "ERROR(scaffold-central): テンプレートの取得に失敗しました: $(TEMPLATE_URL)" >&2; \
			echo "  手動で $(CENTRAL_DIR)/$(APP_NAME) に新規 Xcode プロジェクトを用意してください。" >&2; \
			exit 1; \
		fi; \
	fi

# ============================================================
# 検査 / 後始末
# ============================================================
verify: init ## 実機検査（子へ委譲 / 読み取り専用＋[y/N]書込確認）
	$(MAKE) -C $(SUBMODULE_DIR) verify

clean: ## ビルド成果物を削除（子のビルド＋blinky ビルド）
	-@$(MAKE) -C $(SUBMODULE_DIR) clean
	@rm -rf "$(CURDIR)/build"
	@echo "==> clean: 完了"

.PHONY: help init setup phase1 flash-blinky flash-peripheral phase2 phase3 \
        scaffold-central verify clean
