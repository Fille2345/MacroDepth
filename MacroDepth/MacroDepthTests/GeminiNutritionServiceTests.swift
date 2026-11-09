// MacroDepthTests/GeminiNutritionServiceTests.swift

import Foundation
import Testing
@testable import MacroDepth

/// A queue of canned responses that records every request it receives.
private final class StubTransport: @unchecked Sendable {
    typealias Reply = Result<(status: Int, headers: [String: String], body: String), URLError>

    private let lock = NSLock()
    private var replies: [Reply]
    private var recordedRequests: [URLRequest] = []
    private var recordedSleeps: [Duration] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    var requests: [URLRequest] { lock.withLock { recordedRequests } }
    var sleeps: [Duration] { lock.withLock { recordedSleeps } }

    func makeClient(modelID: String = "gemini-test") -> URLSessionGeminiAPIClient {
        URLSessionGeminiAPIClient(
            configuration: AppConfiguration(apiKey: "AIzaSecretTestKey", modelID: modelID),
            transport: { [self] request in try respond(to: request) },
            sleep: { [self] duration in lock.withLock { recordedSleeps.append(duration) } }
        )
    }

    private func respond(to request: URLRequest) throws -> (Data, URLResponse) {
        let reply = lock.withLock {
            recordedRequests.append(request)
            return replies.removeFirst()
        }
        let value = try reply.get()
        let response = HTTPURLResponse(url: request.url!, statusCode: value.status, httpVersion: nil, headerFields: value.headers)!
        return (Data(value.body.utf8), response)
    }
}

private func reply(_ status: Int, _ body: String = "{}", headers: [String: String] = [:]) -> StubTransport.Reply {
    .success((status, headers, body))
}

/// A successful envelope containing `text` as the model's answer.
private func envelope(_ text: String, finishReason: String = "STOP") throws -> String {
    let object: [String: Any] = [
        "candidates": [["content": ["parts": [["text": text]]], "finishReason": finishReason]],
    ]
    return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

struct GeminiNutritionServiceTests {
    private let image = Data([0xFF, 0xD8, 0x01])

    private func detectionRequest() throws -> GeminiGenerateContentRequest {
        try .detection(images: [image], userNotes: nil)
    }

    private func thrownError(_ body: () async throws -> Void) async -> NutritionServiceError? {
        do {
            try await body()
            return nil
        } catch {
            return error as? NutritionServiceError
        }
    }

    // MARK: Request

    @Test func sendsThePostToTheModelEndpointWithTheKeyInAHeader() async throws {
        let stub = StubTransport([reply(200, try envelope(#"{"items":[]}"#))])
        _ = try await stub.makeClient().generateContent(try detectionRequest())

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-test:generateContent")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "AIzaSecretTestKey")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpBody?.isEmpty == false)
    }

    @Test func detectionRequestIncludesTheResponseSchema() throws {
        let data = try JSONEncoder().encode(try detectionRequest())
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let config = try #require(json["generation_config"] as? [String: Any])
        #expect(config["response_mime_type"] as? String == "application/json")

        let schema = try #require(config["response_schema"] as? [String: Any])
        #expect(schema["type"] as? String == "OBJECT")
        #expect(schema["required"] as? [String] == ["items"])

        let items = try #require((schema["properties"] as? [String: Any])?["items"] as? [String: Any])
        #expect(items["type"] as? String == "ARRAY")
        let item = try #require(items["items"] as? [String: Any])
        #expect(item["propertyOrdering"] as? [String] == ["label", "category", "box_2d", "confidence"])

        let properties = try #require(item["properties"] as? [String: Any])
        let category = try #require(properties["category"] as? [String: Any])
        #expect(category["enum"] as? [String] == FoodCategory.allCases.map(\.rawValue))
        let box = try #require(properties["box_2d"] as? [String: Any])
        #expect(box["minItems"] as? Int == 4)
        #expect(box["maxItems"] as? Int == 4)
    }

    @Test func nutritionSchemaLimitsIdsToTheQueriesAndLeavesGramsOptional() throws {
        let query = NutritionQuery(id: UUID(), label: "Rice", category: .grainOrStarch, measuredVolume: nil)
        let request = try GeminiGenerateContentRequest.nutrition(queries: [query], images: [image], userNotes: nil)
        let data = try JSONEncoder().encode(request)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let config = try #require(json["generation_config"] as? [String: Any])
        let schema = try #require(config["response_schema"] as? [String: Any])
        let items = try #require((schema["properties"] as? [String: Any])?["items"] as? [String: Any])
        let item = try #require(items["items"] as? [String: Any])
        let properties = try #require(item["properties"] as? [String: Any])

        #expect((properties["id"] as? [String: Any])?["enum"] as? [String] == [query.id.uuidString])
        let required = try #require(item["required"] as? [String])
        #expect(required.contains("per_100g"))
        #expect(!required.contains("estimated_grams"))
    }

    @Test func rejectsAnOversizedRequestWithoutSendingIt() async throws {
        let stub = StubTransport([])
        let big = Data(repeating: 1, count: URLSessionGeminiAPIClient.maximumRequestBytes)
        let request = try GeminiGenerateContentRequest.detection(images: [big], userNotes: nil)

        let error = await thrownError { _ = try await stub.makeClient().generateContent(request) }
        guard case .imageTooLarge = error else {
            Issue.record("Expected imageTooLarge, got \(String(describing: error))")
            return
        }
        #expect(stub.requests.isEmpty)
    }

    // MARK: Full service

    @Test func runsBothStagesThroughTheClient() async throws {
        let query = NutritionQuery(id: UUID(), label: "Rice", category: .grainOrStarch, measuredVolume: nil)
        let nutrition = """
        {"items":[{"id":"\(query.id.uuidString)","density_g_per_cm3":0.8,"estimated_grams":150,\
        "per_100g":{"protein_g":2.7,"carbohydrate_g":28,"fat_g":0.3,"fiber_g":0.4,"energy_kcal":130},"confidence":0.8}]}
        """
        let detection = #"{"items":[{"label":"Rice","category":"grainOrStarch","box_2d":[100,200,500,600],"confidence":0.9}]}"#
        let stub = StubTransport([reply(200, try envelope(detection)), reply(200, try envelope(nutrition))])
        let service = GeminiNutritionService(client: stub.makeClient())

        let items = try await service.detectFoodItems(in: [image], userNotes: nil)
        let estimates = try await service.estimateNutrition(for: [query], images: [image], userNotes: nil)

        #expect(items.map(\.label) == ["Rice"])
        #expect(items.first?.boundingBox.minX == 0.2)
        #expect(estimates.first?.visualEstimateGrams == 150)
        #expect(estimates.first?.macrosPer100Grams.proteinGrams == 2.7)
    }

    @Test func noQueriesMakesNoRequest() async throws {
        let stub = StubTransport([])
        let estimates = try await GeminiNutritionService(client: stub.makeClient())
            .estimateNutrition(for: [], images: [image], userNotes: nil)
        #expect(estimates.isEmpty)
        #expect(stub.requests.isEmpty)
    }

    @Test func modelTextThatIsNotThePayloadIsADecodingFailure() async throws {
        let stub = StubTransport([reply(200, try envelope("Here is your food!"))])
        let error = await thrownError {
            _ = try await GeminiNutritionService(client: stub.makeClient()).detectFoodItems(in: [image], userNotes: nil)
        }
        guard case .decodingFailed = error else {
            Issue.record("Expected decodingFailed, got \(String(describing: error))")
            return
        }
    }

    // MARK: Response envelope

    @Test func joinsTextPartsAndSkipsThoughts() throws {
        let json = """
        {"candidates":[{"content":{"parts":[{"text":"planning","thought":true},{"text":"{\\"items\\""},{"text":":[]}"}]},"finishReason":"STOP"}]}
        """
        let response = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: Data(json.utf8))
        #expect(try response.payloadText() == #"{"items":[]}"#)
    }

    @Test(arguments: [
        (#"{"promptFeedback":{"blockReason":"SAFETY"}}"#, "blocked"),
        (#"{"candidates":[{"finishReason":"PROHIBITED_CONTENT"}]}"#, "blocked"),
        (#"{"candidates":[{"content":{"parts":[{"text":"{\"items\":["}]},"finishReason":"MAX_TOKENS"}]}"#, "truncated"),
        (#"{"candidates":[{"content":{"parts":[{"text":"{}"}]},"finishReason":"OTHER"}]}"#, "empty"),
        (#"{"candidates":[]}"#, "empty"),
        (#"{"candidates":[{"content":{"parts":[]},"finishReason":"STOP"}]}"#, "empty"),
    ])
    func unusableResponsesThrow(json: String, expected: String) throws {
        let response = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: Data(json.utf8))
        do {
            _ = try response.payloadText()
            Issue.record("Expected an error for \(json)")
        } catch NutritionServiceError.contentBlocked {
            #expect(expected == "blocked")
        } catch NutritionServiceError.decodingFailed {
            #expect(expected == "truncated")
        } catch NutritionServiceError.emptyResponse {
            #expect(expected == "empty")
        }
    }

    // MARK: Errors and retries

    @Test func retriesServerErrorsWithBackoffThenSucceeds() async throws {
        let stub = StubTransport([reply(503), reply(500), reply(200, try envelope("{}"))])
        let text = try await stub.makeClient().generateContent(try detectionRequest())

        #expect(text == "{}")
        #expect(stub.requests.count == 3)
        #expect(stub.sleeps.count == 2)
        #expect(stub.sleeps[0] >= .seconds(1) && stub.sleeps[0] < .seconds(2))
        #expect(stub.sleeps[1] >= .seconds(2) && stub.sleeps[1] < .seconds(3))
    }

    @Test func stopsAfterTheMaximumAttempts() async throws {
        let stub = StubTransport([reply(503), reply(503), reply(503)])
        let error = await thrownError { _ = try await stub.makeClient().generateContent(try detectionRequest()) }

        #expect(error == .httpStatus(code: 503, message: nil))
        #expect(stub.requests.count == URLSessionGeminiAPIClient.maximumAttempts)
    }

    @Test func shortRateLimitWaitsTheRequestedTimeAndLongOneFailsImmediately() async throws {
        let short = StubTransport([
            reply(429, #"{"error":{"code":429,"message":"Slow down","details":[{"retryDelay":"3s"}]}}"#),
            reply(200, try envelope("{}")),
        ])
        _ = try await short.makeClient().generateContent(try detectionRequest())
        #expect(short.sleeps == [.seconds(3)])

        let long = StubTransport([reply(429, headers: ["Retry-After": "60"])])
        let error = await thrownError { _ = try await long.makeClient().generateContent(try detectionRequest()) }
        #expect(error == .rateLimited(retryAfterSeconds: 60))
        #expect(long.requests.count == 1)
    }

    @Test func unreadableAndStringCodedErrorBodiesAreStillMapped() async throws {
        let html = StubTransport([reply(400, "<html>Bad</html>")])
        let htmlError = await thrownError { _ = try await html.makeClient().generateContent(try detectionRequest()) }
        #expect(htmlError == .httpStatus(code: 400, message: nil))

        let stringCode = StubTransport([reply(400, #"{"error":{"code":"invalid_request","message":"Bad field"}}"#)])
        let stringError = await thrownError { _ = try await stringCode.makeClient().generateContent(try detectionRequest()) }
        #expect(stringError == .httpStatus(code: 400, message: "Bad field"))
        #expect(stringCode.requests.count == 1)
    }

    @Test(arguments: [
        (400, #"{"error":{"message":"API key not valid.","details":[{"reason":"API_KEY_INVALID"}]}}"#),
        (401, #"{"error":{"message":"Unauthorized"}}"#),
        (403, #"{"error":{"message":"Forbidden"}}"#),
        (404, #"{"error":{"message":"Not found"}}"#),
    ])
    func keyAndModelProblemsAreConfigurationErrorsThatDoNotRetry(status: Int, body: String) async throws {
        let stub = StubTransport([reply(status, body)])
        let error = await thrownError { _ = try await stub.makeClient(modelID: "gemini-gone").generateContent(try detectionRequest()) }

        guard case .invalidConfiguration(let detail) = error else {
            Issue.record("Expected invalidConfiguration, got \(String(describing: error))")
            return
        }
        #expect(stub.requests.count == 1)
        #expect(error?.isRetryable == false)
        #expect(!detail.contains("AIzaSecretTestKey"))
        if status == 404 { #expect(detail.contains("gemini-gone")) }
    }

    @Test func transportFailuresMapToTypedErrorsWithoutRetrying() async throws {
        for (code, expected) in [(URLError.Code.notConnectedToInternet, NutritionServiceError.offline), (.timedOut, .timedOut)] {
            let stub = StubTransport([.failure(URLError(code))])
            let error = await thrownError { _ = try await stub.makeClient().generateContent(try detectionRequest()) }
            #expect(error == expected)
            #expect(stub.requests.count == 1)
        }
    }

    @Test func cancelledRequestThrowsCancellationError() async throws {
        let stub = StubTransport([.failure(URLError(.cancelled))])
        let request = try detectionRequest()
        await #expect(throws: CancellationError.self) {
            try await stub.makeClient().generateContent(request)
        }
    }

}

/// Calls the real API, so it only runs when given a key:
/// `TEST_RUNNER_GEMINI_API_KEY=… xcodebuild test -only-testing:MacroDepthTests/GeminiLiveTests …`
/// It never prints the key.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GEMINI_API_KEY"]?.isEmpty == false))
struct GeminiLiveTests {
    @Test func realAPIAcceptsBothRequestsAndSchemas() async throws {
        let key = try AppConfiguration.validatedAPIKey(ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? "").get()
        let configuration = AppConfiguration(apiKey: key, modelID: AppConfiguration.modelID())
        let service = GeminiNutritionService(configuration: configuration)
        let image = try SampleScene.renderJPEG()

        let items = try await service.detectFoodItems(in: [image], userNotes: "Cooked in butter.")
        print("Live Gemini (\(configuration.modelID)) detected:", items.map(\.label))

        let query = NutritionQuery(id: UUID(), label: items.first?.label ?? "Steamed white rice", category: items.first?.category ?? .grainOrStarch, measuredVolume: nil)
        let estimates = try await service.estimateNutrition(for: [query], images: [image], userNotes: "Cooked in butter.")
        print("Live Gemini estimates:", estimates)

        #expect(estimates.count == 1)
        #expect(estimates.first?.macrosPer100Grams.isValid == true)
    }
}
