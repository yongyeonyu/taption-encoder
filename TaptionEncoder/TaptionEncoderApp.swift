import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppOrientationController.shared.supportedOrientations
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        application.isIdleTimerDisabled = true
        AppLogger.info("Idle timer disabled while app is active", category: .app)
    }

    func applicationWillResignActive(_ application: UIApplication) {
        application.isIdleTimerDisabled = false
        AppLogger.info("Idle timer restored because app is no longer active", category: .app)
    }
}

@MainActor
final class AppOrientationController {
    static let shared = AppOrientationController()

    private(set) var supportedOrientations: UIInterfaceOrientationMask = .portrait

    private init() {}

    func activatePreviewOrientations(requestGeometryUpdate: Bool = true) {
        setSupportedOrientations(
            [.portrait, .landscapeLeft, .landscapeRight],
            requestGeometryUpdate: requestGeometryUpdate
        )
    }

    func restorePortrait(requestGeometryUpdate: Bool = true) {
        setSupportedOrientations(.portrait, requestGeometryUpdate: requestGeometryUpdate)
    }

    private func setSupportedOrientations(
        _ orientations: UIInterfaceOrientationMask,
        requestGeometryUpdate: Bool
    ) {
        guard supportedOrientations != orientations else {
            return
        }
        supportedOrientations = orientations

        guard requestGeometryUpdate else {
            return
        }

        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        if #available(iOS 16.0, *) {
            windowScenes.forEach { scene in
                scene.windows.forEach {
                    $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
                scene.requestGeometryUpdate(
                    .iOS(interfaceOrientations: orientations)
                ) { error in
                    AppLogger.warning(
                        "Orientation geometry update failed",
                        category: .ui,
                        metadata: ["error": String(describing: error)]
                    )
                }
            }
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}

@main
struct TaptionEncoderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasSeenActiveScene = false

    init() {
        AppLogger.configure()
        AppLogger.info("Application init", category: .app)
        TaptionTestVideoSeeder.seedBundledSamplesIntoDocuments()
        AdMobBootstrapper.start()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, newPhase in
            AppLogger.info(
                "Scene phase changed",
                category: .app,
                metadata: ["phase": "\(newPhase)"]
            )
            guard newPhase == .active else {
                return
            }
            Task {
                await AdMobBootstrapper.refreshOnActive()
                guard hasSeenActiveScene else {
                    hasSeenActiveScene = true
                    AppLogger.info("App open ad skipped for initial active scene", category: .ads)
                    return
                }
                await AdMobBootstrapper.showAppOpenAdIfAvailable()
            }
        }
    }
}
