import AppKit
import FanCurveUI
import SwiftUI

/// The curve editor's window. A menubar app has no main window, so this is a plain NSWindow that
/// sizes itself to the SwiftUI view. Closing it drops the views — a closed editor must not keep
/// redrawing with every status — but keeps the session, so the draft survives; reopening a clean
/// editor reloads the daemon's config, while "Curves…" on an open one only brings it forward.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private let app: AppModel
    private var window: NSWindow?
    private var session: CurveEditorSession?
    /// The window grows after it opens (the loading view is much smaller than the editor, and
    /// the smoothing section adds more), so every resize centres it again — until the user drags it
    /// somewhere; from then on it stays where they put it.
    private var keepCentred = true

    init(app: AppModel) {
        self.app = app
    }

    func show() {
        let session = self.session ?? CurveEditorSession(link: app.link)
        self.session = session
        let window = self.window ?? makeWindow()
        self.window = window
        if window.contentViewController == nil {
            let controller = NSHostingController(rootView: CurveEditorView(session: session, app: app))
            controller.sizingOptions = [.preferredContentSize]
            window.contentViewController = controller
            if !session.model.isDirty {
                session.load()
            }
        }
        if keepCentred {
            window.center()  // on screen at once, even if the config never loads
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidResize(_ notification: Notification) {
        if keepCentred {
            window?.center()
        }
    }

    /// Sent when the user starts dragging the window, not for `center()`.
    func windowWillMove(_ notification: Notification) {
        keepCentred = false
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = UIText.editorTitle
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}
