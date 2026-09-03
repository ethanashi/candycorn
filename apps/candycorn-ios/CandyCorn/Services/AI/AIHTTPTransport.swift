import Foundation

actor URLSessionAIHTTPTransport: AIHTTPTransport {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.url != nil, request.httpMethod == "POST" else {
            throw AIProviderError.invalidInput
        }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }
        return (data, httpResponse)
    }
}

struct TaskAIBackoffSleeper: AIBackoffSleeping {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

struct SystemAIMonotonicClock: AIMonotonicClock {
    func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

struct NoOpAIEventLogger: AIEventLogging {
    func record(_ name: AIEventName, metrics: AIEventMetrics) {
        _ = name
        _ = metrics
    }
}
