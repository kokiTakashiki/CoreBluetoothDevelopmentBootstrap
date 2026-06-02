# CoreBluetoothDevelopmentBootstrap

Core Bluetooth（BLE）の検証環境を、Makefile 一つで自動構築するための個人用リポジトリ。導入対象は nRF Connect SDK（NCS）・Wireshark・nRF Sniffer など。各ツールの導入・ビルド・実機書き込みまでを `make` のコマンド（ターゲット）から実行できる。

> 対象: Apple Silicon Mac。Xcode / iOS 実機署名の自動化は対象外。

## 用語

このドキュメントで繰り返し使う略語・ツール固有の用語をまとめる。

| 用語 | 展開・読み | 意味 |
| --- | --- | --- |
| NCS | nRF Connect SDK | Nordic 製の SDK。Zephyr RTOS をベースにした BLE 開発環境。 |
| Zephyr | — | NCS の土台となる RTOS。 |
| west | — | Zephyr 公式のコマンドラインツール。複数リポジトリの取得（`west init` / `west update`）とビルドをまとめて駆動する（Zephyr ではこれを「メタツール」と呼ぶ）。 |
| ツールチェイン | toolchain | コンパイラやビルド依存の一式。NCS の「ツールチェイン」と「ソースツリー」は別物で、両方が揃って初めてビルドできる。 |
| DK | Development Kit（開発キット） | nRF52840 DK。デバッグ機能付きの開発ボード。 |
| Dongle（ドングル） | — | nRF52840 Dongle。USB スティック型のボード。本リポジトリでは Sniffer 用ファームウェアの書き込み先として使う。 |
| DFU | Device Firmware Update | ファームウェアを書き込む方式の一つ。ここではドングルへの USB 経由の書き込みに使う。 |
| Open Bootloader | — | nRF52840 Dongle に最初から書かれている DFU 用のブートローダ。RESET ボタンで起動する。 |
| extcap | external capture | Wireshark が外部プログラムをキャプチャ元として使う仕組み。nRF Sniffer はこの仕組みで BLE パケットを Wireshark に取り込む。 |
| 既定ターゲット | default goal | 引数なしの `make` で実行されるターゲット。本リポジトリでは `help`。 |

## 使い方

| コマンド | 説明 |
| --- | --- |
| `make` | ターゲット一覧を表示する。 |
| `make setup` | ソフトウェア環境を構築する。前提の確認、ツールの導入、ファームウェアのビルドまでを行う。 |
| `make deploy` | ファームウェアを実機へ書き込む。DK とドングルの接続が必要で、書き込み結果の検証は `make verify` で行う。 |
| `make check-os` | 実行環境の前提を確認する。arm64 アーキテクチャかどうかと、Homebrew がインストールされているかを調べる。 |
| `make install-nrfutil` | nrfutil 本体を導入する。Nordic 公式の arm64 バイナリを使う。 |
| `make install-tools` | nrfutil コマンド・NCS Toolchain・west・Wireshark を導入する。 |
| `make install-sniffer` | nRF Sniffer の extcap プラグインを配置する。 |
| `make fetch-ncs` | NCS ソースツリーを取得する。数 GB のダウンロードを伴う。 |
| `make build-firmware` | peripheral_uart をビルドする。ソース未取得なら先に fetch-ncs が実行される。 |
| `make flash-dk` | 開発キット（DK）へ書き込む。DK の接続が必要。 |
| `make flash-sniffer-dongle` | ドングルへ Sniffer ファームウェアを書き込む。ドングルの接続が必要。 |
| `make verify` | 書き込みと検査をまとめて実行する。実行前に `[y/N]` で確認し、既定は N。 |
| `make clean` | ビルド成果物を削除する。 |

### 基本の流れ

1. `make setup` でソフトウェア環境（ツール一式とビルド済みファームウェア）を用意する。この段階では実機が無くても完走する。
2. nRF52840 DK とドングルを接続する。
3. `make verify` を実行する。実機へファームウェアを書き込んだうえで、DK が BLE で広告しているか、Wireshark に Sniffer インタフェースが現れるかを検査する。これにより、環境整備が正常に完了したかを確認できる。

`make verify` は書き込みの前に `[y/N]` で確認し、`y` と答えたときだけ書き込む（既定は N）。書き込みだけを行いたい場合は `make deploy` を使う。

> **`flash-sniffer-dongle`（ドングルへの書き込み）について:**
> - 書き込みは nRF52840 Dongle の Open Bootloader 経由の DFU で行う。実行前にドングルを挿し、**RESET ボタンを押して LED が赤く点滅する状態（＝ Open Bootloader 起動中）**にしておくこと。
> - ドングルは `/dev/tty.usbmodem*` として列挙される。複数検出された場合は `SERIAL_PORT=` で対象を明示する。
> - 書き込みコマンドには、統合版（unified）nrfutil の `nrf5sdk-tools`（`pkg generate` → `dfu usb-serial`）を使う。旧来の `pip install nrfutil` 系にあった `nrfutil pkg` / `nrfutil dfu` は統合版 nrfutil 本体には存在しない（詳細は [DESIGN-001 DL-5](docs/DESIGN-001.md)）。

## `make setup` が導入するもの

`make setup` は依存ターゲット（`install-tools`）を通じて以下を導入する。各項目は導入前に存在検査され、導入済みならスキップされる。なお nRF Sniffer extcap プラグインの配置（`install-sniffer`）は `deploy` 系（`flash-sniffer-dongle`）の依存で実行される。

| ツール | 入手元 | 配置先 | 用途 | 区分 |
| --- | --- | --- | --- | --- |
| **nrfutil**（本体） | Nordic 公式 arm64 バイナリ（`files.nordicsemi.com`） | `$(brew --prefix)/bin/nrfutil` | NCS ツールチェイン管理・デバイス操作の統合 CLI | 必須 |
| nrfutil **toolchain-manager** コマンド | `nrfutil install toolchain-manager` | nrfutil 管理下 | NCS ツールチェインの導入 / `launch` 実行 | 必須 |
| nrfutil **device** コマンド | `nrfutil install device` | nrfutil 管理下 | 接続デバイスの操作 | 必須 |
| nrfutil **nrf5sdk-tools** コマンド | `nrfutil install nrf5sdk-tools` | nrfutil 管理下 | `pkg generate` / `dfu usb-serial`（ドングルの DFU 書き込み）を提供 | 必須 |
| **NCS Toolchain**（`NCS_VERSION`） | `nrfutil toolchain-manager install` | `/opt/nordic/ncs/toolchains/…` | Zephyr/NCS のコンパイラ・ビルド依存一式（数 GB） | 必須 |
| **NCS ソースツリー**（`NCS_VERSION`） | `west init -m sdk-nrf --mr` + `west update`（`fetch-ncs` が実行） | `$(HOME)/ncs/$(NCS_VERSION)`（`nrf/`・`zephyr/`・`samples/` 等） | サンプル（`peripheral_uart`）と Zephyr 本体のソース。ビルドに必須（数 GB） | 必須 |
| **west** | `python3 -m pip install --user west` | Python ユーザー site の `bin` | Zephyr メタツール（ビルド駆動） | 必須 |
| **Wireshark** | Homebrew cask | `/Applications/Wireshark.app` | パケット解析 | 必須 |
| **nRF Connect for Desktop** | Homebrew cask | `/Applications` | GUI ツール群（Programmer 等） | 任意 |
| **nrfjprog ＋ SEGGER J-Link** | Homebrew cask `nordic-nrf-command-line-tools`（`segger-jlink` を依存導入） | `/usr/local/bin` ほか | DK の J-Link 書き込み（`flash-dk`）。`.pkg` のため導入時に sudo を求める場合あり | 必須 |
| **nRF Sniffer extcap プラグイン** | ローカルの nRF Sniffer 配布物（`SNIFFER_PKG_DIR`）からコピー | `WIRESHARK_EXTCAP_DIR`（既定 `~/.local/lib/wireshark/extcap`） | Wireshark で BLE をキャプチャ | 必須 |

> 初回の `make setup` は数 GB のダウンロードを伴うため、環境によっては時間がかかる。ファームウェアのビルドには、ツールチェインだけでなく NCS のソースツリー（`nrf/`・`zephyr/`・`samples/` など）も必要になる。ソースツリーは `fetch-ncs` が取得し、`make setup` が自動で呼び出す。取得済みなら再ダウンロードはしない。

**`make setup` では導入されず、事前に用意が必要なもの**:

| 前提条件 | 用途 | 補足 |
| --- | --- | --- |
| Homebrew | 各 cask / nrfutil 配置先の基盤 | `check-os` が存在を検査（無ければ停止） |
| nRF Sniffer 配布物 | extcap プラグイン・Sniffer hex の供給元 | `SNIFFER_PKG_DIR` に展開しておく（Nordic の[配布ページ](https://www.nordicsemi.com/Products/Development-tools/nRF-Sniffer-for-Bluetooth-LE/Download)からダウンロード） |
| 実機（nRF52840 DK / Dongle） | フラッシュ・検証 | `flash-*` / `verify` で必要 |

> nrfjprog ＋ SEGGER J-Link（DK の書き込みに必要）は `make setup` が自動で導入する。手動で用意が必要なのは、上記の nRF Sniffer 配布物と実機の接続だけ。

## 設定を変えたいとき

ビルドや書き込みの挙動は、以下の Make 変数で変えられる。既定値のままでも動作するが、別のボードを対象にしたい、NCS のバージョンを変えたいといった場合は、コマンドラインで変数を渡して上書きする。

```sh
make build-firmware BOARD=... NCS_VERSION=...
```

| 変数 | 既定値 | 説明 |
| --- | --- | --- |
| `NCS_VERSION` | `v2.6.1` | 使用する nRF Connect SDK のバージョン。 |
| `BOARD` | `nrf52840dk_nrf52840` | ビルド対象のボード。 |
| `WIRESHARK_EXTCAP_DIR` | `~/.local/lib/wireshark/extcap` | extcap プラグインの配置先。 |
| `SERIAL_PORT` | 自動検出 | 書き込み対象のシリアルポート。複数見つかった場合は、この変数で対象を指定する必要がある。 |

## サードパーティのツールとライセンス

本リポジトリに含まれるのは Makefile とドキュメントだけで、これらは MIT ライセンスです。**第三者のツール・SDK・ファームウェアは一切同梱しておらず**、`make` の実行時に各ツールを公式ソースからダウンロードします。これは Homebrew の formula や Nordic 公式の `nrf-docker` と同じ方式です。したがって本リポジトリの MIT ライセンスは自作物にのみ適用され、各ツールはそれぞれのライセンスや EULA に従います。本リポジトリのライセンスと各ツールのライセンスは、互いに独立しています。

| ツール | 取得元 | ライセンス（概略） |
| --- | --- | --- |
| nrfutil / nRF Connect for Desktop / nRF Command Line Tools | Nordic 公式（`files.nordicsemi.com` / Homebrew） | Nordic 独自 EULA（プロプライエタリ） |
| nRF Connect SDK — `nrf/`（sdk-nrf） | github.com/nrfconnect/sdk-nrf（`west`） | LicenseRef-Nordic-5-Clause |
| nRF Connect SDK — Zephyr 等の構成要素 | `west update` で取得 | Apache-2.0 ほか |
| nRF Sniffer for Bluetooth LE（extcap / FW） | Nordic 公式 | Nordic 独自ライセンス |
| Wireshark | Homebrew cask | GPL-2.0-or-later |

> 上表のライセンスは概略です。各ツールの「利用」には提供元の EULA／ライセンスが適用され、**それはツールを使う利用者が従うもの**です。本リポジトリはこれらを**再配布せず、取得を自動化するスクリプトのみ**を提供します。正確な条件は各提供元の一次ライセンス文書をご確認ください。

## ライセンス

[MIT License](LICENSE) © 2026 kokiTakeda
