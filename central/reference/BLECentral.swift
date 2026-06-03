import CoreBluetooth
import Foundation

/// Nordic UART Service（NUS）を相手取る Central の最小参照実装。
///
/// DESIGN-001 Phase 3 の「検証主体」を満たす最小コード。
/// scan → connect → discoverServices → discoverCharacteristics →
/// setNotifyValue / writeValue の一連を示す。接続先は Phase 1 で構築した
/// peripheral_uart 搭載の nRF52840 DK。
///
/// 使い方（Xcode 側）:
///   let central = BLECentral()        // 生成と同時に scan を開始する
///   central.send("hello")             // RX 特性へ書き込み（往復確認）
final class BLECentral: NSObject {
    // NUS の UUID 群（Nordic 定義）
    static let nusService = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let nusRX      = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // Central → Peripheral（Write）
    static let nusTX      = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // Peripheral → Central（Notify）

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?

    override init() {
        super.init()
        // delegate を自身に、コールバックはメインキューで受ける。
        central = CBCentralManager(delegate: self, queue: .main)
    }

    /// RX 特性へ文字列を書き込む（往復確認用）。
    func send(_ text: String) {
        guard let peripheral, let rx = rxCharacteristic, let data = text.data(using: .utf8) else { return }
        // NUS RX は Write Without Response を受け付ける。
        peripheral.writeValue(data, for: rx, type: .withoutResponse)
    }
}

extension BLECentral: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            print("Bluetooth 利用不可: state=\(central.state.rawValue)")
            return
        }
        // NUS を広告している Peripheral を走査する。
        central.scanForPeripherals(withServices: [Self.nusService])
        print("scan 開始")
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        print("発見: \(peripheral.name ?? "unknown") RSSI=\(RSSI)")
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("接続: \(peripheral.name ?? "unknown")")
        // 必要な Service のみを探索する。
        peripheral.discoverServices([Self.nusService])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        print("切断: \(error?.localizedDescription ?? "正常")")
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
            case Self.nusRX:
                rxCharacteristic = characteristic
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
        print("受信(TX): \(text)")
    }
}
