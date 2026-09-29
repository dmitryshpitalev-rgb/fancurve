import FanCurveCore
import FanCurveDaemon
import FanCurveHardware
import Foundation

/// Run by uninstall.sh: hands the fans back and restores gpuswitch; works even if the daemon is dead.
func runRestore() -> Never {
    requireRoot()
    let profile = HardwareProfile.macBookPro16_1
    var failed = false
    do {
        try openActuator(profile).actuator.release()
        print("fans handed back to macOS")
    } catch {
        print("fan release failed: \(error); the fans return to macOS at the next sleep or restart")
        failed = true
    }
    let loadedConfig = ConfigStore(url: DaemonPaths.system.config).load()
    let loadedState = StateStore(url: DaemonPaths.system.state).load()
    if let error = loadedConfig.error { print(error) }
    if let error = loadedState.error { print(error) }
    switch GPUSwitchRestore.decide(gpuPolicyEnabled: loadedConfig.config.gpuPolicy.enabled,
                                   saved: loadedState.state.gpuSwitchOriginal) {
    case .restore(let original):
        do {
            try PMSet.setGPUSwitch(ac: original.ac, battery: original.battery)
            print("gpuswitch restored: ac \(original.ac), battery \(original.battery)")
        } catch {
            print("gpuswitch restore failed: \(error); set graphics switching in System Settings > Battery")
            failed = true
        }
    case .untouched:
        break
    case .lost:
        print("gpuswitch not restored: auto-graphics was on, but the values from before it are lost; "
            + "set graphics switching in System Settings > Battery")
        failed = true
    }
    exit(failed ? 1 : 0)
}
