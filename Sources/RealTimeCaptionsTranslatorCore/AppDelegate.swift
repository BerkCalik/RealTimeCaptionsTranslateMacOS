import AppKit
import SwiftUI

@MainActor
public final class RealTimeCaptionsTranslatorApplicationDelegate: NSObject, NSApplicationDelegate {
    private var floatingPanelController: FloatingPanelController<SubtitleView>?

    private lazy var subtitleViewModel: SubtitleViewModel = {
        let audioService = AudioCaptureService()
        let realtimeService = RealtimeWebRTCService()
        let qaService = RealtimeQuestionAnswerService()

        return SubtitleViewModel(
            audioService: audioService,
            realtimeService: realtimeService,
            qaService: qaService
        )
    }()

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let subtitleView = SubtitleView(viewModel: subtitleViewModel)
        let panelController = FloatingPanelController(rootView: subtitleView)

        floatingPanelController = panelController
        panelController.showWindow(nil)
        panelController.window?.orderFrontRegardless()

        NSApp.activate(ignoringOtherApps: true)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor [weak self] in
            await self?.subtitleViewModel.shutdown()
        }
    }
}
