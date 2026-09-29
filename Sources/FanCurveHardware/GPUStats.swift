import Foundation
import IOKit

public struct GPUStats: Equatable, Sendable {
    public var temperature: Double?
    public var power: Double?
    public var activity: Double?

    init(temperature: Double? = nil, power: Double? = nil, activity: Double? = nil) {
        self.temperature = temperature
        self.power = power
        self.activity = activity
    }
}

/// Reads the Radeon's statistics from the IORegistry. Works without root.
public enum GPUStatsReader {
    /// Extracts fields from an AMD IOAccelerator "PerformanceStatistics" dictionary.
    static func parsePerformanceStatistics(_ stats: [String: Any]) -> GPUStats {
        GPUStats(
            temperature: number(stats["Temperature(C)"]),
            power: number(stats["Total Power(W)"]),
            activity: number(stats["GPU Activity(%)"])
        )
    }

    /// Fields are nil when their source is absent (for example, while the Radeon is powered off).
    public static func read() -> GPUStats {
        firstMatch(className: "IOAccelerator", where: { ioClass(of: $0).contains("AMD") }) { service in
            dictionary(service, "PerformanceStatistics").map(parsePerformanceStatistics)
        } ?? GPUStats()
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    /// The "IOClass" registry property, e.g. "AMDRadeonX6000_AMDNavi14GraphicsAccelerator".
    private static func ioClass(of service: io_object_t) -> String {
        IORegistryEntryCreateCFProperty(service, "IOClass" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String ?? ""
    }

    private static func dictionary(_ service: io_object_t, _ name: String) -> [String: Any]? {
        IORegistryEntryCreateCFProperty(service, name as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
    }

    private static func firstMatch<T>(
        className: String,
        where predicate: (io_object_t) -> Bool,
        _ body: (io_object_t) -> T?
    ) -> T? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == kIOReturnSuccess else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if predicate(service), let value = body(service) {
                return value
            }
        }
        return nil
    }
}
