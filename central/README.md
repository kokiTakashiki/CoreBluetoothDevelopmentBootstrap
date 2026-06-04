# central/ — Phase 3: Xcode で Central 最小実装

DESIGN-001 Phase 3 の「検証主体」。iOS Central のアプリは **実装フェーズに iOSAppTemplate(Genesis) で生成**する。このディレクトリが追跡するのは生成物ではなく、**生成オプションと注入する BLE ソースだけ**である。

## このディレクトリの中身

| パス | 役割 | git 追跡 |
| --- | --- | --- |
| `central-options.yml` | iOSAppTemplate(Genesis) の生成オプション。アプリ名・Bundle ID・対応言語などを定義する。 | ○ |
| `BLECentral.swift` | NUS を相手取る `CBCentralManager` の最小実装。生成アプリへ自動注入される。 | ○ |
| `<appName>/`（既定 `BLECentralSample/`） | `make generate-central` が生成した Xcode アプリ一式（`project.yml`・Swift・`.xcodeproj` 等）。 | ×（`.gitignore`） |
| `.iOSAppTemplate/` | iOSAppTemplate の clone キャッシュ。 | ×（`.gitignore`） |

生成アプリは追跡しない。`make generate-central` を実行すれば、`central-options.yml` から何度でも同じものを再生成できる（生成物を git に載せない＝差分はテンプレ/スペックのみ。DESIGN-001 D-7）。

## 仕組み

`make generate-central`（`make setup` の最後でも実行される）は次を行う:

1. iOSAppTemplate を取得（`central/.iOSAppTemplate` にキャッシュ）。
2. Genesis を `central-options.yml` で非対話実行し、`central/<appName>/` にアプリ一式を生成。
3. `BLECentral.swift` を生成アプリのソースへ注入。
4. `xcodegen generate` で `.xcodeproj` を生成（`.xcodeproj` と `Info.plist` は生成アプリ側でも `.gitignore`）。

```sh
make setup          # 検証環境一式を用意（この生成も含む）
make open-central   # 生成された .xcodeproj を開く
```

> アプリ名を変えるときは `central-options.yml` の `appName` と `make … APP_NAME=` を合わせる。

## 以降の実装（人手）

Apple の署名・ビルド・実行は Make の対象外（DESIGN-001 D-6）。Xcode で:

1. 生成アプリのどこか（例: `SceneDelegate`）で `BLECentral()` を生成して起動する。
2. Phase 1 の peripheral_uart 搭載 DK へ `scan → connect → discoverServices → discoverCharacteristics → readValue/setNotifyValue` が流れることを確認する。
3. 同じ通信を Phase 2 の Wireshark でも観測し、Swift 実装が出すバイト列を可視化する。

## NUS（Nordic UART Service）UUID

| 特性 | UUID | 向き |
| --- | --- | --- |
| Service | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` | — |
| RX | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` | Central → Peripheral（Write） |
| TX | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` | Peripheral → Central（Notify） |
