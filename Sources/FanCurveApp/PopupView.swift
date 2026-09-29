import AppKit
import FanCurveCore
import FanCurveUI
import SwiftUI

/// The menubar popup.
struct PopupView: View {
    @ObservedObject var model: AppModel
    let openEditor: () -> Void
    /// The pointer over the charts. It lives here, not in `ChartsView`: `ChartsView` is rebuilt
    /// with every status, and a new object there would make SwiftUI recompute all three charts.
    @State private var hover = ChartHover()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = model.snapshot {
                ModeLine(snapshot: snapshot)
                TilesRow(snapshot: snapshot)
                FansLine(snapshot: snapshot)
                ChartsView(history: model.history, ranges: snapshot.fans.map(\.range), hover: hover)
                Divider()
                ActionsView(model: model, snapshot: snapshot, openEditor: openEditor)
            } else {
                UnreachableView(problem: model.connectionProblem)
                Divider()
                QuitButton()
            }
        }
        .padding(14)
        .frame(width: 380)
        .onAppear { model.popupDidAppear() }
        .onDisappear { model.popupDidDisappear() }
    }
}

/// Who drives the fans. The icon carries the status with the text, so colour never speaks alone.
struct ModeLine: View {
    let snapshot: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(UIText.mode(snapshot.mode)).font(.headline)
            } icon: {
                Image(systemName: symbol).foregroundStyle(color)
            }
            if let error = snapshot.smcError {
                Text(UIText.smcErrorLine(error)).font(.caption).foregroundStyle(.secondary)
            }
            if let error = snapshot.configError {
                Text(UIText.configErrorLine(error)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var symbol: String {
        switch snapshot.mode {
        case .active: return "checkmark.circle.fill"
        case .safe: return "exclamationmark.triangle.fill"
        case .starting, .released, .disabled: return "pause.circle.fill"
        }
    }

    private var color: Color {
        switch snapshot.mode {
        case .active: return Palette.good
        case .safe: return Palette.critical
        case .starting, .released, .disabled: return .secondary
        }
    }
}

struct TilesRow: View {
    let snapshot: Snapshot

    var body: some View {
        HStack(spacing: 8) {
            ForEach(UIText.tiles(snapshot), id: \.title) { tile in
                TileView(tile: tile)
            }
        }
    }
}

struct TileView: View {
    let tile: UIText.Tile

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.title).font(.caption).foregroundStyle(.secondary)
            Text(tile.value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(tile.detail.isEmpty ? " " : tile.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(tile.highlighted ? Color.accentColor.opacity(0.14) : Palette.card))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(tile.highlighted ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
    }
}

struct FansLine: View {
    let snapshot: Snapshot

    var body: some View {
        HStack {
            Text(UIText.fansTitle).foregroundStyle(.secondary)
            Spacer()
            Text(UIText.fans(snapshot)).monospacedDigit()
        }
        .font(.callout)
    }
}

struct ActionsView: View {
    @ObservedObject var model: AppModel
    let snapshot: Snapshot
    let openEditor: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(UIText.gpuPolicyToggle)
                    Text(UIText.gpuPolicyDetail(snapshot.gpuPolicy)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(UIText.gpuPolicyToggle,
                       isOn: Binding(get: { snapshot.gpuPolicy.enabled }, set: { model.setGPUPolicy($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            HStack {
                Button(UIText.curvesButton, action: openEditor)
                Spacer()
                modeButton
            }
            if let error = model.actionError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.critical)
            }
            QuitButton()
        }
        .disabled(model.busy)
    }

    @ViewBuilder private var modeButton: some View {
        switch snapshot.mode {
        case .safe:
            Button(UIText.retryButton) { model.retry() }
        case .disabled:
            Button(UIText.resumeButton) { model.setEnabled(true) }
        case .starting, .active, .released:
            Button(UIText.releaseButton) { model.setEnabled(false) }
        }
    }
}

struct QuitButton: View {
    var body: some View {
        Button(UIText.quitButton) { NSApp.terminate(nil) }
            .buttonStyle(.link)
            .font(.callout)
    }
}

/// No snapshot: still connecting, or the daemon does not answer — the red state and how to get it
/// back.
struct UnreachableView: View {
    let problem: String?

    var body: some View {
        if let problem {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(Palette.critical)
                VStack(alignment: .leading, spacing: 4) {
                    Text(UIText.unreachableTitle).font(.headline)
                    Text(UIText.installHint).font(.callout).textSelection(.enabled)
                    Text(problem).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        } else {
            Label(UIText.connecting, systemImage: "hourglass").foregroundStyle(.secondary)
        }
    }
}
