import Foundation
import Testing
@testable import QingLiCore

@Suite("节假日订阅更新")
struct HolidaySubscriptionTests {
    @Test("处理折行、提醒、全天跨年与带时区的补班")
    func parsesCalendar() throws {
        let events = regularEvents(year: 2027, excluding: ["元旦"]) + [
            event("20261231", "元旦 假期 第1天/共3天", end: "20270101"),
            event("20270101", "元旦 假期 第2天/共3天"),
            event("20270102", "元旦 假期 第3天/共3天"),
            event("20270207T180000Z", "春节 补班 第1天/共2天", extra: [
                "BEGIN:VALARM", "SUMMARY:不应覆盖事件标题", "END:VALARM"
            ]),
            event("20270209T090000", "春节 补班 第2天/共2天", parameters: ";TZID=\"Asia/Shanghai\""),
            event("20270105", "普通纪念日", extra: ["RRULE:FREQ=YEARLY"]),
            event("20270106", "地方节日\\,纪念日（休）")
        ]
        let data = calendar(events).replacingOccurrences(of: "劳动节 假期", with: "劳动\r\n 节 假期")
        let years = try HolidayICSParser.years(in: Data(data.utf8), startingAt: 2027)
        let year = try #require(years.first)
        #expect(years.map(\.year) == [2027])
        #expect(year.failureReason == nil)
        #expect(!year.totalsWereVerified)
        let records = Dictionary(uniqueKeysWithValues: year.records.map { ($0.date.description, $0) })
        #expect(records["2027-01-01"]?.name == "元旦")
        #expect(records["2027-01-02"]?.name == "元旦")
        #expect(records["2027-01-03"] == nil)
        #expect(records["2027-02-08"]?.name == "春节调休")
        #expect(records["2027-02-09"]?.kind == .adjustedWorkday)
        #expect(records["2027-05-01"]?.name == "劳动节")
        #expect(records["2027-01-05"] == nil)
        #expect(records["2027-01-06"]?.name == "地方节日,纪念日")
    }

    @Test("保留合格年份，禁止导入缺序号、冲突或未知时区的年份", arguments: [
        event("20270208", "春节 补班 第1天/共2天"),
        event("20270501", "春节 补班 第1天/共1天"),
        event("20270208T090000", "春节 补班 第1天/共1天", parameters: ";TZID=Example/Unknown"),
        event("20270208", "春节 补班 第1天/共1天", extra: ["RRULE:FREQ=DAILY;UNTIL=20270209"]),
        event("20260208", "春节 补班 第1天/共1天", extra: ["RRULE:FREQ=YEARLY;UNTIL=20270208"]),
        event("20270208", "仅纪念")
    ])
    func isolatesInvalidYear(invalidEvent: String) throws {
        let events = regularEvents(year: 2027) + [invalidEvent] + completeEvents(year: 2028)
        let years = try HolidayICSParser.years(in: Data(calendar(events).utf8), startingAt: 2027)
        #expect(years.map(\.year) == [2027, 2028])
        #expect(years[0].failureReason != nil)
        #expect(years[1].failureReason == nil)
        #expect(years[1].totalsWereVerified)
    }

    @Test("Apple 格式兼容，无天数的完整候选仍可导入")
    func parsesAppleFormatWithoutCounts() throws {
        let events = regularEvents(year: 2027).map {
            $0.replacingOccurrences(of: " 假期 第1天/共1天", with: "（休）\r\nX-APPLE-SPECIAL-DAY:WORK-HOLIDAY")
        } + [event("20270208", "春节（班）", extra: ["X-APPLE-SPECIAL-DAY:ALTERNATE-WORKDAY"])]
        let years = try HolidayICSParser.years(in: Data(calendar(events).utf8), startingAt: 2027)
        let year = try #require(years.first)
        #expect(year.failureReason == nil)
        #expect(!year.totalsWereVerified)
        #expect(year.records.count == 8)
    }

    @Test("比较增改删，确认后完整替换所选年份并拒绝过期预览")
    func replacesOnlySelectedYears() async throws {
        let initialRecords = [
            HolidayRecord(date: CivilDate(year: 2026, month: 1, day: 1), name: "元旦", kind: .holiday),
            HolidayRecord(date: CivilDate(year: 2027, month: 5, day: 1), name: "劳动节调休", kind: .adjustedWorkday),
            HolidayRecord(date: CivilDate(year: 2027, month: 5, day: 2), name: "劳动节", kind: .holiday)
        ]
        let existingSource = HolidayYearSource(name: "原来源")
        let current = HolidayDataset(
            revision: "existing", coveredYears: [2026, 2027], records: initialRecords,
            yearSources: [2026: existingSource, 2027: existingSource], lastUpdatedAt: nil
        )
        let events = completeEvents(year: 2027) + completeEvents(year: 2028)
        let updater = HolidayCalendarUpdater(client: StubHolidaySubscriptionHTTPClient(calendar(events)))
        let downloaded = Date(timeIntervalSince1970: 100)
        let imported = Date(timeIntervalSince1970: 200)
        let preview = try await updater.prepareUpdate(
            subscription: .recommended, currentDataset: current, currentYear: 2027, downloadedAt: downloaded
        )
        let updatedYear = try #require(preview.years.first)
        #expect(updatedYear.status == .revised)
        #expect(updatedYear.changes.contains { $0.kind == .added })
        #expect(updatedYear.changes.contains { $0.kind == .modified && $0.date.day == 1 && $0.date.month == 5 })
        #expect(updatedYear.changes.contains { $0.kind == .removed && $0.date.day == 2 && $0.date.month == 5 })
        let saved = try updater.applying(preview, selectedYears: [2027], to: current, importedAt: imported)
        #expect(saved.records == [initialRecords[0]] + updatedYear.records)
        #expect(saved.coveredYears == [2026, 2027])
        #expect(saved.yearSources[2026] == existingSource)
        #expect(saved.yearSources[2027]?.name == HolidaySubscription.recommended.name)
        #expect(saved.yearSources[2027]?.downloadedAt == downloaded)
        #expect(saved.lastUpdatedAt == imported)
        #expect(throws: HolidaySubscriptionError.stalePreview) {
            try updater.applying(preview, selectedYears: [2028], to: saved)
        }
        let checkAgain = try await updater.prepareUpdate(subscription: .recommended, currentDataset: saved, currentYear: 2027)
        #expect(checkAgain.years.first?.status == .unchanged)
        let newSource = try HolidaySubscription(name: "改名的来源", address: HolidaySubscription.recommended.url.absoluteString)
        let changeSource = try await updater.prepareUpdate(subscription: newSource, currentDataset: saved, currentYear: 2027)
        #expect(changeSource.years.first?.status == .sourceOnly)
        #expect(changeSource.years.first?.changes.isEmpty == true)
    }

    @Test("webcal 地址可规范化，拒绝 HTTP 以及损坏的 ICS")
    func validatesAddressAndCalendar() throws {
        let source = try HolidaySubscription(name: " 来源 ", address: " webcal://Example.COM/calendar?region=cn ")
        #expect(source.name == "来源")
        #expect(source.url.absoluteString == "https://example.com/calendar?region=cn")
        #expect(throws: HolidaySubscriptionError.invalidAddress) {
            try HolidaySubscription(name: "HTTP", address: "http://example.com")
        }
        #expect(throws: HolidayUpdateError.self) {
            try HolidayICSParser.years(in: Data("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nEND:VCALENDAR".utf8), startingAt: 2027)
        }
        #expect(throws: HolidayUpdateError.self) {
            try HolidayICSParser.years(in: Data(calendar([event("20270105", "纪念日")]).utf8), startingAt: 2027)
        }
    }

    private func regularEvents(year: Int, excluding: Set<String> = []) -> [String] {
        [
            ("0101", "元旦"), ("0205", "春节"), ("0405", "清明"), ("0501", "劳动节"),
            ("0610", "端午节"), ("0915", "中秋节"), ("1001", "国庆节")
        ].filter { !excluding.contains($0.1) }.map {
            event("\(year)\($0.0)", "\($0.1) 假期 第1天/共1天")
        }
    }

    private func completeEvents(year: Int) -> [String] {
        regularEvents(year: year) + [event("\(year)0208T090000", "春节 补班 第1天/共1天")]
    }

    private func calendar(_ events: [String]) -> String {
        (["BEGIN:VCALENDAR", "VERSION:2.0"] + events + ["END:VCALENDAR"]).joined(separator: "\r\n")
    }
}

private func event(
    _ start: String,
    _ title: String,
    end: String? = nil,
    parameters: String = "",
    extra: [String] = []
) -> String {
    var lines = ["BEGIN:VEVENT", "DTSTART\(parameters):\(start)", "SUMMARY;LANGUAGE=zh_CN:\(title)"]
    if let end { lines.append("DTEND:\(end)") }
    return (lines + extra + ["END:VEVENT"]).joined(separator: "\r\n")
}

private struct StubHolidaySubscriptionHTTPClient: HolidayHTTPClient {
    let data: Data

    init(_ text: String) { data = Data(text.utf8) }

    func data(for url: URL) async throws -> HolidayHTTPResponse {
        HolidayHTTPResponse(url: url, data: data, statusCode: 200)
    }
}
