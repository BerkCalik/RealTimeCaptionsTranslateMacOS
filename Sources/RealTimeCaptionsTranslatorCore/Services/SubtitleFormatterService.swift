import Foundation

struct SubtitleFormatterService: SubtitleFormatting {
    private let maxWordsPerLine = 12

    private static let fillerRegex: NSRegularExpression = {
        let pattern = #"\b(um|uh|like)\b|\byou know\b"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    func format(_ raw: String) -> SubtitlePayload {
        let lines = formatLines(raw)
        guard lines.isEmpty == false else {
            return .empty
        }

        if lines.count == 1 {
            return SubtitlePayload(line1: lines[0], line2: nil)
        }

        return SubtitlePayload(line1: lines[lines.count - 2], line2: lines.last)
    }

    func formatLines(_ raw: String) -> [String] {
        let cleaned = clean(raw)
        guard cleaned.isEmpty == false else {
            return []
        }

        let words = cleaned
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard words.isEmpty == false else {
            return []
        }

        var chunks: [[String]] = []
        var index = 0

        while index < words.count {
            let remaining = words.count - index
            var takeCount = min(maxWordsPerLine, remaining)

            // Keep the last line from becoming a single orphan word.
            if remaining == maxWordsPerLine + 1 {
                takeCount -= 1
            }

            chunks.append(Array(words[index ..< (index + takeCount)]))
            index += takeCount
        }

        if chunks.count > 1, chunks.last?.count == 1 {
            let previousIndex = chunks.count - 2
            if let movedWord = chunks[previousIndex].popLast() {
                chunks[chunks.count - 1].insert(movedWord, at: 0)
            }
        }

        var lines = chunks
            .map { $0.joined(separator: " ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        guard lines.isEmpty == false else {
            return []
        }

        lines[0] = sentenceCased(lines[0])
        lines[lines.count - 1] = ensureTerminalPunctuation(lines[lines.count - 1])
        return lines
    }

    private func clean(_ raw: String) -> String {
        let range = NSRange(location: 0, length: raw.utf16.count)
        let withoutFillers = Self.fillerRegex.stringByReplacingMatches(
            in: raw,
            options: [],
            range: range,
            withTemplate: ""
        )

        let normalizedSpacing = withoutFillers
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.!?])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ensureTerminalPunctuation(normalizedSpacing)
    }

    private func ensureTerminalPunctuation(_ text: String) -> String {
        guard text.isEmpty == false else { return text }
        guard let last = text.last else { return text }
        if [".", "!", "?"].contains(last) {
            return text
        }
        return text + "."
    }

    private func sentenceCased(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
