/// The modes of the fancurved binary, exactly one per run: it runs as root, so an ambiguous
/// command line such as `--dry-run --restore` is rejected rather than resolved to one of its
/// modes. The mode flag comes first.
public enum DaemonInvocation: Equatable, Sendable {
    case daemon
    case watchdog
    case restore
    case dryRun(root: String)
    case simulate(trace: String, profile: String, config: String?)

    /// Parses the arguments after the program name; nil for anything else (the caller prints usage).
    public static func parse(_ arguments: [String]) -> DaemonInvocation? {
        guard let mode = arguments.first else { return .daemon }
        let rest = arguments.dropFirst()
        switch mode {
        case "--watchdog":
            return rest.isEmpty ? .watchdog : nil
        case "--restore":
            return rest.isEmpty ? .restore : nil
        case "--dry-run":
            guard let options = options(rest, allowed: ["--root"]), let root = options["--root"] else { return nil }
            return .dryRun(root: root)
        case "--simulate":
            guard let trace = rest.first, !trace.hasPrefix("--"),
                  let options = options(rest.dropFirst(), allowed: ["--profile", "--config"]),
                  let profile = options["--profile"] else { return nil }
            return .simulate(trace: trace, profile: profile, config: options["--config"])
        default:
            return nil
        }
    }

    /// `--name value` pairs, each name at most once and from `allowed`; nil otherwise.
    private static func options(_ arguments: ArraySlice<String>, allowed: Set<String>) -> [String: String]? {
        var result: [String: String] = [:]
        var rest = arguments
        while let name = rest.first {
            rest = rest.dropFirst()
            guard allowed.contains(name), result[name] == nil, let value = rest.first, !value.hasPrefix("--") else {
                return nil
            }
            result[name] = value
            rest = rest.dropFirst()
        }
        return result
    }
}
