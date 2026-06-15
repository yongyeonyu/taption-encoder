import Foundation

struct AppEnvironment {
    var configuration: AppConfiguration
    var featureFlags: FeatureFlags
    var mediaInspector: MediaInspecting
    var encoderService: EncoderServicing
    var storageChecker: StorageChecking
    var sourceOpener: SourceOpening
    var outputResolver: OutputResolving
    var pendingSaveStore: PendingSaveStoring
    var adGate: AdGate
    var bannerAdProvider: BannerAdProviding
    var rewardedAdProvider: RewardedAdProviding
    var backgroundCoordinator: BackgroundEncodingCoordinating
    var projectDocumentStore: ProjectDocumentStoring

    init(
        configuration: AppConfiguration,
        featureFlags: FeatureFlags,
        mediaInspector: MediaInspecting,
        encoderService: EncoderServicing,
        storageChecker: StorageChecking,
        sourceOpener: SourceOpening,
        outputResolver: OutputResolving,
        pendingSaveStore: PendingSaveStoring,
        adGate: AdGate,
        bannerAdProvider: BannerAdProviding,
        rewardedAdProvider: RewardedAdProviding,
        backgroundCoordinator: BackgroundEncodingCoordinating,
        projectDocumentStore: ProjectDocumentStoring
    ) {
        self.configuration = configuration
        self.featureFlags = featureFlags
        self.mediaInspector = mediaInspector
        self.encoderService = encoderService
        self.storageChecker = storageChecker
        self.sourceOpener = sourceOpener
        self.outputResolver = outputResolver
        self.pendingSaveStore = pendingSaveStore
        self.adGate = adGate
        self.bannerAdProvider = bannerAdProvider
        self.rewardedAdProvider = rewardedAdProvider
        self.backgroundCoordinator = backgroundCoordinator
        self.projectDocumentStore = projectDocumentStore
    }

    static var phase0: AppEnvironment {
        let configuration = AppConfiguration()
        let pendingSaveStore = FakePendingSaveStore.shared
        let adGate = FakeAdGate()
        return AppEnvironment(
            configuration: configuration,
            featureFlags: .phase0,
            mediaInspector: AVFoundationMediaInspector(),
            encoderService: AVFoundationHEVCEncoderService(),
            storageChecker: FileSystemStorageChecker(),
            sourceOpener: FakeSourceOpener(),
            outputResolver: DefaultOutputResolver(namingPolicy: TaptionOutputNamingPolicy(suffix: configuration.outputSuffix)),
            pendingSaveStore: pendingSaveStore,
            adGate: adGate,
            bannerAdProvider: FakeBannerAdProvider(),
            rewardedAdProvider: FakeRewardedAdProvider(),
            backgroundCoordinator: FakeBackgroundEncodingCoordinator(),
            projectDocumentStore: FakeProjectFileStore()
        )
    }

    var videoCoreServices: TaptionVideoCoreServices {
        TaptionVideoCoreServices(
            inspector: mediaInspector,
            encoder: encoderService,
            storageChecker: storageChecker,
            pendingSaveStore: pendingSaveStore,
            saveGateAuthorizer: adGate,
            backgroundCoordinator: backgroundCoordinator,
            projectStore: projectDocumentStore
        )
    }
}
