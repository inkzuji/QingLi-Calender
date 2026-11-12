import Foundation

public protocol HolidayDatasetStoring: Sendable {
    func loadCached() throws -> HolidayDataset?
    func save(_ dataset: HolidayDataset) throws
}

/// 用户最后一次检查日历，以及最后一次确认导入数据的时间。
public struct HolidayUpdateMetadata: Codable, Equatable, Sendable {
    public let lastCheckedAt: Date?
    public let lastUpdatedAt: Date?

    public init(lastCheckedAt: Date? = nil, lastUpdatedAt: Date? = nil) {
        self.lastCheckedAt = lastCheckedAt
        self.lastUpdatedAt = lastUpdatedAt
    }
}

public protocol HolidayUpdateMetadataStoring: Sendable {
    func loadMetadata() throws -> HolidayUpdateMetadata
    func saveMetadata(_ metadata: HolidayUpdateMetadata) throws
}

/// 与完整数据集置于同一 App Group 容器的更新状态文件。
public struct HolidayUpdateMetadataStore: HolidayUpdateMetadataStoring, Sendable {
    public static let filename = "holiday-update-metadata.json"

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func appGroup(fileManager: FileManager = .default) throws -> HolidayUpdateMetadataStore {
        guard let directory = fileManager.containerURL(forSecurityApplicationGroupIdentifier: HolidayDatasetStore.appGroupIdentifier) else {
            throw HolidayUpdateError.unavailableSharedContainer
        }
        return HolidayUpdateMetadataStore(fileURL: directory.appendingPathComponent(filename, isDirectory: false))
    }

    public func loadMetadata() throws -> HolidayUpdateMetadata {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return HolidayUpdateMetadata() }
        return try JSONDecoder().decode(HolidayUpdateMetadata.self, from: Data(contentsOf: fileURL))
    }

    public func saveMetadata(_ metadata: HolidayUpdateMetadata) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata).write(to: fileURL, options: .atomic)
    }

    public func markChecked(at date: Date = Date()) throws {
        let current = try loadMetadata()
        try saveMetadata(HolidayUpdateMetadata(lastCheckedAt: date, lastUpdatedAt: current.lastUpdatedAt))
    }
}

/// App 与小组件共用的完整节假日数据集文件。
public struct HolidayDatasetStore: HolidayDatasetStoring, Sendable {
    public static let appGroupIdentifier = "group.com.qingli.app"
    public static let filename = "holiday-dataset-v2.json"
    public static let legacyFilename = "holiday-dataset.json"

    public let fileURL: URL
    private let legacyFileURL: URL?

    public init(fileURL: URL, legacyFileURL: URL? = nil) {
        self.fileURL = fileURL
        self.legacyFileURL = legacyFileURL
    }

    public static func appGroup(fileManager: FileManager = .default) throws -> HolidayDatasetStore {
        guard let directory = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw HolidayUpdateError.unavailableSharedContainer
        }
        return HolidayDatasetStore(
            fileURL: directory.appendingPathComponent(filename, isDirectory: false),
            legacyFileURL: directory.appendingPathComponent(legacyFilename, isDirectory: false)
        )
    }

    public func loadCached() throws -> HolidayDataset? {
        guard let legacyFileURL else { return try load(fileURL) }
        if let current = try? load(fileURL, schemaVersion: 2) {
            return current
        }
        return try load(legacyFileURL, schemaVersion: 1)
    }

    public func save(_ dataset: HolidayDataset) throws {
        try HolidayDatasetValidator.validate(dataset)
        let current = dataset.migrated()
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(current).write(to: fileURL, options: .atomic)
    }

    private func load(_ url: URL, schemaVersion: Int? = nil) throws -> HolidayDataset? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let dataset = try JSONDecoder().decode(HolidayDataset.self, from: Data(contentsOf: url))
        if let schemaVersion, dataset.schemaVersion != schemaVersion {
            throw HolidayUpdateError.invalidDataset("文件版本与预期不符")
        }
        try HolidayDatasetValidator.validate(dataset)
        return dataset
    }
}
