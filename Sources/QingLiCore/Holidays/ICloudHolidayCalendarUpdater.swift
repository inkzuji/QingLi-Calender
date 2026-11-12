import Foundation

public struct HolidayUpdateApplyResult: Sendable {
    public let dataset: HolidayDataset
    public let metadataWasSaved: Bool

    public init(dataset: HolidayDataset, metadataWasSaved: Bool) {
        self.dataset = dataset
        self.metadataWasSaved = metadataWasSaved
    }
}

public struct HolidayNoticeUpdatePreview: Sendable {
    public let targetYear: Int
    public let notice: HolidayNotice
    public let records: [HolidayRecord]
    public let mergedDataset: HolidayDataset

    public init(targetYear: Int, notice: HolidayNotice, records: [HolidayRecord], mergedDataset: HolidayDataset) {
        self.targetYear = targetYear
        self.notice = notice
        self.records = records
        self.mergedDataset = mergedDataset
    }
}

public protocol HolidayNoticeUpdating: Sendable {
    func prepareUpdate(currentDataset: HolidayDataset) async throws -> HolidayNoticeUpdatePreview
    func apply(_ preview: HolidayNoticeUpdatePreview, to store: any HolidayDatasetStoring) throws -> HolidayDataset
}

public struct ICloudHolidayCalendarUpdater: HolidayNoticeUpdating, Sendable {
    public static let calendarURL = URL(string: "https://calendars.icloud.com/holidays/cn_zh.ics")!

    private let client: any HolidayHTTPClient

    public init(client: any HolidayHTTPClient = URLSessionHolidayHTTPClient()) {
        self.client = client
    }

    public func prepareUpdate(currentDataset: HolidayDataset) async throws -> HolidayNoticeUpdatePreview {
        try HolidayDatasetValidator.validate(currentDataset)
        let targetYear = (currentDataset.coveredYears.max() ?? Calendar.qingLiGregorian.component(.year, from: Date()) - 1) + 1
        let response = try await client.data(for: Self.calendarURL)
        guard (200...299).contains(response.statusCode) else {
            throw HolidayUpdateError.unexpectedHTTPStatus(response.statusCode)
        }
        try ICloudHolidayCalendarURL.validate(response.url)
        let records = try ICloudHolidayCalendarParser.records(in: response.data, year: targetYear)
        let notice = HolidayNotice(
            year: targetYear,
            title: "iCloud 中国大陆节假日日历",
            publishedAt: Self.downloadDateString(),
            sourceURL: Self.calendarURL
        )
        let merged = merge(currentDataset: currentDataset, notice: notice, records: records)
        try HolidayDatasetValidator.validate(merged)
        return HolidayNoticeUpdatePreview(
            targetYear: targetYear,
            notice: notice,
            records: records,
            mergedDataset: merged
        )
    }

    /// 记录本次检查后准备导入首个缺失年份的节假日日历。
    public func prepareUpdate(
        currentDataset: HolidayDataset,
        metadataStore: any HolidayUpdateMetadataStoring,
        checkedAt: Date = Date()
    ) async throws -> HolidayNoticeUpdatePreview {
        let current = (try? metadataStore.loadMetadata()) ?? HolidayUpdateMetadata()
        try? metadataStore.saveMetadata(HolidayUpdateMetadata(lastCheckedAt: checkedAt, lastUpdatedAt: current.lastUpdatedAt))
        return try await prepareUpdate(currentDataset: currentDataset)
    }

    public func apply(_ preview: HolidayNoticeUpdatePreview, to store: any HolidayDatasetStoring) throws -> HolidayDataset {
        try HolidayDatasetValidator.validate(preview.mergedDataset)
        guard preview.mergedDataset.coveredYears.contains(preview.targetYear) else {
            throw HolidayUpdateError.invalidDataset("预览结果缺少目标年份")
        }
        try store.save(preview.mergedDataset)
        return preview.mergedDataset
    }

    /// 以完整数据集原子写入作为提交点；更新状态写入失败不撤销已提交的数据。
    public func apply(
        _ preview: HolidayNoticeUpdatePreview,
        to store: any HolidayDatasetStoring,
        metadataStore: any HolidayUpdateMetadataStoring,
        updatedAt: Date = Date()
    ) throws -> HolidayUpdateApplyResult {
        let dataset = try apply(preview, to: store)
        do {
            let current = try metadataStore.loadMetadata()
            try metadataStore.saveMetadata(HolidayUpdateMetadata(lastCheckedAt: current.lastCheckedAt, lastUpdatedAt: updatedAt))
            return HolidayUpdateApplyResult(dataset: dataset, metadataWasSaved: true)
        } catch {
            return HolidayUpdateApplyResult(dataset: dataset, metadataWasSaved: false)
        }
    }

    private func merge(currentDataset: HolidayDataset, notice: HolidayNotice, records: [HolidayRecord]) -> HolidayDataset {
        let targetYear = notice.year
        let existingRecords = currentDataset.records.filter { $0.date.year != targetYear }
        let existingNotices = currentDataset.notices.filter { $0.year != targetYear }
        return HolidayDataset(
            version: "\(targetYear).1",
            coveredYears: (Set(currentDataset.coveredYears).union([targetYear])).sorted(),
            notices: (existingNotices + [notice]).sorted { $0.year < $1.year },
            records: (existingRecords + records).sorted { $0.date < $1.date }
        )
    }

    private static func downloadDateString(now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

public enum ICloudHolidayCalendarURL {
    public static func validate(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "calendars.icloud.com",
              url.path == "/holidays/cn_zh.ics" else {
            throw HolidayUpdateError.invalidCalendarSource
        }
    }
}

/// 为兼容内置历史数据与 iCloud 更新记录而保留的来源校验入口。
public enum HolidayOfficialURL {
    public static func validate(_ url: URL) throws {
        if (try? validateGovernmentNotice(url)) != nil { return }
        try ICloudHolidayCalendarURL.validate(url)
    }

    static func validateGovernmentNotice(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "www.gov.cn",
              url.path.hasPrefix("/zhengce/zhengceku/"),
              url.path.lowercased().contains("content_") else {
            throw HolidayUpdateError.invalidDataset("官方通知地址无效")
        }
    }
}

private enum ICloudHolidayCalendarParser {
    private static let holidayOrder = ["元旦", "春节", "清明节", "劳动节", "端午节", "中秋节", "国庆节"]

    static func records(in data: Data, year: Int) throws -> [HolidayRecord] {
        guard let content = String(data: data, encoding: .utf8) else {
            throw HolidayUpdateError.invalidCalendar("不是 UTF-8 文本")
        }
        let events = events(in: unfoldedLines(content))
        var holidays = [CivilDate: Set<String>]()
        var workdays = [CivilDate: Set<String>]()

        for event in events {
            guard let specialDay = event["X-APPLE-SPECIAL-DAY"],
                  let summary = event["SUMMARY"],
                  let name = normalizedHolidayName(summary),
                  let start = civilDate(event["DTSTART"]) else {
                continue
            }
            let kind: HolidayKind
            switch specialDay {
            case "WORK-HOLIDAY": kind = .holiday
            case "ALTERNATE-WORKDAY": kind = .adjustedWorkday
            default: continue
            }
            let dates: [CivilDate]
            if kind == .holiday {
                let end = event["DTEND"].flatMap(civilDate)
                dates = try holidayDates(start: start, exclusiveEnd: end)
            } else {
                dates = [start]
            }
            for date in dates where date.year == year {
                switch kind {
                case .holiday: holidays[date, default: []].insert(name)
                case .adjustedWorkday: workdays[date, default: []].insert(name)
                }
            }
        }

        guard Set(holidays.values.flatMap { $0 }) == Set(holidayOrder) else {
            throw HolidayUpdateError.incompleteArrangement(year: year)
        }
        guard Set(holidays.keys).isDisjoint(with: Set(workdays.keys)) else {
            throw HolidayUpdateError.invalidCalendar("同一天同时标记为放假和补班")
        }

        let holidayRecords = holidays.map { date, names in
            HolidayRecord(date: date, name: combinedName(names), kind: .holiday)
        }
        let workdayRecords = workdays.map { date, names in
            HolidayRecord(date: date, name: "\(combinedName(names))调休", kind: .adjustedWorkday)
        }
        return (holidayRecords + workdayRecords).sorted { $0.date < $1.date }
    }

    private static func unfoldedLines(_ content: String) -> [String] {
        content.split(whereSeparator: \.isNewline).reduce(into: [String]()) { lines, line in
            let value = String(line)
            if value.first == " " || value.first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += String(value.dropFirst())
            } else {
                lines.append(value)
            }
        }
    }

    private static func events(in lines: [String]) -> [[String: String]] {
        var result = [[String: String]]()
        var event: [String: String]?
        for line in lines {
            if line == "BEGIN:VEVENT" {
                event = [:]
            } else if line == "END:VEVENT" {
                if let event { result.append(event) }
                event = nil
            } else if event != nil, let separator = line.firstIndex(of: ":") {
                let key = String(line[..<separator]).split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
                event?[key] = String(line[line.index(after: separator)...])
            }
        }
        return result
    }

    private static func civilDate(_ value: String?) -> CivilDate? {
        guard let value else { return nil }
        let digits = value.prefix(8)
        guard digits.count == 8,
              let year = Int(digits.prefix(4)),
              let month = Int(digits.dropFirst(4).prefix(2)),
              let day = Int(digits.suffix(2)) else { return nil }
        let date = CivilDate(year: year, month: month, day: day)
        return HolidayDatasetValidator.isValid(date) ? date : nil
    }

    private static func holidayDates(start: CivilDate, exclusiveEnd: CivilDate?) throws -> [CivilDate] {
        guard let exclusiveEnd else { return [start] }
        guard start < exclusiveEnd else {
            throw HolidayUpdateError.invalidCalendar("放假区间结束日期无效")
        }
        let calendar = Calendar(identifier: .gregorian)
        guard let startDate = start.date(in: calendar), let endDate = exclusiveEnd.date(in: calendar) else {
            throw HolidayUpdateError.invalidCalendar("放假区间日期无效")
        }
        var result = [CivilDate]()
        var current = startDate
        while current < endDate {
            if let date = CivilDate(current, calendar: calendar) { result.append(date) }
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return result
    }

    private static func normalizedHolidayName(_ summary: String) -> String? {
        let base = summary
            .replacingOccurrences(of: "（休）", with: "")
            .replacingOccurrences(of: "（班）", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch base {
        case "清明": return "清明节"
        case "元旦", "春节", "劳动节", "端午节", "中秋节", "国庆节": return base
        default: return nil
        }
    }

    private static func combinedName(_ names: Set<String>) -> String {
        names.sorted {
            (holidayOrder.firstIndex(of: $0) ?? holidayOrder.count) < (holidayOrder.firstIndex(of: $1) ?? holidayOrder.count)
        }.joined(separator: "、")
    }
}
