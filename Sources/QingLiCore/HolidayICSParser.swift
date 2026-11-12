import Foundation

enum HolidayICSParser {
    struct Year {
        let year: Int
        let records: [HolidayRecord]
        let failureReason: String?
        let totalsWereVerified: Bool
    }

    private struct Property {
        let name: String
        let parameters: [String: String]
        let value: String
    }

    private struct Numbering: Hashable {
        let index: Int
        let total: Int
    }

    private struct Event {
        let dates: [CivilDate]
        let names: Set<String>
        let kind: HolidayKind
        let numbering: Numbering?
    }

    private struct UnsupportedRecurrence: Error {
        let years: Set<Int>
        let ranges: [ClosedRange<Int>]
    }

    private struct Group: Hashable {
        let year: Int
        let names: Set<String>
        let kind: HolidayKind

        init(_ event: Event) {
            let start = event.dates[0]
            year = event.names == ["元旦"] && start.month == 12 ? start.year + 1 : start.year
            names = event.names
            kind = event.kind
        }
    }

    private enum EventDate {
        case day(CivilDate)
        case time(Date)

        var civilDate: CivilDate {
            switch self {
            case let .day(date): return date
            case let .time(date): return CivilDate(date, calendar: HolidayICSParser.shanghaiCalendar)!
            }
        }
    }

    private static let holidayOrder = ["元旦", "春节", "清明节", "劳动节", "端午节", "中秋节", "国庆节"]
    private static let holidayMarkers = ["（休）", "(休)", "假期", "放假"]
    private static let workdayMarkers = ["（班）", "(班)", "调休上班", "补班"]
    private static let shanghaiCalendar: Calendar = {
        var calendar = Calendar.qingLiGregorian
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    static func years(in data: Data, startingAt currentYear: Int) throws -> [Year] {
        var recognized = [Event]()
        var failures = [Int: String]()
        var recurrences = [UnsupportedRecurrence]()
        for properties in try events(in: data) {
            try Task.checkCancellation()
            do {
                if let event = try interpret(properties) { recognized.append(event) }
            } catch let recurrence as UnsupportedRecurrence {
                recurrences.append(recurrence)
            } catch let error as HolidayUpdateError {
                let affectedYears = try affectedYears(for: properties, error: error)
                for year in affectedYears where year >= currentYear {
                    failures[year] = failures[year] ?? error.localizedDescription
                }
            }
        }
        guard !recognized.isEmpty || !failures.isEmpty || !recurrences.isEmpty else {
            throw HolidayUpdateError.invalidCalendar("未识别到放假或调休补班事件")
        }
        for group in Dictionary(grouping: recognized, by: Group.init).values where !validNumbering(in: group) {
            for year in group.flatMap(\.dates).map(\.year) where year >= currentYear {
                failures[year] = failures[year] ?? "休班事件的序号或总数不一致"
            }
        }

        var grouped = [Int: [CivilDate: [HolidayKind: Set<String>]]]()
        var yearsWithMissingTotals = Set<Int>()
        for event in recognized {
            for date in event.dates where date.year >= currentYear {
                grouped[date.year, default: [:]][date, default: [:]][event.kind, default: []].formUnion(event.names)
                if event.numbering == nil { yearsWithMissingTotals.insert(date.year) }
            }
        }
        let recurringYears = Set(recurrences.flatMap(\.years).filter { $0 >= currentYear })
        let recurringRanges = recurrences.flatMap(\.ranges)
        return Set(grouped.keys).union(failures.keys).union(recurringYears).sorted().map { year in
            if let reason = failures[year] { return invalidYear(year, reason: reason) }
            if recurringYears.contains(year) || recurringRanges.contains(where: { $0.contains(year) }) {
                return invalidYear(year, reason: "暂不支持重复休班事件")
            }
            let entries = grouped[year, default: [:]]
            guard !entries.values.contains(where: { $0.count > 1 }) else {
                return invalidYear(year, reason: "同一天同时标记为放假和补班")
            }
            let holidays = Set(entries.values.flatMap { $0[.holiday, default: []] })
            guard Set(holidayOrder).isSubset(of: holidays), entries.values.contains(where: { $0[.adjustedWorkday] != nil }) else {
                return invalidYear(year, reason: "缺少所需节日或调休补班安排")
            }
            let records = entries.keys.sorted().compactMap { date -> HolidayRecord? in
                guard let (kind, names) = entries[date]?.first else { return nil }
                let name = combinedName(names) + (kind == .adjustedWorkday ? "调休" : "")
                return HolidayRecord(date: date, name: name, kind: kind)
            }
            return Year(year: year, records: records, failureReason: nil, totalsWereVerified: !yearsWithMissingTotals.contains(year))
        }
    }

    private static func invalidYear(_ year: Int, reason: String) -> Year {
        Year(year: year, records: [], failureReason: reason, totalsWereVerified: false)
    }

    private static func events(in data: Data) throws -> [[Property]] {
        let content = try unfoldedContent(data)
        var components = [String]()
        var events = [[Property]]()
        var current = [Property]()
        var hasCalendar = false
        for line in content.split(whereSeparator: \.isNewline) {
            let property = try property(in: line)
            switch property.name {
            case "BEGIN":
                let component = property.value.uppercased()
                switch component {
                case "VCALENDAR":
                    guard components.isEmpty, !hasCalendar else { throw invalidStructure }
                    hasCalendar = true
                case "VEVENT":
                    guard components == ["VCALENDAR"] else { throw invalidStructure }
                    current = []
                default:
                    guard !components.isEmpty else { throw invalidStructure }
                }
                components.append(component)
            case "END":
                let component = property.value.uppercased()
                guard components.popLast() == component else { throw invalidStructure }
                if component == "VEVENT" { events.append(current) }
            default:
                guard !components.isEmpty else { throw invalidStructure }
                if components == ["VCALENDAR", "VEVENT"] { current.append(property) }
            }
        }
        guard hasCalendar, components.isEmpty else { throw invalidStructure }
        return events
    }

    private static var invalidStructure: HolidayUpdateError { .invalidCalendar("iCalendar 结构不完整") }

    // 先在字节层处理折行，允许折行位置落在 UTF-8 字符内部。
    private static func unfoldedContent(_ data: Data) throws -> String {
        var unfolded = [UInt8]()
        unfolded.reserveCapacity(data.count)
        let bytes = [UInt8](data)
        var index = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 10 || byte == 13 {
                index += 1
                if byte == 13, index < bytes.count, bytes[index] == 10 { index += 1 }
                if index < bytes.count, bytes[index] == 32 || bytes[index] == 9 {
                    index += 1
                } else {
                    unfolded.append(10)
                }
            } else {
                unfolded.append(byte)
                index += 1
            }
        }
        guard let content = String(bytes: unfolded, encoding: .utf8) else {
            throw HolidayUpdateError.invalidCalendar("不是 UTF-8 文本")
        }
        return content
    }

    private static func property(in line: Substring) throws -> Property {
        var quoted = false
        var segments = [Substring]()
        var start = line.startIndex
        for index in line.indices {
            switch line[index] {
            case "\"":
                quoted.toggle()
            case ";" where !quoted:
                segments.append(line[start..<index])
                start = line.index(after: index)
            case ":" where !quoted:
                segments.append(line[start..<index])
                guard let name = segments.first, !name.isEmpty else { throw invalidStructure }
                var parameters = [String: String]()
                for segment in segments.dropFirst() {
                    let pair = segment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    guard pair.count == 2, !pair[0].isEmpty else { throw invalidStructure }
                    let value = pair[1]
                    parameters[pair[0].uppercased()] = value.hasPrefix("\"") && value.hasSuffix("\"")
                        ? String(value.dropFirst().dropLast()) : String(value)
                }
                return Property(name: name.uppercased(), parameters: parameters, value: String(line[line.index(after: index)...]))
            default:
                break
            }
        }
        throw invalidStructure
    }

    private static func interpret(_ properties: [Property]) throws -> Event? {
        let fields = Dictionary(grouping: properties, by: \.name)
        guard fields["STATUS"]?.first?.value.uppercased() != "CANCELLED" else { return nil }
        var summary = unescapedText(fields["SUMMARY"]?.first?.value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let numbering: Numbering?
        if let match = summary.firstMatch(of: #/第\s*([0-9]+)\s*天\s*[/／]\s*共\s*([0-9]+)\s*天\s*$/#) {
            numbering = Numbering(index: Int(match.1) ?? 0, total: Int(match.2) ?? 0)
            summary = String(summary[..<match.range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            numbering = nil
        }
        guard let kind = try kind(in: fields, summary: summary) else { return nil }
        for key in ["SUMMARY", "DTSTART", "DTEND"] where (fields[key]?.count ?? 0) > 1 {
            throw HolidayUpdateError.invalidCalendar("休班事件包含重复的 \(key)")
        }
        guard fields["DURATION"] == nil else {
            throw HolidayUpdateError.invalidCalendar("暂不支持使用 DURATION 的休班事件")
        }
        let names = normalizedNames(summary, kind: kind)
        guard !names.isEmpty else { throw HolidayUpdateError.invalidCalendar("缺少休班名称") }
        guard let start = fields["DTSTART"]?.first else { throw HolidayUpdateError.invalidCalendar("缺少休班开始日期") }
        let dates = try dates(from: eventDate(start), to: fields["DTEND"]?.first.map(eventDate))
        if let recurrence = unsupportedRecurrence(in: fields, dates: dates) { throw recurrence }
        return Event(dates: dates, names: names, kind: kind, numbering: numbering)
    }

    private static func unsupportedRecurrence(in fields: [String: [Property]], dates: [CivilDate]) -> UnsupportedRecurrence? {
        let keys = ["RRULE", "RDATE", "EXDATE", "EXRULE", "RECURRENCE-ID"]
        guard keys.contains(where: { fields[$0] != nil }), let start = dates.first, let end = dates.last else {
            return nil
        }
        var years = Set(dates.map(\.year))
        var ranges = [ClosedRange<Int>]()
        for field in fields["RDATE", default: []] + fields["RECURRENCE-ID", default: []] {
            for value in field.value.split(whereSeparator: { $0 == "," || $0 == "/" }) {
                if let year = referenceYear(of: String(value), parameters: field.parameters) { years.insert(year) }
            }
        }
        for field in fields["RRULE", default: []] + fields["EXRULE", default: []] {
            let rule = field.value.uppercased().split(separator: ";")
            let until = rule.first { $0.hasPrefix("UNTIL=") }
                .flatMap { referenceYear(of: String($0.dropFirst("UNTIL=".count))) }
            // 未知截止时间的重复安排可能影响源内任意后续候选年份。
            let last = until.map { $0 + end.year - start.year } ?? (rule.contains("COUNT=1") ? end.year : 9999)
            ranges.append(start.year...max(end.year, last))
        }
        return UnsupportedRecurrence(years: years, ranges: ranges)
    }

    private static func referenceYear(of value: String, parameters: [String: String] = [:]) -> Int? {
        let property = Property(name: "DTSTART", parameters: parameters, value: value)
        let year = (try? eventDate(property))?.civilDate.year ?? Int(value.prefix(4))
        return year.flatMap { (1...9999).contains($0) ? $0 : nil }
    }

    private static func kind(in fields: [String: [Property]], summary: String) throws -> HolidayKind? {
        switch fields["X-APPLE-SPECIAL-DAY"]?.first?.value.uppercased() {
        case "WORK-HOLIDAY": return .holiday
        case "ALTERNATE-WORKDAY": return .adjustedWorkday
        default: break
        }
        let categories = Set(fields["CATEGORIES", default: []].flatMap { property in
            property.value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
        })
        let holiday = !categories.isDisjoint(with: ["WORK-HOLIDAY", "法定放假", "放假", "假期"])
        let workday = !categories.isDisjoint(with: ["ALTERNATE-WORKDAY", "调休补班", "补班"])
        if holiday && workday { throw HolidayUpdateError.invalidCalendar("事件同时标记为放假和补班") }
        if holiday { return .holiday }
        if workday { return .adjustedWorkday }

        let markedHoliday = holidayMarkers.contains { summary.hasPrefix($0) || summary.hasSuffix($0) }
        let markedWorkday = workdayMarkers.contains { summary.hasPrefix($0) || summary.hasSuffix($0) }
        if markedHoliday && markedWorkday { throw HolidayUpdateError.invalidCalendar("事件同时标记为放假和补班") }
        if markedHoliday { return .holiday }
        if markedWorkday { return .adjustedWorkday }
        return nil
    }

    private static func normalizedNames(_ summary: String, kind: HolidayKind) -> Set<String> {
        var title = summary
        for marker in holidayMarkers + workdayMarkers {
            if title.hasPrefix(marker) { title = String(title.dropFirst(marker.count)) }
            if title.hasSuffix(marker) { title = String(title.dropLast(marker.count)) }
            title = title.trimmingCharacters(in: CharacterSet(charactersIn: " ：:\t\n"))
        }
        if kind == .adjustedWorkday, title.hasSuffix("调休") { title = String(title.dropLast(2)) }
        guard !title.isEmpty else { return [] }
        let names = title.split(separator: "、").map { part in
            let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
            return name == "清明" ? "清明节" : name
        }
        if names.count == 1 || names.allSatisfy(holidayOrder.contains) { return Set(names) }
        return [title]
    }

    private static func unescapedText(_ value: String) -> String {
        var text = ""
        var escaped = false
        for character in value {
            if escaped {
                switch character {
                case "n", "N": text.append("\n")
                case "\\", ",", ";": text.append(character)
                default:
                    text.append("\\")
                    text.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                text.append(character)
            }
        }
        if escaped { text.append("\\") }
        return text
    }

    private static func eventDate(_ property: Property) throws -> EventDate {
        let value = property.value
        let type = property.parameters["VALUE"]?.uppercased()
        let identifier = property.parameters["TZID"]
        if let match = value.wholeMatch(of: /([0-9]{4})([0-9]{2})([0-9]{2})/),
           type == nil || type == "DATE", identifier == nil {
            let date = civilDate(year: match.1, month: match.2, day: match.3)
            guard HolidayDatasetValidator.isValid(date), date.year > 0 else { throw invalidDate }
            return .day(date)
        }
        guard let match = value.wholeMatch(of: /([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})(Z?)/),
              type == nil || type == "DATE-TIME" else { throw invalidDate }
        var calendar = shanghaiCalendar
        if match.7 == "Z" {
            guard identifier == nil else { throw invalidDate }
            calendar.timeZone = .gmt
        } else if let identifier {
            guard let zone = TimeZone(identifier: identifier) else {
                throw HolidayUpdateError.invalidCalendar("无法识别休班事件时区 \(identifier)")
            }
            calendar.timeZone = zone
        }
        let date = civilDate(year: match.1, month: match.2, day: match.3)
        guard HolidayDatasetValidator.isValid(date), date.year > 0,
              let hour = Int(match.4), (0..<24).contains(hour),
              let minute = Int(match.5), (0..<60).contains(minute),
              let second = Int(match.6), (0..<60).contains(second),
              let instant = calendar.date(from: DateComponents(
                year: date.year, month: date.month, day: date.day, hour: hour, minute: minute, second: second
              )) else {
            throw invalidDate
        }
        let local = calendar.dateComponents([.hour, .minute, .second], from: instant)
        guard CivilDate(instant, calendar: calendar) == date,
              local.hour == hour, local.minute == minute, local.second == second else { throw invalidDate }
        return .time(instant)
    }

    private static var invalidDate: HolidayUpdateError { .invalidCalendar("休班事件日期或时间无效") }

    private static func civilDate(year: Substring, month: Substring, day: Substring) -> CivilDate {
        CivilDate(year: Int(year)!, month: Int(month)!, day: Int(day)!)
    }

    private static func dates(from start: EventDate, to end: EventDate?) throws -> [CivilDate] {
        guard let end else { return [start.civilDate] }
        let calendar = shanghaiCalendar
        let last: CivilDate
        switch (start, end) {
        case let (.day(startDay), .day(endDay)):
            guard startDay < endDay else { throw invalidDate }
            let previousDay = calendar.date(byAdding: .day, value: -1, to: endDay.date(in: calendar)!)!
            last = CivilDate(previousDay, calendar: calendar)!
        case let (.time(startTime), .time(endTime)):
            guard startTime < endTime else { throw invalidDate }
            last = CivilDate(endTime.addingTimeInterval(-1), calendar: calendar)!
        default:
            throw invalidDate
        }
        var current = start.civilDate.date(in: calendar)!
        let final = last.date(in: calendar)!
        guard calendar.dateComponents([.day], from: current, to: final).day ?? 0 <= 366 else {
            throw HolidayUpdateError.invalidCalendar("单个休班事件跨越超过一年")
        }
        var dates = [CivilDate]()
        while current <= final {
            dates.append(CivilDate(current, calendar: calendar)!)
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return dates
    }

    private static func affectedYears(for properties: [Property], error: HolidayUpdateError) throws -> ClosedRange<Int> {
        let dateProperties = properties.filter { ["DTSTART", "DTEND"].contains($0.name) }
        let years = dateProperties.compactMap { property in
            referenceYear(of: property.value, parameters: property.parameters)
        }
        guard let first = years.min(), let last = years.max(), first == last || last - first == 1 else { throw error }
        return first...last
    }

    private static func validNumbering(in events: [Event]) -> Bool {
        let numbered = events.compactMap(\.numbering)
        guard let total = numbered.first?.total else { return true }
        guard total > 0, numbered.allSatisfy({ $0.total == total }) else { return false }
        var datesByIndex = [Int: CivilDate]()
        for event in events {
            guard let index = event.numbering?.index, event.dates.count == 1, (1...total).contains(index) else {
                return false
            }
            let date = event.dates[0]
            if let existing = datesByIndex.updateValue(date, forKey: index), existing != date { return false }
        }
        guard datesByIndex.count == total else { return false }
        let dates = datesByIndex.sorted { $0.key < $1.key }.map(\.value)
        return dates == dates.sorted() && Set(dates).count == total
    }

    private static func combinedName(_ names: Set<String>) -> String {
        names.sorted {
            let left = holidayOrder.firstIndex(of: $0) ?? holidayOrder.count
            let right = holidayOrder.firstIndex(of: $1) ?? holidayOrder.count
            return (left, $0) < (right, $1)
        }.joined(separator: "、")
    }
}
