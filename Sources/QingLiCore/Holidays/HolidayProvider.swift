import Foundation
import CryptoKit

public enum HolidayKind: String, Codable, Sendable {
    case holiday
    case adjustedWorkday

    public var label: String { self == .holiday ? "休" : "班" }
    public var accessibilityLabel: String { self == .holiday ? "法定放假日" : "调休补班日" }
}

public struct HolidayRecord: Codable, Hashable, Sendable {
    public let date: CivilDate
    public let name: String
    public let kind: HolidayKind

    public init(date: CivilDate, name: String, kind: HolidayKind) {
        self.date = date
        self.name = name
        self.kind = kind
    }
}

public struct HolidayNotice: Codable, Hashable, Sendable {
    public let year: Int
    public let title: String
    public let publishedAt: String
    public let sourceURL: URL
}

public struct HolidayYearSource: Codable, Hashable, Sendable {
    public let name: String
    public let requestURL: URL?
    public let finalURL: URL?
    public let downloadedAt: Date?
    public let importedAt: Date?
    public let officialNotice: HolidayNotice?

    public init(
        name: String,
        requestURL: URL? = nil,
        finalURL: URL? = nil,
        downloadedAt: Date? = nil,
        importedAt: Date? = nil,
        officialNotice: HolidayNotice? = nil
    ) {
        self.name = name
        self.requestURL = requestURL
        self.finalURL = finalURL
        self.downloadedAt = downloadedAt
        self.importedAt = importedAt
        self.officialNotice = officialNotice
    }
}

public struct HolidayDataset: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case storedSchemaVersion = "schemaVersion"
        case storedRevision = "revision"
        case storedYearSources = "yearSources"
        case legacyVersion = "version"
        case legacyNotices = "notices"
        case coveredYears, records, lastUpdatedAt
    }

    private let storedSchemaVersion: Int?
    private let storedRevision: String?
    private let storedYearSources: [Int: HolidayYearSource]?
    private let legacyVersion: String?
    private let legacyNotices: [HolidayNotice]?
    public let coveredYears: [Int]
    public let records: [HolidayRecord]
    public let lastUpdatedAt: Date?
    public var schemaVersion: Int { storedSchemaVersion ?? 1 }

    public var version: String {
        (schemaVersion == 1 ? legacyVersion : storedRevision) ?? ""
    }

    public var revision: String {
        guard schemaVersion == 1 else { return version }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self) else { return version }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public var notices: [HolidayNotice] {
        if schemaVersion == 1 { return legacyNotices ?? [] }
        return coveredYears.compactMap { storedYearSources?[$0]?.officialNotice }
    }

    public var yearSources: [Int: HolidayYearSource] {
        guard schemaVersion == 1 else { return storedYearSources ?? [:] }
        let sources = notices.map { notice in
            let source: HolidayYearSource
            if (try? ICloudHolidayCalendarURL.validate(notice.sourceURL)) != nil {
                // 旧格式将下载日放在公告发布日期中。迁移时保留来源，时间留空。
                source = HolidayYearSource(name: notice.title, requestURL: ICloudHolidayCalendarUpdater.calendarURL)
            } else {
                source = HolidayYearSource(name: "内置 · 国务院通知", officialNotice: notice)
            }
            return (notice.year, source)
        }
        return Dictionary(sources, uniquingKeysWith: { first, _ in first })
    }

    init(version: String, coveredYears: [Int], notices: [HolidayNotice], records: [HolidayRecord]) {
        storedSchemaVersion = nil
        storedRevision = nil
        storedYearSources = nil
        legacyVersion = version
        legacyNotices = notices
        self.coveredYears = coveredYears
        self.records = records
        lastUpdatedAt = nil
    }

    public init(
        revision: String,
        coveredYears: [Int],
        records: [HolidayRecord],
        yearSources: [Int: HolidayYearSource],
        lastUpdatedAt: Date?
    ) {
        storedSchemaVersion = 2
        storedRevision = revision
        storedYearSources = yearSources
        legacyVersion = nil
        legacyNotices = nil
        self.coveredYears = coveredYears
        self.records = records
        self.lastUpdatedAt = lastUpdatedAt
    }

    func migrated() -> HolidayDataset {
        guard schemaVersion == 1 else { return self }
        return HolidayDataset(
            revision: revision,
            coveredYears: coveredYears,
            records: records,
            yearSources: yearSources,
            lastUpdatedAt: nil
        )
    }
}

public protocol HolidayProviding: Sendable {
    func holiday(on date: CivilDate) -> HolidayRecord?
    func isCovered(year: Int) -> Bool
    func notice(for year: Int) -> HolidayNotice?
}

public struct HolidayProvider: HolidayProviding, Sendable {
    private let dataset: HolidayDataset

    public var holidayDataset: HolidayDataset { dataset }
    private let lookup: [CivilDate: HolidayRecord]

    public init(dataset: HolidayDataset) {
        self.dataset = dataset
        self.lookup = Dictionary(uniqueKeysWithValues: dataset.records.map { ($0.date, $0) })
    }

    public init() throws {
        try self.init(bundle: qingLiCoreBundle)
    }

    /// 共享容器内存在并且通过校验的数据优先于应用内置数据。
    public init(bundle: Bundle, store: (any HolidayDatasetStoring)? = nil) throws {
        let resolvedStore = store ?? (try? HolidayDatasetStore.appGroup())
        if let resolvedStore, let cached = try? resolvedStore.loadCached() {
            self.init(dataset: cached)
        } else {
            guard let url = bundle.url(forResource: "holidays", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let bundled = try JSONDecoder().decode(HolidayDataset.self, from: Data(contentsOf: url))
            try HolidayDatasetValidator.validate(bundled)
            self.init(dataset: bundled)
        }
    }

    public func holiday(on date: CivilDate) -> HolidayRecord? { lookup[date] }
    public func isCovered(year: Int) -> Bool { dataset.coveredYears.contains(year) }
    public func notice(for year: Int) -> HolidayNotice? { dataset.yearSources[year]?.officialNotice }
}

private final class QingLiCoreBundleToken {}

private let qingLiCoreBundle: Bundle = {
    #if SWIFT_PACKAGE
    return .module
    #else
    return Bundle(for: QingLiCoreBundleToken.self)
    #endif
}()
