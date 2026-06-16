import Foundation

enum HW_AppleDeviceCodecConfidence: String, Codable, Equatable {
    case applePublishedSpec
    case runtimeProbeRequired
    case conservativeFallback
}

struct HW_AppleDeviceCodecProfile: Codable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var platformScope: String
    var representativeDevices: [String]
    var chipFamilies: [String]
    var hardwareDecodeCodecs: Set<TaptionVideoCodec>
    var hardwareEncodeCodecs: Set<TaptionVideoCodec>
    var confidence: HW_AppleDeviceCodecConfidence
    var notes: String

    var hardwareSupportProfile: TaptionCodecHardwareSupportProfile {
        TaptionCodecHardwareSupportProfile(
            name: id,
            hardwareDecodeCodecs: hardwareDecodeCodecs,
            hardwareEncodeCodecs: hardwareEncodeCodecs
        )
    }
}

struct HW_AppleDeviceCodecModel: Codable, Equatable, Identifiable {
    var id: String { modelIdentifier }
    var modelIdentifier: String
    var marketingName: String
    var profileID: String
    var chipFamily: String
    var minimumOSScope: String
    var notes: String

    var profile: HW_AppleDeviceCodecProfile? {
        HW_AppleDeviceCodecProfiles.profile(id: profileID)
    }

    var hardwareSupportProfile: TaptionCodecHardwareSupportProfile? {
        guard let profile else {
            return nil
        }
        return TaptionCodecHardwareSupportProfile(
            name: modelIdentifier,
            hardwareDecodeCodecs: profile.hardwareDecodeCodecs,
            hardwareEncodeCodecs: profile.hardwareEncodeCodecs
        )
    }

    var platformName: String {
        if modelIdentifier.hasPrefix("iPhone") {
            return "iPhone"
        }
        if modelIdentifier.hasPrefix("iPad") {
            return "iPad"
        }
        return "Unknown"
    }

    var identifierFamily: String {
        modelIdentifier.split(separator: ",").first.map(String.init) ?? modelIdentifier
    }
}

struct HW_AppleDeviceCodecModelCoverageReport: Codable, Equatable {
    var scope: String
    var modelCount: Int
    var iPhoneModelCount: Int
    var iPadModelCount: Int
    var duplicateModelIdentifierCount: Int
    var profileChipFamilyMismatchCount: Int
    var missingProfileIDs: Set<String>
    var profileCounts: [String: Int]
    var identifierFamilyCounts: [String: Int]
    var av1HardwareDecodeModelCount: Int
    var hevcHardwareEncodeModelCount: Int
    var h264OnlyModelCount: Int
    var proResHardwareEncodeModelCount: Int

    var isPassing: Bool {
        duplicateModelIdentifierCount == 0
            && profileChipFamilyMismatchCount == 0
            && missingProfileIDs.isEmpty
            && modelCount == iPhoneModelCount + iPadModelCount
    }
}

enum HW_AppleDeviceCodecModelMatrix {
    static let compatibilityScope = "iOS/iPadOS 18+ supported devices plus iOS/iPadOS 26 current devices"

    static let all: [HW_AppleDeviceCodecModel] =
        iPhoneModels
        + iPadBaseModels
        + iPadMiniModels
        + iPadAirModels
        + iPadProModels

    static var routeSimulationProfiles: [TaptionCodecHardwareSupportProfile] {
        all.compactMap(\.hardwareSupportProfile)
    }

    static var modelIdentifiers: Set<String> {
        Set(all.map(\.modelIdentifier))
    }

    static var missingProfileIDs: Set<String> {
        Set(all.compactMap { model in
            HW_AppleDeviceCodecProfiles.profile(id: model.profileID) == nil ? model.profileID : nil
        })
    }

    static func coverageReport(
        models: [HW_AppleDeviceCodecModel] = all
    ) -> HW_AppleDeviceCodecModelCoverageReport {
        let identifiers = models.map(\.modelIdentifier)
        let duplicateCount = identifiers.count - Set(identifiers).count
        let profilesByID = Dictionary(
            uniqueKeysWithValues: HW_AppleDeviceCodecProfiles.all.map { ($0.id, $0) }
        )

        return HW_AppleDeviceCodecModelCoverageReport(
            scope: compatibilityScope,
            modelCount: models.count,
            iPhoneModelCount: models.filter { $0.platformName == "iPhone" }.count,
            iPadModelCount: models.filter { $0.platformName == "iPad" }.count,
            duplicateModelIdentifierCount: duplicateCount,
            profileChipFamilyMismatchCount: models.filter { model in
                guard let profile = profilesByID[model.profileID] else {
                    return true
                }
                return !profile.chipFamilies.contains(model.chipFamily)
            }.count,
            missingProfileIDs: Set(models.compactMap { model in
                profilesByID[model.profileID] == nil ? model.profileID : nil
            }),
            profileCounts: Dictionary(grouping: models, by: \.profileID).mapValues(\.count),
            identifierFamilyCounts: Dictionary(grouping: models, by: \.identifierFamily).mapValues(\.count),
            av1HardwareDecodeModelCount: models.filter { model in
                profilesByID[model.profileID]?.hardwareDecodeCodecs.contains(.av1) == true
            }.count,
            hevcHardwareEncodeModelCount: models.filter { model in
                profilesByID[model.profileID]?.hardwareEncodeCodecs.contains(.hevc) == true
            }.count,
            h264OnlyModelCount: models.filter { model in
                guard let profile = profilesByID[model.profileID] else {
                    return false
                }
                return profile.hardwareDecodeCodecs == [.h264]
                    && profile.hardwareEncodeCodecs == [.h264]
            }.count,
            proResHardwareEncodeModelCount: models.filter { model in
                profilesByID[model.profileID]?.hardwareEncodeCodecs.contains(.proRes) == true
            }.count
        )
    }

    static func model(identifier: String) -> HW_AppleDeviceCodecModel? {
        all.first { $0.modelIdentifier == identifier }
    }

    static func hardwareSupportProfile(identifier: String) -> TaptionCodecHardwareSupportProfile? {
        model(identifier: identifier)?.hardwareSupportProfile
    }

    private static func model(
        _ identifier: String,
        _ marketingName: String,
        profileID: String,
        chipFamily: String,
        minimumOSScope: String = "iOS/iPadOS 18+",
        notes: String = "Static simulation seed. Runtime VideoToolbox probing remains authoritative."
    ) -> HW_AppleDeviceCodecModel {
        HW_AppleDeviceCodecModel(
            modelIdentifier: identifier,
            marketingName: marketingName,
            profileID: profileID,
            chipFamily: chipFamily,
            minimumOSScope: minimumOSScope,
            notes: notes
        )
    }

    private static let iPhoneModels: [HW_AppleDeviceCodecModel] = [
        model("iPhone11,2", "iPhone XS", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12 Bionic"),
        model("iPhone11,4", "iPhone XS Max", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12 Bionic"),
        model("iPhone11,6", "iPhone XS Max", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12 Bionic"),
        model("iPhone11,8", "iPhone XR", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12 Bionic"),
        model("iPhone12,1", "iPhone 11", profileID: "apple_a13_a14_h264_hevc", chipFamily: "A13 Bionic"),
        model("iPhone12,3", "iPhone 11 Pro", profileID: "apple_a13_a14_h264_hevc", chipFamily: "A13 Bionic"),
        model("iPhone12,5", "iPhone 11 Pro Max", profileID: "apple_a13_a14_h264_hevc", chipFamily: "A13 Bionic"),
        model("iPhone12,8", "iPhone SE (2nd generation)", profileID: "apple_a13_a14_h264_hevc", chipFamily: "A13 Bionic"),
        model("iPhone13,1", "iPhone 12 mini", profileID: "apple_a13_a14_h264_hevc", chipFamily: "A14 Bionic"),
        model("iPhone13,2", "iPhone 12", profileID: "apple_a13_a14_h264_hevc", chipFamily: "A14 Bionic"),
        model("iPhone13,3", "iPhone 12 Pro", profileID: "apple_a13_a14_h264_hevc", chipFamily: "A14 Bionic"),
        model("iPhone13,4", "iPhone 12 Pro Max", profileID: "apple_a13_a14_h264_hevc", chipFamily: "A14 Bionic"),
        model("iPhone14,2", "iPhone 13 Pro", profileID: "apple_iphone_pro_a15_a16_prores", chipFamily: "A15 Bionic"),
        model("iPhone14,3", "iPhone 13 Pro Max", profileID: "apple_iphone_pro_a15_a16_prores", chipFamily: "A15 Bionic"),
        model("iPhone14,4", "iPhone 13 mini", profileID: "apple_a15_a16_h264_hevc", chipFamily: "A15 Bionic"),
        model("iPhone14,5", "iPhone 13", profileID: "apple_a15_a16_h264_hevc", chipFamily: "A15 Bionic"),
        model("iPhone14,6", "iPhone SE (3rd generation)", profileID: "apple_a15_a16_h264_hevc", chipFamily: "A15 Bionic"),
        model("iPhone14,7", "iPhone 14", profileID: "apple_a15_a16_h264_hevc", chipFamily: "A15 Bionic"),
        model("iPhone14,8", "iPhone 14 Plus", profileID: "apple_a15_a16_h264_hevc", chipFamily: "A15 Bionic"),
        model("iPhone15,2", "iPhone 14 Pro", profileID: "apple_iphone_pro_a15_a16_prores", chipFamily: "A16 Bionic"),
        model("iPhone15,3", "iPhone 14 Pro Max", profileID: "apple_iphone_pro_a15_a16_prores", chipFamily: "A16 Bionic"),
        model("iPhone15,4", "iPhone 15", profileID: "apple_a15_a16_h264_hevc", chipFamily: "A16 Bionic"),
        model("iPhone15,5", "iPhone 15 Plus", profileID: "apple_a15_a16_h264_hevc", chipFamily: "A16 Bionic"),
        model("iPhone16,1", "iPhone 15 Pro", profileID: "apple_a17pro_av1_decode", chipFamily: "A17 Pro"),
        model("iPhone16,2", "iPhone 15 Pro Max", profileID: "apple_a17pro_av1_decode", chipFamily: "A17 Pro"),
        model("iPhone17,1", "iPhone 16 Pro", profileID: "apple_a18pro_av1_decode_prores", chipFamily: "A18 Pro", minimumOSScope: "iOS 26+"),
        model("iPhone17,2", "iPhone 16 Pro Max", profileID: "apple_a18pro_av1_decode_prores", chipFamily: "A18 Pro", minimumOSScope: "iOS 26+"),
        model("iPhone17,3", "iPhone 16", profileID: "apple_a18_av1_decode", chipFamily: "A18", minimumOSScope: "iOS 26+"),
        model("iPhone17,4", "iPhone 16 Plus", profileID: "apple_a18_av1_decode", chipFamily: "A18", minimumOSScope: "iOS 26+"),
        model("iPhone17,5", "iPhone 16e", profileID: "apple_a18_av1_decode", chipFamily: "A18", minimumOSScope: "iOS 26+"),
        model("iPhone18,1", "iPhone 17 Pro", profileID: "apple_a19pro_av1_decode_prores_raw", chipFamily: "A19 Pro", minimumOSScope: "iOS 26+"),
        model("iPhone18,2", "iPhone 17 Pro Max", profileID: "apple_a19pro_av1_decode_prores_raw", chipFamily: "A19 Pro", minimumOSScope: "iOS 26+"),
        model("iPhone18,3", "iPhone 17", profileID: "apple_a19_av1_decode", chipFamily: "A19", minimumOSScope: "iOS 26+"),
        model("iPhone18,4", "iPhone Air", profileID: "apple_a19pro_av1_decode", chipFamily: "A19 Pro", minimumOSScope: "iOS 26+"),
        model("iPhone18,5", "iPhone 17e", profileID: "apple_a19_av1_decode", chipFamily: "A19", minimumOSScope: "iOS 26+")
    ]

    private static let iPadBaseModels: [HW_AppleDeviceCodecModel] = [
        model("iPad7,11", "iPad (7th generation) Wi-Fi", profileID: "apple_ipados18_legacy_a10_h264", chipFamily: "A10 Fusion"),
        model("iPad7,12", "iPad (7th generation) Cellular", profileID: "apple_ipados18_legacy_a10_h264", chipFamily: "A10 Fusion"),
        model("iPad11,6", "iPad (8th generation) Wi-Fi", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12 Bionic"),
        model("iPad11,7", "iPad (8th generation) Cellular", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12 Bionic"),
        model("iPad12,1", "iPad (9th generation) Wi-Fi", profileID: "apple_a13_a14_h264_hevc", chipFamily: "A13 Bionic"),
        model("iPad12,2", "iPad (9th generation) Cellular", profileID: "apple_a13_a14_h264_hevc", chipFamily: "A13 Bionic"),
        model("iPad13,18", "iPad (10th generation) Wi-Fi", profileID: "apple_a13_a14_h264_hevc", chipFamily: "A14 Bionic"),
        model("iPad13,19", "iPad (10th generation) Cellular", profileID: "apple_a13_a14_h264_hevc", chipFamily: "A14 Bionic"),
        model("iPad15,7", "iPad (A16) Wi-Fi", profileID: "apple_a15_a16_h264_hevc", chipFamily: "A16 Bionic", minimumOSScope: "iPadOS 26+"),
        model("iPad15,8", "iPad (A16) Cellular", profileID: "apple_a15_a16_h264_hevc", chipFamily: "A16 Bionic", minimumOSScope: "iPadOS 26+")
    ]

    private static let iPadMiniModels: [HW_AppleDeviceCodecModel] = [
        model("iPad11,1", "iPad mini (5th generation) Wi-Fi", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12 Bionic"),
        model("iPad11,2", "iPad mini (5th generation) Cellular", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12 Bionic"),
        model("iPad14,1", "iPad mini (6th generation) Wi-Fi", profileID: "apple_a15_a16_h264_hevc", chipFamily: "A15 Bionic"),
        model("iPad14,2", "iPad mini (6th generation) Cellular", profileID: "apple_a15_a16_h264_hevc", chipFamily: "A15 Bionic"),
        model("iPad16,1", "iPad mini (A17 Pro) Wi-Fi", profileID: "apple_a17pro_av1_decode", chipFamily: "A17 Pro", minimumOSScope: "iPadOS 26+"),
        model("iPad16,2", "iPad mini (A17 Pro) Cellular", profileID: "apple_a17pro_av1_decode", chipFamily: "A17 Pro", minimumOSScope: "iPadOS 26+")
    ]

    private static let iPadAirModels: [HW_AppleDeviceCodecModel] = [
        model("iPad11,3", "iPad Air (3rd generation) Wi-Fi", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12 Bionic"),
        model("iPad11,4", "iPad Air (3rd generation) Cellular", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12 Bionic"),
        model("iPad13,1", "iPad Air (4th generation) Wi-Fi", profileID: "apple_a13_a14_h264_hevc", chipFamily: "A14 Bionic"),
        model("iPad13,2", "iPad Air (4th generation) Cellular", profileID: "apple_a13_a14_h264_hevc", chipFamily: "A14 Bionic"),
        model("iPad13,16", "iPad Air (5th generation) Wi-Fi", profileID: "apple_ipad_air_m1_m2_h264_hevc", chipFamily: "M1"),
        model("iPad13,17", "iPad Air (5th generation) Cellular", profileID: "apple_ipad_air_m1_m2_h264_hevc", chipFamily: "M1"),
        model("iPad14,8", "iPad Air 11-inch (M2) Wi-Fi", profileID: "apple_ipad_air_m1_m2_h264_hevc", chipFamily: "M2"),
        model("iPad14,9", "iPad Air 11-inch (M2) Cellular", profileID: "apple_ipad_air_m1_m2_h264_hevc", chipFamily: "M2"),
        model("iPad14,10", "iPad Air 13-inch (M2) Wi-Fi", profileID: "apple_ipad_air_m1_m2_h264_hevc", chipFamily: "M2"),
        model("iPad14,11", "iPad Air 13-inch (M2) Cellular", profileID: "apple_ipad_air_m1_m2_h264_hevc", chipFamily: "M2"),
        model("iPad15,3", "iPad Air 11-inch (M3) Wi-Fi", profileID: "apple_ipad_m3_m4_av1_prores", chipFamily: "M3", minimumOSScope: "iPadOS 26+"),
        model("iPad15,4", "iPad Air 11-inch (M3) Cellular", profileID: "apple_ipad_m3_m4_av1_prores", chipFamily: "M3", minimumOSScope: "iPadOS 26+"),
        model("iPad15,5", "iPad Air 13-inch (M3) Wi-Fi", profileID: "apple_ipad_m3_m4_av1_prores", chipFamily: "M3", minimumOSScope: "iPadOS 26+"),
        model("iPad15,6", "iPad Air 13-inch (M3) Cellular", profileID: "apple_ipad_m3_m4_av1_prores", chipFamily: "M3", minimumOSScope: "iPadOS 26+")
    ]

    private static let iPadProModels: [HW_AppleDeviceCodecModel] = [
        model("iPad8,1", "iPad Pro 11-inch (1st generation) Wi-Fi", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12X Bionic"),
        model("iPad8,2", "iPad Pro 11-inch (1st generation) Wi-Fi", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12X Bionic"),
        model("iPad8,3", "iPad Pro 11-inch (1st generation) Cellular", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12X Bionic"),
        model("iPad8,4", "iPad Pro 11-inch (1st generation) Cellular", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12X Bionic"),
        model("iPad8,5", "iPad Pro 12.9-inch (3rd generation) Wi-Fi", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12X Bionic"),
        model("iPad8,6", "iPad Pro 12.9-inch (3rd generation) Wi-Fi", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12X Bionic"),
        model("iPad8,7", "iPad Pro 12.9-inch (3rd generation) Cellular", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12X Bionic"),
        model("iPad8,8", "iPad Pro 12.9-inch (3rd generation) Cellular", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12X Bionic"),
        model("iPad8,9", "iPad Pro 11-inch (2nd generation) Wi-Fi", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12Z Bionic"),
        model("iPad8,10", "iPad Pro 11-inch (2nd generation) Cellular", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12Z Bionic"),
        model("iPad8,11", "iPad Pro 12.9-inch (4th generation) Wi-Fi", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12Z Bionic"),
        model("iPad8,12", "iPad Pro 12.9-inch (4th generation) Cellular", profileID: "apple_ios18_a12_h264_hevc", chipFamily: "A12Z Bionic"),
        model("iPad13,4", "iPad Pro 11-inch (3rd generation) Wi-Fi", profileID: "apple_ipad_pro_m1_m2_prores", chipFamily: "M1"),
        model("iPad13,5", "iPad Pro 11-inch (3rd generation) Wi-Fi", profileID: "apple_ipad_pro_m1_m2_prores", chipFamily: "M1"),
        model("iPad13,6", "iPad Pro 11-inch (3rd generation) Cellular", profileID: "apple_ipad_pro_m1_m2_prores", chipFamily: "M1"),
        model("iPad13,7", "iPad Pro 11-inch (3rd generation) Cellular", profileID: "apple_ipad_pro_m1_m2_prores", chipFamily: "M1"),
        model("iPad13,8", "iPad Pro 12.9-inch (5th generation) Wi-Fi", profileID: "apple_ipad_pro_m1_m2_prores", chipFamily: "M1"),
        model("iPad13,9", "iPad Pro 12.9-inch (5th generation) Wi-Fi", profileID: "apple_ipad_pro_m1_m2_prores", chipFamily: "M1"),
        model("iPad13,10", "iPad Pro 12.9-inch (5th generation) Cellular", profileID: "apple_ipad_pro_m1_m2_prores", chipFamily: "M1"),
        model("iPad13,11", "iPad Pro 12.9-inch (5th generation) Cellular", profileID: "apple_ipad_pro_m1_m2_prores", chipFamily: "M1"),
        model("iPad14,3", "iPad Pro 11-inch (4th generation) Wi-Fi", profileID: "apple_ipad_pro_m1_m2_prores", chipFamily: "M2"),
        model("iPad14,4", "iPad Pro 11-inch (4th generation) Cellular", profileID: "apple_ipad_pro_m1_m2_prores", chipFamily: "M2"),
        model("iPad14,5", "iPad Pro 12.9-inch (6th generation) Wi-Fi", profileID: "apple_ipad_pro_m1_m2_prores", chipFamily: "M2"),
        model("iPad14,6", "iPad Pro 12.9-inch (6th generation) Cellular", profileID: "apple_ipad_pro_m1_m2_prores", chipFamily: "M2"),
        model("iPad16,3", "iPad Pro 11-inch (M4) Wi-Fi", profileID: "apple_ipad_m3_m4_av1_prores", chipFamily: "M4", minimumOSScope: "iPadOS 26+"),
        model("iPad16,4", "iPad Pro 11-inch (M4) Cellular", profileID: "apple_ipad_m3_m4_av1_prores", chipFamily: "M4", minimumOSScope: "iPadOS 26+"),
        model("iPad16,5", "iPad Pro 13-inch (M4) Wi-Fi", profileID: "apple_ipad_m3_m4_av1_prores", chipFamily: "M4", minimumOSScope: "iPadOS 26+"),
        model("iPad16,6", "iPad Pro 13-inch (M4) Cellular", profileID: "apple_ipad_m3_m4_av1_prores", chipFamily: "M4", minimumOSScope: "iPadOS 26+")
    ]
}

enum HW_AppleDeviceCodecProfiles {
    static let all: [HW_AppleDeviceCodecProfile] = [
        iPadOS18LegacyA10,
        iOSA12Family,
        iOSA13A14Family,
        iOSA15A16Family,
        iPhoneProA15A16ProRes,
        iPadProM1M2ProRes,
        iPadAirM1M2,
        iPhoneA17ProAV1,
        iPhoneA18AV1,
        iPhoneA18ProAV1ProRes,
        iPhoneA19AV1,
        iPhoneA19ProAV1,
        iPhoneA19ProAV1ProResRAW,
        iPadM3M4AV1ProRes
    ]

    static var routeSimulationProfiles: [TaptionCodecHardwareSupportProfile] {
        all.map(\.hardwareSupportProfile)
    }

    static func profile(id: String) -> HW_AppleDeviceCodecProfile? {
        all.first { $0.id == id }
    }

    private static let iPadOS18LegacyA10 = HW_AppleDeviceCodecProfile(
        id: "apple_ipados18_legacy_a10_h264",
        displayName: "iPadOS 18 legacy A10 H.264 class",
        platformScope: "iPadOS 18+",
        representativeDevices: [
            "iPad (7th generation)"
        ],
        chipFamilies: [
            "A10 Fusion"
        ],
        hardwareDecodeCodecs: [
            .h264
        ],
        hardwareEncodeCodecs: [
            .h264
        ],
        confidence: .conservativeFallback,
        notes: "Oldest iPadOS 18 class. Treat H.265 as software-fallback unless runtime probing proves hardware encode support."
    )

    private static let iOSA12Family = HW_AppleDeviceCodecProfile(
        id: "apple_ios18_a12_h264_hevc",
        displayName: "iOS/iPadOS 18 A12 HEVC class",
        platformScope: "iOS 18+ / iPadOS 18+",
        representativeDevices: [
            "iPhone XS",
            "iPhone XR",
            "iPad mini (5th generation)",
            "iPad Air (3rd generation)",
            "iPad (8th generation)",
            "iPad Pro 11-inch (1st generation)",
            "iPad Pro 12.9-inch (3rd generation)"
        ],
        chipFamilies: [
            "A12 Bionic",
            "A12X Bionic",
            "A12Z Bionic"
        ],
        hardwareDecodeCodecs: h264HEVCDolbyVisionDecode,
        hardwareEncodeCodecs: h264HEVCEncode,
        confidence: .runtimeProbeRequired,
        notes: "Baseline modern HEVC class for older supported iPhone/iPad devices. No AV1 hardware route."
    )

    private static let iOSA13A14Family = HW_AppleDeviceCodecProfile(
        id: "apple_a13_a14_h264_hevc",
        displayName: "A13/A14 HEVC class",
        platformScope: "iOS 18+ / iPadOS 18+ / iOS 26+",
        representativeDevices: [
            "iPhone 11 family",
            "iPhone 12 family",
            "iPad (9th generation)",
            "iPad (10th generation)",
            "iPad Air (4th generation)"
        ],
        chipFamilies: [
            "A13 Bionic",
            "A14 Bionic"
        ],
        hardwareDecodeCodecs: h264HEVCDolbyVisionDecode,
        hardwareEncodeCodecs: h264HEVCEncode,
        confidence: .runtimeProbeRequired,
        notes: "HEVC hardware class without AV1. AV1 input should use software decode plus hardware H.265 encode."
    )

    private static let iOSA15A16Family = HW_AppleDeviceCodecProfile(
        id: "apple_a15_a16_h264_hevc",
        displayName: "A15/A16 HEVC class",
        platformScope: "iOS 18+ / iPadOS 18+ / iOS 26+",
        representativeDevices: [
            "iPhone 13 family",
            "iPhone 14 family",
            "iPhone 15",
            "iPhone 15 Plus",
            "iPad mini (6th generation)",
            "iPad (A16)"
        ],
        chipFamilies: [
            "A15 Bionic",
            "A16 Bionic"
        ],
        hardwareDecodeCodecs: h264HEVCDolbyVisionDecode,
        hardwareEncodeCodecs: h264HEVCEncode,
        confidence: .runtimeProbeRequired,
        notes: "Common recent mobile class. AV1 is still a software-decode route unless runtime probing reports support."
    )

    private static let iPhoneProA15A16ProRes = HW_AppleDeviceCodecProfile(
        id: "apple_iphone_pro_a15_a16_prores",
        displayName: "iPhone Pro A15/A16 ProRes class",
        platformScope: "iOS 18+ / iOS 26+",
        representativeDevices: [
            "iPhone 13 Pro family",
            "iPhone 14 Pro family"
        ],
        chipFamilies: [
            "A15 Bionic",
            "A16 Bionic"
        ],
        hardwareDecodeCodecs: h264HEVCDolbyVisionDecode.union([.proRes]),
        hardwareEncodeCodecs: h264HEVCEncode.union([.proRes]),
        confidence: .runtimeProbeRequired,
        notes: "Adds ProRes-class media paths. AV1 remains software-fallback."
    )

    private static let iPadProM1M2ProRes = HW_AppleDeviceCodecProfile(
        id: "apple_ipad_pro_m1_m2_prores",
        displayName: "iPad Pro M1/M2 ProRes class",
        platformScope: "iPadOS 18+ / iPadOS 26+",
        representativeDevices: [
            "iPad Pro 11-inch (3rd generation)",
            "iPad Pro 11-inch (4th generation)",
            "iPad Pro 12.9-inch (5th generation)",
            "iPad Pro 12.9-inch (6th generation)"
        ],
        chipFamilies: [
            "M1",
            "M2"
        ],
        hardwareDecodeCodecs: h264HEVCDolbyVisionDecode.union([.proRes, .proResRaw]),
        hardwareEncodeCodecs: h264HEVCEncode.union([.proRes]),
        confidence: .runtimeProbeRequired,
        notes: "Pro iPad media-engine class before AV1 decode. AV1 input should fall back to software decode."
    )

    private static let iPadAirM1M2 = HW_AppleDeviceCodecProfile(
        id: "apple_ipad_air_m1_m2_h264_hevc",
        displayName: "iPad Air M1/M2 HEVC class",
        platformScope: "iPadOS 18+ / iPadOS 26+",
        representativeDevices: [
            "iPad Air (5th generation)",
            "iPad Air 11-inch (M2)",
            "iPad Air 13-inch (M2)"
        ],
        chipFamilies: [
            "M1",
            "M2"
        ],
        hardwareDecodeCodecs: h264HEVCDolbyVisionDecode,
        hardwareEncodeCodecs: h264HEVCEncode,
        confidence: .applePublishedSpec,
        notes: "Apple-published M2 iPad Air media-engine spec lists hardware H.264 and HEVC, not AV1."
    )

    private static let iPhoneA17ProAV1 = HW_AppleDeviceCodecProfile(
        id: "apple_a17pro_av1_decode",
        displayName: "A17 Pro AV1 decode class",
        platformScope: "iOS 18+ / iPadOS 26+",
        representativeDevices: [
            "iPhone 15 Pro",
            "iPhone 15 Pro Max",
            "iPad mini (A17 Pro)"
        ],
        chipFamilies: [
            "A17 Pro"
        ],
        hardwareDecodeCodecs: h264HEVCDolbyVisionDecode.union([.av1, .proRes]),
        hardwareEncodeCodecs: h264HEVCEncode.union([.proRes]),
        confidence: .applePublishedSpec,
        notes: "AV1 decode is available; AV1 encode is not treated as hardware-supported."
    )

    private static let iPhoneA18AV1 = HW_AppleDeviceCodecProfile(
        id: "apple_a18_av1_decode",
        displayName: "A18 AV1 decode class",
        platformScope: "iOS 26+",
        representativeDevices: [
            "iPhone 16",
            "iPhone 16 Plus",
            "iPhone 16e"
        ],
        chipFamilies: [
            "A18"
        ],
        hardwareDecodeCodecs: h264HEVCDolbyVisionDecode.union([.av1]),
        hardwareEncodeCodecs: h264HEVCEncode,
        confidence: .applePublishedSpec,
        notes: "Base A18 class has AV1 playback/decode support but no planned AV1 hardware encode path."
    )

    private static let iPhoneA18ProAV1ProRes = HW_AppleDeviceCodecProfile(
        id: "apple_a18pro_av1_decode_prores",
        displayName: "A18 Pro AV1 + ProRes class",
        platformScope: "iOS 26+",
        representativeDevices: [
            "iPhone 16 Pro",
            "iPhone 16 Pro Max"
        ],
        chipFamilies: [
            "A18 Pro"
        ],
        hardwareDecodeCodecs: h264HEVCDolbyVisionDecode.union([.av1, .proRes]),
        hardwareEncodeCodecs: h264HEVCEncode.union([.proRes]),
        confidence: .applePublishedSpec,
        notes: "Pro iPhone class with AV1 decode and ProRes support. AV1 output remains software/planned."
    )

    private static let iPhoneA19AV1 = HW_AppleDeviceCodecProfile(
        id: "apple_a19_av1_decode",
        displayName: "A19 AV1 decode class",
        platformScope: "iOS 26+",
        representativeDevices: [
            "iPhone 17",
            "iPhone 17e"
        ],
        chipFamilies: [
            "A19"
        ],
        hardwareDecodeCodecs: h264HEVCDolbyVisionDecode.union([.av1]),
        hardwareEncodeCodecs: h264HEVCEncode,
        confidence: .applePublishedSpec,
        notes: "A19 iPhone class lists HEVC, H.264, and AV1 playback while recording remains HEVC/H.264."
    )

    private static let iPhoneA19ProAV1 = HW_AppleDeviceCodecProfile(
        id: "apple_a19pro_av1_decode",
        displayName: "A19 Pro AV1 decode class",
        platformScope: "iOS 26+",
        representativeDevices: [
            "iPhone Air"
        ],
        chipFamilies: [
            "A19 Pro"
        ],
        hardwareDecodeCodecs: h264HEVCDolbyVisionDecode.union([.av1]),
        hardwareEncodeCodecs: h264HEVCEncode,
        confidence: .applePublishedSpec,
        notes: "Thin A19 Pro iPhone class lists AV1 playback but not ProRes recording."
    )

    private static let iPhoneA19ProAV1ProResRAW = HW_AppleDeviceCodecProfile(
        id: "apple_a19pro_av1_decode_prores_raw",
        displayName: "A19 Pro AV1 + ProRes RAW class",
        platformScope: "iOS 26+",
        representativeDevices: [
            "iPhone 17 Pro",
            "iPhone 17 Pro Max"
        ],
        chipFamilies: [
            "A19 Pro"
        ],
        hardwareDecodeCodecs: h264HEVCDolbyVisionDecode.union([.av1, .proRes, .proResRaw]),
        hardwareEncodeCodecs: h264HEVCEncode.union([.proRes]),
        confidence: .applePublishedSpec,
        notes: "Pro iPhone 17 class lists AV1 and ProRes playback plus ProRes RAW recording; ProRes RAW transcode output still requires runtime verification before HW encode is assumed."
    )

    private static let iPadM3M4AV1ProRes = HW_AppleDeviceCodecProfile(
        id: "apple_ipad_m3_m4_av1_prores",
        displayName: "iPad M3/M4 AV1 + ProRes class",
        platformScope: "iPadOS 26+",
        representativeDevices: [
            "iPad Air 11-inch (M3)",
            "iPad Air 13-inch (M3)",
            "iPad Pro 11-inch (M4)",
            "iPad Pro 13-inch (M4)"
        ],
        chipFamilies: [
            "M3",
            "M4"
        ],
        hardwareDecodeCodecs: h264HEVCDolbyVisionDecode.union([.av1, .proRes, .proResRaw]),
        hardwareEncodeCodecs: h264HEVCEncode.union([.proRes]),
        confidence: .applePublishedSpec,
        notes: "Modern iPad media-engine class with AV1 decode and ProRes-family hardware media paths."
    )

    private static let h264HEVCDolbyVisionDecode: Set<TaptionVideoCodec> = [
        .h264,
        .hevc,
        .hevcWithAlpha,
        .dolbyVisionHEVC
    ]

    private static let h264HEVCEncode: Set<TaptionVideoCodec> = [
        .h264,
        .hevc
    ]
}

struct HW_CodecRouteSimulationRow: Codable, Equatable, Identifiable {
    var profile: String
    var sourceCodec: TaptionVideoCodec
    var outputCodec: TaptionVideoCodec
    var support: TaptionCodecRouteSupport
    var executionKind: TaptionCodecRouteExecutionKind
    var selectedMode: TaptionEncoderMode
    var decodeBackend: TaptionEncodingBackend?
    var encodeBackend: TaptionEncodingBackend?
    var expectsHardwareDecode: Bool
    var expectsHardwareEncode: Bool
    var isEncodableNow: Bool
    var reason: String

    var id: String {
        "\(profile)-\(sourceCodec.rawValue)-\(outputCodec.rawValue)"
    }

    var route: TaptionCodecRoute {
        TaptionCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
    }

    var tsvFields: [String] {
        [
            profile,
            sourceCodec.rawValue,
            outputCodec.rawValue,
            support.rawValue,
            executionKind.rawValue,
            selectedMode.rawValue,
            decodeBackend?.rawValue ?? "",
            encodeBackend?.rawValue ?? "",
            expectsHardwareDecode ? "hardware" : "software_or_unavailable",
            expectsHardwareEncode ? "hardware" : "software_or_unavailable",
            isEncodableNow ? "true" : "false",
            HW_CodecRouteSimulator.cleanTSV(reason)
        ]
    }
}

struct HW_CodecRouteSimulationSummary: Codable, Equatable {
    var profileCount: Int
    var sourceCodecCount: Int
    var outputCodecCount: Int
    var routeCountPerProfile: Int
    var rowCount: Int
    var implementedRowCount: Int
    var plannedRowCount: Int
    var unsupportedRowCount: Int
    var hardwareDecodePreferenceViolationCount: Int
    var hardwareEncodePreferenceViolationCount: Int
    var av1ToHEVCPathCounts: [TaptionCodecRouteExecutionKind: Int]

    var isPassing: Bool {
        unsupportedRowCount == 0
            && hardwareDecodePreferenceViolationCount == 0
            && hardwareEncodePreferenceViolationCount == 0
    }

    var av1ToHEVCPathSummary: String {
        TaptionCodecRouteExecutionKind.allDisplayOrder.compactMap { kind in
            guard let count = av1ToHEVCPathCounts[kind], count > 0 else {
                return nil
            }
            return "\(kind.shortDisplayName) \(count)"
        }
        .joined(separator: " · ")
    }
}

enum HW_CodecRouteSimulator {
    static let tsvHeader = [
        "profile",
        "source_codec",
        "output_codec",
        "support",
        "path",
        "selected_mode",
        "decode_backend",
        "encode_backend",
        "expected_decode_priority",
        "expected_encode_priority",
        "encodable_now",
        "reason"
    ]

    static func rows(
        profiles: [TaptionCodecHardwareSupportProfile] = TaptionCodecHardwareSupportProfile.simulationProfiles,
        sourceCodecs: [TaptionVideoCodec] = TaptionCodecRegistry.universalSourceCodecs,
        outputCodecs: [TaptionVideoCodec] = TaptionCodecRegistry.universalOutputCodecs
    ) -> [HW_CodecRouteSimulationRow] {
        profiles.flatMap { profile in
            sourceCodecs.flatMap { sourceCodec in
                let asset = simulatedAsset(sourceCodec: sourceCodec)
                return outputCodecs.map { outputCodec in
                    let selection = TaptionCodecRoutePlanner.selectRoute(
                        for: asset,
                        outputCodec: outputCodec,
                        requestedMode: .automatic,
                        hardwareSupport: profile
                    )
                    return HW_CodecRouteSimulationRow(
                        profile: profile.name,
                        sourceCodec: sourceCodec,
                        outputCodec: outputCodec,
                        support: selection.support,
                        executionKind: selection.executionKind,
                        selectedMode: selection.selectedMode,
                        decodeBackend: selection.decodeBackend,
                        encodeBackend: selection.encodeBackend,
                        expectsHardwareDecode: profile.canHardwareDecode(sourceCodec),
                        expectsHardwareEncode: profile.canHardwareEncode(outputCodec),
                        isEncodableNow: selection.isEncodableNow,
                        reason: selection.reason
                    )
                }
            }
        }
    }

    static func summary(
        rows: [HW_CodecRouteSimulationRow] = rows()
    ) -> HW_CodecRouteSimulationSummary {
        let profiles = Set(rows.map(\.profile))
        let sourceCodecs = Set(rows.map(\.sourceCodec))
        let outputCodecs = Set(rows.map(\.outputCodec))
        let routeCountPerProfile = sourceCodecs.count * outputCodecs.count
        let implementedRows = rows.filter(\.isEncodableNow)
        let plannedRows = rows.filter { $0.executionKind == .planned }
        let unsupportedRows = rows.filter { $0.support == .unsupported }
        let hardwareDecodeViolations = rows.filter {
            $0.support != .unsupported
                && $0.expectsHardwareDecode
                && $0.decodeBackend != .appleAVAssetExport
        }
        let hardwareEncodeViolations = rows.filter {
            $0.support != .unsupported
                && $0.expectsHardwareEncode
                && $0.encodeBackend != .appleVideoToolbox
        }
        let av1ToHEVCRows = rows.filter {
            $0.sourceCodec == .av1 && $0.outputCodec == .hevc
        }
        let pathCounts = Dictionary(
            grouping: av1ToHEVCRows,
            by: \.executionKind
        ).mapValues(\.count)

        return HW_CodecRouteSimulationSummary(
            profileCount: profiles.count,
            sourceCodecCount: sourceCodecs.count,
            outputCodecCount: outputCodecs.count,
            routeCountPerProfile: routeCountPerProfile,
            rowCount: rows.count,
            implementedRowCount: implementedRows.count,
            plannedRowCount: plannedRows.count,
            unsupportedRowCount: unsupportedRows.count,
            hardwareDecodePreferenceViolationCount: hardwareDecodeViolations.count,
            hardwareEncodePreferenceViolationCount: hardwareEncodeViolations.count,
            av1ToHEVCPathCounts: pathCounts
        )
    }

    static func validationFailures(
        rows: [HW_CodecRouteSimulationRow] = rows()
    ) -> [String] {
        var failures: [String] = []
        let summary = summary(rows: rows)
        let expectedRouteCount = TaptionCodecRegistry.universalSourceCodecs.count
            * TaptionCodecRegistry.universalOutputCodecs.count

        if summary.routeCountPerProfile != expectedRouteCount {
            failures.append("Universal route matrix expected \(expectedRouteCount) routes per profile, got \(summary.routeCountPerProfile).")
        }

        if summary.rowCount != summary.profileCount * expectedRouteCount {
            failures.append("Simulation expected \(summary.profileCount * expectedRouteCount) rows, got \(summary.rowCount).")
        }

        for row in rows where row.support == .implemented && row.isEncodableNow {
            if ![.hardware, .mixed, .software].contains(row.executionKind) {
                failures.append("\(row.profile) \(row.route.displayName) selected invalid implemented path \(row.executionKind.rawValue).")
            }

            if row.expectsHardwareDecode,
               row.expectsHardwareEncode,
               row.executionKind != .hardware {
                failures.append("\(row.profile) \(row.route.displayName) should prefer hardware.")
            }
        }

        for row in rows where row.support == .implemented && !row.isEncodableNow {
            failures.append("\(row.profile) \(row.route.displayName) is implemented but not encodable in the simulated profile.")
        }

        for row in rows where row.support != .unsupported {
            if row.expectsHardwareDecode,
               row.decodeBackend != .appleAVAssetExport {
                failures.append("\(row.profile) \(row.route.displayName) should use hardware decode backend when available.")
            }
            if row.expectsHardwareEncode,
               row.encodeBackend != .appleVideoToolbox {
                failures.append("\(row.profile) \(row.route.displayName) should use hardware encode backend when available.")
            }
        }

        for row in rows where row.support == .unsupported {
            failures.append("\(row.profile) \(row.route.displayName) should be covered by the universal route roadmap.")
        }

        let av1ToHEVCRows = rows.filter {
            $0.sourceCodec == .av1 && $0.outputCodec == .hevc
        }
        if av1ToHEVCRows.count != summary.profileCount {
            failures.append("AV1 to H.265 should have one simulation row per profile.")
        }
        if av1ToHEVCRows.contains(where: { $0.support != .implemented || !$0.isEncodableNow }) {
            failures.append("AV1 to H.265 should stay implemented and encodable for every simulation profile.")
        }

        return failures
    }

    static func cleanTSV(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func simulatedAsset(sourceCodec: TaptionVideoCodec) -> TaptionVideoAsset {
        TaptionVideoAsset(
            displayName: "\(sourceCodec.rawValue).mp4",
            location: TaptionVideoAssetLocation(kind: .file),
            container: .mp4,
            duration: 1,
            videoTrack: TaptionVideoTrackInfo(
                codec: sourceCodec,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30)
            ),
            audioTracks: [
                TaptionAudioTrackInfo(codec: .aac, channelCount: 2, sampleRate: 48_000)
            ],
            fingerprint: TaptionMediaFingerprint(fileSize: 1_000_000)
        )
    }
}

private extension TaptionCodecRouteExecutionKind {
    static let allDisplayOrder: [TaptionCodecRouteExecutionKind] = [
        .hardware,
        .mixed,
        .software,
        .planned,
        .unsupported
    ]
}
