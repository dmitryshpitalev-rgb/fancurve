import FanCurveCore
import FanCurveIPC
import Foundation

/// Everything the menubar app shows the user, in Russian, Ukrainian or English after the system
/// language. `UIText.applyButton` and `UIText.mode(_:)` read the current language's table;
/// `UIText.Table(.uk)` is one language on its own, for tests. Pure: no I/O, no clock.
@dynamicMemberLookup
public enum UIText {
    /// Decided once, from the system language; `--snapshot DIR <language>` overrides it.
    nonisolated(unsafe) public static var language = Language.forSystem()

    static var current: Table { Table(language) }

    /// `UIText.applyButton` is `Table(language).applyButton`.
    public static subscript<T>(dynamicMember keyPath: KeyPath<Table, T>) -> T {
        Table(language)[keyPath: keyPath]
    }

    public struct Tile: Equatable, Sendable {
        public var title: String
        public var value: String
        public var detail: String
        public var highlighted: Bool

        public init(title: String, value: String, detail: String, highlighted: Bool) {
            self.title = title
            self.value = value
            self.detail = detail
            self.highlighted = highlighted
        }
    }

    // MARK: The current language

    public static func mode(_ mode: Mode) -> String { current.mode(mode) }
    public static func temperature(_ celsius: Double?) -> String { current.temperature(celsius) }
    public static func tiles(_ snapshot: Snapshot) -> [Tile] { current.tiles(snapshot) }
    public static func fans(_ snapshot: Snapshot) -> String { current.fans(snapshot) }
    public static func menuBarTemperature(_ snapshot: Snapshot) -> String { current.menuBarTemperature(snapshot) }
    public static func gpuPolicyDetail(_ state: GPUPolicyState) -> String { current.gpuPolicyDetail(state) }
    public static func actionFailed(_ error: Error) -> String { current.actionFailed(error) }
    public static func connectionProblem(_ error: Error) -> String { current.connectionProblem(error) }
    public static func smcErrorLine(_ error: String) -> String { current.smcErrorLine(error) }
    public static func configErrorLine(_ error: String) -> String { current.configErrorLine(error) }
    public static func chartWindow(minutes: Int) -> String { current.chartWindow(minutes: minutes) }
    public static func seriesName(_ series: ChartSeries) -> String { current.seriesName(series) }
    public static func readout(_ sample: Sample, fanPercent: Double?, timeZone: TimeZone = .current) -> String {
        current.readout(sample, fanPercent: fanPercent, timeZone: timeZone)
    }
    public static func smoothingLabel(_ field: SmoothingField) -> String { current.smoothingLabel(field) }
    public static func smoothingRange(_ field: SmoothingField) -> String { current.smoothingRange(field) }
    public static func smoothingNotANumber(_ field: SmoothingField) -> String { current.smoothingNotANumber(field) }
    public static func validationMessage(for error: ValidationError) -> String { current.validationMessage(for: error) }
    public static func editorTab(_ kind: CurveKind) -> String { current.editorTab(kind) }
    public static func editorAxis(_ kind: CurveKind) -> String { current.editorAxis(kind) }
    public static func editorYLabel(percent value: Double, fan: FanRange?) -> String { current.editorYLabel(percent: value, fan: fan) }
    public static func curveReadout(input: Double, output: Double, kind: CurveKind, fan: FanRange?) -> String {
        current.curveReadout(input: input, output: output, kind: kind, fan: fan)
    }
    public static func liveReadout(input: Double, output: Double, kind: CurveKind, fan: FanRange?) -> String {
        current.liveReadout(input: input, output: output, kind: kind, fan: fan)
    }

    // MARK: One language

    /// Every text in one language. Each entry lists Russian, Ukrainian and English, in that order.
    /// `locale` writes what the region decides: the numbers shown beside what the user types (the
    /// smoothing ranges, the validation messages) and the readout's clock.
    public struct Table {
        public let language: Language
        public let locale: Locale

        public init(_ language: Language, locale: Locale = .current) {
            self.language = language
            self.locale = locale
        }

        func t(_ ru: String, _ uk: String, _ en: String) -> String {
            switch language {
            case .ru: return ru
            case .uk: return uk
            case .en: return en
            }
        }

        // MARK: Modes

        public func mode(_ mode: Mode) -> String {
            switch mode {
            case .starting: return t("Запуск…", "Запуск…", "Starting…")
            case .active: return t("Кривая управляет вентиляторами", "Крива керує вентиляторами", "The curve drives the fans")
            case .released(let reason): return t("Управляет macOS: ", "Керує macOS: ", "macOS is in charge: ") + releaseReason(reason)
            case .disabled: return t("Управляет macOS: вы отдали управление", "Керує macOS: ви віддали керування", "macOS is in charge: you handed control over")
            case .safe(let reason): return t("Безопасный режим: ", "Безпечний режим: ", "Safe mode: ") + safeReason(reason)
            }
        }

        public func releaseReason(_ reason: ReleaseReason) -> String {
            switch reason {
            case .sensorLoss: return t("пропали датчики", "зникли датчики", "sensors lost")
            case .sleep: return t("сон", "сон", "sleep")
            }
        }

        public func safeReason(_ reason: SafeReason) -> String {
            switch reason {
            case .crashLoop:
                let starts = CrashLoopGuard.maxStarts
                return t("демон запускался \(starts) раз за минуту", "демон запускався \(starts) разів за хвилину",
                         "the daemon started \(starts) times in a minute")
            case .unsupportedModel: return t("эта модель Mac не поддерживается", "ця модель Mac не підтримується", "this Mac model is not supported")
            case .missingKeys: return t("в SMC нет нужных ключей", "в SMC немає потрібних ключів", "the SMC lacks the needed keys")
            case .smcWriteFailed: return t("SMC не принимает запись оборотов", "SMC не приймає запис обертів", "the SMC refuses fan speed writes")
            }
        }

        // MARK: Numbers

        public func temperature(_ celsius: Double?) -> String {
            guard let celsius, celsius.isFinite else { return "—" }
            return whole(celsius) + "°"
        }

        public func watts(_ watts: Double?) -> String {
            guard let watts, watts.isFinite else { return "—" }
            return whole(watts) + t(" Вт", " Вт", " W")
        }

        public func percent(_ percent: Double?) -> String {
            guard let percent, percent.isFinite else { return "—" }
            return whole(percent) + "%"
        }

        public func rpm(_ rpm: Double?) -> String {
            guard let rpm, rpm.isFinite else { return "—" }
            return whole(rpm)
        }

        var rpmUnit: String { t("об/мин", "об/хв", "rpm") }

        /// Half away from zero, and never a trap: `Int(_:)` would crash on a garbage reading.
        private func whole(_ value: Double) -> String {
            String(format: "%.0f", value.rounded())
        }

        /// A number shown beside what the user types, so it is written like the field: in the
        /// locale's digits and decimal separator.
        private func number(_ value: Double) -> String {
            SmoothingInput.text(value, locale: locale)
        }

        private func number(_ value: Int) -> String {
            number(Double(value))
        }

        /// The time of day as the locale writes it, like the charts' time axis.
        private func clock(_ t: Double, timeZone: TimeZone) -> String {
            var style = Date.FormatStyle.dateTime.hour().minute().second().locale(locale)
            style.timeZone = timeZone
            return Date(timeIntervalSince1970: t).formatted(style)
        }

        // MARK: Terms

        /// The chassis and the watts as the tiles, the chart legend, the readout and the editor's
        /// tabs name them.
        var chassisName: String { t("Корпус", "Корпус", "Chassis") }
        var wattsName: String { t("Ватты", "Вати", "Watts") }

        // MARK: Popup

        /// CPU, GPU, chassis, watts: each reading as the curves see it (filtered, raw as a fallback),
        /// under it the demand of the curve that reads it, and the leading curve's tile lit.
        public func tiles(_ snapshot: Snapshot) -> [Tile] {
            let demand = snapshot.demand
            let curve = t("кривая ", "крива ", "curve ")
            func value(_ id: ChannelID) -> Double? { snapshot.filtered[id] ?? snapshot.raw[id] }
            func dieDetail(_ die: ChannelID) -> String {
                demand.hotDie == die ? curve + percent(demand.hotspot) : ""
            }
            func auxDetail(_ kind: CurveKind, _ id: ChannelID) -> String {
                if let curveDemand = demand[kind] { return curve + percent(curveDemand) }
                // The input reads but the curve gave nothing: it is switched off.
                return value(id) == nil ? "" : t("кривая выкл", "крива вимк", "curve off")
            }
            let leadingDie = demand.leading == .hotspot ? demand.hotDie : nil
            return [
                Tile(title: "CPU", value: temperature(value(.cpu)), detail: dieDetail(.cpu), highlighted: leadingDie == .cpu),
                Tile(title: "GPU", value: temperature(value(.gpu)), detail: dieDetail(.gpu), highlighted: leadingDie == .gpu),
                Tile(title: chassisName, value: temperature(value(.chassis)), detail: auxDetail(.chassis, .chassis),
                     highlighted: demand.leading == .chassis),
                Tile(title: wattsName, value: watts(value(.power)), detail: auxDetail(.power, .power),
                     highlighted: demand.leading == .power),
            ]
        }

        /// "3650 · 3380 rpm · output 48%": the left and right fan, then the output.
        public func fans(_ snapshot: Snapshot) -> String {
            let speeds = snapshot.fans.map { rpm($0.actualRPM) }.joined(separator: " · ")
            return "\(speeds) \(rpmUnit) · " + t("выход ", "вихід ", "output ") + percent(snapshot.outputPercent)
        }

        /// The number next to the menubar wheel: the hotter die as the curve sees it.
        public func menuBarTemperature(_ snapshot: Snapshot) -> String {
            let dies = [snapshot.filtered.cpu ?? snapshot.raw.cpu, snapshot.filtered.gpu ?? snapshot.raw.gpu]
            return temperature(dies.compactMap { $0 }.filter(\.isFinite).max())
        }

        public func gpuSwitch(_ value: Int?) -> String {
            switch value {
            case 0?: return t("встроенная", "вбудована", "integrated")
            case 1?: return "Radeon"
            case 2?: return t("авто", "авто", "auto")
            default: return "?"
            }
        }

        public func gpuPolicyDetail(_ state: GPUPolicyState) -> String {
            t("сейчас: зарядка — ", "зараз: зарядка — ", "now: charger — ") + gpuSwitch(state.acSwitch)
                + t(", батарея — ", ", батарея — ", ", battery — ") + gpuSwitch(state.batterySwitch)
        }

        /// A failed button action: the daemon's own message (English, as it came), or why the daemon
        /// could not be reached.
        public func actionFailed(_ error: Error) -> String {
            if let daemonError = error as? DaemonError {
                switch daemonError {
                case .remote(let message): return message
                case .emptyReply: return t("демон ответил без данных", "демон відповів без даних", "the daemon replied without data")
                }
            }
            return connectionProblem(error)
        }

        /// Why the daemon cannot be reached: the usual socket failures in words, anything else under
        /// a lead with its technical detail.
        public func connectionProblem(_ error: Error) -> String {
            let lead = t("ошибка связи с демоном: ", "помилка зв'язку з демоном: ", "connection error with the daemon: ")
            if let socketError = error as? SocketError {
                switch socketError {
                case .system(call: "connect", code: ENOENT), .system(call: "connect", code: ECONNREFUSED):
                    return t("демон не запущен: сокета нет или он не принимает подключения",
                             "демон не запущений: сокета немає або він не приймає підключень",
                             "the daemon is not running: no socket, or it accepts no connections")
                case .system(call: "connect", code: EACCES):
                    return t("нет доступа к сокету демона: пользователь должен быть в группе admin",
                             "немає доступу до сокета демона: користувач має бути в групі admin",
                             "no access to the daemon's socket: the user must be in the admin group")
                case .timedOut, .system(_, code: EAGAIN), .system(_, code: ETIMEDOUT):
                    return t("демон не ответил вовремя", "демон не відповів вчасно", "the daemon did not answer in time")
                case .closed:
                    return t("демон закрыл соединение", "демон закрив з'єднання", "the daemon closed the connection")
                default:
                    return lead + "\(socketError)"
                }
            }
            if error is DecodingError {
                return t("ответ демона не читается: версии демона и приложения разошлись",
                         "відповідь демона не читається: версії демона та застосунку розійшлися",
                         "the daemon's reply is unreadable: the daemon and the app are out of step")
            }
            return lead + "\(error)"
        }

        public var gpuPolicyToggle: String { t("На зарядке — всегда Radeon", "На зарядці — завжди Radeon", "On the charger — always Radeon") }
        public var curvesButton: String { t("Кривые…", "Криві…", "Curves…") }
        public var releaseButton: String { t("Отдать управление macOS", "Віддати керування macOS", "Hand control to macOS") }
        public var resumeButton: String { t("Вернуть кривую", "Повернути криву", "Resume the curve") }
        public var retryButton: String { t("Попробовать снова", "Спробувати знову", "Try again") }
        public var quitButton: String { t("Закрыть менюбар (демон продолжит работу)", "Закрити менюбар (демон працюватиме далі)", "Quit the menu bar (the daemon keeps running)") }
        public var connecting: String { t("Подключение к демону…", "Підключення до демона…", "Connecting to the daemon…") }
        public var unreachableTitle: String { t("Демон не отвечает", "Демон не відповідає", "The daemon does not answer") }
        public var installHint: String { t("Установить или обновить: sudo ./scripts/install.sh", "Встановити або оновити: sudo ./scripts/install.sh", "Install or update: sudo ./scripts/install.sh") }
        public var fansTitle: String { t("Вентиляторы", "Вентилятори", "Fans") }
        /// VoiceOver names of the menubar picture.
        public var menuBarAccessibility: String { "FanCurve" }
        public var menuBarAlertAccessibility: String { t("FanCurve: сбой", "FanCurve: збій", "FanCurve: failure") }

        /// The daemon's last SMC write error (technical, English) under a lead.
        public func smcErrorLine(_ error: String) -> String {
            t("Ошибка записи в SMC: ", "Помилка запису в SMC: ", "SMC write error: ") + error
        }

        /// Why the daemon's config file was refused (English, as it came) under a lead.
        public func configErrorLine(_ error: String) -> String {
            t("Ошибка конфига: ", "Помилка конфігу: ", "Config error: ") + error
        }

        // MARK: Charts

        public var temperatureChart: String { t("Температура, °C", "Температура, °C", "Temperature, °C") }
        public var fanChart: String { t("Вентиляторы, % диапазона", "Вентилятори, % діапазону", "Fans, % of range") }
        public var powerChart: String { t("Мощность CPU + Radeon, Вт", "Потужність CPU + Radeon, Вт", "CPU + Radeon power, W") }

        /// VoiceOver's name for the segmented control that picks the time range, which shows no label.
        public var chartWindowPicker: String { t("Период графиков", "Період графіків", "Chart time range") }

        /// Names of the plotted values; VoiceOver reads them.
        public var chartTimeValue: String { t("Время", "Час", "Time") }
        public var chartLineValue: String { t("Линия", "Лінія", "Line") }
        public var chartThresholdValue: String { t("Порог", "Поріг", "Threshold") }
        public var editorInputValue: String { t("Вход", "Вхід", "Input") }
        public var editorOutputValue: String { t("Обороты", "Оберти", "Speed") }

        /// The popup's time range, e.g. "15 min".
        public func chartWindow(minutes: Int) -> String {
            "\(minutes) " + t("мин", "хв", "min")
        }

        /// A line's name in the legend. Only the temperatures have a legend; the fans and the watts,
        /// alone in their panels, get the names the popup already uses for them.
        public func seriesName(_ series: ChartSeries) -> String {
            switch series {
            case .cpu: return "CPU"
            case .gpu: return "GPU"
            case .chassis: return chassisName
            case .fans: return fansTitle
            case .power: return wattsName
            }
        }

        /// The line above the charts: every value at one moment (the hovered one, or the latest).
        public func readout(_ sample: Sample, fanPercent: Double?, timeZone: TimeZone = .current) -> String {
            "\(clock(sample.t, timeZone: timeZone)) · CPU \(temperature(sample.cpu)) · GPU \(temperature(sample.gpu))"
                + " · \(chassisName) \(temperature(sample.chassis))"
                + " · " + t("вент.", "вент.", "fans") + " \(percent(fanPercent)) · \(watts(sample.power))"
        }

        // MARK: Curve editor

        public var editorTitle: String { t("FanCurve — кривые", "FanCurve — криві", "FanCurve — curves") }
        public var curveEnabled: String { t("включена", "увімкнена", "enabled") }
        public var editorHint: String {
            t("Тяните точки мышью. Клик по пустому месту — новая точка, Delete — удалить выбранную.",
              "Тягніть точки мишею. Клік по порожньому місцю — нова точка, Delete — видалити вибрану.",
              "Drag points with the mouse. Click empty space for a new point, Delete removes the selected one.")
        }
        public var deletePoint: String { t("Удалить точку", "Видалити точку", "Delete point") }
        /// VoiceOver's name for the segmented control that picks the curve, which shows no label.
        public var curvePicker: String { t("Кривая", "Крива", "Curve") }
        public var smoothingTitle: String { t("Сглаживание", "Згладжування", "Smoothing") }

        /// The label beside a smoothing field.
        public func smoothingLabel(_ field: SmoothingField) -> String {
            switch field {
            case .up: return t("Скорость вверх, %/с", "Швидкість угору, %/с", "Ramp up, %/s")
            case .hold: return t("Удержание после пика, с", "Утримання після піку, с", "Hold after a peak, s")
            case .down: return t("Скорость вниз, %/с", "Швидкість униз, %/с", "Ramp down, %/s")
            case .deadband: return t("Мёртвая зона записи, %", "Мертва зона запису, %", "Write deadband, %")
            }
        }

        /// What the core accepts in a smoothing field, e.g. "0,5–50".
        public func smoothingRange(_ field: SmoothingField) -> String {
            let range = Smoothing.range(for: field)
            return "\(number(range.lowerBound))–\(number(range.upperBound))"
        }

        public var applyButton: String { t("Применить", "Застосувати", "Apply") }
        /// A smoothing field whose text is not a number.
        public func smoothingNotANumber(_ field: SmoothingField) -> String {
            let label = smoothingLabel(field)
            return t("«\(label)»: введите число", "«\(label)»: введіть число", "“\(label)”: enter a number")
        }
        public var revertButton: String { t("Отменить изменения", "Скасувати зміни", "Discard changes") }
        public var defaultsButton: String { t("Стартовые значения", "Початкові значення", "Defaults") }
        public var applied: String { t("Применено", "Застосовано", "Applied") }
        public var loading: String { t("Загрузка кривых…", "Завантаження кривих…", "Loading curves…") }
        public var reloadButton: String { t("Загрузить снова", "Завантажити знову", "Load again") }

        /// Why a draft is refused, in the user's words.
        public func validationMessage(for error: ValidationError) -> String {
            switch error.kind {
            case .pointCount(let curve, let count):
                let (name, lo, hi, n) = (curveName(curve), number(CurveLimits.minPoints), number(CurveLimits.maxPoints), number(count))
                return t("\(name): нужно от \(lo) до \(hi) точек, сейчас \(n)",
                         "\(name): потрібно від \(lo) до \(hi) точок, зараз \(n)",
                         "\(name): needs \(lo) to \(hi) points, has \(n)")
            case .pointNotANumber(let curve, let index):
                let (name, p) = (curveName(curve), number(index))
                return t("\(name): точка \(p) не число",
                         "\(name): точка \(p) не число",
                         "\(name): point \(p) is not a number")
            case .xOutOfRange(let curve, let x, let range):
                let (name, v, lo, hi) = (curveName(curve), number(x), number(range.lowerBound), number(range.upperBound))
                return t("\(name): x=\(v) вне \(lo)…\(hi)",
                         "\(name): x=\(v) поза \(lo)…\(hi)",
                         "\(name): x=\(v) outside \(lo)…\(hi)")
            case .yOutOfRange(let curve, let y):
                let (name, v, lo, hi) = (curveName(curve), number(y), number(0), number(100))
                return t("\(name): обороты \(v)% вне \(lo)…\(hi)",
                         "\(name): оберти \(v)% поза \(lo)…\(hi)",
                         "\(name): speed \(v)% outside \(lo)…\(hi)")
            case .xNotIncreasing(let curve, let index):
                let (name, p) = (curveName(curve), number(index))
                return t("\(name): x должен строго возрастать (точка \(p))",
                         "\(name): x має строго зростати (точка \(p))",
                         "\(name): x must strictly increase (point \(p))")
            case .yDecreasing(let curve, let index):
                let (name, p) = (curveName(curve), number(index))
                return t("\(name): обороты не должны падать с ростом x (точка \(p))",
                         "\(name): оберти не мають падати зі зростанням x (точка \(p))",
                         "\(name): speed must not fall as x grows (point \(p))")
            case .smoothingOutOfRange(let field, let value, let range):
                let (name, v, lo, hi) = (smoothingFieldName(field), number(value), number(range.lowerBound), number(range.upperBound))
                return t("\(name): \(v) вне \(lo)…\(hi)",
                         "\(name): \(v) поза \(lo)…\(hi)",
                         "\(name): \(v) outside \(lo)…\(hi)")
            case .other(let message):
                return message
            }
        }

        func curveName(_ kind: CurveKind) -> String {
            switch kind {
            case .hotspot: return t("горячий кристалл", "гарячий кристал", "hot die")
            case .power: return t("ватты", "вати", "watts")
            case .chassis: return t("корпус", "корпус", "chassis")
            }
        }

        func smoothingFieldName(_ field: SmoothingField) -> String {
            switch field {
            case .up: return t("скорость вверх, %/с", "швидкість угору, %/с", "ramp up, %/s")
            case .hold: return t("удержание, с", "утримання, с", "hold, s")
            case .down: return t("скорость вниз, %/с", "швидкість униз, %/с", "ramp down, %/s")
            case .deadband: return t("мёртвая зона, %", "мертва зона, %", "deadband, %")
            }
        }

        public func editorTab(_ kind: CurveKind) -> String {
            switch kind {
            case .hotspot: return t("Кристалл", "Кристал", "Die")
            case .power: return wattsName
            case .chassis: return chassisName
            }
        }

        public func editorAxis(_ kind: CurveKind) -> String {
            switch kind {
            case .hotspot: return t("Горячий кристалл (CPU или Radeon), °C", "Гарячий кристал (CPU або Radeon), °C", "Hot die (CPU or Radeon), °C")
            case .power: return t("CPU + Radeon, Вт", "CPU + Radeon, Вт", "CPU + Radeon, W")
            case .chassis: return t("Корпус, °C", "Корпус, °C", "Chassis, °C")
            }
        }

        public func inputValue(_ value: Double, kind: CurveKind) -> String {
            kind == .power ? watts(value) : temperature(value)
        }

        /// The editor's Y axis: the percent and the left fan's rpm at it. A range no fan can have
        /// shows the percent alone: `rpm(forPercent:)` would trap on it.
        public func editorYLabel(percent value: Double, fan: FanRange?) -> String {
            guard let fan, fan.isUsable else { return percent(value) }
            return "\(percent(value)) · \(fan.rpm(forPercent: value))"
        }

        /// "76° → 46% · 3575 rpm"
        public func curveReadout(input: Double, output: Double, kind: CurveKind, fan: FanRange?) -> String {
            var text = "\(inputValue(input, kind: kind)) → \(percent(output))"
            if let fan, fan.isUsable {
                text += " · \(fan.rpm(forPercent: output)) \(rpmUnit)"
            }
            return text
        }

        /// The live marker: the input right now and where the edited curve puts it.
        public func liveReadout(input: Double, output: Double, kind: CurveKind, fan: FanRange?) -> String {
            t("сейчас ", "зараз ", "now ") + curveReadout(input: input, output: output, kind: kind, fan: fan)
        }
    }
}
