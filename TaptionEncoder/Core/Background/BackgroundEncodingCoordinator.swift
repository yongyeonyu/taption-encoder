import Foundation

protocol BackgroundEncodingCoordinating: TaptionBackgroundEncodingCoordinating {}

struct FakeBackgroundEncodingCoordinator: BackgroundEncodingCoordinating {
    var support: TaptionBackgroundEncodingSupport {
        .unavailableKeepAppOpen
    }

    func beginBackgroundEncoding(plan: TaptionEncodingPlan) async throws {}

    func endBackgroundEncoding(planID: UUID) async {}
}
