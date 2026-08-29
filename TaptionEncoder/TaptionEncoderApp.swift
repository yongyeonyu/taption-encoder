import SwiftUI
import UIKit

extension Notification.Name {
    static let taptionExternalVideoOpenRequested = Notification.Name("TaptionExternalVideoOpenRequested")
}

@MainActor
enum ExternalVideoOpenInbox {
    private static var pendingURLs: [URL] = []

    static func enqueue(_ url: URL, postsNotification: Bool = true) {
        pendingURLs.append(url)
        if postsNotification {
            NotificationCenter.default.post(name: .taptionExternalVideoOpenRequested, object: nil)
        }
    }

    static func drainPendingURLs() -> [URL] {
        let urls = pendingURLs
        pendingURLs.removeAll()
        return urls
    }
}

@MainActor
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

    func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        let canHandleURL = ExternalVideoOpenPolicy.canHandle(url: url)
        AppLogger.info(
            "Application received external URL",
            category: .fileImport,
            metadata: [
                "name": url.lastPathComponent,
                "handled": "\(canHandleURL)"
            ]
        )
        if canHandleURL {
            AdMobBootstrapper.suppressAppOpenAdsForExternalPlayback()
            ExternalVideoOpenInbox.enqueue(url)
        }
        return canHandleURL
    }
}

@MainActor
final class AppOrientationController {
    static let shared = AppOrientationController()

    private(set) var supportedOrientations: UIInterfaceOrientationMask

    private init() {
        supportedOrientations = Self.homeOrientations(for: UIDevice.current.userInterfaceIdiom)
    }

    static func homeOrientations(for userInterfaceIdiom: UIUserInterfaceIdiom) -> UIInterfaceOrientationMask {
        userInterfaceIdiom == .pad
            ? [.portrait, .landscapeLeft, .landscapeRight]
            : .portrait
    }

    func activatePreviewOrientations(requestGeometryUpdate: Bool = true) {
        setSupportedOrientations(
            [.portrait, .landscapeLeft, .landscapeRight],
            requestGeometryUpdate: requestGeometryUpdate
        )
    }

    func restorePortrait(requestGeometryUpdate: Bool = true) {
        setSupportedOrientations(
            Self.homeOrientations(for: UIDevice.current.userInterfaceIdiom),
            requestGeometryUpdate: requestGeometryUpdate
        )
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
            rootView
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

    private var rootView: some View {
        let view = HomeView()
            .preferredColorScheme(.dark)

        #if DEBUG
        return view.task {
            await DebugLiveActivityProbe.startIfRequested()
        }
        #else
        return view
        #endif
    }
}

#if DEBUG
@MainActor
private enum DebugLiveActivityProbe {
    private static let coordinator = ActivityKitEncodingLiveActivityCoordinator()
    private static var didStart = false

    static func startIfRequested() async {
        guard !didStart else {
            return
        }
        let environment = ProcessInfo.processInfo.environment
        guard environment["TAPTION_DEBUG_LIVE_ACTIVITY"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--taption-debug-live-activity") else {
            return
        }

        didStart = true
        let snapshot = TaptionEncodingActivitySnapshot(
            sessionID: "debug-live-activity-\(UUID().uuidString)",
            statusText: "Encoding",
            sourceName: "iPad Lock Screen Preview.mov",
            mode: .folder,
            currentIndex: 2,
            totalCount: 5,
            fractionCompleted: 0.42,
            elapsedSeconds: 65,
            remainingSeconds: 125,
            codecPathText: "HW/SW Codec Path",
            outputText: "H.265 / HEVC MP4"
        )
        await coordinator.start(snapshot: snapshot)
        AppLogger.info(
            "Debug Live Activity probe requested",
            category: .encoding,
            metadata: [
                "source": snapshot.sourceName,
                "progress": snapshot.contentState.percentText
            ]
        )
    }
}
#endif
