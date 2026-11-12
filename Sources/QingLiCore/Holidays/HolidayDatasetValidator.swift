import Foundation

public enum HolidayDatasetValidator {
    public static func validate(_ dataset: HolidayDataset) throws {
        guard (1...2).contains(dataset.schemaVersion) else {
            throw HolidayUpdateError.invalidDataset("不支持的文件版本")
        }
        guard !dataset.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HolidayUpdateError.invalidDataset("版本不能为空")
        }
        let years = Set(dataset.coveredYears)
        guard !years.isEmpty, years.count == dataset.coveredYears.count else {
            throw HolidayUpdateError.invalidDataset("覆盖年份不能为空且不能重复")
        }
        if dataset.schemaVersion == 1 {
            try validateLegacyNotices(dataset.notices, years: years)
        } else {
            try validateYearSources(dataset.yearSources, years: years)
        }
        var dates = Set<CivilDate>()
        for record in dataset.records {
            guard years.contains(record.date.year) else {
                throw HolidayUpdateError.invalidDataset("日期 \(record.date) 不在覆盖年份中")
            }
            guard isValid(record.date) else {
                throw HolidayUpdateError.invalidDataset("日期 \(record.date) 不合法")
            }
            guard !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HolidayUpdateError.invalidDataset("节假日名称不能为空")
            }
            guard dates.insert(record.date).inserted else {
                throw HolidayUpdateError.invalidDataset("存在重复日期 \(record.date)")
            }
        }
    }

    private static func validateLegacyNotices(_ notices: [HolidayNotice], years: Set<Int>) throws {
        let noticeYears = Set(notices.map(\.year))
        guard noticeYears == years, notices.count == noticeYears.count else {
            throw HolidayUpdateError.invalidDataset("通知年份与覆盖年份不一致")
        }
        for notice in notices {
            try HolidayOfficialURL.validate(notice.sourceURL)
            try validateNoticeText(notice)
        }
    }

    private static func validateYearSources(_ sources: [Int: HolidayYearSource], years: Set<Int>) throws {
        guard Set(sources.keys) == years else {
            throw HolidayUpdateError.invalidDataset("来源年份与覆盖年份不一致")
        }
        for (year, source) in sources {
            guard !source.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HolidayUpdateError.invalidDataset("订阅来源名称不能为空")
            }
            for url in [source.requestURL, source.finalURL].compactMap({ $0 }) {
                guard (try? HolidaySubscription.validateHTTPS(url)) != nil else {
                    throw HolidayUpdateError.invalidDataset("订阅来源地址无效")
                }
            }
            if let notice = source.officialNotice {
                guard notice.year == year else {
                    throw HolidayUpdateError.invalidDataset("通知年份与来源年份不一致")
                }
                try HolidayOfficialURL.validateGovernmentNotice(notice.sourceURL)
                try validateNoticeText(notice)
            }
        }
    }

    private static func validateNoticeText(_ notice: HolidayNotice) throws {
        guard !notice.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !notice.publishedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HolidayUpdateError.invalidDataset("通知信息不完整")
        }
    }

    static func isValid(_ date: CivilDate) -> Bool {
        guard (1...12).contains(date.month), date.day > 0 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        guard let firstDay = calendar.date(from: DateComponents(year: date.year, month: date.month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: firstDay) else { return false }
        return range.contains(date.day)
    }
}
