/// What `fancurved --restore` (run by uninstall.sh) does with gpuswitch.
public enum GPUSwitchRestore: Equatable, Sendable {
    /// Write these values back: the ones from before auto-graphics.
    case restore(GPUSwitchValues)
    /// Auto-graphics is off and nothing is saved: gpuswitch is the user's own choice, leave it.
    case untouched
    /// Auto-graphics is on but the values from before it are gone: they cannot be restored.
    case lost

    public static func decide(gpuPolicyEnabled: Bool, saved: GPUSwitchValues?) -> GPUSwitchRestore {
        if let saved {
            return .restore(saved)
        }
        return gpuPolicyEnabled ? .lost : .untouched
    }
}
