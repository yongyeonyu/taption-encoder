//
//  CodecRoutePlannerTests+SourceAndUniversal.swift
//  Tests 2093-4004 of the original CodecRoutePlannerTests.swift, moved here
//  unchanged. The name is the two leading subjects of the tests in this
//  range, counted from the test names.
//

import AVFoundation
import AudioToolbox
import CoreImage
import CoreMedia
import SwiftUI
import SwiftVLC
import UIKit
import XCTest
@testable import Taption_Encoder

extension CodecRoutePlannerTests {
    func testUniversalVideoCommandPlannerBuildsEveryPlannableSourceOutputPair() throws {
        for sourceCodec in TaptionCodecRegistry.universalSourceCodecs {
            for outputCodec in SW_FFmpegCodecCommandPlanner.plannableVideoOutputCodecs {
                let route = TaptionCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
                let request = TaptionCodecTranscodeRequest(
                    sourceURL: URL(fileURLWithPath: "/tmp/input-\(sourceCodec.rawValue).mkv"),
                    outputURL: URL(fileURLWithPath: "/tmp/output-\(outputCodec.rawValue).mp4"),
                    route: route,
                    options: .preservingSource(outputCodec: outputCodec, container: .mp4)
                )

                let plan = try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(request: request)

                XCTAssertEqual(plan.backend, .ffmpegFamily, route.displayName)
                XCTAssertEqual(plan.routeSummary, route.displayName, route.displayName)
                XCTAssertTrue(plan.arguments.contains("-c:v"), route.displayName)
                XCTAssertEqual(
                    plan.arguments.last,
                    "/tmp/output-\(outputCodec.rawValue).mp4",
                    route.displayName
                )
            }
        }
    }

    func testUniversalVideoCommandPlannerAcceptsEveryReadableInputContainer() throws {
        let route = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc)

        for inputContainer in SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.readableContainers.sorted(by: containerSort) {
            let request = TaptionCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/input.\(inputContainer.defaultFileExtension)"),
                outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
                route: route,
                options: .preservingSource(outputCodec: .hevc, container: .mp4)
            )

            let plan = try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(request: request)

            XCTAssertEqual(plan.sourceURL.pathExtension, inputContainer.defaultFileExtension, inputContainer.rawValue)
            XCTAssertEqual(plan.routeSummary, route.displayName, inputContainer.rawValue)
        }
    }

    func testUniversalVideoCommandPlannerAcceptsEveryWritableOutputContainer() throws {
        let route = TaptionCodecRoute(sourceCodec: .vp9, outputCodec: .hevc)

        for outputContainer in SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.writableContainers.sorted(by: containerSort) {
            let request = TaptionCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/input.webm"),
                outputURL: URL(fileURLWithPath: "/tmp/output.\(outputContainer.defaultFileExtension)"),
                route: route,
                options: .preservingSource(outputCodec: .hevc, container: outputContainer)
            )

            let plan = try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(request: request)

            XCTAssertEqual(
                plan.arguments.last,
                "/tmp/output.\(outputContainer.defaultFileExtension)",
                outputContainer.rawValue
            )
        }
    }

    func testUniversalAudioCommandPlannerAcceptsEveryReadableInputContainer() throws {
        let route = TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac)

        for inputContainer in SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.readableContainers.sorted(by: containerSort) {
            let request = TaptionAudioCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/audio.\(inputContainer.defaultFileExtension)"),
                outputURL: URL(fileURLWithPath: "/tmp/audio-output.mp4"),
                route: route,
                options: .preservingSource(outputCodec: .flac, outputContainer: .mp4)
            )

            let plan = try SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(request: request)

            XCTAssertEqual(plan.sourceURL.pathExtension, inputContainer.defaultFileExtension, inputContainer.rawValue)
            XCTAssertEqual(plan.routeSummary, route.displayName, inputContainer.rawValue)
        }
    }

    func testUniversalCommandPlannerRejectsUnknownInputContainer() {
        let videoRoute = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc)
        let videoRequest = TaptionCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.notmedia"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            route: videoRoute,
            options: .preservingSource(outputCodec: .hevc, container: .mp4)
        )
        let audioRoute = TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac)
        let audioRequest = TaptionAudioCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/audio.notmedia"),
            outputURL: URL(fileURLWithPath: "/tmp/audio-output.mp4"),
            route: audioRoute,
            options: .preservingSource(outputCodec: .flac, outputContainer: .mp4)
        )

        XCTAssertThrowsError(try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(request: videoRequest)) { error in
            XCTAssertEqual(
                error as? SW_FFmpegCodecCommandPlannerError,
                .inputContainerUnavailable(.unknown)
            )
        }
        XCTAssertThrowsError(try SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(request: audioRequest)) { error in
            XCTAssertEqual(
                error as? SW_FFmpegCodecCommandPlannerError,
                .inputContainerUnavailable(.unknown)
            )
        }
    }

    func testVideoContainerInferenceCoversLegacyAndRawAliases() {
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "qt"), .mov)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "mts"), .mpegTransportStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "m2ts"), .mpegTransportStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "m2t"), .mpegTransportStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "tp"), .mpegTransportStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "trp"), .mpegTransportStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "tod"), .mpegTransportStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "mpe"), .mpegProgramStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "vob"), .mpegProgramStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "mod"), .mpegProgramStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "dat"), .mpegProgramStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "divx"), .avi)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "lrf"), .lrf)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "dif"), .dv)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "ogv"), .ogg)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "ogm"), .ogg)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "f4v"), .flv)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "3gpp"), .threeGP)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "3g2"), .threeGPP2)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "3gpp2"), .threeGPP2)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "dvr-ms"), .asf)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "nut"), .nut)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "roq"), .roq)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "rm"), .realMedia)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "rmvb"), .realMedia)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "av1"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "hevc"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "264"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "265"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "h263"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "h261"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "m1v"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "m2v"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "vc1"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "notmedia"), .unknown)
    }

    func testUniversalVideoCommandPlannerAcceptsRepresentativeReadableAliases() throws {
        let route = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc)
        let aliases: [(fileExtension: String, container: TaptionVideoContainer)] = [
            ("divx", .avi),
            ("m2t", .mpegTransportStream),
            ("tp", .mpegTransportStream),
            ("trp", .mpegTransportStream),
            ("tod", .mpegTransportStream),
            ("mpe", .mpegProgramStream),
            ("mod", .mpegProgramStream),
            ("dat", .mpegProgramStream),
            ("dif", .dv),
            ("ogm", .ogg),
            ("3gpp", .threeGP),
            ("3gpp2", .threeGPP2),
            ("dvr-ms", .asf),
            ("nut", .nut),
            ("roq", .roq),
            ("rm", .realMedia),
            ("rmvb", .realMedia),
            ("264", .rawElementaryStream),
            ("265", .rawElementaryStream),
            ("av1", .rawElementaryStream),
            ("h263", .rawElementaryStream),
            ("h261", .rawElementaryStream),
            ("m1v", .rawElementaryStream),
            ("m2v", .rawElementaryStream),
            ("vc1", .rawElementaryStream)
        ]

        for alias in aliases {
            let request = TaptionCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/input.\(alias.fileExtension)"),
                outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
                route: route,
                options: .preservingSource(outputCodec: .hevc, container: .mp4)
            )

            let plan = try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(request: request)

            XCTAssertEqual(
                TaptionVideoContainer.inferred(fromFileExtension: alias.fileExtension),
                alias.container,
                alias.fileExtension
            )
            XCTAssertEqual(plan.sourceURL.pathExtension, alias.fileExtension, alias.fileExtension)
            XCTAssertEqual(plan.routeSummary, route.displayName, alias.fileExtension)
        }
    }

    func testImportableVideoTypesMatchCurrentLaunchInputContainers() throws {
        let launchExtensions = Set(
            TaptionLaunchSupportCatalog.supportedInputContainers
                .flatMap(\.supportedFileExtensions)
        )
        let pickerExtensions = Set(ImportableVideoTypes.fileExtensions)

        XCTAssertEqual(pickerExtensions, launchExtensions)
        XCTAssertEqual(SupportedVideoFileExtensions.fileExtensionSet, launchExtensions)

        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = rootURL
            .appendingPathComponent("TaptionEncoder/Info.plist")
        let thumbnailProviderURL = rootURL
            .appendingPathComponent("TaptionEncoderThumbnailExtension/ThumbnailProvider.swift")
        let plistData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let declarations = try XCTUnwrap(
            plist["UTExportedTypeDeclarations"] as? [[String: Any]]
        )
        XCTAssertNil(plist["UTImportedTypeDeclarations"])
        let documentTypes = try XCTUnwrap(
            plist["CFBundleDocumentTypes"] as? [[String: Any]]
        )
        let legacyDocumentType = try XCTUnwrap(
            documentTypes.first { documentType in
                (documentType["LSItemContentTypes"] as? [String])?.contains("com.taption.legacy-video") == true
            }
        )
        let standardVideoDocumentType = try XCTUnwrap(
            documentTypes.first { documentType in
                (documentType["LSItemContentTypes"] as? [String])?.contains("public.movie") == true
            }
        )
        let plistExtensions = Set(
            declarations.flatMap { declaration -> [String] in
                guard let tagSpecification = declaration["UTTypeTagSpecification"] as? [String: Any],
                      let fileExtensions = tagSpecification["public.filename-extension"] as? [String] else {
                    return []
                }
                return fileExtensions
            }
        )
        let documentContentTypes = Set(
            documentTypes.flatMap { documentType -> [String] in
                documentType["LSItemContentTypes"] as? [String] ?? []
            }
        )
        let documentHandlerRanks = Set(
            documentTypes.compactMap { documentType in
                documentType["LSHandlerRank"] as? String
            }
        )
        let documentIconFiles = Set(
            documentTypes.flatMap { documentType -> [String] in
                documentType["CFBundleTypeIconFiles"] as? [String] ?? []
            }
        )
        let exportedIdentifiers = Set(
            declarations.compactMap { declaration in
                declaration["UTTypeIdentifier"] as? String
            }
        )
        let exportedConformance = Set(
            declarations.flatMap { declaration -> [String] in
                declaration["UTTypeConformsTo"] as? [String] ?? []
            }
        )
        let exportedIconFiles = Set(
            declarations.compactMap { declaration in
                declaration["UTTypeIconFile"] as? String
            }
        )
        let systemHandledExtensions: Set<String> = [
            "3g2",
            "3gp",
            "3gpp",
            "3gpp2",
            "m4v",
            "mov",
            "mp4",
            "qt"
        ]
        let legacySystemContentTypes: Set<String> = [
            "public.avi",
            "org.smpte.mxf",
            "public.dv-movie",
            "com.microsoft.advanced-systems-format",
            "com.microsoft.windows-media-wmv",
            "com.real.realmedia",
            "com.real.realmedia-vbr",
            "org.webmproject.webm",
            "com.adobe.flash.video",
            "public.mpeg",
            "public.mpeg-2-video",
            "public.mpeg-2-transport-stream",
            "public.avchd-mpeg-2-transport-stream",
            "org.xiph.ogv",
            "org.xiph.ogg-audio"
        ]
        let externalPlayerExtensions = launchExtensions.subtracting(systemHandledExtensions)
        let standardVideoContentTypes: Set<String> = [
            "public.audiovisual-content",
            "public.movie",
            "public.video",
            "public.mpeg-4",
            "com.apple.m4v-video",
            "com.apple.quicktime-movie",
            "public.3gpp",
            "public.3gpp2"
        ]
        let thumbnailProviderText = try String(contentsOf: thumbnailProviderURL, encoding: .utf8)
        let thumbnailExtensionLiterals = Set(
            thumbnailProviderText
                .split(separator: "\n")
                .compactMap { line -> String? in
                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmedLine.hasPrefix("\"") else {
                        return nil
                    }
                    let valueStart = trimmedLine.index(after: trimmedLine.startIndex)
                    guard let valueEnd = trimmedLine[valueStart...].firstIndex(of: "\"") else {
                        return nil
                    }
                    return String(trimmedLine[valueStart..<valueEnd])
                }
        )
        let thumbnailLegacyExtensions = thumbnailExtensionLiterals.subtracting(systemHandledExtensions)

        XCTAssertTrue(
            plistExtensions.isSuperset(of: externalPlayerExtensions),
            "Missing Info.plist legacy video extensions: \(externalPlayerExtensions.subtracting(plistExtensions).sorted().joined(separator: ", "))"
        )
        XCTAssertEqual(
            plistExtensions,
            externalPlayerExtensions,
            "Info.plist should only claim currently supported Taption Encoder-only video extensions."
        )
        XCTAssertTrue(
            plistExtensions.isDisjoint(with: systemHandledExtensions),
            "Info.plist should not claim default-player video extensions: \(plistExtensions.intersection(systemHandledExtensions).sorted().joined(separator: ", "))"
        )
        XCTAssertEqual(
            thumbnailLegacyExtensions,
            externalPlayerExtensions,
            "Thumbnail extension should only generate legacy posters for currently supported Taption Encoder-only video extensions."
        )
        XCTAssertTrue(
            thumbnailExtensionLiterals.isSuperset(of: systemHandledExtensions),
            "Thumbnail extension should preserve frame thumbnails for system-handled video extensions."
        )
        XCTAssertTrue(documentContentTypes.isSuperset(of: ["com.taption.legacy-video"]))
        XCTAssertTrue(documentContentTypes.isSuperset(of: legacySystemContentTypes))
        XCTAssertTrue(documentContentTypes.isSuperset(of: standardVideoContentTypes))
        XCTAssertEqual(documentHandlerRanks, ["Owner"])
        XCTAssertEqual(legacyDocumentType["LSHandlerRank"] as? String, "Owner")
        XCTAssertEqual(legacyDocumentType["CFBundleTypeRole"] as? String, "Viewer")
        XCTAssertTrue(
            Set(legacyDocumentType["LSItemContentTypes"] as? [String] ?? []).isSuperset(of: legacySystemContentTypes),
            "Legacy document type should claim Files-resolved Taption Encoder video UTIs."
        )
        XCTAssertEqual(standardVideoDocumentType["LSHandlerRank"] as? String, "Owner")
        XCTAssertEqual(standardVideoDocumentType["CFBundleTypeRole"] as? String, "Viewer")
        XCTAssertEqual(documentIconFiles, ["AppIcon60x60"])
        XCTAssertEqual(exportedIdentifiers, ["com.taption.legacy-video"])
        XCTAssertTrue(exportedConformance.isSuperset(of: ["public.movie", "public.video"]))
        XCTAssertEqual(exportedIconFiles, ["AppIcon60x60"])
        XCTAssertEqual(plist["LSSupportsOpeningDocumentsInPlace"] as? Bool, true)
        XCTAssertEqual(plist["UIFileSharingEnabled"] as? Bool, true)
        // The app browses with its own folder pickers, not UIDocumentBrowserViewController. Advertising
        // `UISupportsDocumentBrowser` makes iOS treat the app as a document-browser app (and changes how Files
        // hands files over), so 1.1.13 removed it on purpose. Keep it out.
        XCTAssertNil(
            plist["UISupportsDocumentBrowser"],
            "BOKKI Encoder is not a document-browser app; LSSupportsOpeningDocumentsInPlace is what Files needs."
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(plist["UIBackgroundModes"] as? [String])),
            ["audio", "processing"]
        )
        XCTAssertTrue(SupportedVideoFileExtensions.contains(".mp4"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("qt"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("M4V"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("avi"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("webm"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("DAT"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains(".m2t"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("MTS"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("trp"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("dif"))
        XCTAssertTrue(ImportableVideoTypes.fileExtensions.contains("lrf"))
        XCTAssertTrue(ImportableVideoTypes.fileExtensions.contains("nut"))
        XCTAssertTrue(ImportableVideoTypes.fileExtensions.contains("dvr-ms"))
        XCTAssertTrue(ImportableVideoTypes.fileExtensions.contains("vc1"))
        XCTAssertTrue(ImportableVideoTypes.fileExtensions.contains("h261"))
    }

    func testExternalVideoOpenPolicyHandlesOnlySupportedFileURLs() {
        XCTAssertTrue(ExternalVideoOpenPolicy.canHandle(url: URL(fileURLWithPath: "/tmp/Movie.MP4")))
        XCTAssertTrue(ExternalVideoOpenPolicy.canHandle(url: URL(fileURLWithPath: "/tmp/Legacy.AVI")))
        XCTAssertTrue(ExternalVideoOpenPolicy.canHandle(url: URL(fileURLWithPath: "/tmp/Clip.h261")))
        XCTAssertTrue(ExternalVideoOpenPolicy.canHandle(url: URL(fileURLWithPath: "/tmp/Camera.M2TS")))
        XCTAssertTrue(ExternalVideoOpenPolicy.canHandle(url: URL(fileURLWithPath: "/tmp/DJI.LRF")))
        XCTAssertTrue(ExternalVideoOpenPolicy.canHandle(url: URL(fileURLWithPath: "/tmp/Archive.nut")))
        XCTAssertFalse(ExternalVideoOpenPolicy.canHandle(url: URL(fileURLWithPath: "/tmp/notes.txt")))
        XCTAssertFalse(ExternalVideoOpenPolicy.canHandle(url: URL(string: "https://example.com/movie.mp4")!))
    }

    @MainActor
    func testExternalVideoOpenInboxRetainsDelegateURLUntilHomeViewDrains() {
        _ = ExternalVideoOpenInbox.drainPendingURLs()
        let url = URL(fileURLWithPath: "/tmp/Movie.MP4")

        ExternalVideoOpenInbox.enqueue(url, postsNotification: false)

        XCTAssertEqual(ExternalVideoOpenInbox.drainPendingURLs(), [url])
        XCTAssertEqual(ExternalVideoOpenInbox.drainPendingURLs(), [])
    }

    func testQuickLookThumbnailExtensionCoversDocumentBrowserVideoTypes() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appPlistURL = rootURL.appendingPathComponent("TaptionEncoder/Info.plist")
        let extensionPlistURL = rootURL.appendingPathComponent("TaptionEncoderThumbnailExtension/Info.plist")
        let projectURL = rootURL.appendingPathComponent("TaptionEncoder.xcodeproj/project.pbxproj")
        let appPlist = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: try Data(contentsOf: appPlistURL),
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let extensionPlist = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: try Data(contentsOf: extensionPlistURL),
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let documentTypes = try XCTUnwrap(
            appPlist["CFBundleDocumentTypes"] as? [[String: Any]]
        )
        let documentContentTypes = Set(
            documentTypes.flatMap { documentType in
                documentType["LSItemContentTypes"] as? [String] ?? []
            }
        )
        let extensionInfo = try XCTUnwrap(extensionPlist["NSExtension"] as? [String: Any])
        let attributes = try XCTUnwrap(extensionInfo["NSExtensionAttributes"] as? [String: Any])
        let supportedContentTypes = Set(
            try XCTUnwrap(attributes["QLSupportedContentTypes"] as? [String])
        )
        let appTypeDeclarations = try XCTUnwrap(
            appPlist["UTExportedTypeDeclarations"] as? [[String: Any]]
        )
        let appLegacyDeclaration = try XCTUnwrap(
            appTypeDeclarations.first { declaration in
                declaration["UTTypeIdentifier"] as? String == "com.taption.legacy-video"
            }
        )
        let appLegacyTagSpecification = try XCTUnwrap(
            appLegacyDeclaration["UTTypeTagSpecification"] as? [String: Any]
        )
        let appLegacyFileExtensions = Set(
            try XCTUnwrap(appLegacyTagSpecification["public.filename-extension"] as? [String])
        )
        let extensionImportedDeclarations = try XCTUnwrap(
            extensionPlist["UTImportedTypeDeclarations"] as? [[String: Any]]
        )
        let extensionLegacyDeclaration = try XCTUnwrap(
            extensionImportedDeclarations.first { declaration in
                declaration["UTTypeIdentifier"] as? String == "com.taption.legacy-video"
            }
        )
        let extensionLegacyConformance = Set(
            try XCTUnwrap(extensionLegacyDeclaration["UTTypeConformsTo"] as? [String])
        )
        let extensionLegacyTagSpecification = try XCTUnwrap(
            extensionLegacyDeclaration["UTTypeTagSpecification"] as? [String: Any]
        )
        let extensionLegacyFileExtensions = Set(
            try XCTUnwrap(extensionLegacyTagSpecification["public.filename-extension"] as? [String])
        )
        let projectText = try String(contentsOf: projectURL, encoding: .utf8)
        let filesResolvedContentTypes: Set<String> = [
            "com.apple.m4v-video",
            "public.avi",
            "org.smpte.mxf",
            "public.dv-movie",
            "com.microsoft.advanced-systems-format",
            "com.microsoft.windows-media-wmv",
            "com.real.realmedia",
            "com.real.realmedia-vbr",
            "org.webmproject.webm",
            "com.adobe.flash.video",
            "public.mpeg",
            "public.mpeg-2-video",
            "public.mpeg-2-transport-stream",
            "public.avchd-mpeg-2-transport-stream",
            "org.xiph.ogv",
            "org.xiph.ogg-audio"
        ]

        XCTAssertEqual(
            extensionInfo["NSExtensionPointIdentifier"] as? String,
            "com.apple.quicklook.thumbnail"
        )
        XCTAssertEqual(
            extensionInfo["NSExtensionPrincipalClass"] as? String,
            "$(PRODUCT_MODULE_NAME).ThumbnailProvider"
        )
        XCTAssertEqual(
            supportedContentTypes,
            ["com.taption.legacy-video"],
            "Thumbnail extension must avoid system-supported QL types that App Store Connect rejects."
        )
        XCTAssertTrue(
            supportedContentTypes.isDisjoint(with: documentContentTypes.subtracting(["com.taption.legacy-video"])),
            "Thumbnail extension must not declare system document types: \(supportedContentTypes.intersection(documentContentTypes.subtracting(["com.taption.legacy-video"])).sorted().joined(separator: ", "))"
        )
        XCTAssertTrue(
            supportedContentTypes.isDisjoint(with: filesResolvedContentTypes),
            "Thumbnail extension must not declare system-resolved file UTIs: \(supportedContentTypes.intersection(filesResolvedContentTypes).sorted().joined(separator: ", "))"
        )
        XCTAssertNil(extensionPlist["UTExportedTypeDeclarations"])
        XCTAssertEqual(extensionLegacyFileExtensions, appLegacyFileExtensions)
        XCTAssertTrue(extensionLegacyFileExtensions.contains("h261"))
        XCTAssertTrue(extensionLegacyConformance.isSuperset(of: ["public.movie", "public.video"]))
        XCTAssertTrue(projectText.contains("SampleThumbnailCatalog.swift in Sources"))
        XCTAssertFalse(projectText.contains("SampleThumbnails in Resources"), "Source-only cleanup intentionally removed bundled sample images.")
        let extensionResourcesBlock = try XCTUnwrap(
            projectObjectBlock(
                id: "B10000000000000000000600",
                label: "Resources",
                in: projectText
            )
        )
        let testResourcesBlock = try XCTUnwrap(
            projectObjectBlock(
                id: "8A2B3C4D5E6F701000000600",
                label: "Resources",
                in: projectText
            )
        )
        XCTAssertFalse(extensionResourcesBlock.contains("SampleThumbnails in Resources"))
        let providerText = try String(contentsOf: rootURL.appendingPathComponent("TaptionEncoderThumbnailExtension/ThumbnailProvider.swift"), encoding: .utf8)
        XCTAssertTrue(providerText.contains("avFoundationImage("))
        XCTAssertTrue(providerText.contains("supportedVideoImage("), "Missing samples must retain real-frame and fallback thumbnail paths.")
        XCTAssertFalse(
            testResourcesBlock.contains("SampleThumbnails in Resources"),
            "SampleThumbnails should not be routed only into the test bundle."
        )
        XCTAssertTrue(projectText.contains("TaptionEncoderThumbnailExtension.appex in Embed Foundation Extensions"))
        XCTAssertTrue(projectText.contains("com.apple.product-type.app-extension"))
        XCTAssertTrue(projectText.contains("PRODUCT_BUNDLE_IDENTIFIER = com.taption.encoder.thumbnail"))
        XCTAssertTrue(projectText.contains("APPLICATION_EXTENSION_API_ONLY = YES"))
    }

    func testBundledTestVideosMatchCurrentLaunchVideoSupport() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let testVideosURL = rootURL.appendingPathComponent("TaptionEncoder/TestVideos", isDirectory: true)
        let filenames = try FileManager.default
            .contentsOfDirectory(atPath: testVideosURL.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
        let videoFilenames = filenames.filter { $0 != TaptionTestVideoSeeder.sourceNoticeFilename }

        XCTAssertEqual(Set(videoFilenames), Set(TaptionTestVideoSeeder.expectedBundledVideoSampleFilenames))
        XCTAssertEqual(
            videoFilenames.count,
            bundledAvailableNowSampleCodecExpectations().count
                + bundledPlannedSampleCodecExpectations().count
                + TaptionLaunchSupportCatalog.hardwareGatedInputVideoCodecs.count
        )
        XCTAssertTrue(filenames.contains(TaptionTestVideoSeeder.sourceNoticeFilename))
        XCTAssertFalse(videoFilenames.contains { $0.hasPrefix("available-now_") })
        XCTAssertFalse(videoFilenames.contains { $0.hasPrefix("supported-hardware_") })
        XCTAssertFalse(videoFilenames.contains { $0.contains("_") })
        XCTAssertFalse(videoFilenames.contains("Y41P.avi"))
    }

    func testBundledSampleSourceNoticeRejectsGeneratedOnlyFixtures() throws {
        let sourceNoticeURL = bundledTestVideosURL().appendingPathComponent(TaptionTestVideoSeeder.sourceNoticeFilename)
        let sourceNotice = try String(contentsOf: sourceNoticeURL, encoding: .utf8)

        XCTAssertFalse(sourceNotice.contains("Generated codec-conformance fixture"))
        XCTAssertFalse(sourceNotice.contains("Generated with FFmpeg"))
        XCTAssertFalse(sourceNotice.contains("mpeg_demuxer_crash.mpg"))
        XCTAssertFalse(sourceNotice.contains("real/VC-RV10/thankyou.rm"))
        XCTAssertFalse(sourceNotice.contains("real/VC-RV20/Dolby7.5fps1.rm"))
        XCTAssertFalse(sourceNotice.contains("snow-chroma-bug.avi"))
        XCTAssertFalse(sourceNotice.contains("audible tone track when"))
        XCTAssertFalse(sourceNotice.contains("Derived from Chromium bear.mp4"))
        XCTAssertTrue(sourceNotice.contains("Official Blender Open Movie downloads"))
        XCTAssertTrue(sourceNotice.contains("BigBuckBunny_320x180.mp4"))
        XCTAssertTrue(sourceNotice.contains("sintel_trailer-480p.mp4"))
        XCTAssertTrue(sourceNotice.contains("original"))
        XCTAssertTrue(sourceNotice.contains("source audio"))
        XCTAssertFalse(sourceNotice.contains("Y41P.avi"))
    }

    func testBundledSampleThumbnailResourcesCoverSeededVideos() throws {
        let testVideosURL = bundledTestVideosURL()
        let thumbnailsURL = testVideosURL
            .deletingLastPathComponent()
            .appendingPathComponent(SampleThumbnailCatalog.resourceSubdirectory, isDirectory: true)
        let videoFilenames = try FileManager.default
            .contentsOfDirectory(atPath: testVideosURL.path)
            .filter { !$0.hasPrefix(".") && $0 != TaptionTestVideoSeeder.sourceNoticeFilename }
            .sorted()
        let thumbnailFilenames = try FileManager.default
            .contentsOfDirectory(atPath: thumbnailsURL.path)
            .filter { $0.hasSuffix(".png") }
            .sorted()

        XCTAssertEqual(Set(videoFilenames), SampleThumbnailCatalog.expectedSampleFilenames)
        XCTAssertEqual(thumbnailFilenames.count, videoFilenames.count)

        for filename in videoFilenames {
            let sampleURL = testVideosURL.appendingPathComponent(filename)
            let resourceName = try XCTUnwrap(SampleThumbnailCatalog.resourceName(for: sampleURL), filename)
            let thumbnailURL = thumbnailsURL.appendingPathComponent("\(resourceName).png")
            let data = try Data(contentsOf: thumbnailURL)
            let image = try XCTUnwrap(UIImage(data: data), filename)

            XCTAssertEqual(image.size.width, 320, filename)
            XCTAssertEqual(image.size.height, 180, filename)
            XCTAssertGreaterThan(data.count, 128, filename)
        }

        let visiblePreviewSamples = [
            "H.261.h261",
            "R210.avi",
            "RealVideo 1.0.rm",
            "RealVideo.rm",
            "RoQ Video.roq",
            "Snow.avi"
        ]
        for filename in visiblePreviewSamples {
            let sampleURL = testVideosURL.appendingPathComponent(filename)
            let resourceName = try XCTUnwrap(SampleThumbnailCatalog.resourceName(for: sampleURL), filename)
            let thumbnailURL = thumbnailsURL.appendingPathComponent("\(resourceName).png")
            let metrics = try visiblePixelMetrics(fromPNGData: try Data(contentsOf: thumbnailURL))

            XCTAssertGreaterThan(metrics.nonBlackRatio, 0.2, filename)
            XCTAssertGreaterThan(metrics.standardDeviation, 4, filename)
        }
    }

    func testBundledAvailableNowSamplesInspectToExpectedLaunchCodecs() async throws {
        let testVideosURL = bundledTestVideosURL()
        let expectations = bundledAvailableNowSampleCodecExpectations()

        let sampledCodecs = Set(expectations.map(\.1))
        XCTAssertTrue(Set(TaptionLaunchSupportCatalog.executableNowInputVideoCodecs).isSuperset(of: sampledCodecs))
        XCTAssertTrue(TaptionLaunchSupportCatalog.executableNowInputVideoCodecs.contains(.vc1))
        XCTAssertTrue(TaptionLaunchSupportCatalog.executableNowInputVideoCodecs.contains(.y41p))
        XCTAssertFalse(TaptionLaunchSupportCatalog.plannedInputVideoCodecs.contains(.vc1))
        XCTAssertFalse(TaptionLaunchSupportCatalog.plannedInputVideoCodecs.contains(.y41p))
        XCTAssertFalse(expectations.contains { $0.0 == "Y41P.avi" })

        for (filename, expectedCodec) in expectations {
            let sampleURL = testVideosURL.appendingPathComponent(filename)
            let asset = try await AVFoundationMediaInspector().inspectVideo(at: sampleURL)

            XCTAssertEqual(
                asset.videoTrack?.codec,
                expectedCodec,
                "\(filename) should inspect as \(expectedCodec.displayName)"
            )
            XCTAssertEqual(
                TaptionLaunchSupportCatalog.inputAvailability(for: expectedCodec),
                .availableNow,
                "\(filename) should remain an available-now launch sample"
            )
        }
    }

    func testBundledAvailableNowSamplesAreReadyOnSoftwareOnlyProfile() async throws {
        let testVideosURL = bundledTestVideosURL()

        for (filename, expectedCodec) in bundledAvailableNowSampleCodecExpectations() {
            let sampleURL = testVideosURL.appendingPathComponent(filename)
            let asset = try await AVFoundationMediaInspector().inspectVideo(at: sampleURL)
            let selection = TaptionCodecRoutePlanner.selectRoute(
                for: asset,
                outputCodec: .hevc,
                requestedMode: .automatic,
                hardwareSupport: .softwareOnly
            )

            XCTAssertEqual(asset.videoTrack?.codec, expectedCodec, filename)
            XCTAssertEqual(selection.route, TaptionCodecRoute(sourceCodec: expectedCodec, outputCodec: .hevc), filename)
            XCTAssertTrue(selection.isEncodableNow, filename)
            XCTAssertEqual(selection.executionKind, .software, filename)
            XCTAssertEqual(selection.displayTitle, "Path SW", filename)
        }
    }

    @MainActor
    func testBundledAvailableNowSamplesGenerateQueueThumbnails() async throws {
        var failures: [String] = []

        for filename in filteredBundledAvailableNowSampleFilenames() {
            let sampleURL = bundledTestVideosURL().appendingPathComponent(filename)
            do {
                let image = try await QueueVideoThumbnailRenderer.thumbnailImage(
                    for: sampleURL,
                    timeout: .seconds(4)
                )
                XCTAssertGreaterThan(image.size.width, 0, filename)
                XCTAssertGreaterThan(image.size.height, 0, filename)
                XCTAssertGreaterThan(image.pngData()?.count ?? 0, 128, filename)
            } catch {
                failures.append("\(filename): \(error)")
            }
        }

        XCTAssertTrue(
            failures.isEmpty,
            "Queue thumbnail generation failed for supported bundled samples:\n\(failures.joined(separator: "\n"))"
        )
    }

    @MainActor
    func testQueuePreviewVideoViewProducesVideoOutputForFirstBundledSample() async throws {
        #if targetEnvironment(simulator)
        let sampleURL = bundledTestVideosURL().appendingPathComponent("ASUS V1.avi")
        let player = QueuePreviewPlayerFactory.makePreviewPlayer()
        let media = try Media(url: sampleURL)
        QueuePreviewPlayerFactory.configureSoftwareDecodeOptions(on: media, sourceURL: sampleURL)

        let hostingController = UIHostingController(
            rootView: PiPVideoView(
                player,
                startsAutomaticallyFromInline: true,
                managesAudioSession: false
            )
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .frame(width: 320, height: 240)
                .background(Color.black)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        addTeardownBlock {
            Task { @MainActor in
                window.isHidden = true
                await player.shutdown()
            }
        }
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        hostingController.view.frame = window.bounds
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 250_000_000)

        try player.play(media)
        try await waitForCondition(timeout: 8) {
            player.hasVideoOutput || player.activeVideoOutputs > 0
        }

        let snapshotURL = temporaryTestURL(fileName: "asus-v1-preview.png")
        defer {
            try? FileManager.default.removeItem(at: snapshotURL)
            window.isHidden = true
        }

        try await waitForPreviewSnapshot(
            player: player,
            snapshotURL: snapshotURL,
            timeout: 5
        )

        await player.shutdown()
        #else
        throw XCTSkip("Preview drawable smoke test is simulator-scoped.")
        #endif
    }

    /// libVLC's iOS video output cannot decode a track that carries a second sample description —
    /// which is how Dolby Vision profile 8 stores its base layer — and it does not carry HDR
    /// through its sample-buffer output. In that state `hasVideoOutput` still reports `true`,
    /// because a video track is selected, so the engine choice has to come from the track's colour
    /// description rather than from a playback probe. This is the regression guard for a 4K60
    /// HEVC Main 10 HLG recording that previewed as a black screen.
    func testPreviewRoutesHDRAndTenBitSourcesToTheNativePlayer() {
        func track(
            _ codec: TaptionVideoCodec,
            _ color: TaptionColorDescription
        ) -> TaptionVideoTrackInfo {
            TaptionVideoTrackInfo(
                codec: codec,
                naturalSize: TaptionPixelSize(width: 3840, height: 2160),
                displaySize: TaptionPixelSize(width: 3840, height: 2160),
                color: color
            )
        }

        let sdr8 = TaptionColorDescription(bitDepth: 8)
        let hlg10 = TaptionColorDescription(
            primaries: .bt2020, transfer: .hlg, matrix: .bt2020NonConstantLuminance,
            bitDepth: 10, isHDR: true)
        let pq10 = TaptionColorDescription(
            primaries: .bt2020, transfer: .pq, matrix: .bt2020NonConstantLuminance,
            bitDepth: 10, isHDR: true)
        // Ten bits without an HDR transfer is still beyond libVLC's display path.
        let tenBitSDR = TaptionColorDescription(bitDepth: 10)

        XCTAssertEqual(
            QueuePreviewPlaybackRoutePlanner.route(for: track(.hevc, hlg10), container: .mov),
            .native, "HLG on BT.2020 is the reported black-screen case.")
        XCTAssertEqual(
            QueuePreviewPlaybackRoutePlanner.route(for: track(.hevc, pq10), container: .mp4),
            .native)
        XCTAssertEqual(
            QueuePreviewPlaybackRoutePlanner.route(for: track(.hevc, tenBitSDR), container: .mov),
            .native)
        XCTAssertEqual(
            QueuePreviewPlaybackRoutePlanner.route(for: track(.dolbyVisionHEVC, sdr8), container: .mp4),
            .native, "Dolby Vision keeps a second sample description libVLC cannot decode.")

        // Unchanged: HEVC Alpha needs Apple's compositor, and only in QuickTime files.
        XCTAssertEqual(
            QueuePreviewPlaybackRoutePlanner.route(for: track(.hevcWithAlpha, sdr8), container: .mov),
            .native)
        XCTAssertEqual(
            QueuePreviewPlaybackRoutePlanner.route(for: track(.hevcWithAlpha, sdr8), container: .mp4),
            .vlc)

        // Everything else keeps libVLC, which reads far more containers than AVFoundation.
        XCTAssertEqual(
            QueuePreviewPlaybackRoutePlanner.route(for: track(.hevc, sdr8), container: .mov),
            .vlc)
        XCTAssertEqual(
            QueuePreviewPlaybackRoutePlanner.route(for: track(.h264, sdr8), container: .mp4),
            .vlc)
        XCTAssertEqual(
            QueuePreviewPlaybackRoutePlanner.route(for: track(.av1, sdr8), container: .mkv),
            .vlc)
        XCTAssertEqual(
            QueuePreviewPlaybackRoutePlanner.route(for: track(.hevc, hlg10), container: .mkv),
            .vlc, "AVFoundation cannot open Matroska, so native would have nothing to read.")
        XCTAssertEqual(QueuePreviewPlaybackRoutePlanner.route(for: nil, container: .mov), .vlc)
    }

    /// Proves the engine the planner now chooses for the reported file actually presents frames.
    ///
    /// `export-58107AEB-…MOV` is an iPhone HDR recording that came through the passthrough path:
    /// 3840×2160 HEVC Main 10 at 60 fps, HLG (`arib-std-b67`) on BT.2020, a Dolby Vision `dvvC`
    /// record, **two** `hvc1` sample descriptions on one video track, and six `mebx` metadata
    /// tracks. libVLC decodes it as `kVTVideoDecoderBadDataErr` on a physical device and discards
    /// every frame, which is why this route exists.
    ///
    /// Point `TAPTION_PLAYBACK_FIXTURE` at a different file to reuse the harness.
    @MainActor
    func testNativePlayerPresentsFramesForTenBitHLGDolbyVisionOutput() async throws {
        let fixtureURL = playbackFixtureURL(
            fileName: "export-58107AEB-7F8A-4E21-AB1E-79AA4E5540CA.MOV")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            throw XCTSkip("No playback fixture at \(fixtureURL.path)")
        }

        let inspected = try await AVFoundationMediaInspector().inspectVideo(at: fixtureURL)
        let inspectedTrack = try XCTUnwrap(inspected.videoTrack)
        XCTAssertEqual(inspectedTrack.color.bitDepth, 10)
        XCTAssertTrue(inspectedTrack.color.isHDR)
        XCTAssertEqual(
            QueuePreviewPlaybackRoutePlanner.route(for: inspectedTrack, container: inspected.container),
            .native)

        let asset = AVURLAsset(url: fixtureURL)
        let item = AVPlayerItem(asset: asset)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        XCTAssertTrue(output.suppressesPlayerRendering == false)
        item.add(output)

        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 240, height: 426))
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        let layer = AVPlayerLayer(player: player)
        layer.frame = window.bounds
        window.rootViewController?.view.layer.addSublayer(layer)
        addTeardownBlock {
            Task { @MainActor in
                player.pause()
                window.isHidden = true
            }
        }
        player.play()

        var metrics: (nonBlackRatio: Double, standardDeviation: Double)?
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, metrics == nil {
            let hostTime = output.itemTime(forHostTime: CACurrentMediaTime())
            if output.hasNewPixelBuffer(forItemTime: hostTime),
               let buffer = output.copyPixelBuffer(forItemTime: hostTime, itemTimeForDisplay: nil),
               let data = try? pngData(from: buffer) {
                metrics = try visiblePixelMetrics(fromPNGData: data)
            }
            if metrics == nil {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        let diagnostics = "status=\(item.status.rawValue) "
            + "error=\(String(describing: item.error)) "
            + "presentationSize=\(item.presentationSize) "
            + "time=\(player.currentTime().seconds)"
        let measured = try XCTUnwrap(
            metrics, "AVPlayer produced no frame for a 10-bit HLG Dolby Vision file. \(diagnostics)")
        XCTAssertGreaterThan(
            measured.nonBlackRatio, 0.02,
            "AVPlayer rendered a black frame for a 10-bit HLG Dolby Vision file. \(diagnostics)")
        XCTAssertGreaterThan(
            measured.standardDeviation, 3.0,
            "AVPlayer rendered a flat frame for a 10-bit HLG Dolby Vision file. \(diagnostics)")
    }

    @MainActor
    func testPreviewRegressionSamplesProduceVisibleVideoSnapshots() async throws {
        #if targetEnvironment(simulator)
        let sampleFilenames = [
            "AV1.mp4",
            "Ut Video.avi",
            "Apple Animation.mov"
        ]

        for filename in sampleFilenames {
            let sampleURL = bundledTestVideosURL().appendingPathComponent(filename)
            let player = QueuePreviewPlayerFactory.makePreviewPlayer()
            let media = try Media(url: sampleURL)
            QueuePreviewPlayerFactory.configureSoftwareDecodeOptions(on: media, sourceURL: sampleURL)

            let hostingController = UIHostingController(
                rootView: PiPVideoView(
                    player,
                    startsAutomaticallyFromInline: true,
                    managesAudioSession: false
                )
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 320, height: 240)
                    .background(Color.black)
            )
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
            window.rootViewController = hostingController
            window.makeKeyAndVisible()
            hostingController.view.frame = window.bounds
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 250_000_000)

            try player.play(media)
            try await waitForCondition(timeout: 8) {
                player.hasVideoOutput || player.activeVideoOutputs > 0
            }

            let snapshotURL = temporaryTestURL(fileName: "\(filename)-preview.png")
            defer {
                try? FileManager.default.removeItem(at: snapshotURL)
                window.isHidden = true
            }

            try await waitForPreviewSnapshot(
                player: player,
                snapshotURL: snapshotURL,
                timeout: 5
            )

            let imageData = try Data(contentsOf: snapshotURL)
            let metrics = try visiblePixelMetrics(fromPNGData: imageData)
            XCTAssertGreaterThan(metrics.nonBlackRatio, 0.02, filename)
            XCTAssertGreaterThan(metrics.standardDeviation, 3.0, filename)

            await player.shutdown()
        }
        #else
        throw XCTSkip("Preview visual regression test is simulator-scoped.")
        #endif
    }

    func testQueuePreviewFactoryKeepsQuickTimeDefaultDemuxAndFallsBackToAVFormat() {
        let movURL = URL(fileURLWithPath: "/tmp/Apple Animation.mov")
        let aviURL = URL(fileURLWithPath: "/tmp/ASUS V1.avi")

        XCTAssertEqual(QueuePreviewPlayerFactory.previewDemuxModes(for: movURL), [.automatic, .avformat])
        XCTAssertFalse(
            QueuePreviewPlayerFactory
                .softwareDecodeOptions(for: movURL, demuxMode: .automatic)
                .contains(":demux=avformat")
        )
        XCTAssertTrue(
            QueuePreviewPlayerFactory
                .softwareDecodeOptions(for: movURL, demuxMode: .avformat)
                .contains(":demux=avformat")
        )

        XCTAssertEqual(QueuePreviewPlayerFactory.previewDemuxModes(for: aviURL), [.avformat, .automatic])
        XCTAssertTrue(
            QueuePreviewPlayerFactory
                .softwareDecodeOptions(for: aviURL, demuxMode: .automatic)
                .contains(":demux=avformat")
        )
    }

    func testBundledProResSampleKeepsHardwareGate() async throws {
        let sampleURL = bundledTestVideosURL().appendingPathComponent("Apple ProRes.mov")
        let asset = try await AVFoundationMediaInspector().inspectVideo(at: sampleURL)
        let hardwareSelection = TaptionCodecRoutePlanner.selectRoute(
            for: asset,
            outputCodec: .hevc,
            requestedMode: .automatic,
            hardwareSupport: .proMediaHardware
        )
        let softwareOnlySelection = TaptionCodecRoutePlanner.selectRoute(
            for: asset,
            outputCodec: .hevc,
            requestedMode: .automatic,
            hardwareSupport: .softwareOnly
        )

        XCTAssertEqual(asset.videoTrack?.codec, .proRes)
        XCTAssertEqual(TaptionLaunchSupportCatalog.inputAvailability(for: .proRes), .availableOnSupportedHardware)
        XCTAssertTrue(hardwareSelection.isEncodableNow)
        XCTAssertEqual(hardwareSelection.executionKind, .hardware)
        XCTAssertFalse(softwareOnlySelection.isEncodableNow)
        XCTAssertEqual(softwareOnlySelection.executionKind, .planned)
        XCTAssertEqual(softwareOnlySelection.support, .planned)
    }

    func testRepresentativeBundledAvailableNowSamplesEncodeToHEVCMP4() async throws {
        let sampleFilenames = [
            "H.261.h261",
            "Theora.ogv",
            "JPEG-LS.avi",
            "QuickTime Video.mov",
            "Flash Video.flv"
        ]
        try await assertBundledSamplesEncodeToHEVCMP4(sampleFilenames)
    }

    func testRealDeviceBundledTheoraOpusSampleEncodesHEVCWithAACAudio() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Real-device runtime proof requires a physical iPhone or iPad.")
        #endif

        let sampleURL = bundledTestVideosURL().appendingPathComponent("Theora.ogv")
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            XCTFail("Missing bundled Theora proof sample at \(sampleURL.path)")
            return
        }

        let outputURL = temporaryTestURL(fileName: "real-device-theora-opus-hevc.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: AVFoundationMediaInspector(),
                encoder: AVFoundationHEVCEncoderService(),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate()
            )
        )
        let job = try await core.prepareSingleAssetHEVCJob(
            sourceURL: sampleURL,
            temporaryOutputURL: outputURL,
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )
        let sourceAudioCodec = try XCTUnwrap(job.asset.audioTracks.first?.codec)
        XCTAssertEqual(job.asset.container, .ogg)
        XCTAssertEqual(job.asset.videoTrack?.codec, .theora)
        XCTAssertEqual(sourceAudioCodec, .opus)
        XCTAssertEqual(job.routeSelection.route, TaptionCodecRoute(sourceCodec: .theora, outputCodec: .hevc))
        XCTAssertTrue(job.routeSelection.isEncodableNow)
        XCTAssertEqual(job.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .aac))
        XCTAssertTrue(job.plan.audioPlan?.isRunnableInCurrentBuild ?? false)

        let result = try await core.encodePreparedJob(job, progress: { _ in })
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.temporaryOutputURL.path))
        XCTAssertEqual(result.usedBackend, .softwareVLCDecoder)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertEqual(outputAsset.container, .mp4)
        XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc)
        XCTAssertEqual(outputAsset.audioTracks.first?.codec, .aac)
        XCTAssertEqual(outputAsset.audioTracks.first?.sampleRate ?? 0, 48_000, accuracy: 1)
        XCTAssertEqual(outputAsset.audioTracks.first?.channelCount, 2)
    }

    func testRealDeviceBundledAMRWBH263SampleEncodesHEVCWithAACAudio() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Real-device runtime proof requires a physical iPhone or iPad.")
        #endif

        let sampleURL = bundledTestVideosURL().appendingPathComponent("AMR-WB H.263.3gp")
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            XCTFail("Missing bundled AMR-WB proof sample at \(sampleURL.path)")
            return
        }

        let outputURL = temporaryTestURL(fileName: "real-device-amr-wb-h263-hevc.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: AVFoundationMediaInspector(),
                encoder: AVFoundationHEVCEncoderService(),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate()
            )
        )
        let job = try await core.prepareSingleAssetHEVCJob(
            sourceURL: sampleURL,
            temporaryOutputURL: outputURL,
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )
        let sourceAudioCodec = try XCTUnwrap(job.asset.audioTracks.first?.codec)

        XCTAssertEqual(job.asset.container, .threeGP)
        XCTAssertEqual(job.asset.videoTrack?.codec, .h263)
        XCTAssertEqual(sourceAudioCodec, .amr)
        XCTAssertEqual(job.asset.audioTracks.first?.sampleRate ?? 0, 16_000, accuracy: 1)
        XCTAssertEqual(job.asset.audioTracks.first?.channelCount, 1)
        XCTAssertEqual(job.routeSelection.route, TaptionCodecRoute(sourceCodec: .h263, outputCodec: .hevc))
        XCTAssertTrue(job.routeSelection.isEncodableNow)
        XCTAssertEqual(job.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: .amr, outputCodec: .aac))
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.readiness.readiness, .softwareBackendExecutable)
        XCTAssertEqual(job.plan.audioPlan?.readiness.commandBackend, .softwareVLCDecoder)
        XCTAssertTrue(job.plan.audioPlan?.isRunnableInCurrentBuild ?? false)
        XCTAssertNil(job.plan.audioPlan?.commandPlan)
        XCTAssertEqual(job.plan.audioPlan?.options.sampleRate, 48_000)
        XCTAssertEqual(job.plan.audioPlan?.options.channelCount, 1)
        XCTAssertEqual(job.plan.sourcePreservationRequirements?.audioSampleRate, 48_000)
        XCTAssertEqual(job.plan.sourcePreservationRequirements?.audioChannelCount, 1)

        let result = try await core.encodePreparedJob(job, progress: { _ in })
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.temporaryOutputURL.path))
        XCTAssertEqual(result.usedBackend, .softwareVLCDecoder)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertEqual(outputAsset.container, .mp4)
        XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc)
        XCTAssertEqual(outputAsset.audioTracks.first?.codec, .aac)
        XCTAssertEqual(outputAsset.audioTracks.first?.sampleRate ?? 0, 48_000, accuracy: 1)
        XCTAssertEqual(outputAsset.audioTracks.first?.channelCount, 1)
        XCTAssertFalse(outputAsset.audioTracks.isEmpty)
    }

    func testNextLegacyBundledSamplesEncodeToHEVCMP4() async throws {
        let sampleFilenames = [
            "Microsoft Video 1.avi",
            "ASUS V1.avi",
            "ASUS V2.avi"
        ]
        try await assertBundledSamplesEncodeToHEVCMP4(sampleFilenames)
    }

    func testScreenAndArchiveBundledSamplesEncodeToHEVCMP4() async throws {
        let sampleFilenames = [
            "Flash Screen Video.flv",
            "Flash Screen Video 2.flv",
            "ZMBV.avi",
            "CLJR.avi",
            "FFV1.avi"
        ]
        try await assertBundledSamplesEncodeToHEVCMP4(sampleFilenames)
    }

    func testNextIntermediateBundledSamplesEncodeToHEVCMP4() async throws {
        let sampleFilenames = [
            "HuffYUV.avi",
            "DVCPro.mov",
            "DVCPro HD.mov",
            "DV.dv",
            "CineForm.avi",
            "DNxHD.mov",
            "V308.mov",
            "V210.avi",
            "V408.mov",
            "V410.mov",
            "YUV4.mov"
        ]
        try await assertBundledSamplesEncodeToHEVCMP4(sampleFilenames)
    }

    func testRealVideoAndRoQBundledSamplesEncodeToHEVCMP4() async throws {
        let sampleFilenames = [
            "RealVideo 1.0.rm",
            "RealVideo.rm",
            "RoQ Video.roq"
        ]
        try await assertBundledSamplesEncodeToHEVCMP4(sampleFilenames)
    }

    internal func assertBundledSamplesEncodeToHEVCMP4(_ sampleFilenames: [String]) async throws {
        let outputDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: outputDirectoryURL)
        }
        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: AVFoundationMediaInspector(),
                encoder: AVFoundationHEVCEncoderService(),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate()
            )
        )

        let filteredSampleFilenames: [String]
        if let sampleFilter = ProcessInfo.processInfo.environment["TAPTION_SAMPLE_FILTER"],
           sampleFilter.isEmpty == false {
            filteredSampleFilenames = sampleFilenames.filter { $0 == sampleFilter }
            XCTAssertFalse(filteredSampleFilenames.isEmpty, sampleFilter)
        } else {
            filteredSampleFilenames = sampleFilenames
        }
        let expectedDisplaySizes = [
            "H.261.h261": TaptionPixelSize(width: 176, height: 144),
            "Theora.ogv": TaptionPixelSize(width: 320, height: 240),
            "JPEG-LS.avi": TaptionPixelSize(width: 80, height: 80),
            "QuickTime Video.mov": TaptionPixelSize(width: 160, height: 120),
            "Flash Video.flv": TaptionPixelSize(width: 160, height: 120)
        ]

        for filename in filteredSampleFilenames {
            do {
                let sampleURL = bundledTestVideosURL().appendingPathComponent(filename)
                let outputURL = outputDirectoryURL
                    .appendingPathComponent("\(sampleURL.deletingPathExtension().lastPathComponent)-hevc.mp4")

                let job = try await core.prepareSingleAssetHEVCJob(
                    sourceURL: sampleURL,
                    temporaryOutputURL: outputURL,
                    savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
                )
                let result = try await core.encodePreparedJob(job, progress: { _ in })
                let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)

                XCTAssertTrue(job.routeSelection.isEncodableNow, filename)
                XCTAssertEqual(result.temporaryOutputURL, outputURL, filename)
                XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path), filename)
                XCTAssertEqual(outputAsset.container, .mp4, filename)
                XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc, filename)
                if let expectedDisplaySize = expectedDisplaySizes[filename] {
                    XCTAssertEqual(job.asset.videoTrack?.displaySize, expectedDisplaySize, filename)
                    XCTAssertEqual(outputAsset.videoTrack?.displaySize, expectedDisplaySize, filename)
                }
            } catch {
                XCTFail("\(filename): \(error)")
            }
        }
    }

    func testTestVideoSeederRemovesExistingDocumentsFolderAndCopiesBundledFiles() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceURL = rootURL.appendingPathComponent("Source", isDirectory: true)
        let documentsURL = rootURL.appendingPathComponent("Documents", isDirectory: true)
        let destinationURL = documentsURL.appendingPathComponent(
            TaptionTestVideoSeeder.documentsFolderName,
            isDirectory: true
        )
        defer {
            try? fileManager.removeItem(at: rootURL)
        }

        try fileManager.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let firstFilename = TaptionTestVideoSeeder.expectedBundledVideoSampleFilenames[0]
        let secondFilename = TaptionTestVideoSeeder.expectedBundledVideoSampleFilenames[1]
        let staleDestinationURL = destinationURL.appendingPathComponent(firstFilename)
        let extraDestinationURL = destinationURL.appendingPathComponent("user-leftover.mov")

        try Data("bundle-first".utf8).write(to: sourceURL.appendingPathComponent(firstFilename))
        try Data("bundle-second".utf8).write(to: sourceURL.appendingPathComponent(secondFilename))
        try Data("stale-existing".utf8).write(to: staleDestinationURL)
        try Data("leftover".utf8).write(to: extraDestinationURL)

        let result = try TaptionTestVideoSeeder.seedSamples(
            sourceURL: sourceURL,
            documentsDirectoryURL: documentsURL,
            fileManager: fileManager
        )

        XCTAssertEqual(result.destinationURL, destinationURL)
        XCTAssertTrue(result.removedExistingFolder)
        XCTAssertEqual(result.copiedFilenames, [firstFilename, secondFilename].sorted())
        XCTAssertEqual(try String(contentsOf: staleDestinationURL), "bundle-first")
        XCTAssertEqual(
            try String(contentsOf: destinationURL.appendingPathComponent(secondFilename)),
            "bundle-second"
        )
        XCTAssertFalse(fileManager.fileExists(atPath: extraDestinationURL.path))
    }

    func testTestVideoSeederCreatesDocumentsFolderWhenMissing() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceURL = rootURL.appendingPathComponent("Source", isDirectory: true)
        let documentsURL = rootURL.appendingPathComponent("Documents", isDirectory: true)
        let destinationURL = documentsURL.appendingPathComponent(
            TaptionTestVideoSeeder.documentsFolderName,
            isDirectory: true
        )
        defer {
            try? fileManager.removeItem(at: rootURL)
        }

        try fileManager.createDirectory(at: sourceURL, withIntermediateDirectories: true)

        let filename = TaptionTestVideoSeeder.expectedBundledVideoSampleFilenames[0]
        let sourceFileURL = sourceURL.appendingPathComponent(filename)
        let destinationFileURL = destinationURL.appendingPathComponent(filename)

        try Data("bundle-current".utf8).write(to: sourceFileURL)

        let result = try TaptionTestVideoSeeder.seedSamples(
            sourceURL: sourceURL,
            documentsDirectoryURL: documentsURL,
            fileManager: fileManager
        )

        XCTAssertEqual(result.destinationURL, destinationURL)
        XCTAssertFalse(result.removedExistingFolder)
        XCTAssertEqual(result.copiedFilenames, [filename])
        XCTAssertEqual(try String(contentsOf: destinationFileURL), "bundle-current")
    }

    func testTestVideoSeederDocumentsSampleFolderURLUsesSharedFolderName() throws {
        let sampleURL = try TaptionTestVideoSeeder.documentsSampleFolderURL()

        XCTAssertEqual(sampleURL.lastPathComponent, TaptionTestVideoSeeder.documentsFolderName)
        XCTAssertTrue(sampleURL.path.contains("/Documents/"))
    }

    func testUniversalVideoCommandPlannerRejectsEveryUnsupportedOutputCodec() {
        for sourceCodec in TaptionCodecRegistry.universalSourceCodecs {
            for outputCodec in SW_FFmpegCodecCommandPlanner.commandUnsupportedVideoOutputCodecs {
                let route = TaptionCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
                let request = TaptionCodecTranscodeRequest(
                    sourceURL: URL(fileURLWithPath: "/tmp/input-\(sourceCodec.rawValue).mkv"),
                    outputURL: URL(fileURLWithPath: "/tmp/output-\(outputCodec.rawValue).mp4"),
                    route: route,
                    options: .preservingSource(outputCodec: outputCodec, container: .mp4)
                )

                XCTAssertThrowsError(try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(request: request), route.displayName) { error in
                    XCTAssertEqual(
                        error as? SW_FFmpegCodecCommandPlannerError,
                        .videoEncoderUnavailable(outputCodec),
                        route.displayName
                    )
                }
            }
        }
    }

    func testUniversalVideoCommandPlannerRejectsNonH265OutputRoutes() {
        let route = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .proResRaw)
        let request = TaptionCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mov"),
            route: route,
            options: .preservingSource(outputCodec: .proResRaw, container: .mov)
        )

        XCTAssertThrowsError(try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(request: request)) { error in
            XCTAssertEqual(
                error as? SW_FFmpegCodecCommandPlannerError,
                .videoRouteNotPlannable(route)
            )
        }
    }

    func testCodecTranscodeRequestDefaultsPreserveSourceQuality() {
        let request = TaptionCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            route: TaptionCodecRoute(sourceCodec: .av1, outputCodec: .hevc)
        )

        XCTAssertEqual(request.options.outputPolicy.videoCodec, .hevc)
        XCTAssertEqual(request.options.outputPolicy.container, .mp4)
        XCTAssertEqual(request.options.outputPolicy.qualityPolicy, .preserveSourceVisuals)
        XCTAssertEqual(request.options.outputPolicy.advancedOptions, .preserveSource)
        XCTAssertTrue(request.options.preserveSourceVisualQuality)
        XCTAssertTrue(request.options.preserveAudioWhenPossible)
    }

    func testSourcePreservingOutputResolverFillsEmptyOptionsFromSourceTrack() {
        let sourceColor = TaptionColorDescription(
            primaries: .bt2020,
            transfer: .hlg,
            matrix: .bt2020NonConstantLuminance,
            bitDepth: 10,
            isHDR: true
        )
        let track = TaptionVideoTrackInfo(
            codec: .av1,
            naturalSize: TaptionPixelSize(width: 3840, height: 2160),
            displaySize: TaptionPixelSize(width: 2160, height: 3840),
            nominalFrameRate: TaptionRationalFrameRate(numerator: 60000, denominator: 1001),
            estimatedBitrate: 82_000_000,
            color: sourceColor,
            rotationDegrees: 90
        )
        let asset = TaptionVideoAsset(
            displayName: "hdr-portrait-av1.mp4",
            location: TaptionVideoAssetLocation(kind: .file),
            container: .mp4,
            videoTrack: track
        )

        let policy = TaptionSourcePreservingOutputPolicyResolver.resolvedPolicy(
            for: asset,
            requestedPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4)
        )

        XCTAssertEqual(policy.videoCodec, .hevc)
        XCTAssertEqual(policy.container, .mp4)
        XCTAssertEqual(policy.qualityPolicy, .preserveSourceVisuals)
        XCTAssertEqual(policy.advancedOptions.resizeTo, track.displaySize)
        XCTAssertEqual(policy.advancedOptions.frameRate, track.nominalFrameRate)
        XCTAssertEqual(policy.advancedOptions.targetBitrate, track.estimatedBitrate)
        XCTAssertEqual(policy.advancedOptions.color, sourceColor)
        XCTAssertEqual(policy.advancedOptions.rotationDegrees, 90)
    }

    func testSingleAssetPlanCarriesSourcePreservationRequirementsIntoExecutionAudit() throws {
        let sourceColor = TaptionColorDescription(
            primaries: .bt2020,
            transfer: .pq,
            matrix: .bt2020NonConstantLuminance,
            bitDepth: 10,
            isHDR: true
        )
        let track = TaptionVideoTrackInfo(
            codec: .h264,
            naturalSize: TaptionPixelSize(width: 3840, height: 2160),
            displaySize: TaptionPixelSize(width: 2160, height: 3840),
            nominalFrameRate: TaptionRationalFrameRate(numerator: 60000, denominator: 1001),
            estimatedBitrate: 80_000_000,
            color: sourceColor,
            rotationDegrees: 90
        )
        let asset = TaptionVideoAsset(
            displayName: "portrait-hdr.mp4",
            location: TaptionVideoAssetLocation(kind: .file),
            container: .mp4,
            duration: 2,
            videoTrack: track
        )

        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: asset,
            sourceURL: URL(fileURLWithPath: "/tmp/portrait-hdr.mp4"),
            temporaryOutputURL: URL(fileURLWithPath: "/tmp/portrait-hdr_taption.mp4"),
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4)
        )

        XCTAssertEqual(
            plan.sourcePreservationRequirements,
            TaptionSourcePreservationRequirements(asset: asset)
        )
        XCTAssertEqual(plan.outputPolicy.advancedOptions.resizeTo, track.displaySize)
        XCTAssertEqual(plan.outputPolicy.advancedOptions.frameRate, track.nominalFrameRate)
        XCTAssertEqual(plan.outputPolicy.advancedOptions.targetBitrate, track.estimatedBitrate)
        XCTAssertEqual(plan.outputPolicy.advancedOptions.color, sourceColor)
        XCTAssertEqual(plan.outputPolicy.advancedOptions.rotationDegrees, 90)
        XCTAssertNoThrow(try TaptionSourcePreservingExecutionAudit.validate(plan: plan))

        let metadata = TaptionSourcePreservingExecutionAudit.logMetadata(for: plan)
        XCTAssertEqual(metadata["sourcePreserving"], "tracked")
        XCTAssertEqual(metadata["sourcePreservingMissing"], "")
        XCTAssertEqual(metadata["preserveResolution"], "2160x3840")
        XCTAssertEqual(metadata["preserveFrameRate"], "60000/1001")
        XCTAssertEqual(metadata["preserveBitrate"], "80000000")
        XCTAssertEqual(metadata["preserveOrientation"], "90")
        XCTAssertEqual(metadata["preserveColor"], "bt2020/pq/bt2020NonConstantLuminance/hdr:true")
    }

    func testSourcePreservingOutputVerificationAcceptsMatchingOutputMetadata() throws {
        let sourceColor = TaptionColorDescription(
            primaries: .bt709,
            transfer: .bt709,
            matrix: .bt709,
            bitDepth: 8,
            isHDR: false
        )
        let sourceAsset = TaptionVideoAsset(
            displayName: "source.mp4",
            location: TaptionVideoAssetLocation(kind: .file),
            duration: 4,
            videoTrack: TaptionVideoTrackInfo(
                codec: .h264,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30000, denominator: 1001),
                estimatedBitrate: 12_000_000,
                color: sourceColor,
                rotationDegrees: 0
            ),
            audioTracks: [
                TaptionAudioTrackInfo(codec: .aac, channelCount: 2, sampleRate: 48_000)
            ]
        )
        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: sourceAsset,
            sourceURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            temporaryOutputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4)
        )
        let outputAsset = TaptionVideoAsset(
            displayName: "output.mp4",
            location: TaptionVideoAssetLocation(kind: .temporary),
            container: .mp4,
            duration: 4.03,
            videoTrack: TaptionVideoTrackInfo(
                codec: .hevc,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 2997, denominator: 100),
                color: sourceColor,
                rotationDegrees: 0
            ),
            audioTracks: [
                TaptionAudioTrackInfo(codec: .aac, channelCount: 2, sampleRate: 48_000)
            ]
        )

        let report = try TaptionSourcePreservingExecutionAudit.verifyOutput(
            plan: plan,
            outputAsset: outputAsset
        )

        XCTAssertTrue(report.isPassing)
        XCTAssertEqual(report.metadata["sourcePreservingOutput"], "checked")
        XCTAssertEqual(report.metadata["actualResolution"], "1920x1080")
        XCTAssertEqual(report.metadata["actualAudioTracks"], "1")
    }

    func testSourcePreservingOutputVerificationAcceptsSmallAverageFrameRateDrift() throws {
        let sourceAsset = TaptionVideoAsset(
            displayName: "source.mp4",
            location: TaptionVideoAssetLocation(kind: .file),
            duration: 120.032,
            videoTrack: TaptionVideoTrackInfo(
                codec: .av1,
                naturalSize: TaptionPixelSize(width: 320, height: 180),
                displaySize: TaptionPixelSize(width: 320, height: 180),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 23_902, denominator: 1_000)
            ),
            audioTracks: []
        )
        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: sourceAsset,
            sourceURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            temporaryOutputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4)
        )
        let outputAsset = TaptionVideoAsset(
            displayName: "output.mp4",
            location: TaptionVideoAssetLocation(kind: .temporary),
            container: .mp4,
            duration: 120,
            videoTrack: TaptionVideoTrackInfo(
                codec: .hevc,
                naturalSize: TaptionPixelSize(width: 320, height: 180),
                displaySize: TaptionPixelSize(width: 320, height: 180),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 24)
            )
        )

        let report = try TaptionSourcePreservingExecutionAudit.verifyOutput(
            plan: plan,
            outputAsset: outputAsset
        )

        XCTAssertTrue(report.isPassing)
        XCTAssertEqual(report.metadata["expectedFrameRate"], "23902/1000")
        XCTAssertEqual(report.metadata["actualFrameRate"], "24/1")
    }

    func testSourcePreservingOutputVerificationRejectsMismatchedOutputMetadata() {
        let sourceAsset = TaptionVideoAsset(
            displayName: "source.mp4",
            location: TaptionVideoAssetLocation(kind: .file),
            duration: 10,
            videoTrack: TaptionVideoTrackInfo(
                codec: .h264,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30),
                color: TaptionColorDescription(primaries: .bt709, transfer: .bt709, matrix: .bt709),
                rotationDegrees: 0
            ),
            audioTracks: [
                TaptionAudioTrackInfo(codec: .aac, channelCount: 2, sampleRate: 48_000)
            ]
        )
        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: sourceAsset,
            sourceURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            temporaryOutputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4)
        )
        let outputAsset = TaptionVideoAsset(
            displayName: "output.mp4",
            location: TaptionVideoAssetLocation(kind: .temporary),
            container: .mp4,
            duration: 7,
            videoTrack: TaptionVideoTrackInfo(
                codec: .hevc,
                naturalSize: TaptionPixelSize(width: 1280, height: 720),
                displaySize: TaptionPixelSize(width: 1280, height: 720),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 24),
                color: TaptionColorDescription(primaries: .bt2020, transfer: .bt709, matrix: .bt709),
                rotationDegrees: 0
            ),
            audioTracks: []
        )

        XCTAssertThrowsError(try TaptionSourcePreservingExecutionAudit.verifyOutput(
            plan: plan,
            outputAsset: outputAsset
        )) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(message.contains("resolution expected 1920x1080 but got 1280x720"))
            XCTAssertTrue(message.contains("frame rate expected 30/1 but got 24/1"))
            XCTAssertTrue(message.contains("duration expected 10.000s but got 7.000s"))
            XCTAssertTrue(message.contains("audio track was missing"))
        }
    }

    func testSourcePreservingVisualQualityComparatorAcceptsSimilarSamples() {
        let sourceSample = TaptionVisualQualitySample(
            width: 96,
            height: 54,
            averageRed: 0.42,
            averageGreen: 0.50,
            averageBlue: 0.44,
            averageLuma: 0.48,
            lumaStandardDeviation: 0.18,
            nonBlackRatio: 0.96
        )
        let outputSample = TaptionVisualQualitySample(
            width: 96,
            height: 54,
            averageRed: 0.40,
            averageGreen: 0.49,
            averageBlue: 0.43,
            averageLuma: 0.47,
            lumaStandardDeviation: 0.16,
            nonBlackRatio: 0.95
        )

        let report = TaptionSourcePreservingVisualQualityComparator.verify(
            sourceSample: sourceSample,
            outputSample: outputSample
        )

        XCTAssertTrue(report.isPassing)
        XCTAssertEqual(report.metadata["visualQuality"], "checked")
        XCTAssertNotNil(report.metadata["visualLumaDelta"])
        XCTAssertNotNil(report.metadata["visualColorDelta"])
    }

    func testSourcePreservingVisualQualityComparatorRejectsCollapsedOutput() {
        let sourceSample = TaptionVisualQualitySample(
            width: 96,
            height: 54,
            averageRed: 0.62,
            averageGreen: 0.50,
            averageBlue: 0.31,
            averageLuma: 0.52,
            lumaStandardDeviation: 0.22,
            nonBlackRatio: 0.90
        )
        let outputSample = TaptionVisualQualitySample(
            width: 96,
            height: 54,
            averageRed: 0.01,
            averageGreen: 0.01,
            averageBlue: 0.01,
            averageLuma: 0.01,
            lumaStandardDeviation: 0.001,
            nonBlackRatio: 0.0
        )

        let report = TaptionSourcePreservingVisualQualityComparator.verify(
            sourceSample: sourceSample,
            outputSample: outputSample
        )

        XCTAssertFalse(report.isPassing)
        XCTAssertTrue(report.failures.contains("visual sample lost source contrast and appears flat"))
        XCTAssertTrue(report.failures.contains("visual sample collapsed to near-black output"))
    }

    func testSourcePreservingVisualQualityComparatorPassesWithoutSourceSampleButWarns() {
        let outputSample = TaptionVisualQualitySample(
            width: 96,
            height: 54,
            averageRed: 0.30,
            averageGreen: 0.35,
            averageBlue: 0.40,
            averageLuma: 0.34,
            lumaStandardDeviation: 0.08,
            nonBlackRatio: 0.80
        )

        let report = TaptionSourcePreservingVisualQualityComparator.verify(
            sourceSample: nil,
            outputSample: outputSample
        )

        XCTAssertTrue(report.isPassing)
        XCTAssertEqual(report.metadata["sourceVisualSample"], "unavailable")
        XCTAssertTrue(report.warnings.contains("Source visual sample was unavailable; output visual decodability was verified only."))
    }

    func testSourcePreservingExecutionAuditRejectsMissingKnownSourceFields() {
        let plan = TaptionEncodingPlan(
            input: TaptionEncodingInput(kind: .singleAsset),
            outputPolicy: TaptionVideoOutputPolicy(
                videoCodec: .hevc,
                container: .mp4,
                qualityPolicy: .preserveSourceVisuals,
                advancedOptions: .preserveSource
            ),
            codecRoute: TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc),
            codecExecutionKind: .hardware,
            sourcePreservationRequirements: TaptionSourcePreservationRequirements(
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                frameRate: TaptionRationalFrameRate(numerator: 30),
                targetBitrate: 12_000_000,
                color: TaptionColorDescription(primaries: .bt709, transfer: .bt709, matrix: .bt709),
                rotationDegrees: 0
            ),
            sourceURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            temporaryOutputURL: URL(fileURLWithPath: "/tmp/output.mp4")
        )

        XCTAssertThrowsError(try TaptionSourcePreservingExecutionAudit.validate(plan: plan)) { error in
            XCTAssertEqual(
                error as? TaptionSourcePreservingVerificationError,
                .failed("Source-preserving output plan is incomplete: resolution, frame rate, bitrate, color metadata, orientation.")
            )
        }
    }

    func testSourcePreservingOutputResolverKeepsExplicitAdvancedOptions() {
        let track = TaptionVideoTrackInfo(
            codec: .av1,
            naturalSize: TaptionPixelSize(width: 3840, height: 2160),
            displaySize: TaptionPixelSize(width: 3840, height: 2160),
            nominalFrameRate: TaptionRationalFrameRate(numerator: 60),
            estimatedBitrate: 82_000_000,
            color: TaptionColorDescription(primaries: .bt2020, transfer: .pq, matrix: .bt2020NonConstantLuminance, bitDepth: 10, isHDR: true),
            rotationDegrees: 0
        )
        let explicitOptions = TaptionAdvancedOutputOptions(
            resizeTo: TaptionPixelSize(width: 1280, height: 720),
            frameRate: TaptionRationalFrameRate(numerator: 24),
            targetBitrate: 6_000_000,
            color: TaptionColorDescription(primaries: .bt709, transfer: .bt709, matrix: .bt709, bitDepth: 8, isHDR: false),
            rotationDegrees: 180
        )
        let asset = TaptionVideoAsset(
            displayName: "custom-output.mp4",
            location: TaptionVideoAssetLocation(kind: .file),
            container: .mp4,
            videoTrack: track
        )
        let requestedPolicy = TaptionVideoOutputPolicy(
            videoCodec: .hevc,
            container: .mov,
            qualityPolicy: .preserveSourceVisuals,
            advancedOptions: explicitOptions
        )

        let policy = TaptionSourcePreservingOutputPolicyResolver.resolvedPolicy(
            for: asset,
            requestedPolicy: requestedPolicy
        )

        XCTAssertEqual(policy.advancedOptions, explicitOptions)
    }

    func testOutputSelectionOnlyMarksCurrentImplementedOutputAsRunnable() {
        XCTAssertTrue(TaptionOutputSelection(videoCodec: .hevc, container: .mp4).isImplementedNow)
        XCTAssertTrue(TaptionOutputSelection(videoCodec: .hevc, container: .mov).isImplementedNow)
        XCTAssertTrue(TaptionOutputSelection(videoCodec: .hevc, audioCodec: .pcm, container: .mov).isImplementedNow)
        XCTAssertTrue(TaptionOutputSelection(videoCodec: .hevc, audioCodec: .alac, container: .mov).isImplementedNow)
        XCTAssertFalse(TaptionOutputSelection(videoCodec: .h264, container: .mp4).isImplementedNow)
        XCTAssertFalse(TaptionOutputSelection(videoCodec: .hevc, audioCodec: .pcm, container: .mp4).isImplementedNow)
        XCTAssertFalse(TaptionOutputSelection(videoCodec: .hevc, audioCodec: .alac, container: .mp4).isImplementedNow)
        XCTAssertFalse(TaptionOutputSelection(videoCodec: .hevc, audioCodec: .opus, container: .mp4).isImplementedNow)
    }

    func testOutputSelectionResolutionPresetBuildsResizePolicy() {
        let selection = TaptionOutputSelection(
            videoCodec: .hevc,
            container: .mp4,
            resolutionPreset: .hd720
        )

        let policy = selection.outputPolicy(for: makeAsset(sourceCodec: .h264))

        XCTAssertEqual(policy.advancedOptions.resizeTo, TaptionPixelSize(width: 1280, height: 720))
    }

    func testOutputSelectionResolutionPresetPreservesPortraitOrientation() {
        let selection = TaptionOutputSelection(
            videoCodec: .hevc,
            container: .mp4,
            resolutionPreset: .hd720
        )

        let policy = selection.outputPolicy(
            for: makeAsset(
                sourceCodec: .h264,
                displaySize: TaptionPixelSize(width: 1080, height: 1920)
            )
        )

        XCTAssertEqual(policy.advancedOptions.resizeTo, TaptionPixelSize(width: 720, height: 1280))
    }

    func testEncodingOptimizationProfileSliderMappingAndSettingsPersistence() {
        XCTAssertEqual(TaptionEncodingOptimizationProfile.fromSliderValue(-1), .batterySaver)
        XCTAssertEqual(TaptionEncodingOptimizationProfile.fromSliderValue(1), .balanced)
        XCTAssertEqual(TaptionEncodingOptimizationProfile.fromSliderValue(2), .performance)
        XCTAssertEqual(TaptionEncodingOptimizationProfile.fromDebugString("max-performance"), .performance)

        let suiteName = "BatteryEncodingSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertEqual(BatteryEncodingSettings.load(defaults: defaults).optimizationProfile, .performance)

        let settings = BatteryEncodingSettings(
            batteryLimitPercent: 45,
            powerConnectedOnly: true,
            optimizationProfile: .performance
        )
        settings.save(defaults: defaults)

        XCTAssertEqual(BatteryEncodingSettings.load(defaults: defaults), settings)
    }

    func testBatterySaverOutputPolicyCapsAutomaticSourceResolutionFrameRateAndBitrate() {
        let asset = makeAsset(
            sourceCodec: .h264,
            displaySize: TaptionPixelSize(width: 3840, height: 2160),
            frameRate: TaptionRationalFrameRate(numerator: 60)
        )
        let balancedPolicy = TaptionOutputSelection(
            videoCodec: .hevc,
            container: .mp4,
            optimizationProfile: .balanced
        ).outputPolicy(for: asset)
        let batteryPolicy = TaptionOutputSelection(
            videoCodec: .hevc,
            container: .mp4,
            optimizationProfile: .batterySaver
        ).outputPolicy(for: asset)

        XCTAssertNil(balancedPolicy.advancedOptions.resizeTo)
        XCTAssertNil(balancedPolicy.advancedOptions.frameRate)
        XCTAssertEqual(batteryPolicy.advancedOptions.resizeTo, TaptionPixelSize(width: 1920, height: 1080))
        XCTAssertEqual(batteryPolicy.advancedOptions.frameRate, TaptionRationalFrameRate(numerator: 30))
        XCTAssertEqual(batteryPolicy.advancedOptions.optimizationProfile, .batterySaver)
        XCTAssertNotNil(balancedPolicy.advancedOptions.targetBitrate)
        XCTAssertNotNil(batteryPolicy.advancedOptions.targetBitrate)
        XCTAssertLessThan(
            batteryPolicy.advancedOptions.targetBitrate ?? Int.max,
            balancedPolicy.advancedOptions.targetBitrate ?? 0
        )
    }

}
