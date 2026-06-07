# central/ — Phase 3: Xcode で Central 最小実装

DESIGN-001 Phase 3 の「検証主体」。iOS Central のアプリ一式をこのディレクトリに**固定（commit）**し、`.xcodeproj` だけを `xcodegen` で生成する。**iOSAppTemplate には実行時依存しない**（テンプレが破壊的に変わっても影響を受けない。D-7）。

> **コードの読み方** … [GUIDE.md](GUIDE.md)（手順0〜7 で Core Bluetooth の設計思想を学ぶ）
> **実機での通し手順（E2E）** … リポジトリ直下の [README](../README.md)（`make setup`→`flash-peripheral`→`capture`→`open-central`）

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
| `CoreBluetoothCentralGuide/CoreBluetoothCentralGuide/Info.plist` | XcodeGen が `project.yml` の `info:` から生成。 | ×（`.gitignore`） |

雛形は iOSAppTemplate(Genesis) で一度生成したものを固定したもの。以後 iOSAppTemplate は不要で、`make` は `xcodegen generate` するだけ。

## 使い方

```sh
make setup          # 検証環境一式を用意（この .xcodeproj 生成も含む）
make open-central   # xcodegen で生成し、Xcode で開く
make format         # Swift を SwiftFormat で整形（Mintfile 固定）
```

> アプリ名を変えるときは `CoreBluetoothCentralGuide/project.yml` の `name`・ディレクトリ名と、Makefile の `APP_NAME` を合わせる。

## 以降の実装

Apple の署名・ビルド・実行は Make の対象外（DESIGN-001 D-6）。Xcode で:

1. 実機（iPhone）を選び、署名チームを設定してビルド・実行する。
2. アプリは起動と同時に scan を開始し、Phase 1 の peripheral_uart 搭載 DK へ
   `scan → connect → discoverServices → discoverCharacteristics → readValue/setNotifyValue`
   を流す。各イベントは Pulse のコンソール画面に出る（検索・フィルタ可）。
3. 同じ通信を Phase 2 の Wireshark でも観測し、Swift 実装が出すバイト列を可視化する。

## NUS（Nordic UART Service）UUID

出典: Nordic 定義の公開固定値（[`nus.h`](https://github.com/nrfconnect/sdk-nrf/blob/main/include/bluetooth/services/nus.h)）。

| 特性 | UUID | 向き |
| --- | --- | --- |
| Service | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` | — |
| RX | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` | Central → Peripheral（Write） |
| TX | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` | Peripheral → Central（Notify） |
