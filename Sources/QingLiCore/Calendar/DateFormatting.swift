import Foundation

public enum QingLiDateFormatter {
    public static func fullDate(_ date: CivilDate, calendar: Calendar = .qingLiGregorian) -> String {
        guard let foundationDate = date.date(in: calendar) else { return date.description }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter.string(from: foundationDate)
    }

    public static func weekday(_ date: CivilDate, calendar: Calendar = .qingLiGregorian) -> String {
        guard let foundationDate = date.date(in: calendar) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: foundationDate)
    }
}
