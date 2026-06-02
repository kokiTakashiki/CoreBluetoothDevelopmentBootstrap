# CoreBluetoothDevelopmentBootstrap

Core Bluetooth（BLE）の検証環境を、Makefile 一つで自動構築するための個人用リポジトリ。導入対象は nRF Connect SDK（NCS）・Wireshark・nRF Sniffer など。各ツールの導入・ビルド・実機書き込みまでを `make` で実行できる。

> 対象: Apple Silicon Mac。Xcode / iOS 実機署名の自動化は対象外。

## 用語

このドキュメントで繰り返し使う略語・ツール固有の用語をまとめる。本文では一般的な技術用語を優先し、ここに挙げる製品固有の用語のみ補足する。

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
| 既定ターゲット | default goal | 引数なしの `make` で実行されるターゲット。本リポジトリでは副作用のない `help`。 |
| 冪等（べきとう） | idempotent | 何回実行しても結果が変わらないこと。本リポジトリでは「導入済みなら処理をスキップする」という意味で使う。 |

## 使い方

```sh
make                      # 既定ターゲット = help（ターゲット一覧を表示・副作用なし）
make setup                # ソフトウェア環境構築（実機不要）: 前提確認 → 導入 → ビルド
make deploy               # 実機へファームウェアを書き込む（要 DK＋ドングル接続。検証は make verify）
make check-os             # 実行環境の前提確認（arm64 / Homebrew）
make install-nrfutil      # nrfutil 本体を導入（公式 arm64 バイナリ）
make install-tools        # nrfutil コマンド / NCS Toolchain / west / Wireshark を導入
make install-sniffer      # nRF Sniffer の extcap プラグインを配置
make fetch-ncs            # NCS ソースツリーを取得（west init+update / 数 GB DL）
make build-firmware       # peripheral_uart をビルド（未取得なら fetch-ncs が先に走る）
make flash-dk             # 開発キットへ書き込み（要 DK 接続）
make flash-sniffer-dongle # ドングルへ Sniffer FW を書き込み（要ドングル）
make verify               # 確認付きで「書き込み→検査」を一括実行（[y/N]、既定 N。y のときだけ deploy）
make clean                # ビルド成果物を削除
```

> **`flash-sniffer-dongle`（ドングルへの書き込み）について:**
> - 書き込みは nRF52840 Dongle の Open Bootloader 経由の DFU で行う。実行前にドングルを挿し、**RESET ボタンを押して LED が赤く点滅する状態（＝ Open Bootloader 起動中）**にしておくこと。
> - ドングルは `/dev/tty.usbmodem*` として列挙される。複数検出された場合は `SERIAL_PORT=` で対象を明示する。
> - 書き込みコマンドには、統合版（unified）nrfutil の `nrf5sdk-tools`（`pkg generate` → `dfu usb-serial`）を使う。旧来の `pip install nrfutil` 系にあった `nrfutil pkg` / `nrfutil dfu` は統合版 nrfutil 本体には存在しない（詳細は [DESIGN-001 DL-5](docs/DESIGN-001.md)）。

## `make setup` が導入するもの

`make setup` は依存ターゲット（`install-tools`）を通じて以下を導入する。各項目は導入前に存在検査され、導入済みならスキップされる（冪等）。なお nRF Sniffer extcap プラグインの配置（`install-sniffer`）は `deploy` 系（`flash-sniffer-dongle`）の依存で実行される。

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
| **nRF Sniffer extcap プラグイン** | ローカルの nRF Sniffer 配布物（`SNIFFER_PKG_DIR`）からコピー | `WIRESHARK_EXTCAP_DIR`（既定 `~/.local/lib/wireshark/extcap`） | Wireshark で BLE をキャプチャ | 必須 |

> **3 つの入口（役割ごとに分離）:**
> - `make setup` … **ソフトウェア環境構築（実機不要）**。前提確認 → ツール導入 → ファームウェアビルドまで。実機が無くても最後まで完走する。
> - `make deploy` … **実機へ書き込むだけ**（`flash-dk` / `flash-sniffer-dongle`）。確認を挟まないそのままの書き込み。**DK / ドングルの接続が必須**。
> - `make verify` … **「書き込み → 検査」を確認付きで一括実行する入口**。`[y/N]` で「実機へ書き込みが行われます。問題ないですか？」と確認し、**`y` のときだけ書き込み（`deploy`）を実行**してから、広告 / Sniffer インタフェースを検査する（既定 N。`y` 以外なら書き込みをスキップして現在の状態だけを検査）。
>
> 書き込みは副作用なので、明示同意（`y`）があったときだけ実行される。`make -n verify`（dry-run）では確認プロンプトは出ない。

> **NCS ソースツリーの自動取得（`fetch-ncs`）:** `install-tools` の `nrfutil toolchain-manager install` は **ツールチェイン（コンパイラ・Zephyr 依存）のみ**を導入し、`nrf/`・`zephyr/`・`samples/` を含む **NCS ソースツリーは取得しない**。そのため `build-firmware` は `fetch-ncs` に依存し、未取得時に `west init -m https://github.com/nrfconnect/sdk-nrf --mr $(NCS_VERSION)` + `west update` + `west zephyr-export` で `$(HOME)/ncs/$(NCS_VERSION)` へソースを展開する（Nordic 公式手順: [Installing the nRF Connect SDK](https://docs.nordicsemi.com/bundle/ncs-latest/page/nrf/installation/install_ncs.html)）。**数 GB のダウンロード**を伴うため初回は時間がかかる。`SAMPLE_DIR` か `$(NCS_BASE)/.west` が既にあれば再取得しない（冪等）。

**`make setup` では導入されず、事前に用意が必要なもの**:

| 前提条件 | 用途 | 補足 |
| --- | --- | --- |
| Homebrew | 各 cask / nrfutil 配置先の基盤 | `check-os` が存在を検査（無ければ停止） |
| nRF Sniffer 配布物 | extcap プラグイン・Sniffer hex の供給元 | `SNIFFER_PKG_DIR` に展開しておく |
| nrfjprog（nRF Command Line Tools） | `flash-dk` の J-Link 書き込み | 未導入時は `flash-dk` が明示エラーで停止 |
| 実機（nRF52840 DK / Dongle） | フラッシュ・検証 | `flash-*` / `verify` で必要 |

主な変数（`make build-firmware BOARD=... NCS_VERSION=...` で上書き可）:

| 変数 | 既定値 | 用途 |
| --- | --- | --- |
| `NCS_VERSION` | `v2.6.1` | nRF Connect SDK のバージョン固定 |
| `BOARD` | `nrf52840dk_nrf52840` | ビルド対象ボード |
| `WIRESHARK_EXTCAP_DIR` | `~/.local/lib/wireshark/extcap` | extcap プラグイン配置先 |
| `SERIAL_PORT` | 自動検出 | 書き込み対象ポート（複数検出時はエラー） |

## サードパーティのツールとライセンス

本リポジトリ（Makefile / ドキュメント）は MIT ライセンスです。**第三者のツール・SDK・ファームウェアは一切同梱しておらず**、`make` 実行時に各**公式ソースからダウンロード**します（Homebrew formula や Nordic 公式 `nrf-docker` と同様の方式）。したがって本リポジトリの MIT は自作物にのみ適用され、各ツールはそれぞれのライセンス／EULA に従います（両者は独立）。

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
