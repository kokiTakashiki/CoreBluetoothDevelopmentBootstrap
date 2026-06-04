# central/ — Phase 3: Xcode で Central 最小実装

DESIGN-001 Phase 3 の「検証主体」。iOS Central のアプリ一式をこのディレクトリに**固定（commit）**し、`.xcodeproj` だけを `xcodegen` で生成する。**iOSAppTemplate には実行時依存しない**（テンプレが破壊的に変わっても影響を受けない。D-7）。

## このディレクトリの中身

| パス | 役割 | git 追跡 |
| --- | --- | --- |
| `BLECentralSample/project.yml` | XcodeGen のプロジェクト定義（`.xcodeproj` の source of truth）。 | ○ |
| `BLECentralSample/BLECentralSample/BLECentral.swift` | NUS を相手取る `CBCentralManager` の最小実装。 | ○ |
| `BLECentralSample/BLECentralSample/BLECentralViewController.swift` | BLECentral を起動し、イベントを画面に出す最小 VC。 | ○ |
| `BLECentralSample/BLECentralSample/{AppDelegate,SceneDelegate}.swift` | UIKit のアプリ起動（雛形）。 | ○ |
| `BLECentralSample/BLECentralSample.xcodeproj` | `xcodegen generate` の生成物。 | ×（`.gitignore`） |
| `BLECentralSample/BLECentralSample/Info.plist` | XcodeGen が `project.yml` の `info:` から生成。 | ×（`.gitignore`） |

雛形は iOSAppTemplate(Genesis) で一度生成したものを固定したもの。以後 iOSAppTemplate は不要で、`make` は `xcodegen generate` するだけ。

## 使い方

```sh
make setup          # 検証環境一式を用意（この .xcodeproj 生成も含む）
make open-central   # xcodegen で生成し、Xcode で開く
```

> アプリ名を変えるときは `BLECentralSample/project.yml` の `name`・ディレクトリ名と、Makefile の `APP_NAME` を合わせる。

## 以降の実装

Apple の署名・ビルド・実行は Make の対象外（DESIGN-001 D-6）。Xcode で:

1. 実機（iPhone）を選び、署名チームを設定してビルド・実行する。
2. アプリは起動と同時に scan を開始し、Phase 1 の peripheral_uart 搭載 DK へ
   `scan → connect → discoverServices → discoverCharacteristics → readValue/setNotifyValue`
   を流す。各イベントは画面とコンソールに出る。
3. 同じ通信を Phase 2 の Wireshark でも観測し、Swift 実装が出すバイト列を可視化する。

## NUS（Nordic UART Service）UUID

| 特性 | UUID | 向き |
| --- | --- | --- |
| Service | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` | — |
| RX | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` | Central → Peripheral（Write） |
| TX | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` | Peripheral → Central（Notify） |
