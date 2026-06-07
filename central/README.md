# central/ — Xcode で Central 最小実装

iOS Central（BLE クライアント）のアプリ一式をこのディレクトリに**固定（commit）**し、`.xcodeproj` だけを `xcodegen` で生成する。**iOSAppTemplate には実行時依存しない**（テンプレが破壊的に変わっても影響を受けない）。

> **コードの読み方** … 同じディレクトリの `GUIDE.md`（手順0〜7 で Core Bluetooth の設計思想を学ぶ。Xcode のナビゲータにも表示される）

## クイックスタート（実機での E2E）

「DK が出す BLE を、この Central アプリで叩き、その通信を Sniffer で電波として裏取りする」までを通す手順。`make` はリポジトリ直下で実行する。

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

iPhone アプリが書いたバイトが、そのまま電波上の ATT パケットとして観測できれば、Peripheral（DK）＋ Sniffer ＋ Central アプリの三者が一本に繋がった ＝ 検証環境が機能している。

> 詰まったら [docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md)（コマンド別）を参照。頻繁に更新される単一原典なので、ここには転記せずリンクで参照する（Xcode では開けないため GitHub / リポジトリで読む）。

## このディレクトリの中身

| パス | 役割 | git 追跡 |
| --- | --- | --- |
| `CoreBluetoothCentralGuide/project.yml` | XcodeGen のプロジェクト定義（`.xcodeproj` の source of truth）。 | ○ |
| `CoreBluetoothCentralGuide/CoreBluetoothCentralGuide/CentralViewController.swift` | Core Bluetooth の Central を手順順に並べたガイド付き教材。scan→connect→discover→notify/write を 1 枚に実装し、各手順をコメントで解説。受信バイト列を Pulse のコンソールに出す。 | ○ |
| `GUIDE.md` | 上記コードを読みながら Core Bluetooth の設計思想を学ぶプログラミングガイド。 | ○ |
| `CoreBluetoothCentralGuide/CoreBluetoothCentralGuide/{AppDelegate,SceneDelegate}.swift` | UIKit のアプリ起動（雛形）。 | ○ |
| `CoreBluetoothCentralGuide/.swiftformat` | SwiftFormat 設定（iOSAppTemplate 由来）。`make format` で使う。 | ○ |
| `CoreBluetoothCentralGuide/Mintfile` | XcodeGen / SwiftFormat を SHA 固定（Mint で実行）。 | ○ |
| `CoreBluetoothCentralGuide/.swift-version` | Swift ツールチェーン版（6.3.1）。無いと整形時に警告が出るため同梱。 | ○ |
| `CoreBluetoothCentralGuide/CoreBluetoothCentralGuide.xcodeproj` | `xcodegen generate` の生成物。 | ×（`.gitignore`） |
| `CoreBluetoothCentralGuide/CoreBluetoothCentralGuide/Info.plist` | XcodeGen が `project.yml` の `info:` から生成（Bluetooth 使用許可も含む）。 | ×（`.gitignore`） |

雛形は iOSAppTemplate(Genesis) で一度生成したものを固定したもの。以後 iOSAppTemplate は不要で、`make` は `xcodegen generate` するだけ。Apple の署名・ビルド・実行は Make の対象外（Xcode で人手）。

## NUS（Nordic UART Service）UUID

出典: Nordic 定義の公開固定値（[`nus.h`](https://github.com/nrfconnect/sdk-nrf/blob/main/include/bluetooth/services/nus.h)）。

| 特性 | UUID | 向き |
| --- | --- | --- |
| Service | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` | — |
| RX | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` | Central → Peripheral（Write） |
| TX | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` | Peripheral → Central（Notify） |
