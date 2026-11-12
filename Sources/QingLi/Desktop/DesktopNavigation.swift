import QingLiCore
import SwiftUI

@MainActor
final class DesktopNavigation: ObservableObject {
    enum Page: String {
        case calendar = "日历"
        case holidays = "全年休班"
        case subscription = "节假日订阅"

        var breadcrumb: String {
            switch self {
            case .calendar: rawValue
            case .holidays: "浏览 / \(rawValue)"
            case .subscription: "设置 / \(rawValue)"
            }
        }
    }

    enum CalendarMode: String, CaseIterable {
        case year = "年"
        case month = "月"
    }

    static let windowID = "qingli-desktop"
    static var today: CivilDate {
        let range = QingLiSupportedDates.range
        let date = CivilDate(Date(), calendar: .qingLiGregorian) ?? range.lowerBound
        return min(max(date, range.lowerBound), range.upperBound)
    }

    @Published var page: Page = .calendar
    @Published var mode: CalendarMode = .year
    @Published var displayedMonth = today
    @Published var selectedDate = today
    @Published var overviewYear = today.year

    func select(_ date: CivilDate) {
        selectedDate = date
        displayedMonth = date
        mode = .month
        page = .calendar
    }
}
