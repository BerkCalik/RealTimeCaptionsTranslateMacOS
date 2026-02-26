import Foundation

struct SubtitleViewModelQuestionDetector {
    private let maxRecentQuestions = 20
    private var processedFinalItemIDs: Set<String> = []
    private var recentQuestions: [String] = []

    mutating func reset() {
        processedFinalItemIDs.removeAll()
        recentQuestions.removeAll()
    }

    mutating func shouldTrigger(itemID: String, text: String) -> Bool {
        guard processedFinalItemIDs.contains(itemID) == false else { return false }
        processedFinalItemIDs.insert(itemID)

        guard let normalized = normalizedQuestionText(from: text) else { return false }
        guard looksLikeQuestion(normalized) else { return false }
        guard recentQuestions.contains(normalized) == false else { return false }

        recentQuestions.append(normalized)
        if recentQuestions.count > maxRecentQuestions {
            recentQuestions.removeFirst(recentQuestions.count - maxRecentQuestions)
        }
        return true
    }

    func normalizedQuestionText(from text: String) -> String? {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.count >= 3 else { return nil }
        guard normalized.rangeOfCharacter(from: .letters) != nil else { return nil }
        return normalized
    }

    func looksLikeQuestion(_ normalizedText: String) -> Bool {
        if normalizedText.contains("?") {
            return true
        }

        let singleWordStarters = [
            "who", "what", "when", "where", "why", "how",
            "can", "could", "would", "should",
            "do", "does", "did",
            "is", "are", "am", "was", "were",
            "describe", "explain", "discuss", "compare",
            "share", "tell", "walk", "talk", "give"
        ]

        for starter in singleWordStarters {
            if normalizedText == starter || normalizedText.hasPrefix(starter + " ") {
                return true
            }
        }

        let phraseStarters = [
            "tell me about",
            "tell me a little about",
            "describe your",
            "describe a time",
            "describe how",
            "explain your",
            "explain how",
            "walk me through",
            "talk about",
            "discuss your",
            "compare your",
            "give me an example",
            "give an example",
            "share a time",
            "share an example"
        ]

        for phrase in phraseStarters {
            if normalizedText == phrase || normalizedText.hasPrefix(phrase + " ") {
                return true
            }
        }

        let interviewPromptSignals = [
            "a time when",
            "an example of",
            "your professional background",
            "your background",
            "your experience with",
            "challenge you solved",
            "problem you solved"
        ]

        for signal in interviewPromptSignals where normalizedText.contains(signal) {
            return true
        }

        return false
    }
}
