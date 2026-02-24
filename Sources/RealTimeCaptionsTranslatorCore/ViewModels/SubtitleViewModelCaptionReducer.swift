import Foundation

struct SubtitleViewModelCaptionReducer {
    private let formatter = TranslationFormatterService()
    private let maxStoredLines = 500

    private(set) var subtitle: SubtitlePayload = .empty
    private(set) var subtitleLines: [String] = []
    private(set) var translatedLines: [String] = []

    private var committedEnglishLines: [String] = []
    private var activeEnglishItemID: String?
    private var activeEnglishBuffer = ""

    private var committedTurkishLines: [String] = []
    private var activeTurkishResponseID: String?
    private var activeTurkishBuffer = ""

    private var finalizedTurkishResponseIDs: Set<String> = []

    mutating func clearAll() {
        subtitle = .empty
        subtitleLines = []
        translatedLines = []

        committedEnglishLines = []
        activeEnglishItemID = nil
        activeEnglishBuffer = ""

        committedTurkishLines = []
        activeTurkishResponseID = nil
        activeTurkishBuffer = ""

        finalizedTurkishResponseIDs.removeAll()
    }

    mutating func resetTurkishFinalDeduplication() {
        finalizedTurkishResponseIDs.removeAll()
    }

    mutating func handleEnglishDelta(itemID: String, text: String) {
        guard text.isEmpty == false else { return }

        if activeEnglishItemID != itemID {
            if activeEnglishBuffer.isEmpty == false {
                commitEnglishBufferAsFinal()
            }
            activeEnglishItemID = itemID
            activeEnglishBuffer = ""
        }

        activeEnglishBuffer = appendDelta(activeEnglishBuffer, delta: text)

        let activeLines = formatter.formatLines(activeEnglishBuffer, isFinal: false)
        subtitleLines = mergedLines(committed: committedEnglishLines, active: activeLines)
        subtitle = payload(from: subtitleLines)
    }

    mutating func handleEnglishFinal(itemID: String, text: String) {
        if activeEnglishItemID != itemID {
            activeEnglishItemID = itemID
            activeEnglishBuffer = ""
        }

        if text.isEmpty == false {
            activeEnglishBuffer = text
        }

        commitEnglishBufferAsFinal()
    }

    mutating func handleTurkishDelta(responseID: String, text: String) {
        guard text.isEmpty == false else { return }

        if activeTurkishResponseID != responseID {
            activeTurkishResponseID = responseID
            activeTurkishBuffer = ""
        }

        activeTurkishBuffer = appendDelta(activeTurkishBuffer, delta: text)
        if isUnwantedAssistantText(activeTurkishBuffer) {
            activeTurkishBuffer = ""
            return
        }

        let activeLines = formatter.formatLines(activeTurkishBuffer, isFinal: false)
        translatedLines = mergedLines(committed: committedTurkishLines, active: activeLines)
    }

    mutating func handleTurkishFinal(responseID: String) {
        guard finalizedTurkishResponseIDs.contains(responseID) == false else { return }
        finalizedTurkishResponseIDs.insert(responseID)

        guard activeTurkishResponseID == responseID else { return }
        commitTurkishBufferAsFinal()
    }

    private mutating func commitEnglishBufferAsFinal() {
        let finalLines = formatter.formatLines(activeEnglishBuffer, isFinal: true)
        if finalLines.isEmpty == false {
            committedEnglishLines = trimmed(mergedLines(committed: committedEnglishLines, active: finalLines))
        }

        activeEnglishItemID = nil
        activeEnglishBuffer = ""
        subtitleLines = committedEnglishLines
        subtitle = payload(from: subtitleLines)
    }

    private mutating func commitTurkishBufferAsFinal() {
        if isUnwantedAssistantText(activeTurkishBuffer) {
            activeTurkishResponseID = nil
            activeTurkishBuffer = ""
            translatedLines = committedTurkishLines
            return
        }

        let finalLines = formatter.formatLines(activeTurkishBuffer, isFinal: true)
        if finalLines.isEmpty == false {
            committedTurkishLines = trimmed(mergedLines(committed: committedTurkishLines, active: finalLines))
        }

        activeTurkishResponseID = nil
        activeTurkishBuffer = ""
        translatedLines = committedTurkishLines
    }

    private func appendDelta(_ current: String, delta: String) -> String {
        if current.hasSuffix(delta) {
            return current
        }

        if delta.hasPrefix(current), delta.count > current.count {
            return delta
        }

        return current + delta
    }

    private func isUnwantedAssistantText(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.isEmpty {
            return false
        }

        let blockedPhrases = [
            "lütfen neyi çevirmemi istediğinizi söyleyin",
            "lütfen neyi çevirmemi istersiniz",
            "please tell me what you want me to translate",
            "what would you like me to translate",
            "what do you want me to translate"
        ]

        for phrase in blockedPhrases where normalized.contains(phrase) {
            return true
        }

        if normalized.hasPrefix("lütfen"),
           normalized.contains("çevir"),
           normalized.contains("söyle") {
            return true
        }

        return false
    }

    private func trimmed(_ lines: [String]) -> [String] {
        if lines.count <= maxStoredLines {
            return lines
        }

        return Array(lines.suffix(maxStoredLines))
    }

    private func payload(from lines: [String]) -> SubtitlePayload {
        guard lines.isEmpty == false else { return .empty }
        if lines.count == 1 {
            return SubtitlePayload(line1: lines[0], line2: nil)
        }
        return SubtitlePayload(line1: lines[lines.count - 2], line2: lines[lines.count - 1])
    }

    private func mergedLines(committed: [String], active: [String]) -> [String] {
        guard active.isEmpty == false else { return committed }
        guard committed.isEmpty == false else { return active }

        let overlap = longestOverlapSuffixPrefix(lhs: committed, rhs: active)
        return committed + active.dropFirst(overlap)
    }

    private func longestOverlapSuffixPrefix(lhs: [String], rhs: [String]) -> Int {
        let limit = min(lhs.count, rhs.count)

        for size in stride(from: limit, through: 1, by: -1) {
            let lhsSuffix = lhs.suffix(size).map(normalizedLine)
            let rhsPrefix = rhs.prefix(size).map(normalizedLine)
            if lhsSuffix.elementsEqual(rhsPrefix) {
                return size
            }
        }

        return 0
    }

    private func normalizedLine(_ line: String) -> String {
        line
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?"))
    }
}
