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

> `flash-sniffer-dongle` は nRF52840 Dongle の Open Bootloader 経由で DFU 書き込みする。実行前にドングルを挿し、**RESET ボタンを押して LED が赤く点滅する状態（Open Bootloader）**にしておくこと。`/dev/tty.usbmodem*` として列挙され、複数検出時は `SERIAL_PORT=` で明示する。書き込みは新 unified nrfutil の `nrf5sdk-tools` コマンド（`pkg generate` → `dfu usb-serial`）で行う（旧 `pip install nrfutil` 系の `nrfutil pkg` / `nrfutil dfu` は新 nrfutil 本体に無い。詳細は [DESIGN-001 DL-5](docs/DESIGN-001.md)）。

## `make setup` が導入するもの

`make setup` は依存ターゲット（`install-tools` / `install-sniffer`）を通じて以下を導入する。各項目は導入前に存在検査され、導入済みならスキップされる（冪等）。

| ツール | 入手元 | 配置先 | 用途 | 区分 |
| --- | --- | --- | --- | --- |
| **nrfutil**（本体） | Nordic 公式 arm64 バイナリ（`files.nordicsemi.com`） | `$(brew --prefix)/bin/nrfutil` | NCS ツールチェイン管理・デバイス操作の統合 CLI | 必須 |
| nrfutil **toolchain-manager** コマンド | `nrfutil install toolchain-manager` | nrfutil 管理下 | NCS ツールチェインの導入 / `launch` 実行 | 必須 |
| nrfutil **device** コマンド | `nrfutil install device` | nrfutil 管理下 | 接続デバイスの操作 | 必須 |
| nrfutil **nrf5sdk-tools** コマンド | `nrfutil install nrf5sdk-tools` | nrfutil 管理下 | `pkg generate` / `dfu usb-serial`（ドングルの DFU 書き込み）を提供 | 必須 |
| **NCS Toolchain**（`NCS_VERSION`） | `nrfutil toolchain-manager install` | `/opt/nordic/ncs/toolchains/…` | Zephyr/NCS のコンパイラ・ビルド依存一式（数 GB） | 必須 |
| **west** | `python3 -m pip install --user west` | Python ユーザー site の `bin` | Zephyr メタツール（ビルド駆動） | 必須 |
| **Wireshark** | Homebrew cask | `/Applications/Wireshark.app` | パケット解析 | 必須 |
| **nRF Connect for Desktop** | Homebrew cask | `/Applications` | GUI ツール群（Programmer 等） | 任意 |
| **nRF Sniffer extcap プラグイン** | ローカルの nRF Sniffer 配布物（`SNIFFER_PKG_DIR`）からコピー | `WIRESHARK_EXTCAP_DIR`（既定 `~/.local/lib/wireshark/extcap`） | Wireshark で BLE をキャプチャ | 必須 |

> `make setup` はこれらの導入に加えて、ファームウェアのビルド（`build-firmware`）と**実機への書き込み**（`flash-dk` / `flash-sniffer-dongle`）・検証（`verify`）まで実行する。書き込みには **DK / ドングルの接続が必須**。

**`make setup` では導入されない前提物**（別途用意が必要）:

| 前提物 | 用途 | 補足 |
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

## 冪等性

各ターゲットは状態検査つきの冪等な単位として定義され、何度実行しても同一の最終状態へ収束する。
ハードウェア非依存部分（`check-os` / `clean` / 全ターゲットのパース・依存解決）は
GitHub Actions（`.github/workflows/idempotency.yml`）で機械的に検証している。

> 注: macOS 標準の GNU Make 3.81 は `.ONESHELL`/`.SHELLFLAGS` 非対応のため、各レシピは
> 単一シェルチェーンで自己完結させている。`gmake` 3.82+ でも動作する。

## ライセンス

[MIT License](LICENSE) © 2026 kokiTakeda
