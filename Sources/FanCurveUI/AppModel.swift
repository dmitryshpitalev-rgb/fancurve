import Combine
import FanCurveCore
import Foundation

/// What the menubar shows, fed by the daemon once a second. Used from the main thread; the link
/// calls back there.
public final class AppModel: ObservableObject {
    static let historySeconds = HistoryLimits.seconds
    /// What a poll asks for while the popup is open: an overlap, so a late poll leaves no hole;
    /// `merge` drops the repeats.
    static let deltaSeconds = 5

    @Published public private(set) var snapshot: Snapshot?
    /// Why the last poll failed, in words; nil while the daemon answers. No snapshot and no problem
    /// means the first answer is still on its way.
    @Published public private(set) var connectionProblem: String?
    @Published public private(set) var history = HistoryBuffer()
    /// The last failed button action, in words; cleared by the next one that succeeds.
    @Published public private(set) var actionError: String?
    /// A button action is on its way to the daemon.
    @Published public private(set) var busy = false

    public let link: DaemonLinking
    /// The menubar picture lives apart, so it is not redrawn with every status.
    public let iconModel = MenuBarIconModel()

    private var statusInFlight = false
    private var popupVisible = false
    private var timer: Timer?

    public init(link: DaemonLinking) {
        self.link = link
    }

    /// Polls now and then once a second; the tolerance lets macOS coalesce the wakeups.
    public func start() {
        poll()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func poll() {
        guard !statusInFlight else { return }
        statusInFlight = true
        link.status { [weak self] result in
            guard let self else { return }
            self.statusInFlight = false
            switch result {
            case .success(let snapshot):
                self.show(snapshot)
                if self.popupVisible {
                    // Until the hour has arrived (its first load failed), ask for the whole hour again.
                    let full = self.history.samples.isEmpty
                    self.loadHistory(seconds: full ? Self.historySeconds : Self.deltaSeconds, replace: full)
                }
            case .failure(let error):
                // Publish only what changed: a daemon that stays down must not redraw the popup every second.
                let problem = UIText.connectionProblem(error)
                if self.snapshot != nil { self.snapshot = nil }
                if self.connectionProblem != problem { self.connectionProblem = problem }
                self.iconModel.update(with: nil)
            }
        }
    }

    public func popupDidAppear() {
        popupVisible = true
        loadHistory(seconds: Self.historySeconds, replace: true)
    }

    public func popupDidDisappear() {
        popupVisible = false
    }

    public func setEnabled(_ enabled: Bool) {
        act({ link, done in link.setEnabled(enabled, done) }) { [weak self] snapshot in
            self?.show(snapshot)
        }
    }

    public func retry() {
        act({ link, done in link.retry(done) }) { [weak self] snapshot in
            self?.show(snapshot)
        }
    }

    public func setGPUPolicy(_ enabled: Bool) {
        act({ link, done in link.setGPUPolicy(enabled, done) }) { [weak self] state in
            self?.snapshot?.gpuPolicy = state
        }
    }

    private func show(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        if connectionProblem != nil {
            connectionProblem = nil
        }
        iconModel.update(with: snapshot)
    }

    private func loadHistory(seconds: Int, replace: Bool) {
        link.history(seconds: seconds) { [weak self] result in
            guard let self, case .success(let samples) = result else { return }
            if replace {
                self.history.replace(with: samples)
            } else {
                self.history.merge(samples)
            }
        }
    }

    private func act<T>(_ call: (DaemonLinking, @escaping (Result<T, Error>) -> Void) -> Void,
                        _ success: @escaping (T) -> Void) {
        busy = true
        call(link) { [weak self] result in
            guard let self else { return }
            self.busy = false
            switch result {
            case .success(let value):
                self.actionError = nil
                success(value)
            case .failure(let error):
                self.actionError = UIText.actionFailed(error)
            }
        }
    }
}
