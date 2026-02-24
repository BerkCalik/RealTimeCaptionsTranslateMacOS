import AppKit
import SwiftUI

final class FloatingPanelController<Content: View>: NSWindowController {
    init(rootView: Content) {
        let panel = NSPanel(
            contentRect: NSRect(x: 180, y: 160, width: 1180, height: 780),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentMinSize = NSSize(width: 980, height: 700)

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
