# ============================================================
# Core Bluetooth（BLE）検証環境 Makefile
#
#   make setup            検証環境の基盤を組み上げる（実機不要・冪等）
#   make flash-blinky     ① 開発キット: blinky を焼いて LED 点滅を見る
#   make flash-peripheral ① 開発キット: peripheral_uart を焼き、続けて往復を対話検査
#   make capture          ② アナライザ: ドングルに Sniffer を焼き Wireshark で観測
#
# nRF ハード固有の工程は submodule external/nrf52840-ble-debug-bootstrap へ委譲する。
# 残りの各コマンド（open-central）は後続の PR で追加する。
# 設計の詳細は docs/DESIGN-001.md を参照。
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
	@echo "==> setup 完了。実機をつないで make flash-blinky を試せます。"

# ============================================================
# 確認（setup 後、実機をつないで試す）
# ============================================================
flash-blinky: init ## ① 開発キット: blinky を焼いて LED 点滅を見る（消灯→点滅で差分を確認）
	@echo "==> flash-blinky: 実行前後で LED 差分が出るよう、消灯させてから書き込みます"
	@# ① blinky を先にビルド（消去〜書込の間を短く保ち、消灯の観測窓を予測可能にする）
	$(MAKE) -C $(SUBMODULE_DIR) build-firmware SAMPLE_DIR='$(BLINKY_SAMPLE)' BUILD_DIR='$(BLINKY_BUILD_DIR)'
	@# ② baseline: 全消去で全 LED を消灯させる（既に点滅中でも無地に揃う）
	$(MAKE) -C $(SUBMODULE_DIR) erase-dk
	@# ③ 消灯を目視確認させる一時停止（対話端末のときだけ。非対話/CI では止めず進む）
	@if [ -t 0 ]; then \
		printf '    >>> DK の全 LED が消灯したのを確認したら Enter を押してください（blinky を書き込みます）... '; \
		read _ ; \
	else \
		echo "    [非対話] 消灯確認の一時停止をスキップして書き込みます"; \
	fi
	@# ④ blinky 書き込み → LED1 が点滅し始める（消灯からの OFF→ON が観測可能な差分）
	$(MAKE) -C $(SUBMODULE_DIR) flash-dk SAMPLE_DIR='$(BLINKY_SAMPLE)' BUILD_DIR='$(BLINKY_BUILD_DIR)'
	@echo "    検証: 消灯状態から LED1 が点滅に変われば OK です。"

flash-peripheral: init ## ① 開発キット: peripheral_uart を焼き、続けて往復を対話検査
	@echo "==> flash-peripheral: peripheral_uart を書き込みます"
	$(MAKE) -C $(SUBMODULE_DIR) flash-dk
	@echo "    peripheral_uart は BLE(NUS) と DK のシリアルを橋渡しするだけです。続けて往復を検査します。"
	@bash "$(CURDIR)/scripts/verify-peripheral.sh" "$(SUBMODULE_DIR)"

verify-peripheral: init ## ① 開発キット: peripheral_uart の往復(上り/下り)だけを対話検査
	@bash "$(CURDIR)/scripts/verify-peripheral.sh" "$(SUBMODULE_DIR)"

capture: init ## ② アナライザ: ドングルに Sniffer を焼き Wireshark で DK↔iPhone を観測
	@echo "==> capture: ドングルへ Sniffer FW を書き込みます（Open Bootloader 確認あり）"
	$(MAKE) -C $(SUBMODULE_DIR) flash-sniffer-dongle
	@echo "==> 前提を自動確認します: DK が peripheral_uart で起動しているか（DK をリセットします）"
	-@$(MAKE) --no-print-directory -C $(SUBMODULE_DIR) uart-fwcheck
	@echo "==> Wireshark を起動します。次の手順で DK↔iPhone の各フェーズを観測してください:"
	@echo ""
	@echo "  1) インターフェイス 'nRF Sniffer for Bluetooth LE' をダブルクリックして捕捉を開始。"
	@echo ""
	@echo "  2) Sniffer ツールバーを表示: メニュー View > Interface Toolbars > nRF Sniffer。"
	@echo ""
	@echo "  3) DK を広告状態にする: iPhone 側を Disconnect にする。Wireshark のフィルタに"
	@echo "     frame contains \"Nordic_UART_Service\"  を入れて、行が出れば広告中であることを確認できる。"
	@echo ""
	@echo "  4) ツールバーの Device で 'Nordic_UART_Service' を選択する。"
	@echo ""
	@echo "  5) iPhone の nRF Connect で 'Nordic_UART_Service' に Connect する。"
	@echo ""
	@echo "  6) 直後の Wireshark の一覧は 'Empty PDU' で埋まる。"
	@echo ""
	@echo "  7) Wireshark のフィルタ欄で  btatt  と打って Enter を押す。Empty PDU が消え、ATT だけが残る。"
	@echo ""
	@echo "  8) Wireshark の Info 列を上から読む。"
	@echo "       MTU 交渉の確認"
	@echo "         - 'Exchange MTU Request/Response'        … と記載があれば確認完了"
	@echo "       サービス探索の確認"
	@echo "         - 'Read By Group Type Request/Response'  … と記載があれば確認完了"
	@echo "       特性・Descriptor の探索の確認"
	@echo "         - 'Read By Type' / 'Find Information'     … と記載があれば確認完了"
	@echo ""
	@echo "  『観測手段の確立』は完了です。"
	@echo ""
	@echo "  9)（任意）iPhone で 'Nordic UART Rx' に hello を Write すると、Wireshark の一覧に"
	@echo "     'Sent Write Request' が出る。その行を選び、詳細ペインの 'Bluetooth Attribute Protocol'"
	@echo "     を展開すると 'Value' に送ったバイト列（hello = 68 65 6c 6c 6f）が見える。"
	@echo ""
	@echo "  うまくいかない時（Sniffer が一覧に出ない / Device に DK が出ない 等）は"
	@echo "  docs/TROUBLESHOOTING.md の 'make capture' の節を参照してください。"
	@open -a Wireshark 2>/dev/null || echo "    （Wireshark を手動で起動してください）"

clean: ## ビルド成果物を削除
	-@$(MAKE) -C $(SUBMODULE_DIR) clean
	@rm -rf "$(CURDIR)/build"
	@echo "==> clean: 完了"

.PHONY: help init setup flash-blinky flash-peripheral verify-peripheral capture clean
