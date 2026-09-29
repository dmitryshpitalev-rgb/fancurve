import FanCurveCore
import FanCurveIPC
import Foundation
import Testing
@testable import FanCurveUI

@Suite struct LanguageTests {
    @Test func theSystemLanguageDecidesRussianUkrainianOrEnglish() {
        #expect(Language.forSystem(["ru-RU", "en"]) == .ru)
        #expect(Language.forSystem(["ru"]) == .ru)
        #expect(Language.forSystem(["uk-UA", "ru-UA", "en"]) == .uk)
        #expect(Language.forSystem(["UK_UA"]) == .uk)
        #expect(Language.forSystem(["en-US", "ru"]) == .en)
        #expect(Language.forSystem(["de-DE", "uk"]) == .en)
        #expect(Language.forSystem(["rue"]) == .en)  // Rusyn is not Russian
        #expect(Language.forSystem([]) == .en)
    }

    @Test func theStaticsReadTheCurrentLanguage() {
        let table = UIText.Table(UIText.language)
        #expect(UIText.applyButton == table.applyButton)
        #expect(UIText.mode(.active) == table.mode(.active))
        #expect(SmoothingField.allCases.map(UIText.smoothingLabel) == SmoothingField.allCases.map(table.smoothingLabel))
    }

    static let ru = UIText.Table(.ru, locale: Locale(identifier: "ru_RU"))
    static let uk = UIText.Table(.uk, locale: Locale(identifier: "uk_UA"))
    static let en = UIText.Table(.en, locale: Locale(identifier: "en_US"))

    @Test func everyLanguageHasItsOwnWords() {
        let (ru, uk, en) = (Self.ru, Self.uk, Self.en)
        #expect([ru.applyButton, uk.applyButton, en.applyButton] == ["Применить", "Застосувати", "Apply"])
        #expect(uk.mode(.active) == "Крива керує вентиляторами")
        #expect(en.mode(.released(.sensorLoss)) == "macOS is in charge: sensors lost")
        #expect(uk.fans(makeSnapshot()) == "3650 · 3380 об/хв · вихід 48%")
        #expect(en.fans(makeSnapshot()) == "3650 · 3380 rpm · output 48%")
        #expect([ru.watts(45.9), uk.watts(45.9), en.watts(45.9)] == ["46 Вт", "46 Вт", "46 W"])
        #expect([ru.chartWindow(minutes: 15), uk.chartWindow(minutes: 15), en.chartWindow(minutes: 15)] == ["15 мин", "15 хв", "15 min"])
        #expect(uk.tiles(makeSnapshot()).map(\.title) == ["CPU", "GPU", "Корпус", "Вати"])
        #expect(en.tiles(makeSnapshot()).map(\.detail) == ["curve 48%", "", "curve off", "curve 44%"])
        #expect(uk.smoothingNotANumber(.hold) == "«Утримання після піку, с»: введіть число")
        #expect(uk.safeReason(.crashLoop) == "демон запускався 5 разів за хвилину")
        #expect(en.safeReason(.crashLoop) == "the daemon started 5 times in a minute")
        let badConfig = "the config does not parse: smoothing.holdSeconds is missing"
        #expect([ru.configErrorLine(badConfig), uk.configErrorLine(badConfig), en.configErrorLine(badConfig)]
                == ["Ошибка конфига: " + badConfig, "Помилка конфігу: " + badConfig, "Config error: " + badConfig])
        #expect([ru.curvePicker, uk.curvePicker, en.curvePicker] == ["Кривая", "Крива", "Curve"])
        #expect([ru.chartWindowPicker, uk.chartWindowPicker, en.chartWindowPicker]
                == ["Период графиков", "Період графіків", "Chart time range"])
        #expect(en.connectionProblem(SocketError.closed) == "the daemon closed the connection")
        #expect(uk.liveReadout(input: 45.9, output: 43.8, kind: .power, fan: nil) == "зараз 46 Вт → 44%")
    }

    @Test func validationProblemsAreToldInEachLanguage() {
        let cases: [(kind: ValidationError.Kind, ru: String, uk: String, en: String)] = [
            (.pointCount(curve: .power, count: 1),
             "ватты: нужно от 2 до 8 точек, сейчас 1",
             "вати: потрібно від 2 до 8 точок, зараз 1",
             "watts: needs 2 to 8 points, has 1"),
            (.pointNotANumber(curve: .chassis, index: 3),
             "корпус: точка 3 не число",
             "корпус: точка 3 не число",
             "chassis: point 3 is not a number"),
            (.xOutOfRange(curve: .hotspot, x: 115.5, range: 20...110),
             "горячий кристалл: x=115,5 вне 20…110",
             "гарячий кристал: x=115,5 поза 20…110",
             "hot die: x=115.5 outside 20…110"),
            (.yOutOfRange(curve: .power, y: 120),
             "ватты: обороты 120% вне 0…100",
             "вати: оберти 120% поза 0…100",
             "watts: speed 120% outside 0…100"),
            (.xNotIncreasing(curve: .chassis, index: 2),
             "корпус: x должен строго возрастать (точка 2)",
             "корпус: x має строго зростати (точка 2)",
             "chassis: x must strictly increase (point 2)"),
            (.yDecreasing(curve: .hotspot, index: 2),
             "горячий кристалл: обороты не должны падать с ростом x (точка 2)",
             "гарячий кристал: оберти не мають падати зі зростанням x (точка 2)",
             "hot die: speed must not fall as x grows (point 2)"),
            (.smoothingOutOfRange(field: .down, value: 0, range: 0.5...50),
             "скорость вниз, %/с: 0 вне 0,5…50",
             "швидкість униз, %/с: 0 поза 0,5…50",
             "ramp down, %/s: 0 outside 0.5…50"),
            (.other("unknown config version: 1"),
             "unknown config version: 1",
             "unknown config version: 1",
             "unknown config version: 1"),
        ]
        for (kind, ru, uk, en) in cases {
            let error = ValidationError(kind)
            #expect(Self.ru.validationMessage(for: error) == ru)
            #expect(Self.uk.validationMessage(for: error) == uk)
            #expect(Self.en.validationMessage(for: error) == en)
        }
    }

    @Test func everySmoothingFieldHasItsEnglishName() {
        let messages = SmoothingField.allCases.map { field in
            Self.en.validationMessage(for: ValidationError(.smoothingOutOfRange(field: field, value: 500,
                                                                                range: Smoothing.range(for: field))))
        }
        #expect(messages == ["ramp up, %/s: 500 outside 1…100", "hold, s: 500 outside 0…120",
                             "ramp down, %/s: 500 outside 0.5…50", "deadband, %: 500 outside 0…10"])
    }

    /// The numbers beside a field are written like the field, as the region decides: a Russian
    /// interface on an American region shows 0.5, an Arabic region its own digits.
    @Test func rangesAndLimitsComeFromTheCoreInTheRegionsDigits() {
        #expect(SmoothingField.allCases.map(Self.ru.smoothingRange) == ["1–100", "0–120", "0,5–50", "0–10"])
        #expect(SmoothingField.allCases.map(Self.en.smoothingRange) == ["1–100", "0–120", "0.5–50", "0–10"])
        let russianOnAnAmericanRegion = UIText.Table(.ru, locale: Locale(identifier: "en_US"))
        #expect(russianOnAnAmericanRegion.smoothingRange(.down) == "0.5–50")
        let tooSlow = ValidationError(.smoothingOutOfRange(field: .down, value: 0.25, range: Smoothing.range(for: .down)))
        #expect(russianOnAnAmericanRegion.validationMessage(for: tooSlow) == "скорость вниз, %/с: 0.25 вне 0.5…50")
        #expect(UIText.Table(.en, locale: Locale(identifier: "ar_SA")).smoothingRange(.down) == "٠٫٥–٥٠")
    }
}

/// The Russian table, word for word.
@Suite struct UITextTests {
    let ru = UIText.Table(.ru, locale: Locale(identifier: "ru_RU"))

    @Test func everyModeHasALine() {
        #expect(ru.mode(.starting) == "Запуск…")
        #expect(ru.mode(.active) == "Кривая управляет вентиляторами")
        #expect(ru.mode(.released(.sleep)) == "Управляет macOS: сон")
        #expect(ru.mode(.released(.sensorLoss)) == "Управляет macOS: пропали датчики")
        #expect(ru.mode(.disabled) == "Управляет macOS: вы отдали управление")
        #expect(ru.mode(.safe(.smcWriteFailed)) == "Безопасный режим: SMC не принимает запись оборотов")
        // CrashLoopGuard counts starts, five in a minute: the words say so.
        #expect(ru.mode(.safe(.crashLoop)) == "Безопасный режим: демон запускался 5 раз за минуту")
        #expect(CrashLoopGuard.windowSeconds == 60)
    }

    @Test func everySafeReasonIsDistinctInEveryLanguage() {
        let reasons: [SafeReason] = [.crashLoop, .unsupportedModel, .missingKeys, .smcWriteFailed]
        for language in Language.allCases {
            let texts = Set(reasons.map(UIText.Table(language).safeReason))
            #expect(texts.count == reasons.count, "\(language)")
            #expect(!texts.contains(""), "\(language)")
        }
    }

    @Test func numbersRoundHalfUpAndShowADashWithoutAReading() {
        #expect(ru.temperature(76.5) == "77°")
        #expect(ru.temperature(nil) == "—")
        #expect(ru.temperature(.nan) == "—")
        #expect(ru.watts(45.9) == "46 Вт")
        #expect(ru.percent(43.825) == "44%")
        #expect(ru.rpm(3650.4) == "3650")
        #expect(!ru.rpm(3.4e38).isEmpty)  // a garbage reading prints, it does not trap
    }

    @Test func tilesShowTheCurvesAndTheLeader() {
        let tiles = ru.tiles(makeSnapshot())
        #expect(tiles.map(\.title) == ["CPU", "GPU", "Корпус", "Ватты"])
        #expect(tiles.map(\.value) == ["77°", "61°", "38°", "46 Вт"])
        #expect(tiles.map(\.detail) == ["кривая 48%", "", "кривая выкл", "кривая 44%"])
        #expect(tiles.map(\.highlighted) == [true, false, false, false])
    }

    @Test func aSleepingRadeonAndAWattsLeaderShowUp() {
        var config = Config.defaults
        config.curves.chassis.enabled = true
        let snapshot = makeSnapshot(raw: PerChannel(cpu: 58, gpu: nil, chassis: 44, power: 70),
                                    filtered: PerChannel(cpu: 57, gpu: nil, chassis: 44, power: 70), config: config)
        let tiles = ru.tiles(snapshot)
        #expect(tiles[1].value == "—")
        #expect(tiles[1].detail == "")
        #expect(tiles[2].detail == "кривая 18%")  // 44°C on 42→0, 46→35: 17.5%
        #expect(tiles.map(\.highlighted) == [false, false, false, true])
    }

    @Test func fansAndMenuBarText() {
        let snapshot = makeSnapshot()
        #expect(ru.fans(snapshot) == "3650 · 3380 об/мин · выход 48%")
        #expect(ru.menuBarTemperature(snapshot) == "77°")
        let hotGPU = makeSnapshot(filtered: PerChannel(cpu: 60, gpu: 71.4, chassis: 38, power: 30))
        #expect(ru.menuBarTemperature(hotGPU) == "71°")
        let noDies = makeSnapshot(raw: .empty, filtered: .empty)
        #expect(ru.menuBarTemperature(noDies) == "—")
    }

    @Test func theGPUPolicyDescribesBothPowerSources() {
        #expect(ru.gpuPolicyDetail(GPUPolicyState(enabled: true, acSwitch: 1, batterySwitch: 2))
                == "сейчас: зарядка — Radeon, батарея — авто")
        #expect(ru.gpuSwitch(0) == "встроенная")
        #expect(ru.gpuSwitch(nil) == "?")
    }

    @Test func seriesAndSMCErrorLines() {
        #expect(ChartSeries.temperatures.map(ru.seriesName) == ["CPU", "GPU", "Корпус"])
        #expect(ru.smcErrorLine("smc result 0x86") == "Ошибка записи в SMC: smc result 0x86")
        #expect(ru.chartWindow(minutes: 15) == "15 мин")
    }

    @Test func actionErrorsKeepTheDaemonsOwnWords() {
        let refusal = DaemonError.remote("safe mode: retry first")
        #expect(ru.actionFailed(refusal) == "safe mode: retry first")
        #expect(ru.actionFailed(DaemonError.emptyReply) == "демон ответил без данных")
        #expect(ru.actionFailed(SocketError.closed) == "демон закрыл соединение")
    }

    @Test func connectionProblemsAreToldInWords() {
        let notRunning = "демон не запущен: сокета нет или он не принимает подключения"
        #expect(ru.connectionProblem(SocketError.system(call: "connect", code: ENOENT)) == notRunning)
        #expect(ru.connectionProblem(SocketError.system(call: "connect", code: ECONNREFUSED)) == notRunning)
        #expect(ru.connectionProblem(SocketError.system(call: "connect", code: EACCES)).hasPrefix("нет доступа"))
        #expect(ru.connectionProblem(SocketError.timedOut) == "демон не ответил вовремя")
        #expect(ru.connectionProblem(SocketError.system(call: "read", code: EAGAIN)) == "демон не ответил вовремя")
        #expect(ru.connectionProblem(SocketError.closed) == "демон закрыл соединение")
        #expect(ru.connectionProblem(SocketError.lineTooLong).hasPrefix("ошибка связи с демоном: "))
        let garbled = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
        #expect(ru.connectionProblem(garbled) == "ответ демона не читается: версии демона и приложения разошлись")
    }

    @Test func readoutListsEveryValueAtOneMoment() {
        let sample = Sample(t: 14 * 3600 + 32 * 60 + 10, cpu: 72.2, gpu: nil, chassis: 38.4, power: 31,
                            demandPercent: 30, leading: .hotspot, fanRPM: [3000, 2800], mode: .active)
        let utc = TimeZone(identifier: "UTC")!
        #expect(ru.readout(sample, fanPercent: 44.6, timeZone: utc)
                == "14:32:10 · CPU 72° · GPU — · Корпус 38° · вент. 45% · 31 Вт")
        // The clock follows the region, like the charts' time axis.
        #expect(UIText.Table(.en, locale: Locale(identifier: "en_US")).readout(sample, fanPercent: 44.6, timeZone: utc)
                == "2:32:10\u{202F}PM · CPU 72° · GPU — · Chassis 38° · fans 45% · 31 W")
    }

    @Test func editorLabelsShowTheLeftFansRPM() {
        let fan = FanRange(minRPM: 1836, maxRPM: 5616)
        #expect(ru.editorYLabel(percent: 50, fan: fan) == "50% · 3726")
        #expect(ru.editorYLabel(percent: 50, fan: nil) == "50%")
        #expect(ru.curveReadout(input: 76, output: 46, kind: .hotspot, fan: fan) == "76° → 46% · 3575 об/мин")
        #expect(ru.liveReadout(input: 45.9, output: 43.8, kind: .power, fan: nil) == "сейчас 46 Вт → 44%")
        #expect(CurveKind.allCases.map(ru.editorTab) == ["Кристалл", "Ватты", "Корпус"])
        // A garbage range (a float key can read 3.4e38) shows no rpm rather than trapping.
        let garbage = FanRange(minRPM: 1836, maxRPM: 3.4e38)
        #expect(ru.editorYLabel(percent: 50, fan: garbage) == "50%")
        #expect(ru.curveReadout(input: 76, output: 46, kind: .hotspot, fan: garbage) == "76° → 46%")
    }
}
