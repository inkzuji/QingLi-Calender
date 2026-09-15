import Foundation

public enum QingLiSupportedDates {
    public static let range = CivilDate(year: 1900, month: 1, day: 31)...CivilDate(year: 2100, month: 12, day: 31)

    public static func contains(_ date: CivilDate) -> Bool {
        range.contains(date)
    }

    public static func year(from input: String) -> Int? {
        guard input.count == 4,
              input.allSatisfy({ $0.isASCII && $0.isNumber }),
              let year = Int(input),
              (range.lowerBound.year...range.upperBound.year).contains(year) else { return nil }
        return year
    }
}

public struct CalendarDay: Identifiable, Hashable, Sendable {
    public let date: CivilDate
    public let isInDisplayedMonth: Bool

    public var id: CivilDate { date }
}

public struct CalendarMonth: Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let days: [CalendarDay]

    public init(year: Int, month: Int, days: [CalendarDay]) {
        self.year = year
        self.month = month
        self.days = days
    }
}

public struct CalendarEngine: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .qingLiGregorian) {
        self.calendar = calendar
    }

    /// 以周一开始，始终返回六行、七列共 42 格。
    public func month(containing date: CivilDate) -> CalendarMonth {
        guard let firstOfMonth = calendar.date(from: DateComponents(year: date.year, month: date.month, day: 1)),
              let start = calendar.date(byAdding: .day, value: -leadingDays(before: firstOfMonth), to: firstOfMonth) else {
            return CalendarMonth(year: date.year, month: date.month, days: [])
        }

        let days = (0..<42).compactMap { offset -> CalendarDay? in
            guard let current = calendar.date(byAdding: .day, value: offset, to: start),
                  let civil = CivilDate(current, calendar: calendar) else { return nil }
            return CalendarDay(date: civil, isInDisplayedMonth: civil.year == date.year && civil.month == date.month)
        }
        return CalendarMonth(year: date.year, month: date.month, days: days)
    }

    public func addingMonths(_ value: Int, to date: CivilDate) -> CivilDate? {
        guard let source = date.date(in: calendar),
              let result = calendar.date(byAdding: .month, value: value, to: source) else { return nil }
        return CivilDate(result, calendar: calendar)
    }

    /// 在给定支持范围内切换月份，并在目标月份只部分受支持时钳制到最近的有效日期。
    public func addingMonths(
        _ value: Int,
        to date: CivilDate,
        limitedTo supportedRange: ClosedRange<CivilDate>
    ) -> CivilDate? {
        guard let sourceMonth = calendar.date(from: DateComponents(year: date.year, month: date.month, day: 1)),
              let targetMonth = calendar.date(byAdding: .month, value: value, to: sourceMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: targetMonth),
              let year = calendar.dateComponents([.year, .month], from: targetMonth).year,
              let month = calendar.dateComponents([.year, .month], from: targetMonth).month else { return nil }

        let candidate = CivilDate(year: year, month: month, day: min(date.day, dayRange.count))
        if candidate < supportedRange.lowerBound,
           year == supportedRange.lowerBound.year,
           month == supportedRange.lowerBound.month {
            return supportedRange.lowerBound
        }
        if candidate > supportedRange.upperBound,
           year == supportedRange.upperBound.year,
           month == supportedRange.upperBound.month {
            return supportedRange.upperBound
        }
        return supportedRange.contains(candidate) ? candidate : nil
    }

    public func addingDays(_ value: Int, to date: CivilDate) -> CivilDate? {
        guard let source = date.date(in: calendar),
              let result = calendar.date(byAdding: .day, value: value, to: source) else { return nil }
        return CivilDate(result, calendar: calendar)
    }

    private func leadingDays(before date: Date) -> Int {
        // Foundation 的 weekday 是周日 1，转换为周一 0。
        (calendar.component(.weekday, from: date) + 5) % 7
    }
}
