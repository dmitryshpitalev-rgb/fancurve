import Dispatch
import IOKit
import IOKit.pwr_mgt

/// System sleep and wake notifications. Callbacks run on the queue given to `start`.
/// Every process registered here must answer "can sleep" and "will sleep", or sleep waits 30 s for it;
/// `willSleep` runs before the answer, so fans are handed back before the machine sleeps.
public final class PowerEvents {
    // iokit_common_msg(...) values; Swift does not import those C macros.
    static let canSystemSleep: UInt32 = 0xE000_0270
    static let systemWillSleep: UInt32 = 0xE000_0280
    static let systemHasPoweredOn: UInt32 = 0xE000_0300

    private let willSleep: () -> Void
    private let didWake: () -> Void
    /// IOAllowPowerChange; a test records the answers instead.
    private let allowPowerChange: (io_connect_t, Int) -> Void
    private var rootPort: io_connect_t = 0
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0

    public convenience init(willSleep: @escaping () -> Void, didWake: @escaping () -> Void) {
        self.init(willSleep: willSleep, didWake: didWake, allowPowerChange: { _ = IOAllowPowerChange($0, $1) })
    }

    init(willSleep: @escaping () -> Void, didWake: @escaping () -> Void,
         allowPowerChange: @escaping (io_connect_t, Int) -> Void) {
        self.willSleep = willSleep
        self.didWake = didWake
        self.allowPowerChange = allowPowerChange
    }

    /// False if the registration failed. Keep the object alive for as long as notifications are wanted.
    public func start(queue: DispatchQueue) -> Bool {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(refcon, &notifyPort, { refcon, _, messageType, argument in
            guard let refcon else { return }
            Unmanaged<PowerEvents>.fromOpaque(refcon).takeUnretainedValue().handle(messageType, argument)
        }, &notifier)
        guard rootPort != 0, let notifyPort else { return false }
        IONotificationPortSetDispatchQueue(notifyPort, queue)
        return true
    }

    deinit {
        if notifier != 0 { IODeregisterForSystemPower(&notifier) }
        if rootPort != 0 { IOServiceClose(rootPort) }
        if let notifyPort { IONotificationPortDestroy(notifyPort) }
    }

    func handle(_ messageType: UInt32, _ argument: UnsafeMutableRawPointer?) {
        switch messageType {
        case Self.canSystemSleep:
            allowPowerChange(rootPort, Int(bitPattern: argument))
        case Self.systemWillSleep:
            willSleep()
            allowPowerChange(rootPort, Int(bitPattern: argument))
        case Self.systemHasPoweredOn:
            didWake()
        default:
            break
        }
    }
}
