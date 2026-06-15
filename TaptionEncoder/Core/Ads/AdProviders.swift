import Foundation

enum AdLoadState: String, Equatable {
    case idle
    case loading
    case ready
    case unavailable
}

protocol BannerAdProviding {
    func currentBannerState() async -> AdLoadState
}

protocol RewardedAdProviding {
    func currentRewardedState() async -> AdLoadState
}

struct FakeBannerAdProvider: BannerAdProviding {
    func currentBannerState() async -> AdLoadState {
        .ready
    }
}

struct FakeRewardedAdProvider: RewardedAdProviding {
    func currentRewardedState() async -> AdLoadState {
        .ready
    }
}
