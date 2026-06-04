# CoreBluetoothDevelopmentBootstrap

Core Bluetooth（BLE）の検証環境を自動構築する Makefile を提供する。iOS Central 開発者が、対向の Peripheral・通信を覗く Sniffer・自分が書く Central 実装の三者を、`make` のコマンドから 3 フェーズで立ち上げられる。

nRF ハード固有の工程（NCS 導入・ファームウェアビルド・実機書き込み・nRF Sniffer）は submodule [`nrf52840-ble-debug-bootstrap`](https://github.com/kokiTakashiki/nrf52840-ble-debug-bootstrap) へ委譲し、本リポジトリはそれを束ねるオーケストレータに徹する。

> 対象ホスト: Apple Silicon Mac。Xcode ビルド / iOS 実機署名は人手（Make の冪等性が保証できないため自動化対象外）。
>
> 設計の詳細は [docs/DESIGN-001.md](docs/DESIGN-001.md)（図は Mermaid）を参照。

## 構成

```
CoreBluetoothDevelopmentBootstrap/   ← 本リポジトリ（オーケストレータ）
├── Makefile                         3 フェーズ・オーケストレータ
├── docs/DESIGN-001.md               構成設計書
├── central/                         Phase 3: Genesis 生成オプション＋注入する BLE ソース（生成物は gitignore）
└── external/
    └── nrf52840-ble-debug-bootstrap/  submodule: nRF52840 製 BLE デバッグ環境（Peripheral＋Sniffer）
```

| レイヤ | 提供物 | 実体 |
| --- | --- | --- |
| 親（本リポジトリ） | 3 フェーズの束ね、Central の足場 | `Makefile` / `central/` |
| 子（submodule） | nRF52840 の Peripheral（DUT）＋ Sniffer（観測） | `external/nrf52840-ble-debug-bootstrap`（独立リポジトリ） |

## 必要な機材

| 機材 | 役割 | フェーズ |
| --- | --- | --- |
| nRF52840 DK（PCA10056） | BLE Peripheral（被検証側 / DUT） | Phase 1 |
| nRF52840 MDBT50Q USB ドングル | nRF Sniffer（観測側） | Phase 2 |
| iPhone | nRF Connect for Mobile ＋ 自作 Central アプリ | Phase 1 / 3 |

## 使い方

人間が手で叩く**二段階**のインターフェース。まず `make setup` で検証に必要なものを一度に用意し、あとは実機をつないで、この環境でできることを 4 つのコマンドで**順不同・何度でも**試す。

```sh
git clone --recurse-submodules https://github.com/kokiTakashiki/CoreBluetoothDevelopmentBootstrap.git
cd CoreBluetoothDevelopmentBootstrap
# 既にクローン済みなら: make init（= git submodule update --init --recursive）

# 準備（一度・冪等・実機/GUI 不要）
make setup            # 検証に必要なものを全部用意する
                      #   = ツール導入 + NCS 取得 + blinky/peripheral_uart ビルド
                      #     + Sniffer extcap 配置 + Xcode Central プロジェクト生成

# この環境でできること（実機をつないで、好きなものを順不同・何度でも試す）
make flash-blinky     # ① 開発キット: blinky を焼いて LED 点滅を見る
make flash-peripheral # ① 開発キット: peripheral_uart を焼く（nRF Connect で往復）
make capture          # ② アナライザ: ドングルに Sniffer を焼き Wireshark でキャプチャ
make open-central     # ③ Central: Xcode プロジェクトを開いてアプリを動かす
```

## 3 フェーズ

| フェーズ | 目的（確定するもの） | Makefile が自動化 | 人手で確認 |
| --- | --- | --- | --- |
| **Phase 1** 開発キット単体 | DUT（BLE Peripheral） | blinky / peripheral_uart の書き込み | LED 点滅・nRF Connect での文字列往復 |
| **Phase 2** プロトコルアナライザ運用 | 観測手段 | Sniffer extcap 配置・ドングルへの FW 書き込み | Wireshark への Sniffer 出現・各フェーズ観測 |
| **Phase 3** Xcode Central 最小実装 | 検証主体（自作 Central） | iOSAppTemplate(Genesis) でアプリ生成・BLE ソース注入・xcodegen で .xcodeproj 化 | Xcode でのビルド・実行・Sniffer 裏取り |

各フェーズの完了条件・Mermaid 図・意思決定ログは [docs/DESIGN-001.md](docs/DESIGN-001.md) を参照。

## コマンド一覧

| 区分 | コマンド | 説明 |
| --- | --- | --- |
| 準備 | `make setup` | 検証に必要なものを全部用意する（実機/GUI 不要・冪等）。ツール導入・NCS 取得・blinky/peripheral_uart ビルド・Sniffer extcap 配置・Xcode Central プロジェクト生成。 |
| できること | `make flash-blinky` | ① 開発キット: blinky を焼いて LED 点滅を見る。 |
| できること | `make flash-peripheral` | ① 開発キット: peripheral_uart を焼く（nRF Connect で往復）。 |
| できること | `make capture` | ② アナライザ: ドングルに Sniffer を焼き、Wireshark でキャプチャ。 |
| できること | `make open-central` | ③ Central: Xcode プロジェクトを開いてアプリを動かす。 |
| その他 | `make` | ターゲット一覧（help）。 |
| その他 | `make init` | submodule を取得・更新（`make setup` が内部で実行）。 |
| その他 | `make generate-central` | Central アプリを iOSAppTemplate(Genesis) で生成し xcodegen で .xcodeproj 化（`make setup`／`open-central` が内部で実行）。 |
| その他 | `make verify` | 機械検査（子へ委譲 / 読み取り専用＋[y/N]書込確認）。 |
| その他 | `make clean` | ビルド成果物を削除（central プロジェクトは残す）。 |

子（submodule）の詳細なターゲット（`flash-dk` / `install-sniffer` / `flash-sniffer-dongle` 等）は [`external/nrf52840-ble-debug-bootstrap`](https://github.com/kokiTakashiki/nrf52840-ble-debug-bootstrap) の README を参照。

## ライセンス

本リポジトリ（Makefile・ドキュメント・参照実装）は [MIT ライセンス](LICENSE)。submodule および各ツール・SDK・ファームウェアはそれぞれのライセンス／EULA に従う。本リポジトリはこれらを再配布せず、取得を自動化するのみ。
