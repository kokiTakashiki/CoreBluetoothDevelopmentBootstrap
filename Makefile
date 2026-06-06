# ============================================================
# Core Bluetooth（BLE）Central 教材アプリ — Makefile
#
#   make open-central      Xcode プロジェクトを生成して開く
#   make generate-central  project.yml から .xcodeproj を生成（Mint 固定 XcodeGen）
#   make format            Swift を整形（Mint 固定 SwiftFormat）
#   make format-check      整形を検査（未整形なら失敗）
#   make clean             生成物（.xcodeproj / Info.plist）を削除
#
# 雛形は iOSAppTemplate(Genesis) で一度生成したものを固定。実行時に iOSAppTemplate へ
# 依存しない。project.yml ＋ Swift ソースが source of truth で、.xcodeproj は生成物（.gitignore）。
# Apple のビルド・署名・実行は Make の対象外（Xcode で行う）。対象ホスト: Apple Silicon Mac。
# ============================================================

SHELL := /bin/bash

# Central の Xcode プロジェクト。
CENTRAL_DIR ?= central
APP_NAME    ?= CoreBluetoothCentralGuide

.DEFAULT_GOAL := help

help: ## このヘルプ（ターゲット一覧）を表示
	@echo "Core Bluetooth（BLE）Central 教材アプリ"
	@echo ""
	@grep -E '^[a-zA-Z][a-zA-Z0-9_-]*:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

generate-central: ## Central の .xcodeproj を生成（Mintfile 固定の XcodeGen）
	@command -v mint >/dev/null 2>&1 || brew install mint
	@echo "==> generate-central: Mintfile 固定の XcodeGen で .xcodeproj を生成します"
	@( cd "$(CENTRAL_DIR)/$(APP_NAME)" && mint run yonaskolb/XcodeGen xcodegen generate )
	@echo "==> generate-central: 完了 ($(CENTRAL_DIR)/$(APP_NAME))"

open-central: generate-central ## Central: Xcode プロジェクトを生成して開く
	@proj="$$(ls -d $(CENTRAL_DIR)/$(APP_NAME)/*.xcworkspace $(CENTRAL_DIR)/$(APP_NAME)/*.xcodeproj 2>/dev/null | head -n1 || true)"; \
	if [ -z "$$proj" ]; then \
		echo "ERROR(open-central): Xcode プロジェクトが見つかりません（generate-central に失敗）。" >&2; \
		exit 1; \
	fi; \
	echo "==> open-central: $$proj を開きます"; \
	echo "    Central 実装（CentralViewController）で、peripheral_uart 搭載の DK へ"; \
	echo "    scan→connect→discoverServices→discoverCharacteristics→setNotifyValue/writeValue を実行してください。"; \
	open "$$proj"

format: ## Central の Swift を整形（Mintfile 固定の SwiftFormat）
	@command -v mint >/dev/null 2>&1 || brew install mint
	@echo "==> format: SwiftFormat で整形します"
	@( cd "$(CENTRAL_DIR)/$(APP_NAME)" && mint run nicklockwood/SwiftFormat swiftformat . )
	@echo "==> format: 完了"

format-check: ## Central の Swift 整形を検査（未整形なら失敗）
	@command -v mint >/dev/null 2>&1 || brew install mint
	@( cd "$(CENTRAL_DIR)/$(APP_NAME)" && mint run nicklockwood/SwiftFormat swiftformat --lint . )

clean: ## 生成物（.xcodeproj / Info.plist）を削除
	@rm -rf "$(CENTRAL_DIR)/$(APP_NAME)/$(APP_NAME).xcodeproj" \
	        "$(CENTRAL_DIR)/$(APP_NAME)/$(APP_NAME)/Info.plist"
	@echo "==> clean: 完了"

.PHONY: help generate-central open-central format format-check clean
