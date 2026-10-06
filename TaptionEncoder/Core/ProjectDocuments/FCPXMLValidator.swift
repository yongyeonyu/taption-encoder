import Foundation

enum FCPXMLValidationResult: Equatable {
    case valid
    case invalid(reason: String)
}

protocol FCPXMLValidating {
    func validateFCPXML(at url: URL) async throws -> FCPXMLValidationResult
}

struct FCPXMLValidator: FCPXMLValidating {
    private let requiredMetadataKey: String

    init(
        requiredMetadataKey: String = TaptionFCPXMLProjectSerializer.embeddedProjectMetadataKey
    ) {
        self.requiredMetadataKey = requiredMetadataKey
    }

    func validateFCPXML(at url: URL) async throws -> FCPXMLValidationResult {
        let data = try Data(contentsOf: url)
        return validate(data: data)
    }

    func validate(data: Data) -> FCPXMLValidationResult {
        let delegate = FCPXMLStructureValidationDelegate(
            requiredMetadataKey: requiredMetadataKey
        )
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            return .invalid(reason: parser.parserError?.localizedDescription ?? "XML parsing failed.")
        }
        return delegate.result
    }
}

struct FakeFCPXMLValidator: FCPXMLValidating {
    func validateFCPXML(at url: URL) async throws -> FCPXMLValidationResult {
        .valid
    }
}

private final class FCPXMLStructureValidationDelegate: NSObject, XMLParserDelegate {
    private let requiredMetadataKey: String
    private var rootElementName: String?
    private var fcpxmlVersion: String?
    private var hasResources = false
    private var hasLibrary = false
    private var hasProject = false
    private var hasSequence = false
    private var hasSpine = false
    private var hasEmbeddedMetadata = false
    private var hasAssetClips = false

    init(requiredMetadataKey: String) {
        self.requiredMetadataKey = requiredMetadataKey
    }

    var result: FCPXMLValidationResult {
        guard rootElementName == "fcpxml" else {
            return .invalid(reason: "Root element must be fcpxml.")
        }
        guard let fcpxmlVersion, !fcpxmlVersion.isEmpty else {
            return .invalid(reason: "FCPXML version is missing.")
        }
        guard hasResources else {
            return .invalid(reason: "FCPXML resources section is missing.")
        }
        guard hasLibrary else {
            return .invalid(reason: "FCPXML library section is missing.")
        }
        guard hasProject else {
            return .invalid(reason: "FCPXML project section is missing.")
        }
        guard hasSequence else {
            return .invalid(reason: "FCPXML sequence section is missing.")
        }
        guard hasSpine else {
            return .invalid(reason: "FCPXML spine section is missing.")
        }
        guard hasEmbeddedMetadata else {
            return .invalid(reason: "YYY Encoder project metadata is missing.")
        }
        guard hasAssetClips else {
            return .invalid(reason: "FCPXML contains no asset clips.")
        }
        return .valid
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if rootElementName == nil {
            rootElementName = elementName
        }

        switch elementName {
        case "fcpxml":
            fcpxmlVersion = attributeDict["version"]
        case "resources":
            hasResources = true
        case "library":
            hasLibrary = true
        case "project":
            hasProject = true
        case "sequence":
            hasSequence = true
        case "spine":
            hasSpine = true
        case "asset-clip":
            hasAssetClips = true
        case "md" where attributeDict["key"] == requiredMetadataKey:
            hasEmbeddedMetadata = attributeDict["value"]?.isEmpty == false
        default:
            break
        }
    }
}
