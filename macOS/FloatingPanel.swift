import AppKit
import SwiftUI

/// Always-on-top, non-activating, borderless panel that hosts `FloatingView`.
final class FloatingPanel: NSPanel {
    init(model: AppModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false   // window shadow is rectangular and lags behind the rounded glass while dragging
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        applySpaces(model.allSpaces)
        let host = NSHostingView(rootView: FloatingView().environment(model))
        host.sizingOptions = [.preferredContentSize]   // panel follows the Wide/Compact size
        contentView = host
        if !setFrameUsingName("Floating") { center() }
        setFrameAutosaveName("Floating")
    }

    func applySpaces(_ all: Bool) {
        collectionBehavior = all ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.moveToActiveSpace, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
}
