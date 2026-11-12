import Foundation
import Testing
@testable import QingLiCore

@Suite("共享节假日缓存")
struct HolidayDatasetStoreTests {
    @Test("旧缓存只读迁移，确认后原子保存数据和逐年来源")
    func migratesLegacyCacheAndPreservesIt() throws {
        let files = try makeFiles()
        defer { try? FileManager.default.trashItem(at: files.directory, resultingItemURL: nil) }
        let legacy = legacyDataset()
        let legacyBytes = try JSONEncoder().encode(legacy)
        try legacyBytes.write(to: files.legacyURL)

        let loaded = try #require(try files.store.loadCached())
        let migratedApple = try #require(loaded.yearSources[2027])
        #expect(loaded.records == legacy.records)
        #expect(loaded.revision == legacy.revision)
        #expect(migratedApple.requestURL == ICloudHolidayCalendarUpdater.calendarURL)
        #expect(migratedApple.officialNotice == nil)
        #expect(migratedApple.downloadedAt == nil)
        #expect(migratedApple.importedAt == nil)
        #expect(!FileManager.default.fileExists(atPath: files.store.fileURL.path))

        let url = try #require(URL(string: "https://example.com/holidays"))
        let source = HolidayYearSource(
            name: "自定义订阅",
            requestURL: url,
            finalURL: url,
            downloadedAt: Date(timeIntervalSince1970: 100),
            importedAt: Date(timeIntervalSince1970: 200)
        )
        let current = HolidayDataset(
            revision: "confirmed",
            coveredYears: loaded.coveredYears,
            records: loaded.records,
            yearSources: [2027: migratedApple, 2028: source],
            lastUpdatedAt: source.importedAt
        )
        try files.store.save(current)

        let reloaded = try #require(try files.store.loadCached())
        #expect(reloaded.schemaVersion == 2)
        #expect(reloaded.revision == current.revision)
        #expect(reloaded.records == current.records)
        #expect(reloaded.yearSources == current.yearSources)
        #expect(reloaded.lastUpdatedAt == current.lastUpdatedAt)
        #expect(try Data(contentsOf: files.legacyURL) == legacyBytes)
    }

    @Test("无效 V2 缓存回退到旧缓存，无效旧缓存回退到内置数据")
    func fallsBackFromInvalidCaches() throws {
        let files = try makeFiles()
        defer { try? FileManager.default.trashItem(at: files.directory, resultingItemURL: nil) }
        let legacy = legacyDataset()
        try JSONEncoder().encode(legacy).write(to: files.legacyURL)
        let invalid = HolidayDataset(
            revision: "invalid",
            coveredYears: legacy.coveredYears,
            records: legacy.records,
            yearSources: [2027: try #require(legacy.yearSources[2027])],
            lastUpdatedAt: nil
        )
        try JSONEncoder().encode(invalid).write(to: files.store.fileURL)
        #expect(try files.store.loadCached()?.schemaVersion == 1)

        let unknown = HolidayNotice(
            year: 2027,
            title: "未知来源",
            publishedAt: "2026-11-12",
            sourceURL: try #require(URL(string: "https://example.com"))
        )
        try JSONEncoder().encode(legacyDataset(replacingNotice: unknown)).write(to: files.legacyURL)
        let bundled = try HolidayProvider(bundle: testBundle, store: files.store)
        #expect(bundled.holidayDataset.coveredYears == [2025, 2026])
        #expect(bundled.notice(for: 2025)?.publishedAt == "2024-11-12")
    }

    private func makeFiles() throws -> (directory: URL, legacyURL: URL, store: HolidayDatasetStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyURL = directory.appendingPathComponent(HolidayDatasetStore.legacyFilename)
        let store = HolidayDatasetStore(
            fileURL: directory.appendingPathComponent(HolidayDatasetStore.filename),
            legacyFileURL: legacyURL
        )
        return (directory, legacyURL, store)
    }

    private func legacyDataset(replacingNotice notice: HolidayNotice? = nil) -> HolidayDataset {
        let years = [2027, 2028]
        let notices = years.map { year in
            if let notice, notice.year == year { return notice }
            return HolidayNotice(
                year: year,
                title: "iCloud 中国大陆节假日日历",
                publishedAt: "2026-11-12",
                sourceURL: ICloudHolidayCalendarUpdater.calendarURL
            )
        }
        return HolidayDataset(
            version: "2028.1",
            coveredYears: years,
            notices: notices,
            records: years.map { year in
                HolidayRecord(date: CivilDate(year: year, month: 1, day: 1), name: "元旦", kind: .holiday)
            }
        )
    }
}

private final class HolidayDatasetStoreTestsBundleToken {}

private let testBundle: Bundle = {
    #if SWIFT_PACKAGE
    return .module
    #else
    return Bundle(for: HolidayDatasetStoreTestsBundleToken.self)
    #endif
}()
