import Foundation
import LunarCore

public struct LunarInfo: Hashable, Sendable {
    public let fullDate: String
    public let shortDate: String
    public let gridDate: String
    public let year: Int
    public let month: Int
    public let day: Int
    public let isLeapMonth: Bool
}

public protocol LunarProviding: Sendable {
    func lunarInfo(for date: CivilDate) -> LunarInfo?
    func solarTerm(for date: CivilDate) -> String?
}

public struct LunarProvider: LunarProviding, Sendable {
    private let calendar = LunarCalendar.shared
    private let formatter = LunarFormatter(locale: .chinese)

    public init() {}

    public func lunarInfo(for date: CivilDate) -> LunarInfo? {
        guard let solar = SolarDate(year: date.year, month: date.month, day: date.day),
              let lunar = calendar.lunarDate(from: solar) else { return nil }
        return LunarInfo(
            fullDate: formatter.string(from: lunar, useGanZhi: true).replacingOccurrences(of: "年", with: "年 "),
            shortDate: formatter.shortString(from: lunar),
            gridDate: lunar.day == 1
                ? formatter.monthName(lunar.month, isLeap: lunar.isLeapMonth)
                : formatter.dayName(lunar.day),
            year: lunar.year,
            month: lunar.month,
            day: lunar.day,
            isLeapMonth: lunar.isLeapMonth
        )
    }

    public func solarTerm(for date: CivilDate) -> String? {
        guard let solar = SolarDate(year: date.year, month: date.month, day: date.day) else { return nil }
        return calendar.solarTerm(on: solar)?.chineseName
    }
}

public struct TraditionalFestivalProvider: Sendable {
    private let lunarProvider: any LunarProviding
    private let calendar: Calendar

    public init(lunarProvider: any LunarProviding = LunarProvider(), calendar: Calendar = .qingLiGregorian) {
        self.lunarProvider = lunarProvider
        self.calendar = calendar
    }

    public func festival(on date: CivilDate) -> String? {
        switch (date.month, date.day) {
        case (1, 1): return "元旦"
        case (5, 1): return "劳动节"
        case (10, 1): return "国庆节"
        default: break
        }

        guard let lunar = lunarProvider.lunarInfo(for: date), !lunar.isLeapMonth else { return nil }
        switch (lunar.month, lunar.day) {
        case (1, 1): return "春节"
        case (1, 15): return "元宵节"
        case (5, 5): return "端午节"
        case (7, 7): return "七夕"
        case (8, 15): return "中秋节"
        case (9, 9): return "重阳节"
        case (12, 8): return "腊八节"
        default:
            guard let next = CalendarEngine(calendar: calendar).addingDays(1, to: date),
                  let nextLunar = lunarProvider.lunarInfo(for: next),
                  nextLunar.month == 1, nextLunar.day == 1, !nextLunar.isLeapMonth else { return nil }
            return "除夕"
        }
    }
}

public struct DayInformation: Hashable, Sendable {
    public let date: CivilDate
    public let lunar: LunarInfo?
    public let festival: String?
    public let solarTerm: String?
    public let holiday: HolidayRecord?
    public let isHolidayArrangementCovered: Bool

    public var popupGridLabel: String {
        if let holiday { return holiday.kind == .holiday ? "放假" : "补班" }
        return festival ?? solarTerm ?? lunar?.gridDate ?? ""
    }

    public var widgetGridLabel: String {
        calendarGridLabel
    }

    public var calendarGridLabel: String {
        festival ?? solarTerm ?? lunar?.gridDate ?? ""
    }

    public var gridLabel: String { popupGridLabel }

    public var accessibilitySummary: String {
        var parts = [date.description]
        if let lunar { parts.append("农历\(lunar.fullDate)") }
        if let festival { parts.append(festival) }
        if let solarTerm { parts.append(solarTerm) }
        if let holiday { parts.append("\(holiday.name)，\(holiday.kind.accessibilityLabel)") }
        if !isHolidayArrangementCovered { parts.append("该年度节假日安排未内置") }
        return parts.joined(separator: "，")
    }
}

public struct QingLiDateService: Sendable {
    public let lunarProvider: any LunarProviding
    public let holidayProvider: any HolidayProviding
    public let festivalProvider: TraditionalFestivalProvider

    public init(
        lunarProvider: any LunarProviding = LunarProvider(),
        holidayProvider: any HolidayProviding = try! HolidayProvider()
    ) {
        self.lunarProvider = lunarProvider
        self.holidayProvider = holidayProvider
        self.festivalProvider = TraditionalFestivalProvider(lunarProvider: lunarProvider)
    }

    public func information(for date: CivilDate) -> DayInformation {
        DayInformation(
            date: date,
            lunar: lunarProvider.lunarInfo(for: date),
            festival: festivalProvider.festival(on: date),
            solarTerm: lunarProvider.solarTerm(for: date),
            holiday: holidayProvider.holiday(on: date),
            isHolidayArrangementCovered: holidayProvider.isCovered(year: date.year)
        )
    }
}
