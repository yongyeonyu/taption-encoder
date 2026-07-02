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
    var starWalletStore: StarWalletManaging
    var starEarningService: StarEarningServing
    var sessionEndAdProvider: SessionEndAdProviding
    var backgroundCoordinator: BackgroundEncodingCoordinating
    var liveActivityCoordinator: EncodingLiveActivityCoordinating
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
        starWalletStore: StarWalletManaging,
        starEarningService: StarEarningServing,
        sessionEndAdProvider: SessionEndAdProviding,
        backgroundCoordinator: BackgroundEncodingCoordinating,
        liveActivityCoordinator: EncodingLiveActivityCoordinating = NoopEncodingLiveActivityCoordinator(),
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
        self.starWalletStore = starWalletStore
        self.starEarningService = starEarningService
        self.sessionEndAdProvider = sessionEndAdProvider
        self.backgroundCoordinator = backgroundCoordinator
        self.liveActivityCoordinator = liveActivityCoordinator
        self.projectDocumentStore = projectDocumentStore
    }

    static var phase0: AppEnvironment {
        let configuration = AppConfiguration()
        let pendingSaveStore = FilePendingSaveStore.shared
        let adMobConfiguration = AdMobRuntimeConfiguration.current()
        let adGate = AdMobRewardedSaveAdGate(configuration: adMobConfiguration)
        let rewardedAdProvider = AdMobRewardedAdProvider(configuration: adMobConfiguration)
        let starWalletStore = StarWalletStore()
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
            bannerAdProvider: AdMobBannerAdProvider(configuration: adMobConfiguration),
            rewardedAdProvider: rewardedAdProvider,
            starWalletStore: starWalletStore,
            starEarningService: DefaultStarEarningService(
                walletStore: starWalletStore,
                rewardedAdProvider: rewardedAdProvider
            ),
            sessionEndAdProvider: AdMobSessionEndAdProvider(configuration: adMobConfiguration),
            backgroundCoordinator: UIApplicationBackgroundEncodingCoordinator(),
            liveActivityCoordinator: ActivityKitEncodingLiveActivityCoordinator(),
            projectDocumentStore: FCPXMLProjectDocumentStore()
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
