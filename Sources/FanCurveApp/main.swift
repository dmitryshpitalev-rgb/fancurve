import AppKit
import FanCurveUI
import Foundation

// `FanCurve --snapshot DIR [ru|uk|en]` draws the screens into PNGs and exits: no menu bar item
// appears. The language defaults to the system's. Anything else starts the menubar app.
let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--snapshot") {
    guard index + 1 < arguments.count else {
        FileHandle.standardError.write(Data("usage: FanCurve --snapshot DIR [ru|uk|en]\n".utf8))
        exit(2)
    }
    if index + 2 < arguments.count {
        guard let language = Language(rawValue: arguments[index + 2]) else {
            FileHandle.standardError.write(Data("unknown language \(arguments[index + 2]): ru, uk or en\n".utf8))
            exit(2)
        }
        UIText.language = language
    }
    let ok = MainActor.assumeIsolated {
        Snapshots.render(to: URL(fileURLWithPath: arguments[index + 1]))
    }
    exit(ok ? 0 : 1)
}
FanCurveApp.main()
