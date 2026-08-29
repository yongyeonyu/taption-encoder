import CryptoKit
import Foundation
import Security

enum StarLedgerEventKind: String, Codable, Equatable {
    case initialInstallBonus
    case rewardEarned
    case encodingStart
    case failureRefund
    case purchase
}

struct StarLedgerEvent: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: StarLedgerEventKind
    var delta: Int
    var note: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: StarLedgerEventKind,
        delta: Int,
        note: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.delta = delta
        self.note = note
        self.createdAt = createdAt
    }
}

struct StarWalletSnapshot: Codable, Equatable {
    var balance: Int
    var totalEarned: Int
    var totalSpent: Int
    var totalPurchased: Int
    var sequence: Int64
    var lastUpdatedAt: Date
    var events: [StarLedgerEvent]

    static let empty = StarWalletSnapshot(
        balance: 0,
        totalEarned: 0,
        totalSpent: 0,
        totalPurchased: 0,
        sequence: 0,
        lastUpdatedAt: Date(timeIntervalSince1970: 0),
        events: []
    )

    var badgeText: String {
        if balance > 999 {
            return "999+"
        }
        return String(format: "%03d", max(balance, 0))
    }
}

enum StarWalletError: LocalizedError, Equatable {
    case insufficientStars(required: Int, available: Int)

    var errorDescription: String? {
        switch self {
        case .insufficientStars(let required, let available):
            return "Not enough stars. Required \(required), available \(available)."
        }
    }
}

protocol StarWalletManaging {
    func currentSnapshot() async -> StarWalletSnapshot
    func earnStar(source: String) async throws -> StarWalletSnapshot
    func consumeStar(source: String) async throws -> StarWalletSnapshot
    func refundStar(source: String) async throws -> StarWalletSnapshot
}

protocol StarEarningServing {
    func currentAdState() async -> AdLoadState
    func prepareNextAd() async -> AdLoadState
    func retryNextAdNow() async -> AdLoadState
    func watchAdAndEarnStar() async throws -> StarEarningResult
}

extension StarEarningServing {
    func prepareNextAd() async -> AdLoadState {
        await currentAdState()
    }

    func retryNextAdNow() async -> AdLoadState {
        await prepareNextAd()
    }
}

struct StarEarningResult: Equatable {
    var adResult: RewardedAdShowResult
    var snapshot: StarWalletSnapshot
}

struct DefaultStarEarningService: StarEarningServing {
    var walletStore: any StarWalletManaging
    var rewardedAdProvider: any RewardedAdProviding

    func currentAdState() async -> AdLoadState {
        await rewardedAdProvider.currentRewardedState()
    }

    func prepareNextAd() async -> AdLoadState {
        await rewardedAdProvider.preloadRewardedAd()
    }

    func retryNextAdNow() async -> AdLoadState {
        await rewardedAdProvider.retryRewardedAdNow()
    }

    func watchAdAndEarnStar() async throws -> StarEarningResult {
        let adResult = await rewardedAdProvider.showRewardedAd()
        switch adResult {
        case .earnedReward:
            let snapshot = try await walletStore.earnStar(source: "rewarded_ad")
            return StarEarningResult(adResult: adResult, snapshot: snapshot)
        case .closedWithoutReward, .unavailable:
            return StarEarningResult(
                adResult: adResult,
                snapshot: await walletStore.currentSnapshot()
            )
        }
    }
}

actor FakeStarWalletStore: StarWalletManaging {
    private var snapshot: StarWalletSnapshot
    private let clock: @Sendable () -> Date

    init(
        snapshot: StarWalletSnapshot = .empty,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.snapshot = snapshot
        self.clock = clock
    }

    func currentSnapshot() async -> StarWalletSnapshot {
        snapshot
    }

    func earnStar(source: String) async throws -> StarWalletSnapshot {
        applyEvent(kind: .rewardEarned, delta: 1, note: source)
    }

    func consumeStar(source: String) async throws -> StarWalletSnapshot {
        guard snapshot.balance >= 1 else {
            throw StarWalletError.insufficientStars(required: 1, available: snapshot.balance)
        }
        return applyEvent(kind: .encodingStart, delta: -1, note: source)
    }

    func refundStar(source: String) async throws -> StarWalletSnapshot {
        applyEvent(kind: .failureRefund, delta: 1, note: source)
    }

    @discardableResult
    private func applyEvent(
        kind: StarLedgerEventKind,
        delta: Int,
        note: String
    ) -> StarWalletSnapshot {
        let now = clock()
        let event = StarLedgerEvent(
            kind: kind,
            delta: delta,
            note: note,
            createdAt: now
        )
        snapshot.balance = max(snapshot.balance + delta, 0)
        snapshot.sequence += 1
        snapshot.lastUpdatedAt = now
        snapshot.events.append(event)
        snapshot.events = Array(snapshot.events.suffix(120))
        if delta > 0 {
            snapshot.totalEarned += delta
        } else if delta < 0 {
            snapshot.totalSpent += abs(delta)
        }
        return snapshot
    }
}

protocol StarWalletSecureStoring: Sendable {
    func loadOrCreateEncryptionKeyData() throws -> Data
    func loadIntegrityMetadata() throws -> StarWalletIntegrityMetadata?
    func saveIntegrityMetadata(_ metadata: StarWalletIntegrityMetadata) throws
    func clearIntegrityMetadata() throws
    func loadLastWalletSnapshot() throws -> StarWalletSnapshot?
    func saveLastWalletSnapshot(_ snapshot: StarWalletSnapshot) throws
    func loadInitialBonusGranted() throws -> Bool
    func saveInitialBonusGranted() throws
}

struct StarWalletIntegrityMetadata: Codable, Equatable, Sendable {
    var sequence: Int64
    var digest: Data
}

struct KeychainStarWalletSecureStore: StarWalletSecureStoring {
    private let service: String
    private let encryptionKeyAccount = "wallet-encryption-key"
    private let integrityAccount = "wallet-integrity-metadata"
    private let lastWalletSnapshotAccount = "last-wallet-snapshot"
    private let initialBonusGrantedAccount = "initial-bonus-granted"

    init(service: String = "\(Bundle.main.bundleIdentifier ?? "com.taption.encoder").stars") {
        self.service = service
    }

    func loadOrCreateEncryptionKeyData() throws -> Data {
        if let existing = try load(account: encryptionKeyAccount) {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try saveOrUpdate(data: data, account: encryptionKeyAccount)
        return data
    }

    func loadIntegrityMetadata() throws -> StarWalletIntegrityMetadata? {
        guard let data = try load(account: integrityAccount) else {
            return nil
        }
        return try JSONDecoder.starWalletDecoder.decode(StarWalletIntegrityMetadata.self, from: data)
    }

    func saveIntegrityMetadata(_ metadata: StarWalletIntegrityMetadata) throws {
        let data = try JSONEncoder.starWalletEncoder.encode(metadata)
        try saveOrUpdate(data: data, account: integrityAccount)
    }

    func clearIntegrityMetadata() throws {
        try delete(account: integrityAccount)
    }

    func loadLastWalletSnapshot() throws -> StarWalletSnapshot? {
        guard let data = try load(account: lastWalletSnapshotAccount) else {
            return nil
        }
        return try JSONDecoder.starWalletDecoder.decode(StarWalletSnapshot.self, from: data)
    }

    func saveLastWalletSnapshot(_ snapshot: StarWalletSnapshot) throws {
        let data = try JSONEncoder.starWalletEncoder.encode(snapshot)
        try saveOrUpdate(data: data, account: lastWalletSnapshotAccount)
    }

    func loadInitialBonusGranted() throws -> Bool {
        guard let data = try load(account: initialBonusGrantedAccount) else {
            return false
        }
        return String(data: data, encoding: .utf8) == "1"
    }

    func saveInitialBonusGranted() throws {
        try saveOrUpdate(data: Data("1".utf8), account: initialBonusGrantedAccount)
    }

    private func load(account: String) throws -> Data? {
        let query = baseQuery(account: account).merging(
            [
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
        ) { _, new in new }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw keychainError(status: status)
        }
    }

    private func saveOrUpdate(data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insertQuery = query
            insertQuery[kSecValueData as String] = data
            insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw keychainError(status: insertStatus)
            }
        default:
            throw keychainError(status: status)
        }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status: status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func keychainError(status: OSStatus) -> NSError {
        NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error"]
        )
    }
}

actor StarWalletStore: StarWalletManaging {
    static let initialInstallBonusStarCount = 3

    private let fileURL: URL
    private let quarantineDirectoryURL: URL
    private let secureStore: any StarWalletSecureStoring
    private let fileManager: FileManager
    private let clock: @Sendable () -> Date
    private var cachedSnapshot: StarWalletSnapshot?

    init(
        fileURL: URL = TaptionEncoderStorageLocations.starWalletFileURL,
        quarantineDirectoryURL: URL = TaptionEncoderStorageLocations.starWalletQuarantineDirectoryURL,
        secureStore: any StarWalletSecureStoring = KeychainStarWalletSecureStore(),
        fileManager: FileManager = .default,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.quarantineDirectoryURL = quarantineDirectoryURL
        self.secureStore = secureStore
        self.fileManager = fileManager
        self.clock = clock
    }

    func currentSnapshot() async -> StarWalletSnapshot {
        if let cachedSnapshot {
            return cachedSnapshot
        }

        do {
            let snapshot = try loadSnapshot()
            cachedSnapshot = snapshot
            return snapshot
        } catch {
            await handleIntegrityFailure(reason: "load_failed", error: error)
            return .empty
        }
    }

    func earnStar(source: String) async throws -> StarWalletSnapshot {
        try await mutate(kind: .rewardEarned, delta: 1, note: source)
    }

    func consumeStar(source: String) async throws -> StarWalletSnapshot {
        let snapshot = await currentSnapshot()
        guard snapshot.balance >= 1 else {
            throw StarWalletError.insufficientStars(required: 1, available: snapshot.balance)
        }
        return try await mutate(kind: .encodingStart, delta: -1, note: source)
    }

    func refundStar(source: String) async throws -> StarWalletSnapshot {
        try await mutate(kind: .failureRefund, delta: 1, note: source)
    }

    private func mutate(
        kind: StarLedgerEventKind,
        delta: Int,
        note: String,
    ) async throws -> StarWalletSnapshot {
        var snapshot = await currentSnapshot()
        let now = clock()
        snapshot.sequence += 1
        snapshot.lastUpdatedAt = now
        snapshot.balance = max(snapshot.balance + delta, 0)
        if delta > 0 {
            snapshot.totalEarned += delta
        } else if delta < 0 {
            snapshot.totalSpent += abs(delta)
        }
        snapshot.events.append(
            StarLedgerEvent(
                kind: kind,
                delta: delta,
                note: note,
                createdAt: now
            )
        )
        snapshot.events = Array(snapshot.events.suffix(120))
        try persist(snapshot)
        cachedSnapshot = snapshot
        return snapshot
    }

    private func loadSnapshot() throws -> StarWalletSnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            if let snapshot = try restoreSnapshotFromSecureStoreIfAvailable() {
                return snapshot
            }
            return try createInitialInstallBonusSnapshotIfNeeded()
        }

        let encryptedData = try Data(contentsOf: fileURL)
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let key = SymmetricKey(data: try secureStore.loadOrCreateEncryptionKeyData())
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        let snapshot = try JSONDecoder.starWalletDecoder.decode(StarWalletSnapshot.self, from: decryptedData)
        try validateIntegrity(snapshot: snapshot, encryptedData: encryptedData)
        try syncIntegrityMetadataIfNeeded(snapshot: snapshot, encryptedData: encryptedData)
        try markInitialBonusGrantedIfNeeded()
        try secureStore.saveLastWalletSnapshot(snapshot)
        return snapshot
    }

    private func restoreSnapshotFromSecureStoreIfAvailable() throws -> StarWalletSnapshot? {
        guard let snapshot = try secureStore.loadLastWalletSnapshot() else {
            return nil
        }
        try persist(snapshot)
        try markInitialBonusGrantedIfNeeded()
        AppLogger.info(
            "Stars wallet restored from Keychain snapshot",
            category: .app,
            metadata: [
                "stars": "\(snapshot.balance)",
                "sequence": "\(snapshot.sequence)"
            ]
        )
        return snapshot
    }

    private func createInitialInstallBonusSnapshotIfNeeded() throws -> StarWalletSnapshot {
        guard try !secureStore.loadInitialBonusGranted() else {
            return .empty
        }

        let now = clock()
        let snapshot = StarWalletSnapshot(
            balance: Self.initialInstallBonusStarCount,
            totalEarned: Self.initialInstallBonusStarCount,
            totalSpent: 0,
            totalPurchased: 0,
            sequence: 1,
            lastUpdatedAt: now,
            events: [
                StarLedgerEvent(
                    kind: .initialInstallBonus,
                    delta: Self.initialInstallBonusStarCount,
                    note: "initial_install_bonus",
                    createdAt: now
                )
            ]
        )
        try persist(snapshot)
        try secureStore.saveInitialBonusGranted()
        AppLogger.info(
            "Initial install Stars bonus granted",
            category: .app,
            metadata: ["stars": "\(Self.initialInstallBonusStarCount)"]
        )
        return snapshot
    }

    private func markInitialBonusGrantedIfNeeded() throws {
        guard try !secureStore.loadInitialBonusGranted() else {
            return
        }
        try secureStore.saveInitialBonusGranted()
    }

    private func persist(_ snapshot: StarWalletSnapshot) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encodedSnapshot = try JSONEncoder.starWalletEncoder.encode(snapshot)
        let key = SymmetricKey(data: try secureStore.loadOrCreateEncryptionKeyData())
        let sealedBox = try AES.GCM.seal(encodedSnapshot, using: key)
        guard let encryptedData = sealedBox.combined else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: CocoaError.fileWriteUnknown.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "The stars wallet could not be encrypted."]
            )
        }
        try encryptedData.write(to: fileURL, options: [.atomic])
        try syncIntegrityMetadataIfNeeded(snapshot: snapshot, encryptedData: encryptedData, force: true)
        try secureStore.saveLastWalletSnapshot(snapshot)
    }

    private func validateIntegrity(
        snapshot: StarWalletSnapshot,
        encryptedData: Data
    ) throws {
        guard let metadata = try secureStore.loadIntegrityMetadata() else {
            return
        }
        let digest = Self.digest(for: encryptedData)
        if snapshot.sequence < metadata.sequence {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: CocoaError.fileReadCorruptFile.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "The stars wallet appears to have rolled back."]
            )
        }
        if snapshot.sequence == metadata.sequence,
           digest != metadata.digest {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: CocoaError.fileReadCorruptFile.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "The stars wallet digest did not match the protected metadata."]
            )
        }
    }

    private func syncIntegrityMetadataIfNeeded(
        snapshot: StarWalletSnapshot,
        encryptedData: Data,
        force: Bool = false
    ) throws {
        let updatedMetadata = StarWalletIntegrityMetadata(
            sequence: snapshot.sequence,
            digest: Self.digest(for: encryptedData)
        )
        if !force,
           let existing = try secureStore.loadIntegrityMetadata(),
           existing == updatedMetadata {
            return
        }
        try secureStore.saveIntegrityMetadata(updatedMetadata)
    }

    private func handleIntegrityFailure(reason: String, error: Error) async {
        AppLogger.error(
            "Stars wallet integrity failure",
            category: .app,
            metadata: [
                "reason": reason,
                "error": error.localizedDescription
            ]
        )
        quarantineCorruptedWalletIfNeeded()
        try? secureStore.clearIntegrityMetadata()
        cachedSnapshot = .empty
    }

    private func quarantineCorruptedWalletIfNeeded() {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        do {
            try fileManager.createDirectory(
                at: quarantineDirectoryURL,
                withIntermediateDirectories: true
            )
            let quarantinedURL = quarantineDirectoryURL
                .appendingPathComponent("stars-wallet-\(UUID().uuidString).enc", isDirectory: false)
            if fileManager.fileExists(atPath: quarantinedURL.path) {
                try fileManager.removeItem(at: quarantinedURL)
            }
            try fileManager.moveItem(at: fileURL, to: quarantinedURL)
        } catch {
            AppLogger.warning(
                "Stars wallet quarantine failed",
                category: .app,
                metadata: ["error": error.localizedDescription]
            )
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private static func digest(for data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}

#if DEBUG
extension StarWalletStore {
    func persistForTesting(_ snapshot: StarWalletSnapshot) throws {
        try persist(snapshot)
    }
}
#endif

extension TaptionEncoderStorageLocations {
    static var starWalletFileURL: URL {
        appSupportDirectoryURL
            .appendingPathComponent("stars-wallet.enc", isDirectory: false)
    }

    static var starWalletQuarantineDirectoryURL: URL {
        appSupportDirectoryURL
            .appendingPathComponent("StarsWalletQuarantine", isDirectory: true)
    }
}

private extension JSONEncoder {
    static let starWalletEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let starWalletDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
