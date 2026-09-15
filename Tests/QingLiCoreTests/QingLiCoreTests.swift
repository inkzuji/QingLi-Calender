import Foundation
import Testing
@testable import QingLiCore

@Suite("清历核心日期规则")
struct QingLiCoreTests {
    private let engine = CalendarEngine()

    @Test("月历始终为周一开始的 42 格")
    func monthGridHasSixWeeks() {
        let month = engine.month(containing: CivilDate(year: 2025, month: 3, day: 1))
        #expect(month.days.count == 42)
        #expect(month.days.first?.date == CivilDate(year: 2025, month: 2, day: 24))
        #expect(month.days.last?.date == CivilDate(year: 2025, month: 4, day: 6))

        let mondayStart = engine.month(containing: CivilDate(year: 2021, month: 2, day: 1))
        #expect(mondayStart.days.first?.date == CivilDate(year: 2021, month: 2, day: 1))

        let sundayStart = engine.month(containing: CivilDate(year: 2023, month: 10, day: 1))
        #expect(sundayStart.days.first?.date == CivilDate(year: 2023, month: 9, day: 25))
    }

    @Test("闰年二月和跨年日期正确")
    func leapYearAndYearBoundary() {
        let february = engine.month(containing: CivilDate(year: 2024, month: 2, day: 1))
        #expect(february.days.contains { $0.date == CivilDate(year: 2024, month: 2, day: 29) })
        #expect(engine.addingDays(1, to: CivilDate(year: 2025, month: 12, day: 31)) == CivilDate(year: 2026, month: 1, day: 1))
    }

    @Test("相邻月日期可被选择并同步切换月份")
    func adjacentMonthDateNavigation() {
        let january = CivilDate(year: 2026, month: 1, day: 15)
        #expect(engine.addingMonths(1, to: january) == CivilDate(year: 2026, month: 2, day: 15))
        #expect(engine.addingDays(-1, to: CivilDate(year: 2026, month: 2, day: 1)) == CivilDate(year: 2026, month: 1, day: 31))
    }

    @Test("支持范围边界的切月会钳制到首末有效日期")
    func supportedRangeMonthNavigation() {
        let range = QingLiSupportedDates.range
        #expect(engine.addingMonths(-1, to: CivilDate(year: 1900, month: 2, day: 1), limitedTo: range) == range.lowerBound)
        #expect(engine.addingMonths(-1, to: range.lowerBound, limitedTo: range) == nil)
        #expect(engine.addingMonths(1, to: range.upperBound, limitedTo: range) == nil)
        #expect(!QingLiSupportedDates.contains(CivilDate(year: 1900, month: 1, day: 30)))
        #expect(QingLiSupportedDates.contains(range.lowerBound))
        #expect(QingLiSupportedDates.contains(range.upperBound))
        #expect(!QingLiSupportedDates.contains(CivilDate(year: 2101, month: 1, day: 1)))
    }

    @Test("年份输入拒绝越界、分组和非整数")
    func validatesYearInput() {
        #expect(QingLiSupportedDates.year(from: "1900") == 1900)
        #expect(QingLiSupportedDates.year(from: "2100") == 2100)
        #expect(QingLiSupportedDates.year(from: "1899") == nil)
        #expect(QingLiSupportedDates.year(from: "2101") == nil)
        #expect(QingLiSupportedDates.year(from: "2,026") == nil)
        #expect(QingLiSupportedDates.year(from: "2026.0") == nil)
        #expect(QingLiSupportedDates.year(from: "二〇二六") == nil)
    }

    @Test("农历春节、闰月和边界日期")
    func lunarBoundaries() {
        let lunar = LunarProvider()
        let newYear = lunar.lunarInfo(for: CivilDate(year: 2025, month: 1, day: 29))
        #expect(newYear?.month == 1)
        #expect(newYear?.day == 1)
        #expect(lunar.lunarInfo(for: CivilDate(year: 2025, month: 7, day: 25))?.isLeapMonth == true)
        #expect(lunar.lunarInfo(for: CivilDate(year: 1900, month: 1, day: 31)) != nil)
        #expect(lunar.lunarInfo(for: CivilDate(year: 2100, month: 12, day: 31)) != nil)
        #expect(lunar.lunarInfo(for: CivilDate(year: 1900, month: 1, day: 30)) == nil)
    }

    @Test("农历提供日历格日名、初一月份和干支年详情")
    func lunarDisplayFormats() throws {
        let lunar = LunarProvider()
        let firstDay = try #require(lunar.lunarInfo(for: CivilDate(year: 2025, month: 1, day: 29)))
        #expect(firstDay.gridDate == "正月")
        #expect(firstDay.shortDate == "正月初一")
        #expect(firstDay.fullDate == "乙巳年 正月初一")

        let prototypeDate = try #require(lunar.lunarInfo(for: CivilDate(year: 2026, month: 9, day: 14)))
        #expect(prototypeDate.gridDate == "初四")
        #expect(prototypeDate.shortDate == "八月初四")
        #expect(prototypeDate.fullDate == "丙午年 八月初四")

        let ordinaryDay = try #require(lunar.lunarInfo(for: CivilDate(year: 2025, month: 1, day: 30)))
        #expect(ordinaryDay.gridDate == "初二")

        let leapMonth = try #require(lunar.lunarInfo(for: CivilDate(year: 2025, month: 7, day: 25)))
        #expect(leapMonth.isLeapMonth)
        #expect(leapMonth.gridDate == "闰六月")
        #expect(leapMonth.shortDate == "闰六月初一")
    }

    @Test("除夕与传统节日规则")
    func traditionalFestivals() {
        let provider = TraditionalFestivalProvider()
        #expect(provider.festival(on: CivilDate(year: 2025, month: 1, day: 28)) == "除夕")
        #expect(provider.festival(on: CivilDate(year: 2025, month: 1, day: 29)) == "春节")
        #expect(provider.festival(on: CivilDate(year: 2025, month: 10, day: 6)) == "中秋节")
    }

    @Test("二十四节气代表日期")
    func solarTerms() {
        let lunar = LunarProvider()
        #expect(lunar.solarTerm(for: CivilDate(year: 2025, month: 4, day: 4)) == "清明")
        #expect(lunar.solarTerm(for: CivilDate(year: 2025, month: 12, day: 21)) == "冬至")
        #expect(lunar.solarTerm(for: CivilDate(year: 2025, month: 4, day: 3)) == nil)
    }

    @Test("国务院 2025、2026 节假日与调休数据完整")
    func holidayDataset() throws {
        let provider = try HolidayProvider()
        #expect(provider.isCovered(year: 2025))
        #expect(provider.isCovered(year: 2026))
        #expect(!provider.isCovered(year: 2027))
        #expect(provider.holiday(on: CivilDate(year: 2025, month: 1, day: 26))?.kind == .adjustedWorkday)
        #expect(provider.holiday(on: CivilDate(year: 2025, month: 10, day: 6))?.kind == .holiday)
        #expect(provider.holiday(on: CivilDate(year: 2026, month: 2, day: 28))?.kind == .adjustedWorkday)
        #expect(provider.holiday(on: CivilDate(year: 2026, month: 9, day: 25))?.name == "中秋节")
        assertOfficialArrangement(
            year: 2025,
            holidays: [(1, 1...1), (1, 28...31), (2, 1...4), (4, 4...6), (5, 1...5), (5, 31...31), (6, 1...2), (10, 1...8)],
            workdays: [(1, 26), (2, 8), (4, 27), (9, 28), (10, 11)],
            provider: provider
        )
        assertOfficialArrangement(
            year: 2026,
            holidays: [(1, 1...3), (2, 15...23), (4, 4...6), (5, 1...5), (6, 19...21), (9, 25...27), (10, 1...7)],
            workdays: [(1, 4), (2, 14), (2, 28), (5, 9), (9, 20), (10, 10)],
            provider: provider
        )
    }

    @Test("同日的法定节假日和传统节日均保留在详情")
    func overlappingEventsAreRetained() {
        let service = QingLiDateService()
        let information = service.information(for: CivilDate(year: 2025, month: 10, day: 6))
        #expect(information.festival == "中秋节")
        #expect(information.holiday?.kind == .holiday)
        #expect(information.popupGridLabel == "放假")
        #expect(information.widgetGridLabel == "中秋节")
    }

    @Test("日历格事件按休班、节日、节气、农历排序")
    func gridEventPriority() {
        let service = QingLiDateService()
        let serviceWithoutHoliday = QingLiDateService(holidayProvider: EmptyHolidayProvider())
        #expect(service.information(for: CivilDate(year: 2025, month: 10, day: 6)).popupGridLabel == "放假")
        #expect(service.information(for: CivilDate(year: 2025, month: 1, day: 26)).popupGridLabel == "补班")
        #expect(serviceWithoutHoliday.information(for: CivilDate(year: 2025, month: 1, day: 29)).popupGridLabel == "春节")
        #expect(serviceWithoutHoliday.information(for: CivilDate(year: 2025, month: 4, day: 4)).popupGridLabel == "清明")
        #expect(serviceWithoutHoliday.information(for: CivilDate(year: 2025, month: 1, day: 30)).popupGridLabel == "初二")

        let overlappingFestivalAndTerm = serviceWithoutHoliday.information(for: CivilDate(year: 1900, month: 9, day: 8))
        #expect(overlappingFestivalAndTerm.festival == "中秋节")
        #expect(overlappingFestivalAndTerm.solarTerm == "白露")
        #expect(overlappingFestivalAndTerm.widgetGridLabel == "中秋节")
    }

    @Test("日期格只在真实节日当天显示节日名称")
    func gridFestivalUsesActualFestivalDate() {
        let service = QingLiDateService()
        let holidayStart = service.information(for: CivilDate(year: 2026, month: 2, day: 15))
        let newYearsEve = service.information(for: CivilDate(year: 2026, month: 2, day: 16))
        let springFestival = service.information(for: CivilDate(year: 2026, month: 2, day: 17))
        let nationalDay = service.information(for: CivilDate(year: 2026, month: 10, day: 1))
        let nationalDayHoliday = service.information(for: CivilDate(year: 2026, month: 10, day: 2))

        #expect(holidayStart.holiday?.name == "春节")
        #expect(holidayStart.holiday?.kind == .holiday)
        #expect(holidayStart.festival == nil)
        #expect(holidayStart.calendarGridLabel == "廿八")
        #expect(newYearsEve.festival == "除夕")
        #expect(newYearsEve.calendarGridLabel == "除夕")
        #expect(springFestival.holiday?.kind == .holiday)
        #expect(springFestival.festival == "春节")
        #expect(springFestival.calendarGridLabel == "春节")
        #expect(nationalDay.festival == "国庆节")
        #expect(nationalDay.calendarGridLabel == "国庆节")
        #expect(nationalDayHoliday.holiday?.kind == .holiday)
        #expect(nationalDayHoliday.calendarGridLabel != "国庆节")
    }

    private func assertOfficialArrangement(
        year: Int,
        holidays: [(Int, ClosedRange<Int>)],
        workdays: [(Int, Int)],
        provider: HolidayProvider
    ) {
        let expectedHolidays = Set(holidays.flatMap { month, days in
            days.map { CivilDate(year: year, month: month, day: $0) }
        })
        let expectedWorkdays = Set(workdays.map { CivilDate(year: year, month: $0.0, day: $0.1) })
        var actualHolidays = Set<CivilDate>()
        var actualWorkdays = Set<CivilDate>()

        for month in 1...12 {
            let limit = Calendar.qingLiGregorian.range(
                of: .day,
                in: .month,
                for: Calendar.qingLiGregorian.date(from: DateComponents(year: year, month: month, day: 1))!
            )!.count
            for day in 1...limit {
                let date = CivilDate(year: year, month: month, day: day)
                switch provider.holiday(on: date)?.kind {
                case .holiday: actualHolidays.insert(date)
                case .adjustedWorkday: actualWorkdays.insert(date)
                case nil: break
                }
            }
        }

        #expect(actualHolidays == expectedHolidays)
        #expect(actualWorkdays == expectedWorkdays)
    }
}

private struct EmptyHolidayProvider: HolidayProviding {
    func holiday(on date: CivilDate) -> HolidayRecord? { nil }
    func isCovered(year: Int) -> Bool { false }
    func notice(for year: Int) -> HolidayNotice? { nil }
}

private struct FixtureHTTPClient: HolidayHTTPClient {
    let response: HolidayHTTPResponse?

    func data(for url: URL) async throws -> HolidayHTTPResponse {
        guard url == ICloudHolidayCalendarUpdater.calendarURL, let response else {
            throw HolidayUpdateError.invalidCalendar("缺少日历夹具")
        }
        return response
    }
}

private final class MemoryHolidayStore: HolidayDatasetStoring, @unchecked Sendable {
    private var dataset: HolidayDataset?

    func loadCached() throws -> HolidayDataset? { dataset }

    func save(_ dataset: HolidayDataset) throws {
        try HolidayDatasetValidator.validate(dataset)
        self.dataset = dataset
    }
}

private final class MemoryHolidayMetadataStore: HolidayUpdateMetadataStoring, @unchecked Sendable {
    private var metadata = HolidayUpdateMetadata()

    func loadMetadata() throws -> HolidayUpdateMetadata { metadata }
    func saveMetadata(_ metadata: HolidayUpdateMetadata) throws { self.metadata = metadata }
}

private struct FailingHolidayMetadataStore: HolidayUpdateMetadataStoring {
    func loadMetadata() throws -> HolidayUpdateMetadata { HolidayUpdateMetadata() }
    func saveMetadata(_ metadata: HolidayUpdateMetadata) throws {
        throw HolidayUpdateError.invalidDataset("元数据写入失败")
    }
}

@Suite("iCloud 节假日日历更新")
struct ICloudHolidayCalendarUpdateTests {
    @Test("解析 ICS 放假区间、补班和同日重叠节日")
    func parsesCalendarAndAppliesFirstMissingYear() async throws {
        let existing = try HolidayProvider().holidayDataset
        let response = HolidayHTTPResponse(
            url: ICloudHolidayCalendarUpdater.calendarURL,
            data: Data(complete2027Calendar.utf8),
            statusCode: 200
        )
        let updater = ICloudHolidayCalendarUpdater(client: FixtureHTTPClient(response: response))

        let preview = try await updater.prepareUpdate(currentDataset: existing)
        #expect(preview.targetYear == 2027)
        #expect(preview.notice.title == "iCloud 中国大陆节假日日历")
        #expect(preview.notice.sourceURL == ICloudHolidayCalendarUpdater.calendarURL)
        #expect(preview.records.contains(HolidayRecord(date: CivilDate(year: 2027, month: 1, day: 3), name: "元旦", kind: .holiday)))
        #expect(!preview.records.contains { $0.date == CivilDate(year: 2027, month: 1, day: 4) && $0.kind == .holiday })
        #expect(preview.records.contains(HolidayRecord(date: CivilDate(year: 2027, month: 2, day: 20), name: "春节调休", kind: .adjustedWorkday)))
        #expect(preview.records.contains(HolidayRecord(date: CivilDate(year: 2027, month: 10, day: 6), name: "中秋节、国庆节", kind: .holiday)))

        let store = MemoryHolidayStore()
        let metadata = MemoryHolidayMetadataStore()
        let result = try updater.apply(preview, to: store, metadataStore: metadata, updatedAt: Date(timeIntervalSince1970: 200))
        #expect(result.dataset.coveredYears == [2025, 2026, 2027])
        #expect(result.metadataWasSaved)
        #expect(try store.loadCached()?.records == result.dataset.records)
        #expect(try metadata.loadMetadata().lastUpdatedAt == Date(timeIntervalSince1970: 200))
    }

    @Test("取消预览不会保存待导入数据")
    func cancellingPreviewLeavesStoredDatasetUntouched() async throws {
        let existing = try HolidayProvider().holidayDataset
        let store = MemoryHolidayStore()
        try store.save(existing)
        let updater = ICloudHolidayCalendarUpdater(client: FixtureHTTPClient(response: HolidayHTTPResponse(
            url: ICloudHolidayCalendarUpdater.calendarURL,
            data: Data(complete2027Calendar.utf8),
            statusCode: 200
        )))

        let preview = try await updater.prepareUpdate(currentDataset: existing)
        #expect(preview.targetYear == 2027)
        #expect(try store.loadCached()?.version == existing.version)
        #expect(try store.loadCached()?.coveredYears == existing.coveredYears)
    }

    @Test("更新状态写入失败时仍提交完整数据集")
    func metadataFailureDoesNotDiscardCommittedDataset() async throws {
        let existing = try HolidayProvider().holidayDataset
        let store = MemoryHolidayStore()
        try store.save(existing)
        let updater = ICloudHolidayCalendarUpdater(client: FixtureHTTPClient(response: HolidayHTTPResponse(
            url: ICloudHolidayCalendarUpdater.calendarURL,
            data: Data(complete2027Calendar.utf8),
            statusCode: 200
        )))
        let preview = try await updater.prepareUpdate(currentDataset: existing)

        let result = try updater.apply(preview, to: store, metadataStore: FailingHolidayMetadataStore())
        #expect(!result.metadataWasSaved)
        #expect(try store.loadCached()?.version == preview.mergedDataset.version)
        #expect(try store.loadCached()?.coveredYears == [2025, 2026, 2027])
    }

    @Test("更新状态写入失败时仍可检查并生成预览")
    func metadataFailureDoesNotBlockPreparingUpdate() async throws {
        let existing = try HolidayProvider().holidayDataset
        let updater = ICloudHolidayCalendarUpdater(client: FixtureHTTPClient(response: HolidayHTTPResponse(
            url: ICloudHolidayCalendarUpdater.calendarURL,
            data: Data(complete2027Calendar.utf8),
            statusCode: 200
        )))

        let preview = try await updater.prepareUpdate(
            currentDataset: existing,
            metadataStore: FailingHolidayMetadataStore()
        )
        #expect(preview.targetYear == 2027)
        #expect(preview.mergedDataset.coveredYears == [2025, 2026, 2027])
    }

    @Test("缺少完整休班安排时不覆盖已有缓存且记录检查时间")
    func rejectsIncompleteCalendarWithoutOverwritingCache() async throws {
        let existing = try HolidayProvider().holidayDataset
        let store = MemoryHolidayStore()
        try store.save(existing)
        let metadata = MemoryHolidayMetadataStore()
        let incomplete = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20270101
        DTEND;VALUE=DATE:20270104
        SUMMARY;LANGUAGE=zh_CN:元旦（休）
        X-APPLE-SPECIAL-DAY:WORK-HOLIDAY
        END:VEVENT
        END:VCALENDAR
        """
        let updater = ICloudHolidayCalendarUpdater(client: FixtureHTTPClient(response: HolidayHTTPResponse(
            url: ICloudHolidayCalendarUpdater.calendarURL,
            data: Data(incomplete.utf8),
            statusCode: 200
        )))
        let checkedAt = Date(timeIntervalSince1970: 100)

        await #expect(throws: HolidayUpdateError.self) {
            try await updater.prepareUpdate(currentDataset: existing, metadataStore: metadata, checkedAt: checkedAt)
        }
        #expect(try store.loadCached()?.version == existing.version)
        #expect(try metadata.loadMetadata().lastCheckedAt == checkedAt)
        #expect(try metadata.loadMetadata().lastUpdatedAt == nil)
    }

    @Test("非 iCloud 响应地址不会被导入")
    func rejectsUnexpectedCalendarSource() async throws {
        let existing = try HolidayProvider().holidayDataset
        let updater = ICloudHolidayCalendarUpdater(client: FixtureHTTPClient(response: HolidayHTTPResponse(
            url: URL(string: "https://example.com/holidays/cn_zh.ics")!,
            data: Data(complete2027Calendar.utf8),
            statusCode: 200
        )))

        await #expect(throws: HolidayUpdateError.self) {
            try await updater.prepareUpdate(currentDataset: existing)
        }
    }

    @Test("有效共享缓存优先于内置节假日数据")
    func cachedDatasetTakesPriority() throws {
        let bundled = try HolidayProvider().holidayDataset
        let cached = HolidayDataset(
            version: "cached-test-version",
            coveredYears: bundled.coveredYears,
            notices: bundled.notices,
            records: bundled.records
        )
        let store = MemoryHolidayStore()
        try store.save(cached)

        let provider = try HolidayProvider(bundle: qingLiTestsBundle, store: store)
        #expect(provider.holidayDataset.version == "cached-test-version")
    }

    private var complete2027Calendar: String {
        """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20270101
        DTEND;VALUE=DATE:20270104
        SUMMARY;LANGUAGE=zh_CN:元旦（休）
        X-APPLE-SPECIAL-DAY:WORK-HOLIDAY
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20270220
        SUMMARY;LANGUAGE=zh_CN:春节（班）
        X-APPLE-SPECIAL-DAY:ALTERNATE-WORKDAY
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20270221
        DTEND;VALUE=DATE:20270301
        SUMMARY;LANGUAGE=zh_CN:春节（休）
        X-APPLE-SPECIAL-DAY:WORK-HOLIDAY
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20270405
        DTEND;VALUE=DATE:20270408
        SUMMARY;LANGUAGE=zh_CN:清明（休）
        X-APPLE-SPECIAL-DAY:WORK-HOLIDAY
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20270501
        DTEND;VALUE=DATE:20270506
        SUMMARY;LANGUAGE=zh_
         CN:劳动节（休）
        X-APPLE-SPECIAL-DAY:WORK-HOLIDAY
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20270610
        DTEND;VALUE=DATE:20270613
        SUMMARY;LANGUAGE=zh_CN:端午节（休）
        X-APPLE-SPECIAL-DAY:WORK-HOLIDAY
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20271001
        DTEND;VALUE=DATE:20271008
        SUMMARY;LANGUAGE=zh_CN:国庆节（休）
        X-APPLE-SPECIAL-DAY:WORK-HOLIDAY
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20271006
        DTEND;VALUE=DATE:20271008
        SUMMARY;LANGUAGE=zh_CN:中秋节（休）
        X-APPLE-SPECIAL-DAY:WORK-HOLIDAY
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20271009
        SUMMARY;LANGUAGE=zh_CN:国庆节（班）
        X-APPLE-SPECIAL-DAY:ALTERNATE-WORKDAY
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20271001
        SUMMARY;LANGUAGE=zh_CN:国庆节
        RRULE:FREQ=YEARLY;COUNT=6
        END:VEVENT
        END:VCALENDAR
        """
    }
}

private final class QingLiTestsBundleToken {}

private let qingLiTestsBundle: Bundle = {
    #if SWIFT_PACKAGE
    return .module
    #else
    return Bundle(for: QingLiTestsBundleToken.self)
    #endif
}()
