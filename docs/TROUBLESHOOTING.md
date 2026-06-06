# トラブルシュート（コマンド別）

`make` の各コマンドで詰まったときの対処をコマンド別にまとめる。各 `make` コマンドの
実行時メッセージからこのファイルの該当節を参照する。

- [make flash-blinky](#make-flash-blinky)
- [make flash-peripheral / make verify-peripheral](#make-flash-peripheral--make-verify-peripheral)
- [make capture](#make-capture)
- [make open-central](#make-open-central)

---

## make flash-blinky

### LED の変化が分からない
`flash-blinky` は「全消去で消灯 → 一時停止 → 書き込みで点滅」と進むため、**消灯から点滅への変化**で書き込み成功を判断する。点滅しっぱなし/消灯しっぱなしに見えるときは、消灯の一時停止（Enter 待ち）を見落としていないか確認する。

### 書き込みに失敗する（nrfjprog / J-Link）
- `nrfjprog` と SEGGER J-Link ランタイムが必要（`make setup` で導入）。`nrfjprog --version` が通るか確認。
- DK が USB で接続され、`nrfjprog --ids` に J-Link が出るか確認。

---

## make flash-peripheral / make verify-peripheral

peripheral_uart は BLE(NUS) と DK のシリアルを橋渡しするだけで、自分からは何も送らない。

### 往復（上り/下り）が確認できない
- **DK のシリアルポートが見つからない**: `ls /dev/cu.usbmodem*` が空なら USB 接続を確認。別ポートのときは `UART_PORT=/dev/cu.xxx` で上書きできる。
- **上り（Mac→iPhone）が出ない**: iPhone の nRF Connect で TX(`6E400003`) の Notify を ON にしているか。
- **下り（iPhone→DK）が出ない**: 書き込み先は **RX(`6E400002`)**。TX に書いても DK のシリアルへは橋渡しされない。
- BLE 内にエコーは無い。往復は必ず「BLE ↔ シリアル」を経由する。

---

## make capture

`make capture` は冒頭で `uart-fwcheck`（DK をリセットして起動ログを判定）を自動実行する。`WARN` が出たら DK は peripheral_uart ではない → `make flash-peripheral` を先に実行する。

### Wireshark のインターフェイス一覧に 'nRF Sniffer for Bluetooth LE' が出ない
ドングルは健在でも、Sniffer FW のハングやホスト側 extcap のスタックで一覧から消えることがある。次の順に試す:

1. **ドングルを挿し直す**（USB ハブ経由なら Mac 本体ポートへ直挿しに変える）。
2. **Sniffer FW を焼き直す**: ドングルを Open Bootloader（赤 LED 点滅）にして `make capture` を再実行し、`[y/N]` に `y`。RAYTAC MDBT50Q はボタンを押したまま挿す。Nordic 純正(PCA10059)は横向き RESET を 1 回。
3. **Wireshark を完全終了して再起動**。
4. それでも駄目なら **Mac を再起動**（USB シリアル / extcap のスタックは再起動で解けることが多い。nRF Sniffer の定番リカバリ）。

### Sniffer ツールバーの Device に 'Nordic_UART_Service' が出ない
DK が広告していない。

- 冒頭の自動確認（`uart-fwcheck`）が `WARN` を出していたら、DK は peripheral_uart でない → `make flash-peripheral`。
- iPhone が DK に接続中だと DK は広告を止める → nRF Connect で **Disconnect**。
- 表示フィルタ `frame contains "Nordic_UART_Service"` で行が出れば広告中。Adv Hop は `37,38,39` にしておくと取りこぼしにくい。

### Connect したのに何も流れない / `btatt` で何も出ない
- DK と iPhone が実際に接続しているか（一覧の Source/Destination が `Central ↔ Peripheral` になっているか）。
- **Device で対象 DK を選んでから接続したか**（選ぶ前に接続すると Sniffer が追跡しない）。
- 接続直後は `Empty PDU`（接続維持の空パケット）で埋まる。探索は接続直後に終わって上へ流れているので、`btatt` で絞ると見える。

---

## make open-central

Apple の署名・ビルド・実行は Make の対象外。Xcode 側の操作になる。

- **`.xcodeproj` が開かない / 生成されない**: `make generate-central`（Mint 固定の XcodeGen）が成功しているか。`central/CoreBluetoothCentralGuide/project.yml` が存在するか。
- **実機で動かない**: Xcode で実機を選び、署名チーム（`DEVELOPMENT_TEAM`）を設定してビルド・実行する。
