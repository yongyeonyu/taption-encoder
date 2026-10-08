import Foundation

enum FCPXMLProjectDocumentError: LocalizedError, Equatable {
    case unsupportedDocumentKind(TaptionProjectDocumentKind)
    case missingEmbeddedProjectMetadata
    case invalidEmbeddedProjectMetadata
    case invalidFCPXMLRoot

    var errorDescription: String? {
        switch self {
        case .unsupportedDocumentKind(let kind):
            return "\(kind.rawValue) project documents are not writable in this build."
        case .missingEmbeddedProjectMetadata:
            return "The FCPXML file does not contain BOKKI Encoder project metadata."
        case .invalidEmbeddedProjectMetadata:
            return "The BOKKI Encoder project metadata in this FCPXML file could not be decoded."
        case .invalidFCPXMLRoot:
            return "The selected file is not a valid FCPXML document."
        }
    }
}

struct FCPXMLProjectDocumentStore: ProjectDocumentStoring, TaptionFCPXMLWriting, TaptionFCPXMLReading {
    private let serializer: TaptionFCPXMLProjectSerializer
    private let parser: TaptionFCPXMLProjectParser

    init(
        serializer: TaptionFCPXMLProjectSerializer = TaptionFCPXMLProjectSerializer(),
        parser: TaptionFCPXMLProjectParser = TaptionFCPXMLProjectParser()
    ) {
        self.serializer = serializer
        self.parser = parser
    }

    func saveProject(_ project: TaptionVideoProject, to url: URL) async throws {
        try await saveProject(project, to: url, as: project.fcpxmlPolicy.documentKind)
    }

    func saveProject(
        _ project: TaptionVideoProject,
        to url: URL,
        as kind: TaptionProjectDocumentKind
    ) async throws {
        guard kind == .fcpxml else {
            throw FCPXMLProjectDocumentError.unsupportedDocumentKind(kind)
        }
        try await writeFCPXML(project: project, to: url)
    }

    func loadProject(from url: URL) async throws -> TaptionVideoProject {
        try await readFCPXML(from: url)
    }

    func writeFCPXML(project: TaptionVideoProject, to url: URL) async throws {
        let data = try serializer.makeData(for: project)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
    }

    func readFCPXML(from url: URL) async throws -> TaptionVideoProject {
        let data = try Data(contentsOf: url)
        return try parser.parseProject(from: data)
    }
}

struct TaptionFCPXMLProjectSerializer {
    static let embeddedProjectMetadataKey = "com.taption.encoder.project-json-v1"
    static let defaultDTDVersion = "1.13"

    private let encoder: JSONEncoder

    init(encoder: JSONEncoder = .taptionProjectDocumentEncoder) {
        self.encoder = encoder
    }

    func makeData(for project: TaptionVideoProject) throws -> Data {
        Data(try makeString(for: project).utf8)
    }

    func makeString(for project: TaptionVideoProject) throws -> String {
        let embeddedProject = try encoder
            .encode(project)
            .base64EncodedString()
        let version = project.fcpxmlPolicy.dtdVersion ?? Self.defaultDTDVersion
        let projectName = xmlEscaped(project.title)
        let formatID = "r1"
        let sequenceDuration = fcpxmlTime(project.timeline.duration)

        var lines: [String] = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<!DOCTYPE fcpxml>",
            "<fcpxml version=\"\(xmlEscaped(version))\">",
            "  <resources>",
            "    <format id=\"\(formatID)\" name=\"BOKKI Encoder Canvas\" \(formatAttributes(for: project.timeline.canvasSize))/>"
        ]

        for (index, asset) in project.assets.enumerated() {
            lines.append(assetResourceLine(for: asset, index: index))
        }

        lines += [
            "  </resources>",
            "  <library>",
            "    <event name=\"BOKKI Encoder\">",
            "      <project name=\"\(projectName)\">",
            "        <metadata>",
            "          <md key=\"\(Self.embeddedProjectMetadataKey)\" value=\"\(embeddedProject)\"/>",
            "        </metadata>",
            "        <sequence duration=\"\(sequenceDuration)\" format=\"\(formatID)\">",
            "          <spine>"
        ]

        for clip in assetClipLines(for: project) {
            lines.append(clip)
        }

        lines += [
            "          </spine>",
            "        </sequence>",
            "      </project>",
            "    </event>",
            "  </library>",
            "</fcpxml>",
            ""
        ]
        return lines.joined(separator: "\n")
    }

    private func formatAttributes(for size: TaptionPixelSize?) -> String {
        guard let size else {
            return "width=\"1920\" height=\"1080\""
        }
        return "width=\"\(max(1, size.width))\" height=\"\(max(1, size.height))\""
    }

    private func assetResourceLine(for asset: TaptionVideoAsset, index: Int) -> String {
        let assetID = fcpxmlAssetID(for: asset.id, fallbackIndex: index)
        let name = xmlEscaped(asset.displayName)
        let duration = fcpxmlTime(asset.duration ?? 0)
        let src = xmlEscaped(asset.location.url?.absoluteString ?? "")
        let srcAttribute = src.isEmpty ? "" : " src=\"\(src)\""
        return "    <asset id=\"\(assetID)\" name=\"\(name)\" duration=\"\(duration)\"\(srcAttribute) hasVideo=\"1\" hasAudio=\"\(asset.audioTracks.isEmpty ? "0" : "1")\"/>"
    }

    private func assetClipLines(for project: TaptionVideoProject) -> [String] {
        let assetIndexes = Dictionary(uniqueKeysWithValues: project.assets.enumerated().map { ($0.element.id, $0.offset) })
        return project.timeline.segments.flatMap { segment in
            segment.slices.filter(\.isEnabled).map { slice in
                let assetID = fcpxmlAssetID(
                    for: segment.assetID,
                    fallbackIndex: assetIndexes[segment.assetID] ?? 0
                )
                let name = xmlEscaped(segment.displayName)
                let offset = fcpxmlTime(slice.timelineStart)
                let start = fcpxmlTime(slice.sourceRange.start)
                let duration = fcpxmlTime(slice.sourceRange.duration)
                return "            <asset-clip name=\"\(name)\" ref=\"\(assetID)\" offset=\"\(offset)\" start=\"\(start)\" duration=\"\(duration)\"/>"
            }
        }
    }

    private func fcpxmlAssetID(for id: UUID, fallbackIndex: Int) -> String {
        let raw = id.uuidString.replacingOccurrences(of: "-", with: "")
        guard !raw.isEmpty else {
            return "asset\(fallbackIndex + 1)"
        }
        return "asset\(raw)"
    }

    private func fcpxmlTime(_ seconds: TimeInterval) -> String {
        let milliseconds = max(0, Int((seconds * 1000).rounded()))
        guard milliseconds > 0 else {
            return "0s"
        }
        return "\(milliseconds)/1000s"
    }

    private func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

struct TaptionFCPXMLProjectParser {
    private let decoder: JSONDecoder

    init(decoder: JSONDecoder = .taptionProjectDocumentDecoder) {
        self.decoder = decoder
    }

    func parseProject(from data: Data) throws -> TaptionVideoProject {
        let delegate = EmbeddedProjectMetadataParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.sawFCPXMLRoot else {
            throw FCPXMLProjectDocumentError.invalidFCPXMLRoot
        }
        guard let encodedProject = delegate.embeddedProject else {
            throw FCPXMLProjectDocumentError.missingEmbeddedProjectMetadata
        }
        guard let projectData = Data(base64Encoded: encodedProject) else {
            throw FCPXMLProjectDocumentError.invalidEmbeddedProjectMetadata
        }

        do {
            return try decoder.decode(TaptionVideoProject.self, from: projectData)
        } catch {
            throw FCPXMLProjectDocumentError.invalidEmbeddedProjectMetadata
        }
    }
}

private final class EmbeddedProjectMetadataParserDelegate: NSObject, XMLParserDelegate {
    var sawFCPXMLRoot = false
    var embeddedProject: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "fcpxml" {
            sawFCPXMLRoot = true
        }

        guard elementName == "md",
              attributeDict["key"] == TaptionFCPXMLProjectSerializer.embeddedProjectMetadataKey,
              let value = attributeDict["value"] else {
            return
        }
        embeddedProject = value
    }
}

private extension JSONEncoder {
    static let taptionProjectDocumentEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let taptionProjectDocumentDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        return decoder
    }()
}
