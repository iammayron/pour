import AppKit
import SwiftUI

/// Always-on-top, non-activating, borderless panel that hosts `FloatingView`.
final class FloatingPanel: NSPanel {
    init(model: AppModel) {
        let size = FloatingView.size(compact: model.compactCard)
        super.init(contentRect: NSRect(origin: .zero, size: size),
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
        contentView = NSHostingView(rootView: FloatingView().environment(model))
        // Restore only the position; the size always comes from the Wide/Compact setting.
        if setFrameUsingName("Floating") { setContentSize(size) } else { center() }
        setFrameAutosaveName("Floating")
    }

    func applySpaces(_ all: Bool) {
        collectionBehavior = all ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.moveToActiveSpace, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
}
