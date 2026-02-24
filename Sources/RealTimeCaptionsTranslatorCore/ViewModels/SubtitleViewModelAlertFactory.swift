import Foundation

struct SubtitleViewModelAlertState {
    let title: String
    let message: String
}

enum SubtitleViewModelAlertFactory {
    static func error(_ message: String) -> SubtitleViewModelAlertState? {
        make(title: "Error", message: message)
    }

    static func info(_ message: String) -> SubtitleViewModelAlertState? {
        make(title: "Info", message: message)
    }

    private static func make(title: String, message: String) -> SubtitleViewModelAlertState? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return SubtitleViewModelAlertState(title: title, message: trimmed)
    }
}
