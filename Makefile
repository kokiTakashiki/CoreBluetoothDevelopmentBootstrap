# ============================================================
# Core Bluetooth（BLE）検証環境 Makefile — 基盤（setup）
#
#   make setup   検証環境の基盤を組み上げる（実機不要・冪等）
#
# nRF ハード固有の工程は submodule external/nrf52840-ble-debug-bootstrap へ委譲する。
# 実機をつないで使う各コマンド（flash-blinky / flash-peripheral / capture / open-central）は
# 後続の PR で追加する。設計の詳細は docs/DESIGN-001.md を参照。
# 対象ホスト: Apple Silicon Mac。Xcode ビルド / iOS 実機署名は人手（対象外）。
# ============================================================

SHELL := /bin/bash

# --- submodule（nRF52840 製 BLE デバッグ環境） ---------------
SUBMODULE_DIR ?= external/nrf52840-ble-debug-bootstrap

# --- blinky を submodule の build へ変数上書きで流す（DESIGN-001 D-5） ---
# submodule を無改変のまま blinky（Zephyr 標準サンプル）をビルドし、成果物は
# submodule の外（このリポジトリの build/）へ出す。peripheral_uart は submodule の既定で扱う。
NCS_VERSION      ?= v2.6.1
NCS_BASE         ?= $(HOME)/ncs/$(NCS_VERSION)
BLINKY_SAMPLE    ?= $(NCS_BASE)/zephyr/samples/basic/blinky
BLINKY_BUILD_DIR ?= $(CURDIR)/build/blinky

# ============================================================
# 既定ゴール: help
# ============================================================
.DEFAULT_GOAL := help

help: ## このヘルプ（ターゲット一覧）を表示
	@echo "Core Bluetooth（BLE）検証環境"
	@echo ""
	@echo "  まず make setup で検証環境の基盤を組み上げる"
	@echo ""
	@grep -E '^[a-zA-Z][a-zA-Z0-9_-]*:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ============================================================
# 構築（実機不要・冪等。実機書き込みや GUI 起動は含めない）
#   setup は submodule の冪等な工程へ委譲する:
#     - ツール導入＋NCS 取得＋peripheral_uart ビルド（submodule の setup）
#     - blinky ビルド（変数上書きで親 build/ へ）
#     - Sniffer extcap 配置（submodule の install-sniffer）
# ============================================================
init: ## submodule を取得・更新
	@git submodule update --init --recursive
	@echo "==> init: submodule 準備完了 ($(SUBMODULE_DIR))"

setup: init ## 検証環境の基盤を組み上げる（実機不要・冪等）
	@echo "==> setup: 検証環境の基盤を組み上げます（実機不要・再実行は冪等）"
	@echo "--> [1/3] ツール導入＋NCS 取得＋peripheral_uart ビルド"
	$(MAKE) -C $(SUBMODULE_DIR) setup
	@echo "--> [2/3] blinky ビルド"
	$(MAKE) -C $(SUBMODULE_DIR) build-firmware SAMPLE_DIR='$(BLINKY_SAMPLE)' BUILD_DIR='$(BLINKY_BUILD_DIR)'
	@echo "--> [3/3] Sniffer extcap 配置"
	$(MAKE) -C $(SUBMODULE_DIR) install-sniffer
	@echo ""
	@echo "==> setup 完了（基盤）。実機をつないで使うコマンドは後続の PR で追加されます。"

clean: ## ビルド成果物を削除
	-@$(MAKE) -C $(SUBMODULE_DIR) clean
	@rm -rf "$(CURDIR)/build"
	@echo "==> clean: 完了"

.PHONY: help init setup clean
