import Foundation

public enum HolidayUpdateError: LocalizedError, Equatable, Sendable {
    case invalidCalendarSource
    case unexpectedHTTPStatus(Int)
    case incompleteArrangement(year: Int)
    case invalidCalendar(String)
    case invalidDataset(String)
    case unavailableSharedContainer

    public var errorDescription: String? {
        switch self {
        case .invalidCalendarSource:
            return "仅支持 iCloud 中国大陆节假日日历"
        case let .unexpectedHTTPStatus(status):
            return "节假日日历返回了无法处理的状态（\(status)）"
        case let .incompleteArrangement(year):
            return "iCloud 日历尚未提供 \(year) 年完整的节假日安排，未保存任何数据"
        case let .invalidCalendar(reason):
            return "节假日日历解析失败：\(reason)"
        case let .invalidDataset(reason):
            return "节假日数据校验失败：\(reason)"
        case .unavailableSharedContainer:
            return "无法访问共享节假日数据容器"
        }
    }
}

public struct HolidayHTTPResponse: Sendable {
    public let url: URL
    public let data: Data
    public let statusCode: Int

    public init(url: URL, data: Data, statusCode: Int) {
        self.url = url
        self.data = data
        self.statusCode = statusCode
    }
}

public protocol HolidayHTTPClient: Sendable {
    func data(for url: URL) async throws -> HolidayHTTPResponse
}

public struct URLSessionHolidayHTTPClient: HolidayHTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for url: URL) async throws -> HolidayHTTPResponse {
        var request = URLRequest(url: url)
        request.setValue("QingLi/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HolidayUpdateError.invalidCalendar("响应不是 HTTP")
        }
        return HolidayHTTPResponse(url: httpResponse.url ?? url, data: data, statusCode: httpResponse.statusCode)
    }
}
