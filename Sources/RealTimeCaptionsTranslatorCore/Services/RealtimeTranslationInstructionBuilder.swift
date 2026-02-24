import Foundation

enum RealtimeTranslationInstructionBuilder {
    static func buildSessionInstructions() -> String {
        "You provide real-time English transcription events from audio. Do not produce assistant text automatically. Wait for explicit response.create translation requests."
    }

    static func buildTranslationRequestInstructions(
        keepTechWordsOriginal: Bool,
        technicalTerms: [String],
        isFinal: Bool = true
    ) -> String {
        let speedRule: String
        if isFinal {
            speedRule = "This is a final utterance. Return a complete Turkish subtitle sentence."
        } else {
            speedRule = "This is a live partial utterance. Respond quickly with the best Turkish fragment so far; sentence may be incomplete."
        }

        var base = "Translate the given English subtitle into natural Turkish subtitle text. Output ONLY Turkish text. No explanations, no labels, no questions. \(speedRule)"

        guard keepTechWordsOriginal else {
            return base
        }

        if technicalTerms.isEmpty {
            return base + " Keep software and technical identifiers in original form."
        }

        let listed = technicalTerms.joined(separator: ", ")
        base += " Keep these technical terms exactly unchanged: \(listed)."
        return base
    }

    static func extractTechnicalTerms(from englishText: String) -> [String] {
        let text = englishText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return [] }

        let patterns = [
            #"`([^`]{1,64})`"#,
            #"\b[A-Z]{2,}\b"#,
            #"\b[A-Za-z]+[A-Z][A-Za-z0-9]*\b"#,
            #"\b[A-Za-z0-9]+(?:[_./-][A-Za-z0-9]+)+\b"#,
            #"\bv\d+(?:\.\d+){0,3}\b"#
        ]

        var ordered: [String] = []
        var seen: Set<String> = []

        for pattern in patterns {
            for match in captureMatches(pattern: pattern, in: text) {
                var term = match.trimmingCharacters(in: CharacterSet(charactersIn: "`'\"()[]{}<>.,;:!? "))
                term = term.trimmingCharacters(in: .whitespacesAndNewlines)
                guard term.count >= 2, term.count <= 64 else { continue }
                guard term.rangeOfCharacter(from: .letters) != nil else { continue }

                let key = term.lowercased()
                guard seen.contains(key) == false else { continue }

                seen.insert(key)
                ordered.append(term)
                if ordered.count == 20 {
                    return ordered
                }
            }
        }

        return ordered
    }

    private static func captureMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)

        return matches.compactMap { match in
            let selectedRange: NSRange
            if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                selectedRange = match.range(at: 1)
            } else {
                selectedRange = match.range
            }
            guard selectedRange.location != NSNotFound else { return nil }
            return nsText.substring(with: selectedRange)
        }
    }
}
