import Combine
import FanCurveCore

public enum IconAppearance: Equatable, Sendable {
    /// The curve drives the fans.
    case normal
    /// macOS drives the fans: starting, released, disabled.
    case dimmed
    /// Safe mode, or the daemon does not answer.
    case alert
}

/// What the menubar shows.
public struct MenuBarIconState: Equatable, Sendable {
    public var level: Int
    public var appearance: IconAppearance
    public var text: String

    public init(level: Int, appearance: IconAppearance, text: String) {
        self.level = level
        self.appearance = appearance
        self.text = text
    }

    /// Before the daemon's first answer: an unlit, dimmed wheel.
    static let initial = MenuBarIconState(level: 0, appearance: .dimmed, text: "")

    /// The state after the latest status; nil when the daemon did not answer. The level keeps its 2%
    /// hysteresis across calls (`fanIconLevel`).
    func next(_ snapshot: Snapshot?) -> MenuBarIconState {
        guard let snapshot else {
            return MenuBarIconState(level: level, appearance: .alert, text: "")
        }
        let appearance: IconAppearance
        switch snapshot.mode {
        case .active: appearance = .normal
        case .safe: appearance = .alert
        case .starting, .released, .disabled: appearance = .dimmed
        }
        let percent = Self.fanPercent(snapshot) ?? 0
        return MenuBarIconState(level: fanIconLevel(percent: percent, previous: level), appearance: appearance,
                                text: appearance == .alert ? "" : UIText.menuBarTemperature(snapshot))
    }

    /// The faster fan's actual speed in % of its range; nil when no tachometer reads.
    static func fanPercent(_ snapshot: Snapshot) -> Double? {
        FanRange.fasterPercent(rpm: snapshot.fans.map(\.actualRPM), ranges: snapshot.fans.map(\.range))
    }
}

/// Publishes only real changes, so the menu bar is redrawn only when its picture changes.
public final class MenuBarIconModel: ObservableObject {
    @Published public private(set) var state = MenuBarIconState.initial

    public init() {}

    func update(with snapshot: Snapshot?) {
        let next = state.next(snapshot)
        if next != state {
            state = next
        }
    }
}
