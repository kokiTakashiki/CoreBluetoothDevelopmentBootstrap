//
//  BLECentral.swift
//  BLECentralSample
//
//  Nordic UART Service（NUS）を相手取る Central の最小実装。
//  DESIGN-001 Phase 3 の「検証主体」を満たす最小コード。
//  scan → connect → discoverServices → discoverCharacteristics →
//  setNotifyValue / writeValue の一連を示す。接続先は Phase 1 で構築した
//  peripheral_uart 搭載の nRF52840 DK。
//
//    let central = BLECentral()
//    central.onEvent = { print($0) }   // 任意: 画面表示などに使う
//    central.start()                   // scan を開始する
//    central.send("hello")             // RX 特性へ書き込み（往復確認）
//

import CoreBluetooth
import Foundation

final class BLECentral: NSObject {
    // NUS の UUID 群（Nordic 定義）
    static let nusService = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let nusRX      = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // Central → Peripheral（Write）
    static let nusTX      = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // Peripheral → Central（Notify）

    /// 各イベント（scan/接続/受信 など）の通知。画面表示などに使う（任意）。
    var onEvent: ((String) -> Void)?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?

    /// scan を開始する。`CBCentralManager` を生成し、poweredOn になり次第 scan する。
    func start() {
        central = CBCentralManager(delegate: self, queue: .main)
    }

    /// RX 特性へ文字列を書き込む（往復確認用）。
    func send(_ text: String) {
        guard let peripheral, let rx = rxCharacteristic, let data = text.data(using: .utf8) else { return }
        // NUS RX は Write Without Response を受け付ける。
        peripheral.writeValue(data, for: rx, type: .withoutResponse)
    }

    private func log(_ message: String) {
        print(message)
        onEvent?(message)
    }
}

extension BLECentral: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            log("Bluetooth 利用不可: state=\(central.state.rawValue)")
            return
        }
        // NUS を広告している Peripheral を走査する。
        central.scanForPeripherals(withServices: [Self.nusService])
        log("scan 開始")
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        log("発見: \(peripheral.name ?? "unknown") RSSI=\(RSSI)")
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("接続: \(peripheral.name ?? "unknown")")
        // 必要な Service のみを探索する。
        peripheral.discoverServices([Self.nusService])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        log("切断: \(error?.localizedDescription ?? "正常")")
    }
}

extension BLECentral: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == Self.nusService {
            peripheral.discoverCharacteristics([Self.nusRX, Self.nusTX], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            switch characteristic.uuid {
            case Self.nusTX:
                // TX(Notify) を購読し、Peripheral からの通知を受ける。
                peripheral.setNotifyValue(true, for: characteristic)
                log("TX を購読")
            case Self.nusRX:
                rxCharacteristic = characteristic
                log("RX を取得")
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == Self.nusTX, let data = characteristic.value else { return }
        // UTF-8 として解釈し、不可なら 16 進ダンプで可視化する。
        let text = String(data: data, encoding: .utf8)
            ?? data.map { String(format: "%02x", $0) }.joined()
        log("受信(TX): \(text)")
    }
}
