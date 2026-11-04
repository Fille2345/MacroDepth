// Services/Nutrition/GeminiAPIClient.swift

import Foundation

/// Sends a `generateContent` request and returns the model's JSON text.
/// A backend proxy can replace the direct call by conforming to this protocol.
protocol GeminiAPIClient: Sendable {
    func generateContent(_ request: GeminiGenerateContentRequest) async throws -> String
}

/// Calls Gemini directly. The key goes in a header, never the URL, so it can't
/// end up in error messages or logs that include the URL.
struct URLSessionGeminiAPIClient: GeminiAPIClient {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    /// Gemini's limit for a request with inline images.
    static let maximumRequestBytes = 20_000_000
    static let maximumAttempts = 3
    /// A longer requested wait, such as a used-up daily quota, is reported to the user instead.
    static let maximumAutomaticWaitSeconds = 8.0
    static let requestTimeoutSeconds: TimeInterval = 60

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private let configuration: AppConfiguration
    private let transport: Transport
    private let sleep: Sleeper

    init(
        configuration: AppConfiguration,
        transport: @escaping Transport = { try await URLSessionGeminiAPIClient.session.data(for: $0) },
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.configuration = configuration
        self.transport = transport
        self.sleep = sleep
    }

    func generateContent(_ request: GeminiGenerateContentRequest) async throws -> String {
        let urlRequest = try makeURLRequest(for: request)
        var attempt = 1
        while true {
            try Task.checkCancellation()
            do {
                return try await send(urlRequest)
            } catch let error as NutritionServiceError {
                guard attempt < Self.maximumAttempts, let delay = Self.retryDelay(for: error, attempt: attempt) else {
                    throw error
                }
                try await sleep(delay)
                attempt += 1
            }
        }
    }

    // MARK: Private

    private func makeURLRequest(for request: GeminiGenerateContentRequest) throws -> URLRequest {
        let body = try JSONEncoder().encode(request)
        guard body.count <= Self.maximumRequestBytes else {
            throw NutritionServiceError.imageTooLarge(byteCount: body.count, limit: Self.maximumRequestBytes)
        }
        let url = configuration.apiBaseURL.appending(path: "models/\(configuration.modelID):generateContent")
        var urlRequest = URLRequest(url: url, timeoutInterval: Self.requestTimeoutSeconds)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = body
        return urlRequest
    }

    private func send(_ request: URLRequest) async throws -> String {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch let error as URLError {
            throw try Self.mapTransportError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NutritionServiceError.emptyResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw Self.mapStatus(
                httpResponse.statusCode,
                body: data,
                retryAfterHeader: httpResponse.value(forHTTPHeaderField: "Retry-After"),
                modelID: configuration.modelID
            )
        }

        do {
            return try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data).payloadText()
        } catch is DecodingError {
            throw NutritionServiceError.decodingFailed("the response wasn't in the expected format")
        }
    }

    private static func retryDelay(for error: NutritionServiceError, attempt: Int) -> Duration? {
        switch error {
        case .rateLimited(let seconds?):
            seconds <= maximumAutomaticWaitSeconds ? .seconds(seconds) : nil
        case .rateLimited(nil):
            backoff(attempt: attempt)
        case .httpStatus where error.isRetryable:
            backoff(attempt: attempt)
        default:
            nil
        }
    }

    /// 1 s, then 2 s, with jitter so clients don't all retry together.
    private static func backoff(attempt: Int) -> Duration {
        .seconds(pow(2, Double(attempt - 1)) + Double.random(in: 0...0.25))
    }

    private static func mapTransportError(_ error: URLError) throws -> NutritionServiceError {
        switch error.code {
        case .cancelled: throw CancellationError()
        case .timedOut: .timedOut
        // Everything else means the request couldn't reach Gemini: no network,
        // lost connection, DNS, TLS or a captive portal.
        default: .offline
        }
    }

    private static func mapStatus(
        _ status: Int,
        body: Data,
        retryAfterHeader: String?,
        modelID: String
    ) -> NutritionServiceError {
        // Error bodies vary between endpoints, so an unreadable one only loses the message.
        let details = (try? JSONDecoder().decode(GeminiAPIErrorBody.self, from: body))?.error
        let message = details?.message

        switch status {
        case 429:
            let retryAfter = retryAfterHeader.flatMap(Double.init) ?? details?.retryDelaySeconds
            return .rateLimited(retryAfterSeconds: retryAfter)
        case 401, 403:
            return .invalidConfiguration("Gemini rejected the API key or project. \(message ?? "")")
        case 400 where details?.hasInvalidAPIKeyReason == true:
            return .invalidConfiguration("Gemini rejected the API key. \(message ?? "")")
        case 404:
            return .invalidConfiguration("Gemini doesn't recognise the model \"\(modelID)\".")
        default:
            return .httpStatus(code: status, message: message)
        }
    }
}

/// The HTTP response envelope around the model's JSON text.
struct GeminiGenerateContentResponse: Decodable, Sendable {
    struct Candidate: Decodable, Sendable {
        struct Content: Decodable, Sendable {
            struct Part: Decodable, Sendable {
                let text: String?
                let thought: Bool?
            }

            let parts: [Part]?
        }

        let content: Content?
        let finishReason: String?
    }

    struct PromptFeedback: Decodable, Sendable {
        let blockReason: String?
    }

    /// Finish reasons meaning the content was refused, so retrying the same photo won't help.
    private static let blockingFinishReasons: Set<String> = [
        "SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII",
        "IMAGE_SAFETY", "IMAGE_PROHIBITED_CONTENT", "IMAGE_RECITATION",
    ]

    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?

    /// The model's answer. Only a complete response counts: JSON from any other
    /// finish reason may be cut off.
    func payloadText() throws -> String {
        if let reason = promptFeedback?.blockReason {
            throw NutritionServiceError.contentBlocked(reason: Self.describe(reason))
        }
        guard let candidate = candidates?.first else {
            throw NutritionServiceError.emptyResponse
        }

        switch candidate.finishReason {
        case nil, "STOP":
            break
        case "MAX_TOKENS":
            throw NutritionServiceError.decodingFailed("the response was cut off")
        case let reason? where Self.blockingFinishReasons.contains(reason):
            throw NutritionServiceError.contentBlocked(reason: Self.describe(reason))
        default:
            throw NutritionServiceError.emptyResponse
        }

        let text = (candidate.content?.parts ?? [])
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NutritionServiceError.emptyResponse
        }
        return text
    }

    private static func describe(_ reason: String) -> String {
        "Gemini declined it (\(reason))."
    }
}

/// Only the fields the app uses. `code` is left out because its type varies.
private struct GeminiAPIErrorBody: Decodable {
    struct Details: Decodable {
        struct Detail: Decodable {
            let reason: String?
            let retryDelay: String?
        }

        let message: String?
        let details: [Detail]?

        var hasInvalidAPIKeyReason: Bool {
            details?.contains { $0.reason == "API_KEY_INVALID" } ?? false
        }

        /// `retryDelay` looks like "17s".
        var retryDelaySeconds: Double? {
            details?.lazy.compactMap { detail in
                detail.retryDelay.flatMap { Double($0.replacingOccurrences(of: "s", with: "")) }
            }.first
        }
    }

    let error: Details
}
