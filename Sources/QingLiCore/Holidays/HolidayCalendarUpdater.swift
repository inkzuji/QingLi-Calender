import Foundation

public struct HolidaySubscription: Codable, Equatable, Sendable {
    public static let recommended = HolidaySubscription(
        name: "中国节假日日历",
        url: URL(string: "https://cdn.jsdelivr.net/gh/lanceliao/china-holiday-calender/holidayCal.ics")!
    )
    public static let projectURL = URL(string: "https://github.com/lanceliao/china-holiday-calender")!

    public let name: String
    public let url: URL

    public init(name: String, address: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60 else {
            throw HolidaySubscriptionError.invalidName
        }
        self.init(name: name, url: try Self.normalizedURL(for: address))
    }

    public static func normalizedURL(for address: String) throws -> URL {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: address) else {
            throw HolidaySubscriptionError.invalidAddress
        }
        switch components.scheme?.lowercased() {
        case "https", "webcal": components.scheme = "https"
        default: throw HolidaySubscriptionError.invalidAddress
        }
        components.host = components.host?.lowercased()
        components.fragment = nil
        guard let url = components.url else { throw HolidaySubscriptionError.invalidAddress }
        try validateHTTPS(url)
        return url
    }

    private init(name: String, url: URL) {
        self.name = name
        self.url = url
    }

    static func validateHTTPS(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https",
              let host = url.host(), !host.isEmpty,
              url.user() == nil, url.password() == nil else {
            throw HolidaySubscriptionError.invalidAddress
        }
    }
}

public enum HolidaySubscriptionError: LocalizedError, Equatable, Sendable {
    case invalidName
    case invalidAddress
    case responseTooLarge
    case stalePreview
    case invalidSelection

    public var errorDescription: String? {
        switch self {
        case .invalidName: return "请输入 1 至 60 个字符的订阅名称"
        case .invalidAddress: return "请输入有效的 HTTPS 或 webcal 订阅地址，订阅下载须全程使用 HTTPS"
        case .responseTooLarge: return "订阅文件超过 2 MB"
        case .stalePreview: return "节假日数据已变更，请重新检查更新"
        case .invalidSelection: return "请选择通过检查的年份"
        }
    }
}

/// 以流式方式读取响应，并在达到体积限制时停止下载。
public struct HTTPSHolidaySubscriptionClient: HolidayHTTPClient {
    private static let maximumBytes = 2 * 1024 * 1024

    public init() {}

    public func data(for url: URL) async throws -> HolidayHTTPResponse {
        try HolidaySubscription.validateHTTPS(url)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration, delegate: HTTPSRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("QingLi/1.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, let finalURL = response.url else {
            throw HolidayUpdateError.invalidCalendar("响应不是 HTTP")
        }
        try HolidaySubscription.validateHTTPS(finalURL)
        guard (200..<300).contains(response.statusCode), response.statusCode != 206 else {
            throw HolidayUpdateError.unexpectedHTTPStatus(response.statusCode)
        }
        guard response.expectedContentLength <= Self.maximumBytes else {
            throw HolidaySubscriptionError.responseTooLarge
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(Int(response.expectedContentLength))
        }
        for try await byte in bytes {
            guard data.count < Self.maximumBytes else { throw HolidaySubscriptionError.responseTooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        return HolidayHTTPResponse(url: finalURL, data: data, statusCode: response.statusCode)
    }
}

private final class HTTPSRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url, (try? HolidaySubscription.validateHTTPS(url)) != nil else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

public enum HolidayDateChangeKind: Sendable {
    case added, modified, removed
}

public struct HolidayDateChange: Identifiable, Sendable {
    public let date: CivilDate
    public let before: HolidayRecord?
    public let after: HolidayRecord?

    public var id: CivilDate { date }
    public var kind: HolidayDateChangeKind {
        if before == nil { return .added }
        if after == nil { return .removed }
        return .modified
    }
}

public enum HolidayYearUpdateStatus: Sendable {
    case added, revised, sourceOnly, unchanged, invalid
}

public struct HolidayYearUpdate: Identifiable, Sendable {
    public let year: Int
    public let records: [HolidayRecord]
    public let changes: [HolidayDateChange]
    public let status: HolidayYearUpdateStatus
    public let failureReason: String?
    public let totalsWereVerified: Bool

    public var id: Int { year }
    public var isSelectable: Bool {
        switch status {
        case .added, .revised, .sourceOnly: return true
        case .unchanged, .invalid: return false
        }
    }
}

public struct HolidaySubscriptionPreview: Sendable {
    public let subscription: HolidaySubscription
    public let finalURL: URL
    public let downloadedAt: Date
    public let baseRevision: String
    public let years: [HolidayYearUpdate]
}

public struct HolidayCalendarUpdater: Sendable {
    private let client: any HolidayHTTPClient

    public init(client: any HolidayHTTPClient = HTTPSHolidaySubscriptionClient()) {
        self.client = client
    }

    public func prepareUpdate(
        subscription: HolidaySubscription,
        currentDataset: HolidayDataset,
        currentYear: Int,
        downloadedAt: Date? = nil
    ) async throws -> HolidaySubscriptionPreview {
        try HolidayDatasetValidator.validate(currentDataset)
        try HolidaySubscription.validateHTTPS(subscription.url)
        let response = try await client.data(for: subscription.url)
        try Task.checkCancellation()
        try HolidaySubscription.validateHTTPS(response.url)
        guard (200..<300).contains(response.statusCode), response.statusCode != 206 else {
            throw HolidayUpdateError.unexpectedHTTPStatus(response.statusCode)
        }
        let downloadedAt = downloadedAt ?? .now
        let parsedYears = try HolidayICSParser.years(in: response.data, startingAt: currentYear)
        let currentYears = Dictionary(grouping: currentDataset.records, by: \.date.year)
        let years = parsedYears.map { parsed in
            compare(
                parsed,
                existing: currentYears[parsed.year, default: []],
                source: currentDataset.yearSources[parsed.year],
                subscription: subscription,
                finalURL: response.url
            )
        }
        return HolidaySubscriptionPreview(
            subscription: subscription,
            finalURL: response.url,
            downloadedAt: downloadedAt,
            baseRevision: currentDataset.revision,
            years: years
        )
    }

    public func applying(
        _ preview: HolidaySubscriptionPreview,
        selectedYears: Set<Int>,
        to currentDataset: HolidayDataset,
        importedAt: Date = .now
    ) throws -> HolidayDataset {
        guard preview.baseRevision == currentDataset.revision else { throw HolidaySubscriptionError.stalePreview }
        let selected = preview.years.filter { selectedYears.contains($0.year) && $0.isSelectable }
        guard !selected.isEmpty, selected.count == selectedYears.count else {
            throw HolidaySubscriptionError.invalidSelection
        }
        let source = HolidayYearSource(
            name: preview.subscription.name,
            requestURL: preview.subscription.url,
            finalURL: preview.finalURL,
            downloadedAt: preview.downloadedAt,
            importedAt: importedAt
        )
        var sources = currentDataset.yearSources
        for year in selectedYears { sources[year] = source }
        let records = currentDataset.records.filter { !selectedYears.contains($0.date.year) } + selected.flatMap(\.records)
        let dataset = HolidayDataset(
            revision: UUID().uuidString,
            coveredYears: Set(currentDataset.coveredYears).union(selectedYears).sorted(),
            records: records.sorted { $0.date < $1.date },
            yearSources: sources,
            lastUpdatedAt: importedAt
        )
        try HolidayDatasetValidator.validate(dataset)
        return dataset
    }

    private func compare(
        _ parsed: HolidayICSParser.Year,
        existing: [HolidayRecord],
        source: HolidayYearSource?,
        subscription: HolidaySubscription,
        finalURL: URL
    ) -> HolidayYearUpdate {
        if let failureReason = parsed.failureReason {
            return HolidayYearUpdate(
                year: parsed.year, records: [], changes: [], status: .invalid,
                failureReason: failureReason, totalsWereVerified: false
            )
        }
        let before = Dictionary(uniqueKeysWithValues: existing.map { ($0.date, $0) })
        let after = Dictionary(uniqueKeysWithValues: parsed.records.map { ($0.date, $0) })
        let changes = Set(before.keys).union(after.keys).sorted().compactMap { date -> HolidayDateChange? in
            guard before[date] != after[date] else { return nil }
            return HolidayDateChange(date: date, before: before[date], after: after[date])
        }
        let sameSource = source?.name == subscription.name && source?.requestURL == subscription.url && source?.finalURL == finalURL
        let status: HolidayYearUpdateStatus
        if source == nil { status = .added }
        else if !changes.isEmpty { status = .revised }
        else { status = sameSource ? .unchanged : .sourceOnly }
        return HolidayYearUpdate(
            year: parsed.year, records: parsed.records, changes: changes, status: status,
            failureReason: nil, totalsWereVerified: parsed.totalsWereVerified
        )
    }
}
