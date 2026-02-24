import SwiftUI
import RealTimeCaptionsTranslatorCore

@main
struct RealTimeCaptionsTranslatorApp: App {
    @NSApplicationDelegateAdaptor(RealTimeCaptionsTranslatorApplicationDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
