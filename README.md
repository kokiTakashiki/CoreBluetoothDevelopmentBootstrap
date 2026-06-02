# CoreBluetoothDevelopmentBootstrap

Core Bluetooth 検証環境（nRF Connect SDK / Wireshark / nRF Sniffer）を **冪等な Makefile** で構築する個人用ブートストラップ。設計は [DESIGN-001](docs/DESIGN-001.md) に基づく（意思決定ログ含む）。

> 対象: Apple Silicon Mac。Xcode / iOS 実機署名の自動化は対象外。

## 使い方

```sh
make                      # 既定ゴール = help（ターゲット一覧を表示・副作用なし）
make setup                # 前提確認 → 導入 → ビルド → 検証 を一括実行
make check-os             # 実行環境の前提確認（arm64 / Homebrew）
make install-tools        # nrfutil / NCS Toolchain / west / Wireshark を導入
make install-sniffer      # nRF Sniffer の extcap プラグインを配置
make build-firmware       # peripheral_uart をビルド
make flash-dk             # 開発キットへ書き込み（要 DK 接続）
make flash-sniffer-dongle # ドングルへ Sniffer FW を書き込み（要ドングル）
make verify               # 広告 / Sniffer インタフェースの検査
make clean                # ビルド成果物を削除
```

主な変数（`make build-firmware BOARD=... NCS_VERSION=...` で上書き可）:

| 変数 | 既定値 | 用途 |
| --- | --- | --- |
| `NCS_VERSION` | `v2.6.1` | nRF Connect SDK のバージョン固定 |
| `BOARD` | `nrf52840dk_nrf52840` | ビルド対象ボード |
| `WIRESHARK_EXTCAP_DIR` | `~/.local/lib/wireshark/extcap` | extcap プラグイン配置先 |
| `SERIAL_PORT` | 自動検出 | 書き込み対象ポート（複数検出時はエラー） |

## 冪等性

各ターゲットは状態検査つきの冪等な単位として定義され、何度実行しても同一の最終状態へ収束する。
ハードウェア非依存部分（`check-os` / `clean` / 全ターゲットのパース・依存解決）は
GitHub Actions（`.github/workflows/idempotency.yml`）で機械的に検証している。

> 注: macOS 標準の GNU Make 3.81 は `.ONESHELL`/`.SHELLFLAGS` 非対応のため、各レシピは
> 単一シェルチェーンで自己完結させている。`gmake` 3.82+ でも動作する。
