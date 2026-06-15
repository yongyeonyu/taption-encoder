import Foundation

enum FCPXMLValidationResult: Equatable {
    case valid
    case invalid(reason: String)
}

protocol FCPXMLValidating {
    func validateFCPXML(at url: URL) async throws -> FCPXMLValidationResult
}

struct FakeFCPXMLValidator: FCPXMLValidating {
    func validateFCPXML(at url: URL) async throws -> FCPXMLValidationResult {
        .valid
    }
}
