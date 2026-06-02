# CoreBluetoothDevelopmentBootstrap

Core Bluetooth 検証環境（nRF Connect SDK / Wireshark / nRF Sniffer）をMakefileで構築する個人用ブートストラップ。

> 対象: Apple Silicon Mac。Xcode / iOS 実機署名の自動化は対象外。

## 使い方

```sh
make                      # 既定ゴール = help（ターゲット一覧を表示・副作用なし）
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
make verify               # フルフロー: 確認[y/N]→y なら書き込み(deploy)→広告/Sniffer 検査
make clean                # ビルド成果物を削除
```

> `flash-sniffer-dongle` は nRF52840 Dongle の Open Bootloader 経由で DFU 書き込みする。実行前にドングルを挿し、**RESET ボタンを押して LED が赤く点滅する状態（Open Bootloader）**にしておくこと。`/dev/tty.usbmodem*` として列挙され、複数検出時は `SERIAL_PORT=` で明示する。書き込みは新 unified nrfutil の `nrf5sdk-tools` コマンド（`pkg generate` → `dfu usb-serial`）で行う（旧 `pip install nrfutil` 系の `nrfutil pkg` / `nrfutil dfu` は新 nrfutil 本体に無い。詳細は [DESIGN-001 DL-5](docs/DESIGN-001.md)）。

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
| **nrfjprog ＋ SEGGER J-Link** | Homebrew cask `nordic-nrf-command-line-tools`（`segger-jlink` を依存導入） | `/usr/local/bin` ほか | DK の J-Link 書き込み（`flash-dk`）。`.pkg` のため導入時に sudo を求める場合あり | 必須 |
| **nRF Sniffer extcap プラグイン** | ローカルの nRF Sniffer 配布物（`SNIFFER_PKG_DIR`）からコピー | `WIRESHARK_EXTCAP_DIR`（既定 `~/.local/lib/wireshark/extcap`） | Wireshark で BLE をキャプチャ | 必須 |

> **3 つの入口（関心の分離）:**
> - `make setup` … **ソフトウェア環境構築（実機不要）**。前提確認→ツール導入→ファームウェアビルドまで。実機が無くても完走する。
> - `make deploy` … **実機へ書き込みのみ**（`flash-dk` / `flash-sniffer-dongle`）。確認なしの素のフラッシュ。**DK / ドングルの接続が必須**。
> - `make verify` … **確認付きフルフローの入口**。`[y/N]` で「実機へ書き込みが行われます。問題ないですか？」と確認し、**`y` のときだけ書き込み（`deploy`）を実行**してから広告 / Sniffer インタフェースを検査する（既定 N。`y` 以外なら書き込みをスキップし現在状態を検査）。
>
> 書き込みは副作用なので明示同意（`y`）を経た場合のみ実行される。`make -n verify`（dry-run）では確認は出ない。

> **NCS ソースツリーの自動取得（`fetch-ncs`）:** `install-tools` の `nrfutil toolchain-manager install` は **ツールチェイン（コンパイラ・Zephyr 依存）のみ**を導入し、`nrf/`・`zephyr/`・`samples/` を含む **NCS ソースツリーは取得しない**。そのため `build-firmware` は `fetch-ncs` に依存し、未取得時に `west init -m https://github.com/nrfconnect/sdk-nrf --mr $(NCS_VERSION)` + `west update` + `west zephyr-export` で `$(HOME)/ncs/$(NCS_VERSION)` へソースを展開する（Nordic 公式手順: [Installing the nRF Connect SDK](https://docs.nordicsemi.com/bundle/ncs-latest/page/nrf/installation/install_ncs.html)）。**数 GB のダウンロード**を伴うため初回は時間がかかる。`SAMPLE_DIR` か `$(NCS_BASE)/.west` が既にあれば再取得しない（冪等）。

**`make setup` では導入されない前提物**（別途用意が必要）:

| 前提物 | 用途 | 補足 |
| --- | --- | --- |
| Homebrew | 各 cask / nrfutil 配置先の基盤 | `check-os` が存在を検査（無ければ停止） |
| nRF Sniffer 配布物 | extcap プラグイン・Sniffer hex の供給元 | `SNIFFER_PKG_DIR` に展開しておく（Nordic の[配布ページ](https://www.nordicsemi.com/Products/Development-tools/nRF-Sniffer-for-Bluetooth-LE/Download)からダウンロード） |
| 実機（nRF52840 DK / Dongle） | フラッシュ・検証 | `flash-*` / `verify` で必要 |

> nrfjprog ＋ SEGGER J-Link は `make setup`（`install-tools`）が自動導入するようになった（以前は手動前提だった）。残る手動準備は **nRF Sniffer 配布物の配置**と**実機の接続**のみ。

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
