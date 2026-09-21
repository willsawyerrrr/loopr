import Foundation

public enum RouteServiceError: LocalizedError, Sendable {
    case server(status: Int, message: String, detail: String?)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .server(_, let message, let detail):
            detail.map { "\(message): \($0)" } ?? message
        case .invalidResponse:
            "The server returned an unreadable response."
        }
    }
}

/// Calls the runna-router API. Reusable from the app UI and from App Intents.
public struct RouteService: Sendable {
    public static let defaultBaseURL = URL(string: "https://runna-router.willsawyerrrr.dev")!

    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let baseURL: URL
    private let timeout: TimeInterval
    private let transport: Transport

    public init(
        baseURL: URL = RouteService.defaultBaseURL,
        timeout: TimeInterval = 60,
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.transport = transport
    }

    public func generate(_ request: RouteRequest) async throws -> RouteResponse {
        var urlRequest = URLRequest(url: baseURL.appending(path: "api/route"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await transport(urlRequest)
        guard let http = response as? HTTPURLResponse else { throw RouteServiceError.invalidResponse }

        guard (200..<300).contains(http.statusCode) else {
            if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
                throw RouteServiceError.server(status: http.statusCode, message: body.error, detail: body.detail)
            }
            throw RouteServiceError.server(status: http.statusCode, message: "Request failed (\(http.statusCode))", detail: nil)
        }
        do {
            return try JSONDecoder().decode(RouteResponse.self, from: data)
        } catch {
            throw RouteServiceError.invalidResponse
        }
    }
}
