import FanCurveCore
import Testing
@testable import FanCurveIPC

@Suite struct StatusTextTests {
    @Test func rendersASnapshot() {
        let snapshot = Snapshot(
            t: 1000, mode: .active,
            raw: PerChannel(cpu: 72.44, gpu: nil, chassis: 41.2, power: 23.5),
            filtered: PerChannel(cpu: 72, gpu: nil, chassis: 41, power: 22),
            demand: DemandResult(hotspot: 36.7, power: 1.5, chassis: nil, hotDie: .cpu, leading: .hotspot, percent: 36.7),
            outputPercent: 30,
            fans: [FanState(actualRPM: 2941.6, targetRPM: 2970, minRPM: 1836, maxRPM: 5616),
                   FanState(actualRPM: nil, targetRPM: 2750, minRPM: 1700, maxRPM: 5200)],
            gpuPolicy: GPUPolicyState(enabled: true, acSwitch: 1, batterySwitch: 2),
            configError: nil,
            smcError: "SMC error 0x86"
        )
        #expect(StatusText.render(snapshot) == """
            mode: active
            cpu 72.4°C  gpu —  chassis 41.2°C  power 23.5 W
            demand 37% (hotspot on cpu)  hotspot 37%  power 2%  chassis —  output 30%
            fan0 2942 rpm → 2970 (1836-5616)
            fan1 — rpm → 2750 (1700-5200)
            auto-graphics on (gpuswitch ac 1, battery 2)
            smc error: SMC error 0x86
            """)
    }

    @Test func historyIsCSV() {
        let sample = Sample(t: 1000, cpu: 72, gpu: nil, chassis: 41.2, power: 23.5, demandPercent: 30,
                            leading: .hotspot, fanRPM: [2941.6, nil], mode: .active)
        #expect(StatusText.csv([sample]) == "t,mode,cpu,gpu,chassis,power,demand,leading,fan0,fan1\n1000,active,72.00,,41.20,23.50,30.00,hotspot,2941.60,\n")
    }

    @Test func historyHasAColumnForEveryFan() {
        func sample(_ fanRPM: [Double?]) -> Sample {
            Sample(t: 1000, cpu: nil, gpu: nil, chassis: nil, power: nil, demandPercent: 0, leading: nil, fanRPM: fanRPM, mode: .active)
        }
        let lines = StatusText.csv([sample([1800]), sample([1800, 1700, nil])]).split(separator: "\n")
        #expect(lines[0] == "t,mode,cpu,gpu,chassis,power,demand,leading,fan0,fan1,fan2")
        #expect(lines[1].hasSuffix(",1800.00,,"))
        #expect(lines[2].hasSuffix(",1800.00,1700.00,"))
        #expect(StatusText.csv([]) == "t,mode,cpu,gpu,chassis,power,demand,leading\n")
    }
}
