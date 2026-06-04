//
//  BLECentralViewController.swift
//  BLECentralSample
//
//  BLECentral の動作を画面に出す最小 VC。起動と同時に scan を開始し、
//  scan→connect→discover→受信 の各イベントをテキストで流す（コンソールにも出る）。
//

import UIKit

final class BLECentralViewController: UIViewController {
    private let central = BLECentral()
    private let textView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        // BLECentral のイベントを画面へ流してから scan を開始する。
        central.onEvent = { [weak self] line in
            self?.textView.text += line + "\n"
        }
        central.start()
    }
}
