# ============================================================
# Core Bluetooth（BLE）検証環境 Makefile
#
#
#   準備
#     make setup            検証に必要なものを全部用意する
#
#   この環境でできること
#     make flash-blinky     ① 開発キット: blinky を焼いて LED 点滅を見る
#     make flash-peripheral ① 開発キット: peripheral_uart を焼く（nRF Connect で往復）
#     make capture          ② アナライザ: ドングルに Sniffer を焼き Wireshark でキャプチャ
#     make open-central     ③ Central: Xcode プロジェクトを開いてアプリを動かす
#
# nRF ハード固有の工程は submodule external/nrf52840-ble-debug-bootstrap へ委譲する。
# 設計の詳細は docs/DESIGN-001.mdを参照。
#
# 対象ホスト: Apple Silicon Mac。Xcode ビルド / iOS 実機署名は人手（対象外）。
# ============================================================

SHELL := /bin/bash

# --- submodule（nRF52840 製 BLE デバッグ環境） ---------------
SUBMODULE_DIR ?= external/nrf52840-ble-debug-bootstrap

# --- blinky を子の build/flash へ変数上書きで流す（DESIGN-001 D-5） ---
# 子 Makefile の SAMPLE_DIR / BUILD_DIR を上書きするだけで、子を無改変のまま
# blinky（Zephyr 標準サンプル）をビルド・書き込みできる。成果物は submodule の
# 外（親の build/）へ出し submodule を汚さない。peripheral_uart は子の既定で扱う。
NCS_VERSION      ?= v2.6.1
NCS_BASE         ?= $(HOME)/ncs/$(NCS_VERSION)
BLINKY_SAMPLE    ?= $(NCS_BASE)/zephyr/samples/basic/blinky
BLINKY_BUILD_DIR ?= $(CURDIR)/build/blinky

# --- Central の Xcode プロジェクト（iOSAppTemplate を展開し履歴を切離。D-7） ---
CENTRAL_DIR  ?= central
APP_NAME     ?= BLECentralSample
TEMPLATE_URL ?= https://github.com/koki-mobile-studio/iOSAppTemplate.git

# ============================================================
# 既定ゴール: help（副作用なし）
# ============================================================
.DEFAULT_GOAL := help

help: ## このヘルプ（ターゲット一覧）を表示
	@echo "Core Bluetooth（BLE）検証環境"
	@echo ""
	@echo "  1. まず make setup で検証に必要なものを全部用意する（実機/GUI 不要・冪等）"
	@echo "  2. 実機をつないで、下のコマンドで確認したいものを順不同・何度でも試す"
	@echo ""
	@grep -E '^[a-zA-Z][a-zA-Z0-9_-]*:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ============================================================
# 構築
#   setup が 3 つの検証環境を全部組み上げる:
#     - ツール導入＋NCS 取得＋peripheral_uart ビルド（子の setup）
#     - blinky ビルド
#     - Sniffer extcap 配置（子の install-sniffer）
#     - Xcode Central プロジェクト生成（generate-central）
#   実機書き込みと GUI 起動は一切含めない（それは確認コマンド側）。
# ============================================================
init: ## submodule（子）を取得・更新
	@git submodule update --init --recursive
	@echo "==> init: submodule 準備完了 ($(SUBMODULE_DIR))"

setup: init ## 3 つの検証環境を全部組み上げる
	@echo "==> setup: 3 つの検証環境を組み上げます（実機不要・再実行は冪等）"
	@echo "--> [1/4] ツール導入＋NCS 取得＋peripheral_uart ビルド"
	$(MAKE) -C $(SUBMODULE_DIR) setup
	@echo "--> [2/4] blinky ビルド"
	$(MAKE) -C $(SUBMODULE_DIR) build-firmware SAMPLE_DIR='$(BLINKY_SAMPLE)' BUILD_DIR='$(BLINKY_BUILD_DIR)'
	@echo "--> [3/4] Sniffer extcap 配置"
	$(MAKE) -C $(SUBMODULE_DIR) install-sniffer
	@echo "--> [4/4] Xcode Central プロジェクト生成（iOSAppTemplate）"
	@$(MAKE) --no-print-directory generate-central
	@echo ""
	@echo "==> setup 完了。実機をつないで以下を試せます:"
	@echo "    make flash-blinky / make flash-peripheral / make capture / make open-central"

# Central アプリは iOSAppTemplate(Genesis) で実装フェーズに生成する。
# リポジトリが追跡するのは生成オプション(central-options.yml)と注入する
# BLECentral.swift だけで、生成物（アプリ一式・.xcodeproj）は .gitignore（D-7）。
generate-central: init ## Central アプリを iOSAppTemplate(Genesis) で生成し xcodegen で .xcodeproj 化
	@echo "==> generate-central: iOSAppTemplate(Genesis) で Central アプリを生成します"
	@command -v mint >/dev/null 2>&1 || brew install mint
	@mint which yonaskolb/Genesis >/dev/null 2>&1 || mint install yonaskolb/Genesis
	@command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
	@if [ ! -d "$(CENTRAL_DIR)/.iOSAppTemplate" ]; then \
		echo "    [clone] $(TEMPLATE_URL)"; \
		git clone --depth 1 "$(TEMPLATE_URL)" "$(CENTRAL_DIR)/.iOSAppTemplate"; \
	fi
	@if [ -d "$(CENTRAL_DIR)/$(APP_NAME)" ]; then \
		echo "    [skip] $(CENTRAL_DIR)/$(APP_NAME) は生成済み（作り直すなら make clean 後）"; \
	else \
		echo "    [generate] Genesis → $(CENTRAL_DIR)/$(APP_NAME)"; \
		( cd "$(CENTRAL_DIR)/.iOSAppTemplate" && \
		  mint run yonaskolb/Genesis genesis generate genesis.yml \
		    --destination "$(CURDIR)/$(CENTRAL_DIR)" \
		    --option-path "$(CURDIR)/$(CENTRAL_DIR)/central-options.yml" \
		    --non-interactive ); \
		cp "$(CENTRAL_DIR)/BLECentral.swift" "$(CENTRAL_DIR)/$(APP_NAME)/$(APP_NAME)/BLECentral.swift"; \
		echo "    [inject] BLECentral.swift を生成アプリへ配置"; \
	fi
	@echo "    [xcodegen] .xcodeproj を生成"
	@( cd "$(CENTRAL_DIR)/$(APP_NAME)" && xcodegen generate )
	@echo "==> generate-central: 完了 ($(CENTRAL_DIR)/$(APP_NAME))"

# ============================================================
# 確認（setup 後、実機をつないで試す）
#   各コマンドは「焼く／開く」という実機・GUI の動作だけを担う。ビルドは
#   setup 済みのため速い（未 setup でも子の依存が必要分だけ補う）。
# ============================================================
flash-blinky: init ## ① 開発キット: blinky を焼いて LED 点滅を見る
	@echo "==> flash-blinky: blinky を書き込みます（DK の LED1 点滅を確認）"
	$(MAKE) -C $(SUBMODULE_DIR) flash-dk SAMPLE_DIR='$(BLINKY_SAMPLE)' BUILD_DIR='$(BLINKY_BUILD_DIR)'

flash-peripheral: init ## ① 開発キット: peripheral_uart を焼く（nRF Connect で往復）
	@echo "==> flash-peripheral: peripheral_uart を書き込みます"
	$(MAKE) -C $(SUBMODULE_DIR) flash-dk
	@echo "    iPhone の nRF Connect for Mobile から 'Nordic_UART_Service'(NUS) に接続し、"
	@echo "    RX/TX で文字列が往復することを確認してください。"

capture: init ## ② アナライザ: ドングルに Sniffer を焼き Wireshark でキャプチャ
	@echo "==> capture: ドングルへ Sniffer FW を書き込みます（Open Bootloader 確認あり）"
	$(MAKE) -C $(SUBMODULE_DIR) flash-sniffer-dongle
	@echo "==> Wireshark を起動します。'nRF Sniffer for Bluetooth LE' を選び、"
	@echo "    DK↔iPhone 通信で Advertise → Connect → MTU 交渉 → GATT Discovery を観測してください。"
	@open -a Wireshark 2>/dev/null || echo "    （Wireshark を手動で起動してください）"

open-central: generate-central ## ③ Central: Xcode プロジェクトを開いてアプリを動かす
	@proj="$$(ls -d $(CENTRAL_DIR)/$(APP_NAME)/*.xcworkspace $(CENTRAL_DIR)/$(APP_NAME)/*.xcodeproj 2>/dev/null | head -n1 || true)"; \
	if [ -z "$$proj" ]; then \
		echo "ERROR(open-central): Xcode プロジェクトが見つかりません（generate-central に失敗）。" >&2; \
		exit 1; \
	fi; \
	echo "==> open-central: $$proj を開きます"; \
	echo "    注入済み BLECentral.swift を使い、Phase 1 の DK へ"; \
	echo "    scan→connect→discoverServices→discoverCharacteristics→readValue/setNotifyValue を実行してください。"; \
	open "$$proj"

# ============================================================
# 検査 / 後始末
# ============================================================
verify: init ## 機械検査（子へ委譲 / 読み取り専用＋[y/N]書込確認）
	$(MAKE) -C $(SUBMODULE_DIR) verify

clean: ## ビルド成果物・生成物を削除（追跡対象の central ソースは残す）
	-@$(MAKE) -C $(SUBMODULE_DIR) clean
	@rm -rf "$(CURDIR)/build"
	@rm -rf "$(CENTRAL_DIR)/$(APP_NAME)" "$(CENTRAL_DIR)/.iOSAppTemplate"
	@echo "==> clean: 完了"

.PHONY: help init setup generate-central flash-blinky flash-peripheral \
        capture open-central verify clean
