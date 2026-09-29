import AppKit
import FanCurveCore
import FanCurveUI
import SwiftUI

/// `FanCurve --snapshot DIR [ru|uk|en]`: the screens drawn from PreviewData into PNGs, light and
/// dark, in the given language (else the system's), so they can be checked without the menu bar.
enum Snapshots {
    /// False when any picture was not written; each failure is told on stderr.
    @MainActor
    static func render(to directory: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            complain("could not create \(directory.path): \(error)")
            return false
        }
        var ok = true
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .dark ? "dark" : "light"
            let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
            appearance.performAsCurrentDrawingAppearance {
                MainActor.assumeIsolated {
                    ok = renderScreens(scheme: scheme, name: name, to: directory) && ok
                }
            }
        }
        return ok
    }

    @MainActor
    private static func renderScreens(scheme: ColorScheme, name: String, to directory: URL) -> Bool {
        let model = AppModel(link: PreviewLink())
        model.poll()
        model.popupDidAppear()
        var ok = write(PopupView(model: model, openEditor: {}), scheme: scheme,
                       to: directory.appendingPathComponent("popup-\(name).png"))
        let session = CurveEditorSession(link: PreviewLink())
        session.load()
        session.model.select(1)
        ok = write(CurveEditorView(session: session, app: model, expandSmoothing: true), scheme: scheme,
                   to: directory.appendingPathComponent("editor-\(name).png")) && ok
        let down = AppModel(link: UnreachableLink())
        down.poll()
        ok = write(PopupView(model: down, openEditor: {}), scheme: scheme,
                   to: directory.appendingPathComponent("popup-unreachable-\(name).png")) && ok
        ok = write(IconSheet(), scheme: scheme, to: directory.appendingPathComponent("icons-\(name).png")) && ok
        return ok
    }

    /// Renders through NSHostingView, so native controls (toggles, pickers, buttons) are drawn too;
    /// ImageRenderer leaves yellow placeholders in their place.
    @MainActor
    static func write<V: View>(_ view: V, scheme: ColorScheme, to url: URL) -> Bool {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, scheme)
            .background(Color(nsColor: .windowBackgroundColor)))
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            complain("could not render \(url.lastPathComponent)")
            return false
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            complain("could not encode \(url.lastPathComponent)")
            return false
        }
        do {
            try png.write(to: url)
            print("wrote \(url.path)")
            return true
        } catch {
            complain("could not write \(url.path): \(error)")
            return false
        }
    }

    private static func complain(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}

/// Every menubar picture: the six wheel levels, active and dimmed, and the alert.
private struct IconSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([IconAppearance.normal, .dimmed], id: \.self) { appearance in
                HStack(spacing: 14) {
                    ForEach(0...5, id: \.self) { level in
                        Image(nsImage: FanIconRenderer.image(for: MenuBarIconState(level: level, appearance: appearance,
                                                                                    text: "\(60 + level * 6)°")))
                    }
                }
            }
            Image(nsImage: FanIconRenderer.image(for: MenuBarIconState(level: 0, appearance: .alert, text: "")))
        }
        .padding(12)
    }
}
