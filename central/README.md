# central/ — Phase 3: Xcode で Central 最小実装

DESIGN-001 Phase 3 の足場。iOS Central（検証主体）をここに用意する。

## 構成

| パス | 役割 | git 追跡 |
| --- | --- | --- |
| `reference/BLECentral.swift` | NUS を相手取る `CBCentralManager` の最小参照実装。組み込み元。 | ○ |
| `<APP_NAME>/`（既定 `BLECentralSample/`） | `make scaffold-central` が iOSAppTemplate を展開した Xcode プロジェクト。改変して所有する。 | ×（`.gitignore`） |

足場は追跡しない（テンプレートは「出発点」であり、追跡し続ける依存ではない。DESIGN-001 D-7）。

## 手順

```sh
make scaffold-central   # iOSAppTemplate を central/BLECentralSample へ展開し git 履歴を切離
make phase3             # 上記＋実装・実行手順の案内
```

以降は人手（Apple の署名フローは Make の冪等性を保証できないため自動化対象外。D-6）:

1. `central/BLECentralSample` を Xcode で開く。
2. `reference/BLECentral.swift` を組み込み、`CBCentralManager` / `CBCentralManagerDelegate` / `CBPeripheralDelegate` を実装する。
3. `scan → connect → discoverServices → discoverCharacteristics → readValue/setNotifyValue` を実行する。
4. 接続先は Phase 1 で構築した peripheral_uart 搭載の nRF52840 DK。同じ通信を Phase 2 の Wireshark でも観測し、Swift 実装が出すバイト列を可視化する。

## NUS（Nordic UART Service）UUID

| 特性 | UUID | 向き |
| --- | --- | --- |
| Service | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` | — |
| RX | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` | Central → Peripheral（Write） |
| TX | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` | Peripheral → Central（Notify） |
