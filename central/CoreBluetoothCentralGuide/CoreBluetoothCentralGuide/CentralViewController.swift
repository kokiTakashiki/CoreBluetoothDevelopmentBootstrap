//
//  CentralViewController.swift
//  CoreBluetoothCentralGuide
//
//  Core Bluetooth の Central を最小で実装したガイド付き教材。
//  コードは「Central がたどる手順」の順に上から下へ並べてある。各手順の
//  ねらい・なぜそうするか・どのデリゲートで結果が返るかをコメントで示す。
//  通しの解説は central/GUIDE.md を参照。
//
//  目的（DESIGN-001 Phase 3）:
//   - scan → connect → discoverServices → discoverCharacteristics →
//     setNotifyValue / writeValue の一連の流れをログで確認する。
//   - peripheral_uart 搭載 DK へ接続し、受信バイト列を hex と UTF-8 で画面に出して
//     Wireshark の観測（ATT パケット）と突き合わせる。
//
//  Core Bluetooth の設計思想（このコードで体感する点）:
//   - 役割: このアプリは Central（クライアント）。相手の DK が Peripheral（サーバ）。
//   - 階層: データは Peripheral > Service > Characteristic の木をたどって取りに行く。
//   - 非同期: 各段（scan/connect/discover/…）の結果はデリゲートで返り、
//            返って初めて次の段へ進む。これが Core Bluetooth の中核モデル。
//   - 状態が先: poweredOn になるまでスキャンしない。
//

import CoreBluetooth
import UIKit

// この教材ファイルは手順順（手順 0 → 7）を学習動線として保つため、宣言の自動整理だけ無効化する。
// 他の整形ルールは適用される。
// swiftformat:disable organizeDeclarations

final class CentralViewController: UIViewController {

    // MARK: Nordic UART Service（NUS）の UUID

    // 相手（peripheral_uart）が公開する GATT。Service の中に RX/TX の 2 特性がある。
    private static let nusService = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private static let nusRX = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // Write : Central → Peripheral
    private static let nusTX = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // Notify: Peripheral → Central

    // MARK: 状態

    // Central Manager・接続中の Peripheral・書き込み先の RX 特性を保持する。
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?

    /// 手順の進行と受信バイト列を流すログビュー。
    private let logView = UITextView()

    // MARK: 手順 0 — Central Manager を起動する

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpLogView()

        // Central の入口。delegate に自分を渡すと、Bluetooth の状態変化・発見・接続が
        // すべてコールバックで返る。queue: .main にして UI 更新を簡単にする。
        // ここではまだスキャンしない（poweredOn を待つ。次の手順 1 へ）。
        central = CBCentralManager(delegate: self, queue: .main)
        log("【0】Central Manager を起動。poweredOn を待つ…")
    }
}

// MARK: - CBCentralManagerDelegate（Central 側: 状態・発見・接続）

extension CentralViewController: CBCentralManagerDelegate {

    /// 手順 1 — 状態が先。poweredOn になって初めてスキャンしてよい。
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            log("Bluetooth 利用不可: state=\(central.state.rawValue)")
            return
        }
        // 必要な Service を指定してスキャン（無駄な発見を絞るのが CB の作法）。
        central.scanForPeripherals(withServices: [Self.nusService])
        log("【1】scan 開始（NUS を広告する Peripheral を探す）")
    }

    /// 手順 2 — 見つかったらスキャンを止めて接続する。
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber)
    {
        log("【2】発見: \(peripheral.name ?? "unknown") RSSI=\(RSSI) → 接続する")
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self // 以降の GATT 探索の結果は CBPeripheralDelegate に返る
        central.connect(peripheral)
    }

    /// 手順 3 — 接続できたら Service を探索する。
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("【3】接続完了 → サービス探索")
        peripheral.discoverServices([Self.nusService])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?)
    {
        log("切断: \(error?.localizedDescription ?? "正常")")
    }
}

// MARK: - CBPeripheralDelegate（接続先の GATT: サービス・特性・値）

extension CentralViewController: CBPeripheralDelegate {

    /// 手順 4 — Service が見つかったら、その中の Characteristic を探索する。
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.nusService }) else {
            return
        }
        log("【4】サービス発見 → 特性探索")
        peripheral.discoverCharacteristics([Self.nusRX, Self.nusTX], for: service)
    }

    /// 手順 5 — Characteristic が見つかったら、TX を購読し RX を控える。
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?)
    {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.nusTX:
                // TX は Notify。購読すると Peripheral からの送信が手順 6 に届く。
                peripheral.setNotifyValue(true, for: characteristic)
                log("【5】TX を購読（setNotifyValue）")
            case Self.nusRX:
                // RX は Write。ここに書くと Peripheral（DK の UART）へ送られる。
                rxCharacteristic = characteristic
                log("【5】RX を取得（writeValue 用）")
            default:
                break
            }
        }
        // 手順 7 — 書き込みを 1 回デモする（Wireshark に ATT Write が現れる）。
        send("Hello from iOS\n")
    }

    /// 手順 6 — 購読した TX の値が届く。バイト列を hex と UTF-8 で表示し、
    /// Wireshark の Handle Value Notification と突き合わせる。
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?)
    {
        guard characteristic.uuid == Self.nusTX, let data = characteristic.value else {
            return
        }
        let hex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
        let text = String(data: data, encoding: .utf8) ?? "(非 UTF-8)"
        log("【6】受信 TX: \(hex)  \"\(text)\"")
    }

    /// 手順 7 — RX へ書き込む（往復確認用）。peripheral_uart は受けた値を DK の
    /// シリアルへ流す。DK のシリアル端末に入力すると TX 経由で手順 6 に返る。
    func send(_ text: String) {
        guard let peripheral, let rx = rxCharacteristic, let data = text.data(using: .utf8) else {
            return
        }
        peripheral.writeValue(data, for: rx, type: .withoutResponse)
        log("【7】送信 RX: \"\(text.trimmingCharacters(in: .newlines))\"")
    }
}

// MARK: - ログビュー（UI は本質ではないので最小限）

private extension CentralViewController {
    func setUpLogView() {
        view.backgroundColor = .systemBackground
        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logView)
        NSLayoutConstraint.activate([
            logView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            logView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            logView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            logView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    func log(_ message: String) {
        print(message) // コンソールにも出す（ロギング要件）
        logView.text += message + "\n"
    }
}
