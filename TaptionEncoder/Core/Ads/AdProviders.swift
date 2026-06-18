import Foundation
import SwiftUI
#if canImport(GoogleMobileAds)
import GoogleMobileAds
import UIKit
#endif

enum AdLoadState: String, Equatable {
    case idle
    case loading
    case ready
    case unavailable
}

enum RewardedAdShowResult: String, Equatable {
    case earnedReward
    case closedWithoutReward
    case unavailable
}

enum SessionEndAdReason: String, Equatable {
    case startingEncoding
    case completedSave
    case cancelledEncoding
    case failedEncoding
}

protocol BannerAdProviding {
    var bannerAdUnitID: String { get }
    func currentBannerState() async -> AdLoadState
}

protocol RewardedAdProviding {
    func currentRewardedState() async -> AdLoadState
    func showRewardedAd() async -> RewardedAdShowResult
}

protocol SessionEndAdProviding {
    func preloadSessionEndAd() async
    func showSessionEndAd(reason: SessionEndAdReason) async
}

struct AdMobRuntimeConfiguration: Equatable, Sendable {
    static let infoDictionaryAppOpenAdUnitIDKey = "TaptionAppOpenAdUnitID"
    static let infoDictionaryHomeBannerAdUnitIDKey = "TaptionHomeBannerAdUnitID"
    static let infoDictionaryRewardedSaveAdUnitIDKey = "TaptionRewardedSaveAdUnitID"
    static let infoDictionarySessionEndInterstitialAdUnitIDKey = "TaptionSessionEndInterstitialAdUnitID"

    let appOpenAdUnitID: String
    let homeBannerAdUnitID: String
    let rewardedSaveAdUnitID: String
    let sessionEndInterstitialAdUnitID: String

    static func current(bundle: Bundle = .main) -> AdMobRuntimeConfiguration {
        #if DEBUG
        AdMobRuntimeConfiguration(
            appOpenAdUnitID: "ca-app-pub-3940256099942544/5575463023",
            homeBannerAdUnitID: "ca-app-pub-3940256099942544/2934735716",
            rewardedSaveAdUnitID: "ca-app-pub-3940256099942544/1712485313",
            sessionEndInterstitialAdUnitID: "ca-app-pub-3940256099942544/4411468910"
        )
        #else
        AdMobRuntimeConfiguration(
            appOpenAdUnitID: normalizedString(
                bundle.object(forInfoDictionaryKey: infoDictionaryAppOpenAdUnitIDKey) as? String
            ) ?? "ca-app-pub-9754025737691277/9568683076",
            homeBannerAdUnitID: normalizedString(
                bundle.object(forInfoDictionaryKey: infoDictionaryHomeBannerAdUnitIDKey) as? String
            ) ?? "ca-app-pub-9754025737691277/6794641076",
            rewardedSaveAdUnitID: normalizedString(
                bundle.object(forInfoDictionaryKey: infoDictionaryRewardedSaveAdUnitIDKey) as? String
            ) ?? "ca-app-pub-9754025737691277/2855396062",
            sessionEndInterstitialAdUnitID: normalizedString(
                bundle.object(forInfoDictionaryKey: infoDictionarySessionEndInterstitialAdUnitIDKey) as? String
            ) ?? "ca-app-pub-9754025737691277/6942519738"
        )
        #endif
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

struct FakeBannerAdProvider: BannerAdProviding {
    var bannerAdUnitID: String {
        "test.banner"
    }

    func currentBannerState() async -> AdLoadState {
        .ready
    }
}

struct FakeRewardedAdProvider: RewardedAdProviding {
    var currentState: AdLoadState = .ready
    var showResult: RewardedAdShowResult = .earnedReward

    func currentRewardedState() async -> AdLoadState {
        currentState
    }

    func showRewardedAd() async -> RewardedAdShowResult {
        showResult
    }
}

struct FakeSessionEndAdProvider: SessionEndAdProviding {
    func preloadSessionEndAd() async {}
    func showSessionEndAd(reason: SessionEndAdReason) async {}
}

struct AdMobBannerAdProvider: BannerAdProviding {
    let configuration: AdMobRuntimeConfiguration

    init(configuration: AdMobRuntimeConfiguration = .current()) {
        self.configuration = configuration
    }

    var bannerAdUnitID: String {
        configuration.homeBannerAdUnitID
    }

    func currentBannerState() async -> AdLoadState {
        configuration.homeBannerAdUnitID.isEmpty ? .unavailable : .ready
    }
}

struct AdMobRewardedAdProvider: RewardedAdProviding {
    let configuration: AdMobRuntimeConfiguration

    init(configuration: AdMobRuntimeConfiguration = .current()) {
        self.configuration = configuration
    }

    func currentRewardedState() async -> AdLoadState {
        #if canImport(GoogleMobileAds)
        return await AdMobRewardedAdManager.shared.currentState(
            adUnitID: configuration.rewardedSaveAdUnitID
        )
        #else
        return .unavailable
        #endif
    }

    func showRewardedAd() async -> RewardedAdShowResult {
        #if canImport(GoogleMobileAds)
        return await AdMobRewardedAdManager.shared.show(
            adUnitID: configuration.rewardedSaveAdUnitID
        )
        #else
        return .unavailable
        #endif
    }
}

struct AdMobSessionEndAdProvider: SessionEndAdProviding {
    let configuration: AdMobRuntimeConfiguration

    init(configuration: AdMobRuntimeConfiguration = .current()) {
        self.configuration = configuration
    }

    func preloadSessionEndAd() async {
        #if canImport(GoogleMobileAds)
        _ = await AdMobInterstitialAdManager.shared.loadIfNeeded(adUnitID: configuration.sessionEndInterstitialAdUnitID)
        #endif
    }

    func showSessionEndAd(reason: SessionEndAdReason) async {
        #if canImport(GoogleMobileAds)
        await AdMobInterstitialAdManager.shared.showIfAvailable(
            adUnitID: configuration.sessionEndInterstitialAdUnitID,
            reason: reason
        )
        #endif
    }
}

enum AdMobBootstrapper {
    static func start() {
        #if canImport(GoogleMobileAds)
        AppLogger.info("AdMob bootstrap started", category: .ads)
        MobileAds.shared.start()
        Task { @MainActor in
            await preloadAllPlacements()
        }
        #else
        AppLogger.warning("AdMob bootstrap skipped because GoogleMobileAds is not linked", category: .ads)
        #endif
    }

    static func refreshOnActive() async {
        #if canImport(GoogleMobileAds)
        AppLogger.info("AdMob refresh requested for active scene", category: .ads)
        await preloadAllPlacements()
        #endif
    }

    static func showAppOpenAdIfAvailable() async {
        #if canImport(GoogleMobileAds)
        let configuration = AdMobRuntimeConfiguration.current()
        AppLogger.info("App open ad show requested", category: .ads)
        await AdMobAppOpenAdManager.shared.showIfAvailable(adUnitID: configuration.appOpenAdUnitID)
        #endif
    }

    #if canImport(GoogleMobileAds)
    @MainActor
    private static func preloadAllPlacements() async {
        let configuration = AdMobRuntimeConfiguration.current()
        AppLogger.info(
            "AdMob preload started",
            category: .ads,
            metadata: [
                "appOpen": configuration.appOpenAdUnitID,
                "banner": configuration.homeBannerAdUnitID,
                "rewarded": configuration.rewardedSaveAdUnitID,
                "interstitial": configuration.sessionEndInterstitialAdUnitID
            ]
        )
        await AdMobAppOpenAdManager.shared.loadIfNeeded(adUnitID: configuration.appOpenAdUnitID)
        _ = await AdMobInterstitialAdManager.shared.loadIfNeeded(adUnitID: configuration.sessionEndInterstitialAdUnitID)
        _ = await AdMobRewardedAdManager.shared.loadIfNeeded(adUnitID: configuration.rewardedSaveAdUnitID)
    }
    #endif
}

struct AdMobBannerSlotView: View {
    let adUnitID: String
    var displayScale: CGFloat = 1

    var body: some View {
        let clampedScale = min(max(displayScale, 0.72), 1)
        ZStack {
            bannerSlotPlaceholder
            #if canImport(GoogleMobileAds)
            AdMobBannerRepresentable(adUnitID: adUnitID)
                .frame(width: 320, height: 50)
            #endif
        }
        .frame(width: 320, height: 50)
        .scaleEffect(clampedScale)
        .frame(maxWidth: .infinity, minHeight: 50 * clampedScale, maxHeight: 50 * clampedScale)
        .accessibilityLabel("Ad banner")
    }

    private var bannerSlotPlaceholder: some View {
        #if canImport(GoogleMobileAds)
        HStack(spacing: 8) {
            Text("Ad")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text("Loading")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.74))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: 320, height: 50)
        .background(Color.white.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(TaptionTheme.accent.opacity(0.45), lineWidth: 1)
        )
        #else
        Text("Ad loading")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.black.opacity(0.74))
            .frame(width: 320, height: 50)
            .background(Color.white.opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(TaptionTheme.accent.opacity(0.45), lineWidth: 1)
            )
        #endif
    }
}

#if canImport(GoogleMobileAds)
private enum AdMobRequestFactory {
    static func makeRequest() -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        return request
    }
}

private enum AdMobRootViewControllerProvider {
    @MainActor
    static func topViewController() -> UIViewController? {
        let rootController = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        return topViewController(from: rootController)
    }

    @MainActor
    private static func topViewController(from controller: UIViewController?) -> UIViewController? {
        if let navigationController = controller as? UINavigationController {
            return topViewController(from: navigationController.visibleViewController)
        }
        if let tabController = controller as? UITabBarController {
            return topViewController(from: tabController.selectedViewController)
        }
        if let presentedController = controller?.presentedViewController {
            return topViewController(from: presentedController)
        }
        return controller
    }
}

private struct AdMobBannerRepresentable: UIViewRepresentable {
    let adUnitID: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator
        banner.backgroundColor = .clear
        context.coordinator.loadIfPossible(banner, adUnitID: adUnitID)
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator
        context.coordinator.loadIfPossible(banner, adUnitID: adUnitID)
    }

    @MainActor
    final class Coordinator: NSObject, BannerViewDelegate {
        private var loadedAdUnitID = ""
        private var retryWorkItem: DispatchWorkItem?
        private var retryCount = 0
        private var fillRetryWorkItem: DispatchWorkItem?
        private var fillRetryCount = 0
        private var isWaitingForFillRetry = false

        func loadIfPossible(_ banner: BannerView, adUnitID: String) {
            banner.rootViewController = AdMobRootViewControllerProvider.topViewController()

            guard !adUnitID.isEmpty else {
                AppLogger.warning("Banner ad load skipped because ad unit is empty", category: .ads)
                return
            }

            guard banner.rootViewController != nil else {
                AppLogger.warning(
                    "Banner ad root view controller missing; scheduling retry",
                    category: .ads,
                    metadata: ["retry": "\(retryCount + 1)"]
                )
                scheduleRetry(for: banner, adUnitID: adUnitID)
                return
            }

            retryWorkItem?.cancel()
            retryWorkItem = nil
            retryCount = 0

            guard !isWaitingForFillRetry else {
                return
            }

            guard loadedAdUnitID != adUnitID else {
                return
            }

            loadedAdUnitID = adUnitID
            AppLogger.info("Banner ad load requested", category: .ads, metadata: ["adUnit": adUnitID])
            banner.load(AdMobRequestFactory.makeRequest())
        }

        private func scheduleRetry(for banner: BannerView, adUnitID: String) {
            guard retryCount < 8 else {
                return
            }
            retryWorkItem?.cancel()
            retryCount += 1
            let workItem = DispatchWorkItem { [weak self, weak banner] in
                guard let self, let banner else { return }
                self.loadIfPossible(banner, adUnitID: adUnitID)
            }
            retryWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        }

        private func scheduleFillRetry(for banner: BannerView, adUnitID: String) {
            guard fillRetryCount < 6,
                  !adUnitID.isEmpty else {
                return
            }
            fillRetryWorkItem?.cancel()
            fillRetryCount += 1
            isWaitingForFillRetry = true
            let delay = min(120, 15 * fillRetryCount)
            AppLogger.warning(
                "Banner ad fill retry scheduled",
                category: .ads,
                metadata: [
                    "retry": "\(fillRetryCount)",
                    "delaySeconds": "\(delay)",
                    "adUnit": adUnitID
                ]
            )
            let workItem = DispatchWorkItem { [weak self, weak banner] in
                guard let self, let banner else { return }
                self.isWaitingForFillRetry = false
                self.loadIfPossible(banner, adUnitID: adUnitID)
            }
            fillRetryWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay), execute: workItem)
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            fillRetryWorkItem?.cancel()
            fillRetryWorkItem = nil
            fillRetryCount = 0
            isWaitingForFillRetry = false
            AppLogger.info("Banner ad loaded", category: .ads)
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            AppLogger.error(
                "Banner ad failed to load",
                category: .ads,
                metadata: ["error": error.localizedDescription]
            )
            let adUnitID = loadedAdUnitID
            loadedAdUnitID = ""
            scheduleFillRetry(for: bannerView, adUnitID: adUnitID)
        }
    }
}

@MainActor
final class AdMobRewardedAdManager: NSObject, FullScreenContentDelegate {
    static let shared = AdMobRewardedAdManager()

    private var preparedAd: RewardedAd?
    private var preparedAdUnitID = ""
    private var activeAd: RewardedAd?
    private var activeContinuation: CheckedContinuation<Bool, Never>?
    private var didEarnReward = false
    private var isLoading = false
    private var lastKnownState: AdLoadState = .idle
    private var retryWorkItem: DispatchWorkItem?
    private var retryCount = 0
    private var isWaitingForRetry = false

    func currentState(adUnitID: String) async -> AdLoadState {
        guard !adUnitID.isEmpty else {
            return .unavailable
        }
        if preparedAd != nil, preparedAdUnitID == adUnitID {
            return .ready
        }
        if isLoading || isWaitingForRetry {
            return .loading
        }
        return lastKnownState
    }

    func loadIfNeeded(adUnitID: String) async -> AdLoadState {
        guard !adUnitID.isEmpty else {
            AppLogger.warning("Rewarded ad load skipped because ad unit is empty", category: .ads)
            lastKnownState = .unavailable
            return .unavailable
        }
        if preparedAd != nil, preparedAdUnitID == adUnitID {
            AppLogger.debug("Rewarded ad already ready", category: .ads)
            lastKnownState = .ready
            return .ready
        }
        if isWaitingForRetry {
            AppLogger.debug("Rewarded ad retry already scheduled", category: .ads)
            lastKnownState = .loading
            return .loading
        }
        guard !isLoading else {
            AppLogger.debug("Rewarded ad already loading", category: .ads)
            lastKnownState = .loading
            return .loading
        }

        isLoading = true
        lastKnownState = .loading
        defer { isLoading = false }

        do {
            AppLogger.info("Rewarded ad load requested", category: .ads, metadata: ["adUnit": adUnitID])
            let ad = try await RewardedAd.load(
                with: adUnitID,
                request: AdMobRequestFactory.makeRequest()
            )
            retryWorkItem?.cancel()
            retryWorkItem = nil
            retryCount = 0
            isWaitingForRetry = false
            ad.fullScreenContentDelegate = self
            preparedAd = ad
            preparedAdUnitID = adUnitID
            lastKnownState = .ready
            AppLogger.info("Rewarded ad loaded", category: .ads)
            return .ready
        } catch {
            preparedAd = nil
            preparedAdUnitID = ""
            lastKnownState = .unavailable
            AppLogger.error(
                "Rewarded ad failed to load",
                category: .ads,
                metadata: ["error": error.localizedDescription]
            )
            scheduleRetry(adUnitID: adUnitID)
            return .unavailable
        }
    }

    func show(adUnitID: String) async -> RewardedAdShowResult {
        guard activeContinuation == nil else {
            AppLogger.warning(
                "Rewarded ad show skipped because another rewarded ad is active",
                category: .ads
            )
            return .unavailable
        }

        let loadState = await prepareForPresentation(adUnitID: adUnitID)
        guard loadState == .ready,
              let ad = preparedAd else {
            AppLogger.warning(
                "Rewarded ad show unavailable after preparation",
                category: .ads,
                metadata: ["loadState": loadState.rawValue]
            )
            return .unavailable
        }

        guard let rootViewController = await waitForTopViewController() else {
            AppLogger.warning(
                "Rewarded ad show unavailable because root view controller is missing",
                category: .ads
            )
            lastKnownState = .unavailable
            return .unavailable
        }

        AppLogger.info("Rewarded ad presenting", category: .ads)
        retryWorkItem?.cancel()
        retryWorkItem = nil
        retryCount = 0
        isWaitingForRetry = false
        preparedAd = nil
        preparedAdUnitID = ""
        activeAd = ad
        didEarnReward = false
        lastKnownState = .loading

        return await withCheckedContinuation { continuation in
            activeContinuation = continuation
            ad.present(from: rootViewController) { [weak self] in
                Task { @MainActor [weak self] in
                    AppLogger.info("Rewarded ad reward earned", category: .ads)
                    self?.didEarnReward = true
                }
            }
        }
        ? .earnedReward : .closedWithoutReward
    }

    private func prepareForPresentation(adUnitID: String) async -> AdLoadState {
        let retryDelays: [UInt64] = [0, 350_000_000, 900_000_000]
        var latestState = await currentState(adUnitID: adUnitID)
        if latestState == .ready {
            return .ready
        }

        for (index, delay) in retryDelays.enumerated() {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }

            latestState = await loadIfNeeded(adUnitID: adUnitID)
            if latestState == .ready {
                return .ready
            }

            if latestState == .loading {
                latestState = await waitForReadyState(adUnitID: adUnitID)
                if latestState == .ready {
                    return .ready
                }
            }

            AppLogger.warning(
                "Rewarded ad not ready after load attempt",
                category: .ads,
                metadata: [
                    "attempt": "\(index + 1)",
                    "loadState": latestState.rawValue
                ]
            )
        }

        return latestState
    }

    private func waitForReadyState(adUnitID: String) async -> AdLoadState {
        for _ in 0..<10 {
            let current = await currentState(adUnitID: adUnitID)
            if current != .loading {
                return current
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return await currentState(adUnitID: adUnitID)
    }

    private func scheduleRetry(adUnitID: String) {
        guard !adUnitID.isEmpty,
              retryCount < 6 else {
            return
        }
        retryWorkItem?.cancel()
        retryCount += 1
        isWaitingForRetry = true
        lastKnownState = .loading
        let delay = min(120, 15 * retryCount)
        AppLogger.warning(
            "Rewarded ad retry scheduled",
            category: .ads,
            metadata: [
                "retry": "\(retryCount)",
                "delaySeconds": "\(delay)",
                "adUnit": adUnitID
            ]
        )
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isWaitingForRetry = false
                _ = await self.loadIfNeeded(adUnitID: adUnitID)
            }
        }
        retryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay), execute: workItem)
    }

    private func waitForTopViewController() async -> UIViewController? {
        for attempt in 0..<10 {
            if let controller = AdMobRootViewControllerProvider.topViewController() {
                return controller
            }
            AppLogger.warning(
                "Rewarded ad root view controller missing; retrying",
                category: .ads,
                metadata: ["attempt": "\(attempt + 1)"]
            )
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return AdMobRootViewControllerProvider.topViewController()
    }

    private func finishCurrentPresentation(allowed: Bool) {
        guard let continuation = activeContinuation else {
            activeAd = nil
            didEarnReward = false
            return
        }

        activeContinuation = nil
        activeAd = nil
        didEarnReward = false
        continuation.resume(returning: allowed)
    }

    private func isCurrentPresentation(_ ad: any FullScreenPresentingAd) -> Bool {
        guard let activeAd else {
            return false
        }
        return (activeAd as AnyObject) === (ad as AnyObject)
    }

    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        guard isCurrentPresentation(ad) else { return }
        let didComplete = didEarnReward
        AppLogger.info(
            "Rewarded ad dismissed",
            category: .ads,
            metadata: ["earned": "\(didComplete)"]
        )
        lastKnownState = .idle
        finishCurrentPresentation(allowed: didComplete)
        Task { @MainActor in
            await loadIfNeeded(adUnitID: AdMobRuntimeConfiguration.current().rewardedSaveAdUnitID)
        }
    }

    func ad(
        _ ad: any FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: any Error
    ) {
        guard isCurrentPresentation(ad) else { return }
        AppLogger.error(
            "Rewarded ad failed to present",
            category: .ads,
            metadata: ["error": error.localizedDescription]
        )
        lastKnownState = .unavailable
        finishCurrentPresentation(allowed: false)
        Task { @MainActor in
            await loadIfNeeded(adUnitID: AdMobRuntimeConfiguration.current().rewardedSaveAdUnitID)
        }
    }
}

@MainActor
final class AdMobInterstitialAdManager: NSObject, FullScreenContentDelegate {
    static let shared = AdMobInterstitialAdManager()

    private var preparedAd: InterstitialAd?
    private var preparedAdUnitID = ""
    private var isLoading = false
    private var isShowing = false

    func loadIfNeeded(adUnitID: String) async -> AdLoadState {
        guard !adUnitID.isEmpty else {
            AppLogger.warning("Interstitial ad load skipped because ad unit is empty", category: .ads)
            return .unavailable
        }
        if preparedAd != nil, preparedAdUnitID == adUnitID {
            AppLogger.debug("Interstitial ad already ready", category: .ads)
            return .ready
        }
        guard !isLoading else {
            AppLogger.debug("Interstitial ad already loading", category: .ads)
            return .loading
        }

        isLoading = true
        defer { isLoading = false }

        do {
            AppLogger.info("Interstitial ad load requested", category: .ads, metadata: ["adUnit": adUnitID])
            let ad = try await InterstitialAd.load(
                with: adUnitID,
                request: AdMobRequestFactory.makeRequest()
            )
            ad.fullScreenContentDelegate = self
            preparedAd = ad
            preparedAdUnitID = adUnitID
            AppLogger.info("Interstitial ad loaded", category: .ads)
            return .ready
        } catch {
            preparedAd = nil
            preparedAdUnitID = ""
            AppLogger.error(
                "Interstitial ad failed to load",
                category: .ads,
                metadata: ["error": error.localizedDescription]
            )
            return .unavailable
        }
    }

    func showIfAvailable(adUnitID: String, reason: SessionEndAdReason) async {
        guard !isShowing else {
            AppLogger.info("Interstitial ad show skipped because another ad is showing", category: .ads)
            return
        }

        if preparedAd == nil || preparedAdUnitID != adUnitID {
            _ = await loadIfNeeded(adUnitID: adUnitID)
        }

        guard let ad = preparedAd,
              let rootViewController = AdMobRootViewControllerProvider.topViewController() else {
            AppLogger.warning(
                "Interstitial ad show unavailable",
                category: .ads,
                metadata: ["reason": reason.rawValue]
            )
            return
        }

        AppLogger.info(
            "Interstitial ad presenting",
            category: .ads,
            metadata: ["reason": reason.rawValue]
        )
        preparedAd = nil
        preparedAdUnitID = ""
        isShowing = true
        ad.fullScreenContentDelegate = self
        ad.present(from: rootViewController)
    }

    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        AppLogger.info("Interstitial ad dismissed", category: .ads)
        isShowing = false
        preparedAd = nil
        preparedAdUnitID = ""
        Task { @MainActor in
            await loadIfNeeded(adUnitID: AdMobRuntimeConfiguration.current().sessionEndInterstitialAdUnitID)
        }
    }

    func ad(
        _ ad: any FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: any Error
    ) {
        AppLogger.error(
            "Interstitial ad failed to present",
            category: .ads,
            metadata: ["error": error.localizedDescription]
        )
        isShowing = false
        preparedAd = nil
        preparedAdUnitID = ""
        Task { @MainActor in
            await loadIfNeeded(adUnitID: AdMobRuntimeConfiguration.current().sessionEndInterstitialAdUnitID)
        }
    }
}

@MainActor
final class AdMobAppOpenAdManager: NSObject, FullScreenContentDelegate {
    static let shared = AdMobAppOpenAdManager()

    private var appOpenAd: AppOpenAd?
    private var appOpenAdUnitID = ""
    private var isLoading = false
    private var isShowing = false
    private var loadTime: Date?
    private let timeoutInterval: TimeInterval = 4 * 3_600

    func loadIfNeeded(adUnitID: String) async {
        guard !adUnitID.isEmpty,
              !isLoading,
              !isAdAvailable(for: adUnitID) else {
            AppLogger.debug("App open ad load skipped", category: .ads)
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            AppLogger.info("App open ad load requested", category: .ads, metadata: ["adUnit": adUnitID])
            let ad = try await AppOpenAd.load(
                with: adUnitID,
                request: AdMobRequestFactory.makeRequest()
            )
            ad.fullScreenContentDelegate = self
            appOpenAd = ad
            appOpenAdUnitID = adUnitID
            loadTime = Date()
            AppLogger.info("App open ad loaded", category: .ads)
        } catch {
            appOpenAd = nil
            appOpenAdUnitID = ""
            loadTime = nil
            AppLogger.error(
                "App open ad failed to load",
                category: .ads,
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    func showIfAvailable(adUnitID: String) async {
        guard !isShowing else {
            AppLogger.info("App open ad show skipped because another app open ad is showing", category: .ads)
            return
        }

        if isLoading {
            await waitForCurrentLoad(adUnitID: adUnitID)
        }

        if !isAdAvailable(for: adUnitID) {
            await loadIfNeeded(adUnitID: adUnitID)
        }

        guard let appOpenAd,
              isAdAvailable(for: adUnitID),
              let rootViewController = AdMobRootViewControllerProvider.topViewController() else {
            AppLogger.warning("App open ad show unavailable", category: .ads)
            return
        }

        AppLogger.info("App open ad presenting", category: .ads)
        self.appOpenAd = nil
        appOpenAdUnitID = ""
        loadTime = nil
        isShowing = true
        appOpenAd.fullScreenContentDelegate = self
        appOpenAd.present(from: rootViewController)
    }

    private func waitForCurrentLoad(adUnitID: String) async {
        for _ in 0..<20 {
            if isAdAvailable(for: adUnitID) || !isLoading {
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func isAdAvailable(for adUnitID: String) -> Bool {
        guard appOpenAd != nil,
              appOpenAdUnitID == adUnitID,
              let loadTime else {
            return false
        }
        return Date().timeIntervalSince(loadTime) < timeoutInterval
    }

    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        AppLogger.info("App open ad dismissed", category: .ads)
        isShowing = false
        Task { @MainActor in
            await loadIfNeeded(adUnitID: AdMobRuntimeConfiguration.current().appOpenAdUnitID)
        }
    }

    func ad(
        _ ad: any FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: any Error
    ) {
        AppLogger.error(
            "App open ad failed to present",
            category: .ads,
            metadata: ["error": error.localizedDescription]
        )
        isShowing = false
        Task { @MainActor in
            await loadIfNeeded(adUnitID: AdMobRuntimeConfiguration.current().appOpenAdUnitID)
        }
    }
}
#endif
