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
├── central/                         Phase 3: Central 参照実装・足場
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

```sh
git clone --recurse-submodules https://github.com/kokiTakashiki/CoreBluetoothDevelopmentBootstrap.git
cd CoreBluetoothDevelopmentBootstrap
# 既にクローン済みなら: make init（= git submodule update --init --recursive）

make setup    # ソフトウェア環境構築（実機不要 / 子へ委譲。NCS 導入＋ peripheral_uart ビルド）
make phase1   # Phase 1: 開発キット単体（blinky→LED 確認→peripheral_uart）
make phase2   # Phase 2: プロトコルアナライザ運用（Sniffer extcap＋FW 書き込み）
make phase3   # Phase 3: Xcode で Central 最小実装（足場生成＋手順案内）
```

## 3 フェーズ

| フェーズ | 目的（確定するもの） | Makefile が自動化 | 人手で確認 |
| --- | --- | --- | --- |
| **Phase 1** 開発キット単体 | DUT（BLE Peripheral） | blinky / peripheral_uart の書き込み | LED 点滅・nRF Connect での文字列往復 |
| **Phase 2** プロトコルアナライザ運用 | 観測手段 | Sniffer extcap 配置・ドングルへの FW 書き込み | Wireshark への Sniffer 出現・各フェーズ観測 |
| **Phase 3** Xcode Central 最小実装 | 検証主体（自作 Central） | iOSAppTemplate の足場生成・参照実装の配置 | Xcode でのビルド・実行・Sniffer 裏取り |

各フェーズの完了条件・Mermaid 図・意思決定ログは [docs/DESIGN-001.md](docs/DESIGN-001.md) を参照。

## コマンド一覧

| コマンド | 説明 |
| --- | --- |
| `make` | ターゲット一覧（help） |
| `make init` | submodule を取得・更新 |
| `make setup` | ソフトウェア環境構築（実機不要 / 子へ委譲） |
| `make phase1` | Phase 1: blinky→確認→peripheral_uart |
| `make flash-blinky` / `make flash-peripheral` | Phase 1 の個別書き込み |
| `make phase2` | Phase 2: Sniffer extcap＋ドングル FW |
| `make phase3` / `make scaffold-central` | Phase 3: Central 足場生成＋案内 |
| `make verify` | 実機検査（子へ委譲 / 読み取り専用＋[y/N]書込確認） |
| `make clean` | ビルド成果物を削除 |

子（submodule）の詳細なターゲット（`flash-dk` / `install-sniffer` / `flash-sniffer-dongle` 等）は [`external/nrf52840-ble-debug-bootstrap`](https://github.com/kokiTakashiki/nrf52840-ble-debug-bootstrap) の README を参照。

## ライセンス

本リポジトリ（Makefile・ドキュメント・参照実装）は [MIT ライセンス](LICENSE)。submodule および各ツール・SDK・ファームウェアはそれぞれのライセンス／EULA に従う。本リポジトリはこれらを再配布せず、取得を自動化するのみ。
