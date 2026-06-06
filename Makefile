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

# --- blinky を submodule の build/flash へ変数上書きで流す（DESIGN-001 D-5） ---
# submodule の Makefile の SAMPLE_DIR / BUILD_DIR を上書きするだけで、submodule を
# 無改変のまま blinky（Zephyr 標準サンプル）をビルド・書き込みできる。成果物は
# submodule の外（このリポジトリの build/）へ出し汚さない。peripheral_uart は submodule の既定で扱う。
NCS_VERSION      ?= v2.6.1
NCS_BASE         ?= $(HOME)/ncs/$(NCS_VERSION)
BLINKY_SAMPLE    ?= $(NCS_BASE)/zephyr/samples/basic/blinky
BLINKY_BUILD_DIR ?= $(CURDIR)/build/blinky

# --- Central の Xcode プロジェクト（同梱 project.yml を xcodegen で生成。D-7） ---
# project.yml と Swift ソースはこのリポジトリに固定。実行時に iOSAppTemplate へ
# 依存しない（テンプレの破壊的変更の影響を受けない）。.xcodeproj は生成物。
CENTRAL_DIR ?= central
APP_NAME    ?= CoreBluetoothCentralGuide

# ============================================================
# 既定ゴール: help
# ============================================================
.DEFAULT_GOAL := help

help: ## このヘルプ（ターゲット一覧）を表示
	@echo "Core Bluetooth（BLE）検証環境"
	@echo ""
	@echo "  1. まず make setup で検証に必要なものを全部用意する"
	@echo "  2. 実機をつないで、下のコマンドで確認したいものを順不同・何度でも試す"
	@echo ""
	@grep -E '^[a-zA-Z][a-zA-Z0-9_-]*:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ============================================================
# 構築
#   setup が 3 つの検証環境を全部組み上げる:
#     - ツール導入＋NCS 取得＋peripheral_uart ビルド（submodule の setup）
#     - blinky ビルド
#     - Sniffer extcap 配置（submodule の install-sniffer）
#     - Xcode Central プロジェクト生成（generate-central）
#   実機書き込みと GUI 起動は一切含めない（それは確認コマンド側）。
# ============================================================
init: ## submodule を取得・更新
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
	@echo "--> [4/4] Xcode Central プロジェクト生成（xcodegen）"
	@$(MAKE) --no-print-directory generate-central
	@echo ""
	@echo "==> setup 完了。実機をつないで以下を試せます:"
	@echo "    make flash-blinky / make flash-peripheral / make capture / make open-central"

# Central アプリの project.yml と Swift ソースはこのリポジトリに同梱。
# ツール（XcodeGen / SwiftFormat）は同梱 Mintfile で SHA 固定し Mint で実行する。
# iOSAppTemplate へは実行時依存しない（D-7）。
generate-central: ## Central の .xcodeproj を生成（Mintfile 固定の XcodeGen）
	@command -v mint >/dev/null 2>&1 || brew install mint
	@echo "==> generate-central: Mintfile 固定の XcodeGen で .xcodeproj を生成します"
	@( cd "$(CENTRAL_DIR)/$(APP_NAME)" && mint run yonaskolb/XcodeGen xcodegen generate )
	@echo "==> generate-central: 完了 ($(CENTRAL_DIR)/$(APP_NAME))"

format: ## Central の Swift を整形（Mintfile 固定の SwiftFormat）
	@command -v mint >/dev/null 2>&1 || brew install mint
	@echo "==> format: SwiftFormat で整形します"
	@( cd "$(CENTRAL_DIR)/$(APP_NAME)" && mint run nicklockwood/SwiftFormat swiftformat . )
	@echo "==> format: 完了"

format-check: ## Central の Swift 整形を検査（未整形なら失敗）
	@command -v mint >/dev/null 2>&1 || brew install mint
	@( cd "$(CENTRAL_DIR)/$(APP_NAME)" && mint run nicklockwood/SwiftFormat swiftformat --lint . )

# ============================================================
# 確認（setup 後、実機をつないで試す）
#   各コマンドは「焼く／開く」という実機・GUI の動作だけを担う。ビルドは
#   setup 済みのため速い（未 setup でも submodule の依存が必要分だけ補う）。
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
	@echo "==> Wireshark を起動します。次の手順で DK↔iPhone の各フェーズを観測してください:"
	@echo ""
	@echo "  前提) DK は peripheral_uart が動いていること（未/別ファームなら make flash-peripheral）。"
	@echo "        ※ DK が blinky 等だと NUS を広告せず、何も観測できません。"
	@echo "  1) インターフェイス 'nRF Sniffer for Bluetooth LE' をダブルクリックして捕捉を開始。"
	@echo "  2) Sniffer ツールバーを表示: メニュー View > Interface Toolbars > nRF Sniffer。"
	@echo "  3) DK を広告状態にする: iPhone 側を一旦 Disconnect（接続中だと DK は広告を止める）。"
	@echo "     表示フィルタに  frame contains \"Nordic_UART_Service\"  を入れて、行が出れば広告中。"
	@echo "     （Source 列のアドレスがその DK。Adv Hop は 37,38,39 にしておくと取りこぼしにくい）"
	@echo "  4) ツールバーの Device で 'Nordic_UART_Service' を選択（その DK だけを追跡する）。"
	@echo "  5) iPhone の nRF Connect で 'Nordic_UART_Service' に Connect。一覧に順に並ぶ:"
	@echo "       Advertise(ADV_IND) → Connect(CONNECT_IND) → MTU/Data Length 交渉(LL_LENGTH/ATT MTU)"
	@echo "       → GATT Discovery(ATT Read By Group Type / Read By Type)。"
	@echo "     表示フィルタを  btatt  にすると GATT のやり取りだけに絞れる。"
	@echo "  これら 4 フェーズが並べば『観測手段の確立』は完了です。"
	@open -a Wireshark 2>/dev/null || echo "    （Wireshark を手動で起動してください）"

open-central: generate-central ## ③ Central: Xcode プロジェクトを開いてアプリを動かす
	@proj="$$(ls -d $(CENTRAL_DIR)/$(APP_NAME)/*.xcworkspace $(CENTRAL_DIR)/$(APP_NAME)/*.xcodeproj 2>/dev/null | head -n1 || true)"; \
	if [ -z "$$proj" ]; then \
		echo "ERROR(open-central): Xcode プロジェクトが見つかりません（generate-central に失敗）。" >&2; \
		exit 1; \
	fi; \
	echo "==> open-central: $$proj を開きます"; \
	echo "    同梱の Central 実装（CentralViewController）で、Phase 1 の DK へ"; \
	echo "    scan→connect→discoverServices→discoverCharacteristics→readValue/setNotifyValue を実行してください。"; \
	open "$$proj"

# ============================================================
# 検査 / 後始末
# ============================================================
verify: init ## 機械検査（submodule へ委譲 / 読み取り専用＋[y/N]書込確認）
	$(MAKE) -C $(SUBMODULE_DIR) verify

clean: ## ビルド成果物・生成物を削除（追跡対象の central ソースは残す）
	-@$(MAKE) -C $(SUBMODULE_DIR) clean
	@rm -rf "$(CURDIR)/build"
	@rm -rf "$(CENTRAL_DIR)/$(APP_NAME)/$(APP_NAME).xcodeproj" \
	        "$(CENTRAL_DIR)/$(APP_NAME)/$(APP_NAME)/Info.plist"
	@echo "==> clean: 完了"

.PHONY: help init setup generate-central format format-check flash-blinky flash-peripheral \
        verify-peripheral capture open-central verify clean
