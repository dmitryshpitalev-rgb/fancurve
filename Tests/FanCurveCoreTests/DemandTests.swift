import Testing
@testable import FanCurveCore

@Suite struct ChannelMathTests {
    @Test func temperatureTakesMaxOfValidReadings() {
        #expect(ChannelMath.temperature([71, nil, 76.5, 129, -3, .nan]) == 76.5)
        #expect(ChannelMath.temperature([nil, 129]) == nil)
        #expect(ChannelMath.temperature([]) == nil)
    }

    @Test func gpuTemperatureFallsBackToIoreg() {
        #expect(ChannelMath.gpuTemperature(smc: [nil, 255.9], ioreg: 58) == 58)
        #expect(ChannelMath.gpuTemperature(smc: [61], ioreg: 58) == 61)
        #expect(ChannelMath.gpuTemperature(smc: [], ioreg: nil) == nil)
    }

    @Test func powerAddsRadeonOnlyWhenActive() {
        #expect(ChannelMath.power(cpuPackage: 30, gpu: 8, gpuActive: true) == 38)
        #expect(ChannelMath.power(cpuPackage: 30, gpu: 8, gpuActive: false) == 30)
        #expect(ChannelMath.power(cpuPackage: 30, gpu: nil, gpuActive: true) == 30)
        #expect(ChannelMath.power(cpuPackage: nil, gpu: 8, gpuActive: true) == nil)
        #expect(ChannelMath.power(cpuPackage: -1, gpu: 8, gpuActive: true) == nil)
    }
}

@Suite struct DemandTests {
    let curves = CurveSet(
        hotspot: Curve([CurvePoint(60, 0), CurvePoint(80, 100)]),
        power: AuxCurve(enabled: true, curve: Curve([CurvePoint(20, 0), CurvePoint(60, 100)])),
        chassis: AuxCurve(enabled: true, curve: Curve([CurvePoint(40, 0), CurvePoint(50, 100)]))
    )

    func values(cpu: Double? = nil, gpu: Double? = nil, chassis: Double? = nil, power: Double? = nil) -> PerChannel<Double?> {
        PerChannel(cpu: cpu, gpu: gpu, chassis: chassis, power: power)
    }

    @Test func theHotterDieFeedsTheHotspotCurve() {
        let result = Demand.evaluate(curves: curves, values: values(cpu: 65, gpu: 75))
        #expect(result.hotDie == .gpu)
        #expect(result.hotspot == 75)
        #expect(result.leading == .hotspot)
        #expect(result.percent == 75)
    }

    @Test func aTieGoesToTheCPU() {
        let result = Demand.evaluate(curves: curves, values: values(cpu: 70, gpu: 70))
        #expect(result.hotDie == .cpu)
        #expect(result.hotspot == 50)
    }

    @Test func oneDieIsEnough() {
        #expect(Demand.evaluate(curves: curves, values: values(gpu: 65)).hotDie == .gpu)
        #expect(Demand.evaluate(curves: curves, values: values(cpu: 65)).hotDie == .cpu)
    }

    @Test func noDieMeansNoHotspotDemand() {
        let result = Demand.evaluate(curves: curves, values: values(power: 40))
        #expect(result.hotspot == nil)
        #expect(result.hotDie == nil)
        #expect(result.power == 50)
        #expect(result.leading == .power)
        #expect(result.percent == 50)
    }

    @Test func switchedOffCurvesTakeNoPart() {
        var off = curves
        off.power.enabled = false
        off.chassis.enabled = false
        let result = Demand.evaluate(curves: off, values: values(cpu: 60, chassis: 50, power: 60))
        #expect(result.power == nil)
        #expect(result.chassis == nil)
        #expect(result.leading == .hotspot)
        #expect(result.percent == 0)
    }

    @Test func theMaximumLeadsAndTiesFollowKindOrder() {
        let tie = Demand.evaluate(curves: curves, values: values(cpu: 70, chassis: 45, power: 40))
        #expect(tie.leading == .hotspot)
        #expect(tie.percent == 50)
        let chassis = Demand.evaluate(curves: curves, values: values(cpu: 60, chassis: 49, power: 50))
        #expect(chassis.leading == .chassis)
        #expect(chassis.percent == 90)
    }

    @Test func nothingReadMeansNoDemand() {
        #expect(Demand.evaluate(curves: curves, values: .empty) == .empty)
    }

    @Test func subscriptReadsEachCurve() {
        let result = Demand.evaluate(curves: curves, values: values(cpu: 70, chassis: 45, power: 40))
        #expect(result[.hotspot] == 50)
        #expect(result[.power] == 50)
        #expect(result[.chassis] == 50)
    }
}
