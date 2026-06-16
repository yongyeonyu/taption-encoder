import Foundation

enum AdGateDecision: String, Equatable {
    case allowed
    case unavailable
    case skipped
}

protocol AdGate: TaptionSaveGateAuthorizing {
    func requestSaveAuthorization(for state: TaptionPendingSaveState) async throws -> AdGateDecision
}

struct FakeAdGate: AdGate {
    func requestSaveAuthorization(for state: TaptionPendingSaveState) async throws -> AdGateDecision {
        .allowed
    }

    func authorizeFinalSave(for state: TaptionPendingSaveState) async throws -> Bool {
        try await requestSaveAuthorization(for: state) == .allowed
    }
}

struct AdMobRewardedSaveAdGate: AdGate {
    let configuration: AdMobRuntimeConfiguration

    init(configuration: AdMobRuntimeConfiguration = .current()) {
        self.configuration = configuration
    }

    func requestSaveAuthorization(for state: TaptionPendingSaveState) async throws -> AdGateDecision {
        guard state.requiresRewardedAd else {
            AppLogger.info(
                "Rewarded save authorization skipped because flag is already cleared",
                category: .ads,
                metadata: ["id": state.id.uuidString]
            )
            return .allowed
        }

        #if canImport(GoogleMobileAds)
        AppLogger.info(
            "Rewarded save authorization requested",
            category: .ads,
            metadata: ["id": state.id.uuidString]
        )
        let didEarnReward = await AdMobRewardedAdManager.shared.show(
            adUnitID: configuration.rewardedSaveAdUnitID
        )
        AppLogger.info(
            "Rewarded save authorization completed",
            category: .ads,
            metadata: [
                "id": state.id.uuidString,
                "earned": "\(didEarnReward)"
            ]
        )
        return didEarnReward ? .allowed : .unavailable
        #else
        AppLogger.warning("Rewarded save authorization unavailable because GoogleMobileAds is not linked", category: .ads)
        return .unavailable
        #endif
    }

    func authorizeFinalSave(for state: TaptionPendingSaveState) async throws -> Bool {
        try await requestSaveAuthorization(for: state) == .allowed
    }
}
