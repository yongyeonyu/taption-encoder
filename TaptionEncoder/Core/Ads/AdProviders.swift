import Foundation
import SwiftUI
#if canImport(GoogleMobileAds)
import GoogleMobileAds
import UIKit
#endif
#if canImport(UserMessagingPlatform)
import UserMessagingPlatform
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

protocol NativeAdProviding {
    var nativeAdUnitID: String { get }
    func currentNativeState() async -> AdLoadState
}

protocol RewardedAdProviding {
    func currentRewardedState() async -> AdLoadState
    func preloadRewardedAd() async -> AdLoadState
    func retryRewardedAdNow() async -> AdLoadState
    func showRewardedAd() async -> RewardedAdShowResult
}

extension RewardedAdProviding {
    func preloadRewardedAd() async -> AdLoadState {
        await currentRewardedState()
    }

    func retryRewardedAdNow() async -> AdLoadState {
        await preloadRewardedAd()
    }
}

protocol SessionEndAdProviding {
    func preloadSessionEndAd() async
    func showSessionEndAd(reason: SessionEndAdReason) async
}

struct AdMobRuntimeConfiguration: Equatable, Sendable {
    static let infoDictionaryAppOpenAdUnitIDKey = "TaptionAppOpenAdUnitID"
    static let infoDictionaryHomeBannerAdUnitIDKey = "TaptionHomeBannerAdUnitID"
    static let infoDictionaryNativeAdUnitIDKey = "TaptionNativeAdUnitID"
    static let infoDictionaryRewardedSaveAdUnitIDKey = "TaptionRewardedSaveAdUnitID"
    static let infoDictionarySessionEndInterstitialAdUnitIDKey = "TaptionSessionEndInterstitialAdUnitID"
    static let googleDemoAdUnitPrefix = "ca-app-pub-3940256099942544/"

    private static let productionAppOpenAdUnitID = "ca-app-pub-9754025737691277/9568683076"
    private static let productionHomeBannerAdUnitID = "ca-app-pub-9754025737691277/6794641076"
    private static let productionNativeAdUnitID = ""
    private static let productionRewardedSaveAdUnitID = "ca-app-pub-9754025737691277/2855396062"
    private static let productionSessionEndInterstitialAdUnitID = "ca-app-pub-9754025737691277/6942519738"

    let appOpenAdUnitID: String
    let homeBannerAdUnitID: String
    let nativeAdUnitID: String
    let rewardedSaveAdUnitID: String
    let sessionEndInterstitialAdUnitID: String

    static func current(bundle: Bundle = .main) -> AdMobRuntimeConfiguration {
        #if DEBUG
        AdMobRuntimeConfiguration(
            appOpenAdUnitID: "ca-app-pub-3940256099942544/5575463023",
            homeBannerAdUnitID: "ca-app-pub-3940256099942544/2934735716",
            nativeAdUnitID: "ca-app-pub-3940256099942544/3986624511",
            rewardedSaveAdUnitID: "ca-app-pub-3940256099942544/1712485313",
            sessionEndInterstitialAdUnitID: "ca-app-pub-3940256099942544/4411468910"
        )
        #else
        productionConfiguration(
            appOpenAdUnitID: bundle.object(forInfoDictionaryKey: infoDictionaryAppOpenAdUnitIDKey) as? String,
            homeBannerAdUnitID: bundle.object(forInfoDictionaryKey: infoDictionaryHomeBannerAdUnitIDKey) as? String,
            nativeAdUnitID: bundle.object(forInfoDictionaryKey: infoDictionaryNativeAdUnitIDKey) as? String,
            rewardedSaveAdUnitID: bundle.object(forInfoDictionaryKey: infoDictionaryRewardedSaveAdUnitIDKey) as? String,
            sessionEndInterstitialAdUnitID: bundle.object(forInfoDictionaryKey: infoDictionarySessionEndInterstitialAdUnitIDKey) as? String
        )
        #endif
    }

    static func productionConfiguration(
        appOpenAdUnitID: String?,
        homeBannerAdUnitID: String?,
        nativeAdUnitID: String? = nil,
        rewardedSaveAdUnitID: String?,
        sessionEndInterstitialAdUnitID: String?
    ) -> AdMobRuntimeConfiguration {
        AdMobRuntimeConfiguration(
            appOpenAdUnitID: productionAdUnitID(
                appOpenAdUnitID,
                fallback: productionAppOpenAdUnitID
            ),
            homeBannerAdUnitID: productionAdUnitID(
                homeBannerAdUnitID,
                fallback: productionHomeBannerAdUnitID
            ),
            nativeAdUnitID: productionAdUnitID(
                nativeAdUnitID,
                fallback: productionNativeAdUnitID
            ),
            rewardedSaveAdUnitID: productionAdUnitID(
                rewardedSaveAdUnitID,
                fallback: productionRewardedSaveAdUnitID
            ),
            sessionEndInterstitialAdUnitID: productionAdUnitID(
                sessionEndInterstitialAdUnitID,
                fallback: productionSessionEndInterstitialAdUnitID
            )
        )
    }

    private static func productionAdUnitID(_ value: String?, fallback: String) -> String {
        guard let normalized = normalizedString(value),
              !normalized.hasPrefix(googleDemoAdUnitPrefix) else {
            return fallback
        }
        return normalized
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum AdPlacementKind: String, CaseIterable, Codable, Hashable, Sendable {
    case appOpen
    case homeBanner
    case nativeIdle
    case nativeCompleted
    case rewardedSave
    case startInterstitial
    case sessionEndInterstitial
}

struct AdPlacementPolicy: Equatable, Sendable {
    static let overrideJSONKey = "TaptionAdPlacementPolicyJSON"

    var disabledPlacements: Set<AdPlacementKind>
    var minimumIntervals: [AdPlacementKind: TimeInterval]

    init(
        disabledPlacements: Set<AdPlacementKind> = [],
        minimumIntervals: [AdPlacementKind: TimeInterval] = Self.defaultMinimumIntervals
    ) {
        self.disabledPlacements = disabledPlacements
        self.minimumIntervals = minimumIntervals
    }

    static let defaultMinimumIntervals: [AdPlacementKind: TimeInterval] = [
        .appOpen: 15 * 60,
        .startInterstitial: 10 * 60,
        .sessionEndInterstitial: 8 * 60
    ]

    static let defaultPolicy = AdPlacementPolicy()

    static func current(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) -> AdPlacementPolicy {
        if let json = defaults.string(forKey: overrideJSONKey),
           let decoded = decode(jsonString: json) {
            return decoded
        }
        if let json = bundle.object(forInfoDictionaryKey: overrideJSONKey) as? String,
           let decoded = decode(jsonString: json) {
            return decoded
        }
        return defaultPolicy
    }

    static func decode(jsonString: String) -> AdPlacementPolicy? {
        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(AdPlacementPolicyPayload.self, from: data).policy
    }

    func isEnabled(_ placement: AdPlacementKind) -> Bool {
        !disabledPlacements.contains(placement)
    }

    func minimumInterval(for placement: AdPlacementKind) -> TimeInterval? {
        minimumIntervals[placement]
    }
}

private struct AdPlacementPolicyPayload: Decodable {
    var enabledPlacements: [AdPlacementKind]?
    var disabledPlacements: [AdPlacementKind]?
    var minimumIntervals: [String: TimeInterval]?

    var policy: AdPlacementPolicy {
        let disabled: Set<AdPlacementKind>
        if let enabledPlacements {
            disabled = Set(AdPlacementKind.allCases).subtracting(enabledPlacements)
        } else {
            disabled = Set(disabledPlacements ?? [])
        }

        var intervals = AdPlacementPolicy.defaultMinimumIntervals
        for (key, value) in minimumIntervals ?? [:] {
            guard let placement = AdPlacementKind(rawValue: key) else {
                continue
            }
            intervals[placement] = max(0, value)
        }

        return AdPlacementPolicy(
            disabledPlacements: disabled,
            minimumIntervals: intervals
        )
    }
}

@MainActor
final class AdPlacementFrequencyLimiter {
    static let shared = AdPlacementFrequencyLimiter()

    private var lastPresentationDates: [AdPlacementKind: Date] = [:]

    private init() {}

    func canPresent(
        _ placement: AdPlacementKind,
        now: Date = Date(),
        policy: AdPlacementPolicy = .current()
    ) -> Bool {
        guard policy.isEnabled(placement) else {
            return false
        }
        guard let minimumInterval = policy.minimumInterval(for: placement),
              let lastPresentationDate = lastPresentationDates[placement] else {
            return true
        }
        return now.timeIntervalSince(lastPresentationDate) >= minimumInterval
    }

    func recordPresentation(_ placement: AdPlacementKind, now: Date = Date()) {
        lastPresentationDates[placement] = now
    }

    func reset() {
        lastPresentationDates.removeAll()
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

struct FakeNativeAdProvider: NativeAdProviding {
    var nativeAdUnitID: String {
        "test.native"
    }

    func currentNativeState() async -> AdLoadState {
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
        AdPlacementPolicy.current().isEnabled(.homeBanner) ? configuration.homeBannerAdUnitID : ""
    }

    func currentBannerState() async -> AdLoadState {
        bannerAdUnitID.isEmpty ? .unavailable : .ready
    }
}

struct AdMobNativeAdProvider: NativeAdProviding {
    let configuration: AdMobRuntimeConfiguration

    init(configuration: AdMobRuntimeConfiguration = .current()) {
        self.configuration = configuration
    }

    var nativeAdUnitID: String {
        configuration.nativeAdUnitID
    }

    func currentNativeState() async -> AdLoadState {
        configuration.nativeAdUnitID.isEmpty ? .unavailable : .ready
    }
}

struct AdMobRewardedAdProvider: RewardedAdProviding {
    let configuration: AdMobRuntimeConfiguration

    init(configuration: AdMobRuntimeConfiguration = .current()) {
        self.configuration = configuration
    }

    func currentRewardedState() async -> AdLoadState {
        guard AdPlacementPolicy.current().isEnabled(.rewardedSave) else {
            return .unavailable
        }
        #if canImport(GoogleMobileAds)
        return await AdMobRewardedAdManager.shared.currentState(
            adUnitID: configuration.rewardedSaveAdUnitID
        )
        #else
        return .unavailable
        #endif
    }

    func preloadRewardedAd() async -> AdLoadState {
        guard AdPlacementPolicy.current().isEnabled(.rewardedSave) else {
            return .unavailable
        }
        #if canImport(GoogleMobileAds)
        if await AdMobBootstrapper.shouldSkipNonBannerAdRequest(placement: "rewarded", action: "preload") {
            return .unavailable
        }
        guard await AdMobBootstrapper.ensureReadyForAds() else {
            return .unavailable
        }
        return await AdMobRewardedAdManager.shared.loadIfNeeded(
            adUnitID: configuration.rewardedSaveAdUnitID
        )
        #else
        return .unavailable
        #endif
    }

    func retryRewardedAdNow() async -> AdLoadState {
        guard AdPlacementPolicy.current().isEnabled(.rewardedSave) else {
            return .unavailable
        }
        #if canImport(GoogleMobileAds)
        if await AdMobBootstrapper.shouldSkipNonBannerAdRequest(placement: "rewarded", action: "retry") {
            return .unavailable
        }
        guard await AdMobBootstrapper.ensureReadyForAds() else {
            return .unavailable
        }
        return await AdMobRewardedAdManager.shared.loadIfNeeded(
            adUnitID: configuration.rewardedSaveAdUnitID,
            bypassScheduledRetry: true
        )
        #else
        return .unavailable
        #endif
    }

    func showRewardedAd() async -> RewardedAdShowResult {
        guard AdPlacementPolicy.current().isEnabled(.rewardedSave) else {
            return .unavailable
        }
        #if canImport(GoogleMobileAds)
        if await AdMobBootstrapper.shouldSkipNonBannerAdRequest(placement: "rewarded", action: "show") {
            return .unavailable
        }
        guard await AdMobBootstrapper.ensureReadyForAds() else {
            return .unavailable
        }
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
        let policy = AdPlacementPolicy.current()
        guard policy.isEnabled(.startInterstitial) || policy.isEnabled(.sessionEndInterstitial) else {
            return
        }
        if await AdMobBootstrapper.shouldSkipNonBannerAdRequest(placement: "interstitial", action: "preload") {
            return
        }
        guard await AdMobBootstrapper.ensureReadyForAds() else {
            return
        }
        _ = await AdMobInterstitialAdManager.shared.loadIfNeeded(adUnitID: configuration.sessionEndInterstitialAdUnitID)
        #endif
    }

    func showSessionEndAd(reason: SessionEndAdReason) async {
        #if canImport(GoogleMobileAds)
        let placement = adPlacement(for: reason)
        let policy = AdPlacementPolicy.current()
        guard await AdPlacementFrequencyLimiter.shared.canPresent(
            placement,
            policy: policy
        ) else {
            AppLogger.info(
                "Interstitial ad skipped by placement policy",
                category: .ads,
                metadata: ["placement": placement.rawValue]
            )
            return
        }
        if await AdMobBootstrapper.shouldSkipNonBannerAdRequest(placement: "interstitial", action: "show") {
            return
        }
        guard await AdMobBootstrapper.ensureReadyForAds() else {
            return
        }
        let didPresent = await AdMobInterstitialAdManager.shared.showIfAvailable(
            adUnitID: configuration.sessionEndInterstitialAdUnitID,
            reason: reason
        )
        if didPresent {
            await AdPlacementFrequencyLimiter.shared.recordPresentation(placement)
        }
        #endif
    }

    private func adPlacement(for reason: SessionEndAdReason) -> AdPlacementKind {
        switch reason {
        case .startingEncoding:
            return .startInterstitial
        case .completedSave, .cancelledEncoding, .failedEncoding:
            return .sessionEndInterstitial
        }
    }
}

#if canImport(GoogleMobileAds)
@MainActor
final class AdMobConsentManager {
    static let shared = AdMobConsentManager()

    private(set) var canRequestAds = false
    private(set) var lastErrorDescription: String?

    private var didRequestConsentInfo = false
    private var didStartMobileAds = false
    private var isUpdatingConsentInfo = false
    private var isPresentingConsentForm = false
    private var shouldRetryConsentFormPresentation = false

    private init() {}

    func refreshConsentStatusIfNeeded() {
        guard !didRequestConsentInfo else {
            retryConsentFormPresentationIfNeeded()
            startMobileAdsIfAllowed()
            return
        }
        didRequestConsentInfo = true
        refreshConsentStatus()
    }

    func refreshConsentStatus() {
        #if canImport(UserMessagingPlatform)
        guard !isUpdatingConsentInfo else {
            return
        }
        isUpdatingConsentInfo = true
        lastErrorDescription = nil
        let parameters = RequestParameters()
        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.isUpdatingConsentInfo = false
                if let error {
                    self.lastErrorDescription = error.localizedDescription
                    self.canRequestAds = true
                    self.shouldRetryConsentFormPresentation = false
                    AppLogger.warning(
                        "AdMob consent update failed; continuing ad startup",
                        category: .ads,
                        metadata: ["error": error.localizedDescription]
                    )
                    self.startMobileAdsIfAllowed()
                    return
                }

                self.updateConsentState()
                self.startMobileAdsIfAllowed()
                await self.loadAndPresentConsentFormIfRequired()
                self.updateConsentState()
                self.startMobileAdsIfAllowed()
            }
        }
        #else
        canRequestAds = true
        startMobileAdsIfAllowed()
        #endif
    }

    func waitForMobileAdsStartup(timeoutSeconds: TimeInterval = 2.5) async -> Bool {
        refreshConsentStatusIfNeeded()
        let deadline = Date().addingTimeInterval(max(0, timeoutSeconds))
        let pollIntervalNanos: UInt64 = 100_000_000

        while Date() < deadline {
            if didStartMobileAds {
                return true
            }
            retryConsentFormPresentationIfNeeded()
            if canRequestAds {
                startMobileAdsIfAllowed()
                if didStartMobileAds {
                    return true
                }
            }
            do {
                try await Task.sleep(nanoseconds: pollIntervalNanos)
            } catch {
                break
            }
        }

        startMobileAdsIfAllowed()
        return didStartMobileAds
    }

    func presentPrivacyOptionsIfAvailable() async -> Bool {
        #if canImport(UserMessagingPlatform)
        refreshConsentStatusIfNeeded()
        do {
            try await ConsentForm.presentPrivacyOptionsForm(
                from: AdMobRootViewControllerProvider.topViewController()
            )
            updateConsentState()
            startMobileAdsIfAllowed()
            AppLogger.info("AdMob privacy options form presented", category: .ads)
            return true
        } catch {
            lastErrorDescription = error.localizedDescription
            AppLogger.warning(
                "AdMob privacy options form unavailable",
                category: .ads,
                metadata: ["error": error.localizedDescription]
            )
            return false
        }
        #else
        return false
        #endif
    }

    var privacyOptionsStatusText: String {
        #if canImport(UserMessagingPlatform)
        switch ConsentInformation.shared.privacyOptionsRequirementStatus {
        case .required:
            return "Required"
        case .notRequired:
            return "Not required"
        case .unknown:
            return "Checking"
        @unknown default:
            return "Checking"
        }
        #else
        return "Unavailable"
        #endif
    }

    var consentStatusText: String {
        #if canImport(UserMessagingPlatform)
        switch ConsentInformation.shared.consentStatus {
        case .required:
            return "Required"
        case .notRequired:
            return "Not required"
        case .obtained:
            return "Obtained"
        case .unknown:
            return "Checking"
        @unknown default:
            return "Checking"
        }
        #else
        return "Unavailable"
        #endif
    }

    private func loadAndPresentConsentFormIfRequired() async {
        #if canImport(UserMessagingPlatform)
        guard !isPresentingConsentForm else {
            return
        }
        if !canRequestAds,
           AdMobRootViewControllerProvider.topViewController() == nil {
            shouldRetryConsentFormPresentation = true
            AppLogger.warning("AdMob consent form root missing; will retry", category: .ads)
            return
        }

        isPresentingConsentForm = true
        defer { isPresentingConsentForm = false }

        do {
            try await ConsentForm.loadAndPresentIfRequired(
                from: AdMobRootViewControllerProvider.topViewController()
            )
            shouldRetryConsentFormPresentation = false
        } catch {
            lastErrorDescription = error.localizedDescription
            shouldRetryConsentFormPresentation = !ConsentInformation.shared.canRequestAds
            AppLogger.warning(
                "AdMob consent form presentation failed",
                category: .ads,
                metadata: [
                    "canRequestAds": "\(ConsentInformation.shared.canRequestAds)",
                    "error": error.localizedDescription
                ]
            )
        }
        #endif
    }

    private func retryConsentFormPresentationIfNeeded() {
        #if canImport(UserMessagingPlatform)
        guard shouldRetryConsentFormPresentation,
              !canRequestAds,
              !isPresentingConsentForm,
              AdMobRootViewControllerProvider.topViewController() != nil else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.loadAndPresentConsentFormIfRequired()
            self.updateConsentState()
            self.startMobileAdsIfAllowed()
        }
        #endif
    }

    private func updateConsentState() {
        #if canImport(UserMessagingPlatform)
        canRequestAds = ConsentInformation.shared.canRequestAds
        #else
        canRequestAds = true
        #endif
    }

    private func startMobileAdsIfAllowed() {
        guard canRequestAds, !didStartMobileAds else {
            return
        }
        didStartMobileAds = true
        MobileAds.shared.start()
        AppLogger.info("AdMob SDK started after consent gate", category: .ads)
    }
}
#endif

enum AdMobBootstrapper {
    @MainActor
    private static var appOpenAdSuppressedUntil: Date?
    @MainActor
    private static var activeVideoPlaybackSuppressionCount = 0
    @MainActor
    private static var activeCriticalFlowSuppressionCount = 0

    static func start() {
        #if canImport(GoogleMobileAds)
        AppLogger.info("AdMob bootstrap started", category: .ads)
        #else
        AppLogger.warning("AdMob bootstrap skipped because GoogleMobileAds is not linked", category: .ads)
        #endif
    }

    static func refreshOnActive() async {
        #if canImport(GoogleMobileAds)
        AppLogger.info("AdMob refresh requested for active scene", category: .ads)
        if await shouldSkipNonBannerAdRequest(placement: "allNonBanner", action: "refreshOnActive") {
            return
        }
        guard await ensureReadyForAds() else {
            return
        }
        await preloadAllPlacements()
        #endif
    }

    @MainActor
    static func suppressAppOpenAdsForExternalPlayback(seconds: TimeInterval = 20) {
        appOpenAdSuppressedUntil = Date().addingTimeInterval(seconds)
        AppLogger.info(
            "App open ads suppressed for external playback",
            category: .ads,
            metadata: ["seconds": String(format: "%.0f", seconds)]
        )
    }

    @MainActor
    static func beginVideoPlaybackAdSuppression(reason: String) {
        activeVideoPlaybackSuppressionCount += 1
        AppLogger.info(
            "Full-screen ads suppressed during video playback",
            category: .ads,
            metadata: [
                "reason": reason,
                "count": "\(activeVideoPlaybackSuppressionCount)"
            ]
        )
    }

    @MainActor
    static func beginFullScreenAdSuppression(reason: String) {
        activeCriticalFlowSuppressionCount += 1
        AppLogger.info(
            "Full-screen ads suppressed during critical flow",
            category: .ads,
            metadata: [
                "reason": reason,
                "count": "\(activeCriticalFlowSuppressionCount)"
            ]
        )
    }

    @MainActor
    static func endFullScreenAdSuppression(reason: String) {
        activeCriticalFlowSuppressionCount = max(activeCriticalFlowSuppressionCount - 1, 0)
        AppLogger.info(
            "Critical flow ad suppression released",
            category: .ads,
            metadata: [
                "reason": reason,
                "count": "\(activeCriticalFlowSuppressionCount)"
            ]
        )
    }

    @MainActor
    static func endVideoPlaybackAdSuppression(reason: String) {
        activeVideoPlaybackSuppressionCount = max(activeVideoPlaybackSuppressionCount - 1, 0)
        AppLogger.info(
            "Video playback ad suppression released",
            category: .ads,
            metadata: [
                "reason": reason,
                "count": "\(activeVideoPlaybackSuppressionCount)"
            ]
        )
    }

    @MainActor
    static func shouldSkipNonBannerAdRequest(placement: String, action: String) -> Bool {
        let suppressionCount = activeVideoPlaybackSuppressionCount + activeCriticalFlowSuppressionCount
        guard suppressionCount > 0 else {
            return false
        }
        AppLogger.info(
            "Non-banner ad request skipped during protected app flow",
            category: .ads,
            metadata: [
                "placement": placement,
                "action": action,
                "count": "\(suppressionCount)"
            ]
        )
        return true
    }

    static func showAppOpenAdIfAvailable() async {
        #if canImport(GoogleMobileAds)
        let policy = AdPlacementPolicy.current()
        guard await AdPlacementFrequencyLimiter.shared.canPresent(.appOpen, policy: policy) else {
            AppLogger.info("App open ad skipped by placement policy", category: .ads)
            return
        }
        if await shouldSkipNonBannerAdRequest(placement: "appOpen", action: "showAppOpen") {
            return
        }
        if await isAppOpenAdSuppressed {
            AppLogger.info("App open ad skipped for external playback", category: .ads)
            return
        }
        let configuration = AdMobRuntimeConfiguration.current()
        guard !configuration.appOpenAdUnitID.isEmpty,
              await ensureReadyForAds() else {
            return
        }
        AppLogger.info("App open ad show requested", category: .ads)
        let didPresent = await AdMobAppOpenAdManager.shared.showIfAvailable(adUnitID: configuration.appOpenAdUnitID)
        if didPresent {
            await AdPlacementFrequencyLimiter.shared.recordPresentation(.appOpen)
        }
        #endif
    }

    @MainActor
    private static var isAppOpenAdSuppressed: Bool {
        if activeVideoPlaybackSuppressionCount + activeCriticalFlowSuppressionCount > 0 {
            return true
        }
        guard let until = appOpenAdSuppressedUntil else {
            return false
        }
        if until > Date() {
            return true
        }
        appOpenAdSuppressedUntil = nil
        return false
    }

    #if canImport(GoogleMobileAds)
    @MainActor
    static func ensureReadyForAds(timeoutSeconds: TimeInterval = 6.0) async -> Bool {
        AdMobConsentManager.shared.refreshConsentStatusIfNeeded()
        let isReady = await AdMobConsentManager.shared.waitForMobileAdsStartup(
            timeoutSeconds: timeoutSeconds
        )
        if !isReady {
            AppLogger.warning("AdMob startup gate timed out", category: .ads)
        }
        return isReady
    }

    @MainActor
    private static func preloadAllPlacements() async {
        guard !shouldSkipNonBannerAdRequest(placement: "allNonBanner", action: "preload") else {
            return
        }
        let configuration = AdMobRuntimeConfiguration.current()
        let policy = AdPlacementPolicy.current()
        AppLogger.info(
            "AdMob preload started",
            category: .ads,
            metadata: [
                "appOpen": configuration.appOpenAdUnitID,
                "banner": configuration.homeBannerAdUnitID,
                "native": configuration.nativeAdUnitID,
                "rewarded": configuration.rewardedSaveAdUnitID,
                "interstitial": configuration.sessionEndInterstitialAdUnitID
            ]
        )
        if policy.isEnabled(.appOpen),
           !configuration.appOpenAdUnitID.isEmpty {
            await AdMobAppOpenAdManager.shared.loadIfNeeded(adUnitID: configuration.appOpenAdUnitID)
        }
        if policy.isEnabled(.startInterstitial) || policy.isEnabled(.sessionEndInterstitial) {
            _ = await AdMobInterstitialAdManager.shared.loadIfNeeded(adUnitID: configuration.sessionEndInterstitialAdUnitID)
        }
        if policy.isEnabled(.rewardedSave) {
            _ = await AdMobRewardedAdManager.shared.loadIfNeeded(adUnitID: configuration.rewardedSaveAdUnitID)
        }
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

struct AdMobNativeAdSlotView: View {
    let adUnitID: String
    var displayScale: CGFloat = 1
    var title: String = "Sponsored"

    var body: some View {
        let clampedScale = min(max(displayScale, 0.72), 1)
        ZStack {
            nativeSlotPlaceholder
            #if canImport(GoogleMobileAds)
            AdMobNativeAdRepresentable(adUnitID: adUnitID)
                .frame(height: 76)
            #endif
        }
        .frame(maxWidth: .infinity, minHeight: 76 * clampedScale, maxHeight: 76 * clampedScale)
        .scaleEffect(clampedScale)
        .accessibilityLabel("Native ad")
    }

    private var nativeSlotPlaceholder: some View {
        HStack(spacing: 10) {
            Text("Ad")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.74))
                Text("Loading")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.black.opacity(0.54))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76)
        .background(Color.white.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(TaptionTheme.accent.opacity(0.45), lineWidth: 1)
        )
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

private enum AdMobErrorMetadata {
    static func make(error: Error, adUnitID: String? = nil) -> [String: String] {
        let nsError = error as NSError
        var metadata: [String: String] = [
            "error": error.localizedDescription,
            "domain": nsError.domain,
            "code": "\(nsError.code)"
        ]
        if let adUnitID, !adUnitID.isEmpty {
            metadata["adUnit"] = adUnitID
        }
        if !nsError.userInfo.isEmpty {
            metadata["userInfoKeys"] = nsError.userInfo.keys
                .map { String(describing: $0) }
                .sorted()
                .joined(separator: ",")
        }
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            metadata["underlyingDomain"] = underlyingError.domain
            metadata["underlyingCode"] = "\(underlyingError.code)"
            metadata["underlyingError"] = underlyingError.localizedDescription
        }
        return metadata
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

            guard AdMobConsentManager.shared.canRequestAds else {
                scheduleRetry(for: banner, adUnitID: adUnitID)
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
            guard retryCount < 60 else {
                AppLogger.warning(
                    "Banner ad load retry stopped while waiting for AdMob readiness",
                    category: .ads,
                    metadata: ["adUnit": adUnitID]
                )
                return
            }
            retryWorkItem?.cancel()
            retryCount += 1
            let workItem = DispatchWorkItem { [weak self, weak banner] in
                guard let self, let banner else { return }
                self.loadIfPossible(banner, adUnitID: adUnitID)
            }
            retryWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
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
            let adUnitID = loadedAdUnitID
            AppLogger.error(
                "Banner ad failed to load",
                category: .ads,
                metadata: AdMobErrorMetadata.make(error: error, adUnitID: adUnitID)
            )
            loadedAdUnitID = ""
            scheduleFillRetry(for: bannerView, adUnitID: adUnitID)
        }
    }
}

private struct AdMobNativeAdRepresentable: UIViewRepresentable {
    let adUnitID: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> NativeAdView {
        let view = NativeAdView()
        context.coordinator.configure(view)
        context.coordinator.loadIfPossible(adUnitID: adUnitID, into: view)
        return view
    }

    func updateUIView(_ view: NativeAdView, context: Context) {
        context.coordinator.configure(view)
        context.coordinator.loadIfPossible(adUnitID: adUnitID, into: view)
    }

    @MainActor
    final class Coordinator: NSObject, AdLoaderDelegate, NativeAdLoaderDelegate {
        private weak var nativeAdView: NativeAdView?
        private var loadedAdUnitID = ""
        private var adLoader: AdLoader?
        private var retryWorkItem: DispatchWorkItem?
        private var retryCount = 0

        private weak var headlineLabel: UILabel?
        private weak var bodyLabel: UILabel?
        private weak var callToActionButton: UIButton?
        private weak var advertiserLabel: UILabel?

        func configure(_ view: NativeAdView) {
            guard nativeAdView !== view else {
                return
            }

            view.subviews.forEach { $0.removeFromSuperview() }
            view.backgroundColor = UIColor.white.withAlphaComponent(0.96)
            view.layer.cornerRadius = 4
            view.clipsToBounds = true

            let adLabel = UILabel()
            adLabel.text = "Ad"
            adLabel.font = .systemFont(ofSize: 11, weight: .bold)
            adLabel.textAlignment = .center
            adLabel.textColor = .white
            adLabel.backgroundColor = UIColor.black.withAlphaComponent(0.72)
            adLabel.layer.cornerRadius = 4
            adLabel.clipsToBounds = true
            adLabel.translatesAutoresizingMaskIntoConstraints = false

            let headlineLabel = UILabel()
            headlineLabel.font = .systemFont(ofSize: 14, weight: .semibold)
            headlineLabel.textColor = UIColor.black.withAlphaComponent(0.82)
            headlineLabel.numberOfLines = 1

            let bodyLabel = UILabel()
            bodyLabel.font = .systemFont(ofSize: 11, weight: .medium)
            bodyLabel.textColor = UIColor.black.withAlphaComponent(0.58)
            bodyLabel.numberOfLines = 1

            let advertiserLabel = UILabel()
            advertiserLabel.font = .systemFont(ofSize: 10, weight: .medium)
            advertiserLabel.textColor = UIColor.black.withAlphaComponent(0.46)
            advertiserLabel.numberOfLines = 1

            let textStack = UIStackView(arrangedSubviews: [headlineLabel, bodyLabel, advertiserLabel])
            textStack.axis = .vertical
            textStack.spacing = 2
            textStack.alignment = .fill
            textStack.translatesAutoresizingMaskIntoConstraints = false

            let callToActionButton = UIButton(type: .system)
            callToActionButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
            var callToActionConfiguration = UIButton.Configuration.filled()
            callToActionConfiguration.baseForegroundColor = .white
            callToActionConfiguration.baseBackgroundColor = UIColor(red: 0.18, green: 0.55, blue: 1.0, alpha: 1)
            callToActionConfiguration.cornerStyle = .small
            callToActionConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)
            callToActionButton.configuration = callToActionConfiguration
            callToActionButton.clipsToBounds = true
            callToActionButton.isUserInteractionEnabled = false
            callToActionButton.translatesAutoresizingMaskIntoConstraints = false

            let row = UIStackView(arrangedSubviews: [adLabel, textStack, callToActionButton])
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 10
            row.translatesAutoresizingMaskIntoConstraints = false

            view.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
                row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
                row.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
                row.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
                adLabel.widthAnchor.constraint(equalToConstant: 32),
                adLabel.heightAnchor.constraint(equalToConstant: 24),
                callToActionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 70)
            ])

            view.headlineView = headlineLabel
            view.bodyView = bodyLabel
            view.callToActionView = callToActionButton
            view.advertiserView = advertiserLabel

            self.nativeAdView = view
            self.headlineLabel = headlineLabel
            self.bodyLabel = bodyLabel
            self.callToActionButton = callToActionButton
            self.advertiserLabel = advertiserLabel
        }

        func loadIfPossible(adUnitID: String, into view: NativeAdView) {
            nativeAdView = view

            guard !adUnitID.isEmpty else {
                AppLogger.warning("Native ad load skipped because ad unit is empty", category: .ads)
                return
            }

            guard AdMobConsentManager.shared.canRequestAds else {
                scheduleRetry(adUnitID: adUnitID)
                return
            }

            guard loadedAdUnitID != adUnitID else {
                return
            }

            guard let rootController = AdMobRootViewControllerProvider.topViewController() else {
                AppLogger.warning("Native ad root view controller missing; scheduling retry", category: .ads)
                scheduleRetry(adUnitID: adUnitID)
                return
            }

            loadedAdUnitID = adUnitID
            retryWorkItem?.cancel()
            retryWorkItem = nil
            retryCount = 0

            let loader = AdLoader(
                adUnitID: adUnitID,
                rootViewController: rootController,
                adTypes: [.native],
                options: nil
            )
            loader.delegate = self
            adLoader = loader
            AppLogger.info("Native ad load requested", category: .ads, metadata: ["adUnit": adUnitID])
            loader.load(AdMobRequestFactory.makeRequest())
        }

        func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
            guard let view = nativeAdView else {
                return
            }

            nativeAd.rootViewController = AdMobRootViewControllerProvider.topViewController()
            headlineLabel?.text = nativeAd.headline ?? "Sponsored"
            bodyLabel?.text = nativeAd.body ?? nativeAd.advertiser ?? "Recommended"
            advertiserLabel?.text = nativeAd.advertiser
            advertiserLabel?.isHidden = nativeAd.advertiser == nil
            callToActionButton?.setTitle(nativeAd.callToAction ?? "Open", for: .normal)
            view.nativeAd = nativeAd
            AppLogger.info("Native ad loaded", category: .ads)
        }

        func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
            AppLogger.error(
                "Native ad failed to load",
                category: .ads,
                metadata: AdMobErrorMetadata.make(error: error, adUnitID: loadedAdUnitID)
            )
            loadedAdUnitID = ""
            scheduleRetry(adUnitID: adLoader.adUnitID)
        }

        private func scheduleRetry(adUnitID: String) {
            guard retryCount < 12,
                  !adUnitID.isEmpty else {
                return
            }
            retryWorkItem?.cancel()
            retryCount += 1
            let delay = min(30, retryCount * 2)
            let workItem = DispatchWorkItem { [weak self] in
                guard let self,
                      let view = self.nativeAdView else {
                    return
                }
                self.loadIfPossible(adUnitID: adUnitID, into: view)
            }
            retryWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay), execute: workItem)
        }
    }
}

@MainActor
final class AdMobRewardedAdManager: NSObject, FullScreenContentDelegate {
    static let shared = AdMobRewardedAdManager()

    private struct PreparedRewardedAd {
        var ad: RewardedAd
        var adUnitID: String
        var loadedAt: Date
    }

    private let maxPreparedAdCount = 2
    private let preparedAdExpirationInterval: TimeInterval = 55 * 60
    private var preparedAds: [PreparedRewardedAd] = []
    private var activeAd: RewardedAd?
    private var activeContinuation: CheckedContinuation<Bool, Never>?
    private var didEarnReward = false
    private var isLoading = false
    private var lastKnownState: AdLoadState = .idle
    private var retryWorkItem: DispatchWorkItem?
    private var retryCount = 0
    private var isWaitingForRetry = false
    private var isCacheFillScheduled = false

    func currentState(adUnitID: String) async -> AdLoadState {
        guard !adUnitID.isEmpty else {
            return .unavailable
        }
        pruneExpiredPreparedAds()
        if hasPreparedAd(for: adUnitID) {
            return .ready
        }
        if isLoading {
            return .loading
        }
        if isWaitingForRetry {
            return lastKnownState == .loading ? .unavailable : lastKnownState
        }
        return lastKnownState
    }

    func loadIfNeeded(
        adUnitID: String,
        bypassScheduledRetry: Bool = false
    ) async -> AdLoadState {
        guard !AdMobBootstrapper.shouldSkipNonBannerAdRequest(placement: "rewarded", action: "load") else {
            return .unavailable
        }
        guard !adUnitID.isEmpty else {
            AppLogger.warning("Rewarded ad load skipped because ad unit is empty", category: .ads)
            lastKnownState = .unavailable
            return .unavailable
        }
        pruneExpiredPreparedAds()
        discardPreparedAdsForOtherUnits(adUnitID)
        if hasPreparedAd(for: adUnitID) {
            AppLogger.debug(
                "Rewarded ad already ready",
                category: .ads,
                metadata: ["cached": "\(preparedAdCount(for: adUnitID))"]
            )
            lastKnownState = .ready
            fillPreparedAdCacheIfNeeded(adUnitID: adUnitID)
            return .ready
        }
        if isWaitingForRetry {
            guard bypassScheduledRetry else {
                AppLogger.debug("Rewarded ad retry already scheduled", category: .ads)
                return lastKnownState == .loading ? .unavailable : lastKnownState
            }
            AppLogger.info("Rewarded ad retry requested immediately", category: .ads)
            retryWorkItem?.cancel()
            retryWorkItem = nil
            isWaitingForRetry = false
        }
        guard !isLoading else {
            AppLogger.debug("Rewarded ad already loading", category: .ads)
            lastKnownState = .loading
            return .loading
        }

        let state = await loadOneRewardedAd(adUnitID: adUnitID)
        if state == .ready {
            fillPreparedAdCacheIfNeeded(adUnitID: adUnitID)
        }
        return state
    }

    private func loadOneRewardedAd(adUnitID: String) async -> AdLoadState {
        guard preparedAdCount(for: adUnitID) < maxPreparedAdCount else {
            lastKnownState = .ready
            return .ready
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
            preparedAds.append(PreparedRewardedAd(
                ad: ad,
                adUnitID: adUnitID,
                loadedAt: Date()
            ))
            lastKnownState = .ready
            AppLogger.info(
                "Rewarded ad loaded",
                category: .ads,
                metadata: ["cached": "\(preparedAdCount(for: adUnitID))"]
            )
            return .ready
        } catch {
            lastKnownState = .unavailable
            AppLogger.error(
                "Rewarded ad failed to load",
                category: .ads,
                metadata: AdMobErrorMetadata.make(error: error, adUnitID: adUnitID)
            )
            scheduleRetry(adUnitID: adUnitID)
            return .unavailable
        }
    }

    func show(adUnitID: String) async -> RewardedAdShowResult {
        guard !AdMobBootstrapper.shouldSkipNonBannerAdRequest(placement: "rewarded", action: "show") else {
            return .unavailable
        }
        guard activeContinuation == nil else {
            AppLogger.warning(
                "Rewarded ad show skipped because another rewarded ad is active",
                category: .ads
            )
            return .unavailable
        }

        let loadState = await prepareForPresentation(adUnitID: adUnitID)
        guard loadState == .ready,
              let ad = dequeuePreparedAd(for: adUnitID) else {
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
        activeAd = ad
        didEarnReward = false
        lastKnownState = .loading
        fillPreparedAdCacheIfNeeded(adUnitID: adUnitID)

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

    private func fillPreparedAdCacheIfNeeded(adUnitID: String) {
        pruneExpiredPreparedAds()
        guard !AdMobBootstrapper.shouldSkipNonBannerAdRequest(placement: "rewarded", action: "cacheFill"),
              !adUnitID.isEmpty,
              !isLoading,
              !isWaitingForRetry,
              !isCacheFillScheduled,
              preparedAdCount(for: adUnitID) < maxPreparedAdCount else {
            return
        }

        isCacheFillScheduled = true
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer { self.isCacheFillScheduled = false }
            guard !self.isLoading,
                  !self.isWaitingForRetry,
                  self.preparedAdCount(for: adUnitID) < self.maxPreparedAdCount else {
                return
            }
            _ = await self.loadOneRewardedAd(adUnitID: adUnitID)
        }
    }

    private func hasPreparedAd(for adUnitID: String) -> Bool {
        preparedAds.contains { $0.adUnitID == adUnitID }
    }

    private func preparedAdCount(for adUnitID: String) -> Int {
        preparedAds.filter { $0.adUnitID == adUnitID }.count
    }

    private func dequeuePreparedAd(for adUnitID: String) -> RewardedAd? {
        pruneExpiredPreparedAds()
        guard let index = preparedAds.firstIndex(where: { $0.adUnitID == adUnitID }) else {
            return nil
        }
        return preparedAds.remove(at: index).ad
    }

    private func pruneExpiredPreparedAds(now: Date = Date()) {
        preparedAds.removeAll {
            now.timeIntervalSince($0.loadedAt) > preparedAdExpirationInterval
        }
    }

    private func discardPreparedAdsForOtherUnits(_ adUnitID: String) {
        preparedAds.removeAll { $0.adUnitID != adUnitID }
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
        guard !AdMobBootstrapper.shouldSkipNonBannerAdRequest(placement: "rewarded", action: "retrySchedule"),
              !adUnitID.isEmpty,
              retryCount < 6 else {
            return
        }
        retryWorkItem?.cancel()
        retryCount += 1
        isWaitingForRetry = true
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
            metadata: AdMobErrorMetadata.make(error: error)
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
        guard !AdMobBootstrapper.shouldSkipNonBannerAdRequest(placement: "interstitial", action: "load") else {
            return .unavailable
        }
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
                metadata: AdMobErrorMetadata.make(error: error, adUnitID: adUnitID)
            )
            return .unavailable
        }
    }

    func showIfAvailable(adUnitID: String, reason: SessionEndAdReason) async -> Bool {
        guard !AdMobBootstrapper.shouldSkipNonBannerAdRequest(placement: "interstitial", action: "show") else {
            return false
        }
        guard !isShowing else {
            AppLogger.info("Interstitial ad show skipped because another ad is showing", category: .ads)
            return false
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
            return false
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
        return true
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
            metadata: AdMobErrorMetadata.make(error: error)
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
        guard !AdMobBootstrapper.shouldSkipNonBannerAdRequest(placement: "appOpen", action: "load") else {
            return
        }
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
                metadata: AdMobErrorMetadata.make(error: error, adUnitID: adUnitID)
            )
        }
    }

    func showIfAvailable(adUnitID: String) async -> Bool {
        guard !AdMobBootstrapper.shouldSkipNonBannerAdRequest(placement: "appOpen", action: "show") else {
            return false
        }
        guard !isShowing else {
            AppLogger.info("App open ad show skipped because another app open ad is showing", category: .ads)
            return false
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
            return false
        }

        AppLogger.info("App open ad presenting", category: .ads)
        self.appOpenAd = nil
        appOpenAdUnitID = ""
        loadTime = nil
        isShowing = true
        appOpenAd.fullScreenContentDelegate = self
        appOpenAd.present(from: rootViewController)
        return true
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
            metadata: AdMobErrorMetadata.make(error: error)
        )
        isShowing = false
        Task { @MainActor in
            await loadIfNeeded(adUnitID: AdMobRuntimeConfiguration.current().appOpenAdUnitID)
        }
    }
}
#endif
