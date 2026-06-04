//
//  SceneDelegate.swift
//  BLECentralSample
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    // MARK: Properties

    var window: UIWindow?

    // MARK: Functions

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene
        else {
            return
        }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = BLECentralViewController()
        self.window = window
        window.makeKeyAndVisible()
    }
}
