import Foundation

struct ResumeContextLoadResult: Equatable {
    let text: String
    let usingFallback: Bool
    let statusMessage: String?
}

enum ResumeContextLoader {
    static func load(bundle: Bundle = .module) -> ResumeContextLoadResult {
        guard let url = bundle.url(forResource: "ResumeContext", withExtension: "md") else {
            return ResumeContextLoadResult(
                text: fallbackContext,
                usingFallback: true,
                statusMessage: "ResumeContext.md not found. Auto Q&A is using generic mode."
            )
        }

        do {
            let raw = try String(contentsOf: url, encoding: .utf8)
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.isEmpty == false else {
                return ResumeContextLoadResult(
                    text: fallbackContext,
                    usingFallback: true,
                    statusMessage: "ResumeContext.md is empty. Auto Q&A is using generic mode."
                )
            }

            return ResumeContextLoadResult(
                text: normalized,
                usingFallback: false,
                statusMessage: nil
            )
        } catch {
            return ResumeContextLoadResult(
                text: fallbackContext,
                usingFallback: true,
                statusMessage: "ResumeContext.md could not be read. Auto Q&A is using generic mode."
            )
        }
    }

    private static let fallbackContext = "No resume context is available. Answer in professional English, keep claims general, and avoid inventing specific employers, dates, metrics, or certifications."
}
