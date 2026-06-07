# CoreBluetoothDevelopmentBootstrap

Core Bluetooth（BLE）の検証環境を `make` で自動構築する。iOS Central 開発者が、対向の **Peripheral**（nRF52840 DK）・通信を覗く **Sniffer**（USB ドングル＋Wireshark）・自分が書く **Central アプリ**（iPhone）の三者を、コマンドから一気通貫で立ち上げて検証できる。

nRF ハード固有の工程（NCS 導入・ファームウェアビルド・実機書き込み・nRF Sniffer）は submodule [`nrf52840-ble-debug-bootstrap`](https://github.com/kokiTakashiki/nrf52840-ble-debug-bootstrap) に委譲し、このリポジトリはそれと Central アプリをまとめて呼び出す。

> 対象ホスト: Apple Silicon Mac ＋ Homebrew。Xcode の実機ビルド・署名・実行は人手（Make 対象外）。

## 必要な機材

| 機材 | 役割 |
| --- | --- |
| nRF52840 DK（PCA10056） | BLE Peripheral（被検証側 / DUT） |
| nRF52840 MDBT50Q USB ドングル | nRF Sniffer（観測側） |
| iPhone（実機） | 自作 Central アプリの実行先（Core Bluetooth は実機のみ） |

## クイックスタート（実機での E2E）

「DK が出す BLE を、自作の Central アプリで叩き、その通信を Sniffer で電波として裏取りする」までを通す手順。

### 0. 基盤を用意（初回のみ・実機不要・冪等）

```sh
make setup
```

ツール導入・NCS 取得・ファームウェアビルド・Sniffer extcap 配置・Xcode プロジェクト生成までをまとめて行う（初回は数 GB の DL。再実行しても同じ状態に収束する）。

### 1. 開発キットを Peripheral にする

```sh
make flash-peripheral
```

peripheral_uart（Nordic UART Service = NUS）を DK に焼き、続けて BLE↔シリアルの往復を対話検査する（画面の y/N の指示に従う）。

### 2. Sniffer で電波を観測する（Wireshark）

```sh
make capture
```

DK が peripheral_uart で動いているか自動確認し、Wireshark を起動する。Wireshark 側で:

1. インターフェイス **`nRF Sniffer for Bluetooth LE`** をダブルクリックして捕捉を開始。
2. メニュー **`View > Interface Toolbars > nRF Sniffer`** でツールバーを表示。
3. **【重要】手順 3 で iPhone を接続する“前”に、ツールバーの `Device` で `Nordic_UART_Service` を選ぶ。** これで Sniffer がその DK を追跡し、接続の中身（ATT/GATT）まで録れる。**後から選ぶと接続は録れない**（広告しか拾えない）。
   - DK が出ないときは iPhone 側を Disconnect（接続中だと DK は広告を止める）。`frame contains "Nordic_UART_Service"` で広告中を確認できる。

### 3. Central アプリを iPhone で動かす

```sh
make open-central
```

Xcode が開くので:

1. 実機（iPhone）を選び、**Signing & Capabilities で Team を設定**して **Run（⌘R）**。
2. 起動時に出る **「Bluetooth の使用許可」を「許可」**（許可しないと scan できない）。
3. 画面は [Pulse](https://github.com/kean/Pulse) のコンソール。上部の **`▼` で `Console` タブに切り替える**と、ログが流れる:
   `【0】起動 → 【1】scan → 【2】接続(Nordic_UART_Service) → 【3】〜【5】探索 → 【7】"Hello from iOS" 書き込み`

### 4. アプリのログと電波を突き合わせる（検証完了）

Wireshark のフィルタ欄に **`btatt`** と入れて Enter。接続の ATT（GATT）だけが残る:

- `Exchange MTU Request/Response` … **MTU 交渉**
- `Read By Group Type`（→ Nordic UART Service 発見）/ `Read By Type`（→ Nordic UART Rx / Tx 発見）… **GATT Discovery**
- **`Write Command, Handle 0x0015` の `Value` が `Hello from iOS`** … **アプリの【7】書き込みが電波に乗った証拠**（hex `48 65 6c 6c 6f 20 66 72 6f 6d 20 69 4f 53`）

iPhone アプリ（Swift）が書いたバイトが、そのまま電波上の ATT パケットとして観測できれば、**Phase 1（DK）＋ Phase 2（Sniffer）＋ Phase 3（Central アプリ）が一本に繋がった** ＝ 検証環境が機能している。

> 詰まったら [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)（コマンド別）を参照。

## 3 フェーズ

| フェーズ | 目的（確定するもの） | Makefile が自動化 | 人手で確認 |
| --- | --- | --- | --- |
| **Phase 1** 開発キット単体 | DUT（BLE Peripheral） | blinky / peripheral_uart の書き込み | 消灯→LED 点滅・往復 |
| **Phase 2** プロトコルアナライザ運用 | 観測手段 | Sniffer extcap 配置・ドングルへの FW 書き込み | Wireshark で 広告→接続→MTU→GATT を観測 |
| **Phase 3** Xcode Central 最小実装 | 検証主体（自作 Central） | project.yml を xcodegen で .xcodeproj 化（iOSAppTemplate 非依存） | Xcode でのビルド・実行・Sniffer 裏取り |

各フェーズの完了条件・Mermaid 図・意思決定ログは [docs/DESIGN-001.md](docs/DESIGN-001.md) を参照。

## コマンド一覧

| 区分 | コマンド | 説明 |
| --- | --- | --- |
| 準備 | `make setup` | 検証環境の基盤を全部用意する（ツール導入・NCS 取得・FW ビルド・Sniffer extcap 配置・Xcode プロジェクト生成）。実機不要・冪等。 |
| ① 開発キット | `make flash-blinky` | blinky を焼く。全消去で消灯させ、消灯→点滅の差分で書き込み成功を確認。 |
| ① 開発キット | `make flash-peripheral` | peripheral_uart を焼き、続けて BLE↔シリアルの往復を対話検査。 |
| ① 検査 | `make verify-peripheral` | 上の往復検査だけを単体で再実行。 |
| ② アナライザ | `make capture` | ドングルに Sniffer を焼き、Wireshark で DK↔iPhone を観測（広告→接続→MTU→GATT）。 |
| ③ Central | `make open-central` | Xcode プロジェクトを生成して開く（実機ビルド・実行は Xcode で人手）。 |
| ③ Central | `make generate-central` / `make format` / `make format-check` | .xcodeproj 生成 / Swift 整形 / 整形検査（Mintfile 固定）。 |
| その他 | `make` / `make clean` | ターゲット一覧（help）/ 生成物・ビルド成果物の削除。 |

## 用語

| 用語 | 意味 |
| --- | --- |
| Central / Peripheral | BLE の役割。Central＝スキャンして接続しに行く側（iPhone アプリ）。Peripheral＝広告してデータを出す側（DK）。 |
| NUS（Nordic UART Service） | Nordic 定義の UART over BLE。RX(`6E400002`, Write)/TX(`6E400003`, Notify) は Peripheral 視点の呼称。 |
| DK / Dongle | 開発キット（nRF52840 DK）/ USB スティック型ボード（Sniffer 用）。 |
| Sniffer / extcap | BLE を傍受する仕組み / Wireshark が外部プログラムをキャプチャ元にする仕組み。 |

## ライセンス

本リポジトリ（Makefile・スクリプト・Central アプリのソース・ドキュメント）は [MIT ライセンス](LICENSE)。© 2026 kokiTakeda。

第三者のツール・SDK・ファームウェアは同梱せず、`make` 実行時に各ツールを公式ソースから取得する。各ツールはそれぞれのライセンス／EULA に従う（nrfutil・nRF Command Line Tools は Nordic EULA、Wireshark は GPL-2.0-or-later、Pulse は Apache-2.0 ほか）。
