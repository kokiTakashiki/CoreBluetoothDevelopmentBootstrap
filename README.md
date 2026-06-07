# CoreBluetoothDevelopmentBootstrap

Core Bluetooth（BLE）の検証環境を自動構築する Makefile を提供する。各ツールの導入・ビルド・実機書き込みを `make` のコマンドから実行できる。導入対象は nRF Connect SDK（NCS）・Wireshark・nRF Sniffer。

nRF ハード固有の工程（NCS 導入・ファームウェアビルド・実機書き込み・nRF Sniffer）は submodule [`nrf52840-ble-debug-bootstrap`](https://github.com/kokiTakashiki/nrf52840-ble-debug-bootstrap) に委譲する。このリポジトリはそれと iOS Central アプリをまとめて呼び出し、検証環境一式を `make` で用意する。

> 対象ホスト: Apple Silicon Mac ＋ Homebrew。Xcode の実機ビルド・署名・実行は人手（Make 対象外）。

## 必要な機材

| 機材 | 役割 | 使うフェーズ |
| --- | --- | --- |
| nRF52840 DK（PCA10056） | BLE Peripheral（被検証側 / DUT） | ① |
| nRF52840 MDBT50Q USB ドングル | nRF Sniffer（観測側） | ② |
| iPhone（実機） | Central アプリの実行先 | ③ |

## 使い方

```sh
# 準備（初回・実機不要・冪等）
make setup            # ツール導入＋NCS 取得＋FW ビルド＋Sniffer extcap 配置＋Xcode プロジェクト生成

# 実機をつないで、確認したいものを試す
make flash-blinky     # ① 開発キット: blinky を焼いて LED 点滅を見る
make flash-peripheral # ① 開発キット: peripheral_uart を焼き、往復を対話検査
make capture          # ② アナライザ: ドングルに Sniffer を焼き Wireshark で観測
make open-central     # ③ Central: Xcode プロジェクトを開いてアプリを動かす
```

`make setup` は一度だけ。以降の各コマンドは実機をつないで順不同・何度でも試せる。実機書き込みと GUI 起動は `setup` には含めず、各コマンド側が担う。

## コマンド一覧

| 区分 | コマンド | 説明 |
| --- | --- | --- |
| 準備 | `make setup` | 検証環境の基盤を全部用意する（ツール導入・NCS 取得・FW ビルド・Sniffer extcap 配置・Xcode プロジェクト生成）。実機不要・冪等。 |
| ① 開発キット | `make flash-blinky` | blinky を焼く。全消去で消灯させ、消灯→点滅の差分で書き込み成功を確認。 |
| ① 開発キット | `make flash-peripheral` | peripheral_uart を焼き、続けて BLE↔シリアルの往復を対話検査。 |
| ① 検査 | `make verify-peripheral` | 上の往復検査だけを単体で再実行。 |
| ② アナライザ | `make capture` | ドングルに Sniffer を焼き、Wireshark で DK↔iPhone を観測。 |
| ③ Central | `make open-central` | Xcode プロジェクトを生成して開く（実機ビルド・実行は Xcode で人手）。 |
| ③ Central | `make generate-central` / `make format` / `make format-check` | .xcodeproj 生成 / Swift 整形 / 整形検査（Mintfile 固定）。 |
| その他 | `make` / `make clean` | ターゲット一覧（help）/ 生成物・ビルド成果物の削除。 |

## 3 フェーズ

| フェーズ | 目的（確定するもの） | Makefile が自動化 | 人手で確認 |
| --- | --- | --- | --- |
| **Phase 1** 開発キット単体 | DUT（BLE Peripheral） | blinky / peripheral_uart の書き込み | 消灯→LED 点滅・往復 |
| **Phase 2** プロトコルアナライザ運用 | 観測手段 | Sniffer extcap 配置・ドングルへの FW 書き込み | Wireshark で 広告→接続→MTU→GATT を観測 |
| **Phase 3** Xcode Central 最小実装 | 検証主体（自作 Central） | project.yml を xcodegen で .xcodeproj 化（iOSAppTemplate 非依存） | Xcode でのビルド・実行・Sniffer 裏取り |

## ドキュメント

| 内容 | 場所 |
| --- | --- |
| iOS Central アプリと**実機 E2E の通し手順** | [central/README.md](central/README.md) |
| Central のコードの読み方（教材） | [central/GUIDE.md](central/GUIDE.md) |
| 設計・完了条件・意思決定ログ | [docs/DESIGN-001.md](docs/DESIGN-001.md) |
| コマンド別トラブルシュート | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) |
| nRF ハード側（Peripheral＋Sniffer）の詳細 | submodule [`nrf52840-ble-debug-bootstrap`](https://github.com/kokiTakashiki/nrf52840-ble-debug-bootstrap) |

## ライセンス

本リポジトリ（Makefile・スクリプト・Central アプリのソース・ドキュメント）は [MIT ライセンス](LICENSE)。© 2026 kokiTakeda。

第三者のツール・SDK・ファームウェアは同梱せず、`make` 実行時に各ツールを公式ソースから取得する。各ツールはそれぞれのライセンス／EULA に従う（nrfutil・nRF Command Line Tools は Nordic EULA、Wireshark は GPL-2.0-or-later、Pulse は Apache-2.0 ほか）。
