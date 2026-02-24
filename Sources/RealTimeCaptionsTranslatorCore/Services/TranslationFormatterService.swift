import Foundation

struct TranslationFormatterService {
    private let maxWordsPerLine = 12

    func formatLines(_ raw: String, isFinal: Bool) -> [String] {
        let normalized = normalizeWhitespace(raw)
        guard normalized.isEmpty == false else { return [] }

        let words = normalized
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard words.isEmpty == false else { return [] }

        var chunks: [[String]] = []
        var index = 0

        while index < words.count {
            let remaining = words.count - index
            var takeCount = min(maxWordsPerLine, remaining)

            if remaining == maxWordsPerLine + 1 {
                takeCount -= 1
            }

            chunks.append(Array(words[index ..< (index + takeCount)]))
            index += takeCount
        }

        if chunks.count > 1, chunks.last?.count == 1 {
            let previous = chunks.count - 2
            if let movedWord = chunks[previous].popLast() {
                chunks[chunks.count - 1].insert(movedWord, at: 0)
            }
        }

        var lines = chunks
            .map { $0.joined(separator: " ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        guard lines.isEmpty == false else { return [] }

        if isFinal {
            lines[lines.count - 1] = ensureTerminalPunctuation(lines[lines.count - 1])
        }

        return lines
    }

    private func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ensureTerminalPunctuation(_ text: String) -> String {
        guard text.isEmpty == false, let last = text.last else { return text }
        if [".", "!", "?"].contains(last) {
            return text
        }
        return text + "."
    }
}
