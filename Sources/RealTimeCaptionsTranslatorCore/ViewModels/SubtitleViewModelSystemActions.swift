import AppKit
import Foundation

struct SubtitleViewModelSystemActions {
    var openURL: (URL) -> Bool
    var copyStringToPasteboard: (String) -> Void

    init(
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        copyStringToPasteboard: @escaping (String) -> Void = { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    ) {
        self.openURL = openURL
        self.copyStringToPasteboard = copyStringToPasteboard
    }

    func openAudioMidiSetup() -> Bool {
        let primary = URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app")
        let fallback = URL(fileURLWithPath: "/Applications/Utilities/Audio MIDI Setup.app")
        return openURL(primary) || openURL(fallback)
    }
}
