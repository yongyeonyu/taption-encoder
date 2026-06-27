import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
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

@main
struct TaptionEncoderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

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
                await AdMobBootstrapper.showAppOpenAdIfAvailable()
            }
        }
    }
}
