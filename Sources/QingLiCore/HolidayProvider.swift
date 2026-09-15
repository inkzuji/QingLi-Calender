import Foundation

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
}

public struct HolidayNotice: Codable, Hashable, Sendable {
    public let year: Int
    public let title: String
    public let publishedAt: String
    public let sourceURL: URL
}

public struct HolidayDataset: Codable, Sendable {
    public let version: String
    public let coveredYears: [Int]
    public let notices: [HolidayNotice]
    public let records: [HolidayRecord]
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
        guard let url = bundle.url(forResource: "holidays", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let bundled = try JSONDecoder().decode(HolidayDataset.self, from: Data(contentsOf: url))
        try HolidayDatasetValidator.validate(bundled)
        var preferred = bundled
        let resolvedStore = store ?? (try? HolidayDatasetStore.appGroup())
        if let resolvedStore, let cached = try? resolvedStore.loadCached() {
            preferred = cached
        }
        self.init(dataset: preferred)
    }

    public func holiday(on date: CivilDate) -> HolidayRecord? { lookup[date] }
    public func isCovered(year: Int) -> Bool { dataset.coveredYears.contains(year) }
    public func notice(for year: Int) -> HolidayNotice? { dataset.notices.first { $0.year == year } }
}

private final class QingLiCoreBundleToken {}

private let qingLiCoreBundle: Bundle = {
    #if SWIFT_PACKAGE
    return .module
    #else
    return Bundle(for: QingLiCoreBundleToken.self)
    #endif
}()
