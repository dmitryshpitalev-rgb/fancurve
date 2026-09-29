import AppKit
import FanCurveUI
import SwiftUI

struct FanCurveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PopupView(model: delegate.model, openEditor: { delegate.openEditor() })
        } label: {
            MenuBarLabel(icon: delegate.model.iconModel)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Starts polling at launch and owns the curve editor's window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(link: DaemonLink())
    private lazy var editor = EditorWindowController(app: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon even when run outside the bundle; the bundle says LSUIElement as well.
        NSApp.setActivationPolicy(.accessory)
        model.start()
    }

    func openEditor() {
        editor.show()
    }
}

/// The menu bar item: one picture, redrawn only when it changes (`MenuBarIconModel`).
struct MenuBarLabel: View {
    @ObservedObject var icon: MenuBarIconModel

    var body: some View {
        Image(nsImage: FanIconRenderer.image(for: icon.state))
    }
}
