// MacroDepthTests/OpenFoodFactsServiceTests.swift

import Foundation
import Testing
@testable import MacroDepth

/// Canned responses, recording each request. The JSON below is shaped like real responses.
private final class StubFoodTransport: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let status: Int
    private let body: String
    private let failure: URLError?

    init(status: Int = 200, body: String = "{}", failure: URLError? = nil) {
        self.status = status
        self.body = body
        self.failure = failure
    }

    var requests: [URLRequest] { lock.withLock { recorded } }

    var service: OpenFoodFactsService {
        OpenFoodFactsService(transport: { [self] request in
            lock.withLock { recorded.append(request) }
            if let failure { throw failure }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        })
    }
}

private let nutella = """
{"code":"3017620422003","status":1,"status_verbose":"product found","product":{"code":"3017620422003",
"product_name":"Nutella","brands":"Nutella, Ferrero","nutriments":{"carbohydrates_100g":57.5,"energy-kcal_100g":539,
"energy-kj_100g":2252,"energy_100g":2252,"fat_100g":30.9,"fiber_100g":0,"proteins_100g":6.3},"serving_quantity":null}}
"""

struct OpenFoodFactsServiceTests {
    private let barcode = "3017620422003"

    // MARK: Barcode

    @Test func requestsTheProductWithItsFieldsAndUserAgent() async throws {
        let stub = StubFoodTransport(body: nutella)
        _ = try await stub.service.product(forBarcode: barcode)

        let request = try #require(stub.requests.first)
        let url = try #require(request.url)
        #expect(url.host() == "world.openfoodfacts.org")
        #expect(url.path() == "/api/v2/product/3017620422003.json")
        #expect(url.query()?.contains("fields=") == true)
        let userAgent = try #require(request.value(forHTTPHeaderField: "User-Agent"))
        #expect(userAgent.hasPrefix("MacroDepth/"))
        #expect(userAgent.hasSuffix("(iOS; github.com/Fille2345)"))
        #expect(!userAgent.contains("CFNetwork"))
    }

    @Test func mapsARealProductResponse() async throws {
        let product = try #require(try await StubFoodTransport(body: nutella).service.product(forBarcode: barcode))

        #expect(product.id == barcode)
        #expect(product.barcode == barcode)
        #expect(product.name == "Nutella")
        #expect(product.brand == "Nutella, Ferrero")
        #expect(product.category == .other)
        #expect(product.macrosPer100Grams.proteinGrams == 6.3)
        #expect(product.macrosPer100Grams.carbohydrateGrams == 57.5)
        #expect(product.macrosPer100Grams.fatGrams == 30.9)
        #expect(product.macrosPer100Grams.fiberGrams == 0)
        #expect(product.macrosPer100Grams.energyKilocalories == 539)
        #expect(product.typicalServingGrams == OpenFoodFactsProduct.defaultServingGrams)
    }

    /// The API answers an unknown code with HTTP 200 and status 0.
    @Test(arguments: [
        (200, #"{"code":"00000000","status":0,"status_verbose":"no code or invalid code"}"#),
        (200, #"{"code":"123","status":0,"status_verbose":"product not found"}"#),
        (404, #"{"status":0}"#),
        (404, "<html>Not found</html>"),
        (200, #"{"status":1}"#),
    ])
    func unknownCodesAreNotFound(status: Int, body: String) async throws {
        let product = try await StubFoodTransport(status: status, body: body).service.product(forBarcode: barcode)
        #expect(product == nil)
    }

    @Test func productWithoutNutritionSaysSoInsteadOfNotFound() async throws {
        let body = #"{"status":1,"product":{"code":"1","product_name":"Mystery bar","nutriments":{"proteins_100g":5}}}"#
        await #expect(throws: FoodLookupError.missingNutrition(productName: "Mystery bar")) {
            _ = try await StubFoodTransport(body: body).service.product(forBarcode: barcode)
        }
    }

    // MARK: Mapping

    private func map(_ json: String) throws -> FoodProduct? {
        try JSONDecoder().decode(OpenFoodFactsProduct.self, from: Data(json.utf8)).foodProduct(fallbackBarcode: "999")
    }

    private func nutriments(_ extra: String) -> String {
        #"{"product_name":"Food","nutriments":{"proteins_100g":10,"carbohydrates_100g":20,"fat_100g":5\#(extra)}}"#
    }

    @Test func acceptsNumbersWrittenAsStrings() throws {
        let product = try #require(try map(
            #"{"product_name":"Food","nutriments":{"proteins_100g":"10.5","carbohydrates_100g":"20,5","fat_100g":5,"energy-kcal_100g":"170"},"serving_quantity":"30"}"#
        ))
        #expect(product.macrosPer100Grams.proteinGrams == 10.5)
        #expect(product.macrosPer100Grams.carbohydrateGrams == 20.5)
        #expect(product.typicalServingGrams == 30)
    }

    @Test func missingKilocaloriesComeFromKilojoules() throws {
        let product = try #require(try map(nutriments(#","energy-kj_100g":711.28"#)))
        #expect(abs(product.macrosPer100Grams.energyKilocalories - 170) < 0.01)
    }

    @Test func missingEnergyComesFromTheMacros() throws {
        let product = try #require(try map(nutriments("")))
        #expect(abs(product.macrosPer100Grams.energyKilocalories - 165) < 1e-9)   // 40 + 80 + 45
        #expect(product.macrosPer100Grams.fiberGrams == 0)
    }

    @Test func energyFarFromTheMacrosIsCorrected() throws {
        let product = try #require(try map(nutriments(#","energy-kcal_100g":1650"#)))
        #expect(abs(product.macrosPer100Grams.energyKilocalories - 165) < 1e-9)
    }

    @Test(arguments: [
        #"{"nutriments":{"proteins_100g":1,"carbohydrates_100g":1,"fat_100g":1}}"#,                       // no name
        #"{"product_name":"  ","nutriments":{"proteins_100g":1,"carbohydrates_100g":1,"fat_100g":1}}"#,   // blank name
        #"{"product_name":"Food"}"#,                                                                      // no values
        #"{"product_name":"Food","nutriments":[]}"#,                                                      // wrong type
        #"{"product_name":"Food","nutriments":{"carbohydrates_100g":1,"fat_100g":1}}"#,                   // no protein
        #"{"product_name":"Food","nutriments":{"proteins_100g":-1,"carbohydrates_100g":1,"fat_100g":1}}"#,  // negative
        #"{"product_name":"Food","nutriments":{"proteins_100g":60,"carbohydrates_100g":60,"fat_100g":1}}"#, // over 100 g
        #"{"product_name":"Food","nutriments":{"proteins_100g":"n/a","carbohydrates_100g":1,"fat_100g":1}}"#,
    ])
    func unusableProductsAreRejected(json: String) throws {
        #expect(try map(json) == nil)
    }

    @Test func fallsBackToGenericNameAndHandlesBadServings() throws {
        let product = try #require(try map(
            #"{"product_name":"","generic_name":"Plain yogurt","nutriments":{"proteins_100g":4,"carbohydrates_100g":4,"fat_100g":3},"serving_quantity":0}"#
        ))
        #expect(product.name == "Plain yogurt")
        #expect(product.typicalServingGrams == OpenFoodFactsProduct.defaultServingGrams)
        #expect(product.barcode == "999")
    }

    // MARK: Search

    private let searchBody = """
    {"count":3,"products":[
    {"code":"4056489148739","product_name":"Creamy Greek Style Natural Yogurt","brands":"Milbona","serving_quantity":100,
     "nutriments":{"energy-kcal_100g":126.4,"proteins_100g":4.1,"carbohydrates_100g":4.6,"fat_100g":10,"fiber_100g":0.5}},
    {"code":"20416690","product_name":"Incomplete","nutriments":{"proteins_100g":6}},
    {"code":"4056489148739","product_name":"Duplicate","nutriments":{"proteins_100g":1,"carbohydrates_100g":1,"fat_100g":1}},
    {"code":"5411188121213","product_name":"Greek Style Plain","brands":"alpro","serving_quantity":"150",
     "nutriments":{"energy-kcal_100g":65,"proteins_100g":5.6,"carbohydrates_100g":2.2,"fat_100g":3.3,"fiber_100g":1.3}}
    ]}
    """

    @Test func searchKeepsUsableProductsOnce() async throws {
        let results = try await StubFoodTransport(body: searchBody).service.searchFoods(matching: "greek yogurt")
        #expect(results.map(\.name) == ["Creamy Greek Style Natural Yogurt", "Greek Style Plain"])
        #expect(results.last?.typicalServingGrams == 150)
        #expect(results.last?.brand == "alpro")
    }

    @Test func searchEncodesTheQueryAndUsesTheFullTextEndpoint() async throws {
        let stub = StubFoodTransport(body: #"{"products":[]}"#)
        _ = try await stub.service.searchFoods(matching: "  crème & fraîche ")

        let url = try #require(stub.requests.first?.url)
        #expect(url.path() == "/cgi/search.pl")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "search_terms" }?.value == "crème & fraîche")
        #expect(items.first { $0.name == "json" }?.value == "1")
        #expect(items.first { $0.name == "page_size" }?.value == String(OpenFoodFactsService.searchPageSize))
    }

    @Test func blankSearchSendsNothing() async throws {
        let stub = StubFoodTransport()
        #expect(try await stub.service.searchFoods(matching: "  ").isEmpty)
        #expect(stub.requests.isEmpty)
    }

    // MARK: Errors

    @Test(arguments: [
        (429, FoodLookupError.rateLimited),
        (503, .rateLimited),
        (500, .serviceUnavailable),
        (403, .serviceUnavailable),
    ])
    func httpErrorsMapAndDoNotRetry(status: Int, expected: FoodLookupError) async throws {
        let stub = StubFoodTransport(status: status)
        await #expect(throws: expected) {
            _ = try await stub.service.searchFoods(matching: "milk")
        }
        #expect(stub.requests.count == 1)
    }

    @Test func aSearch404IsAnError() async throws {
        await #expect(throws: FoodLookupError.serviceUnavailable) {
            _ = try await StubFoodTransport(status: 404, body: "x").service.searchFoods(matching: "milk")
        }
    }

    @Test func unreadableSuccessBodyIsAnError() async throws {
        await #expect(throws: FoodLookupError.serviceUnavailable) {
            _ = try await StubFoodTransport(body: "<html>Maintenance</html>").service.searchFoods(matching: "milk")
        }
    }

    @Test(arguments: [
        (URLError.Code.notConnectedToInternet, FoodLookupError.offline),
        (.networkConnectionLost, .offline),
        (.timedOut, .serviceUnavailable),
    ])
    func networkFailuresMap(code: URLError.Code, expected: FoodLookupError) async throws {
        await #expect(throws: expected) {
            _ = try await StubFoodTransport(failure: URLError(code)).service.product(forBarcode: barcode)
        }
    }

    @Test func cancellingThrowsCancellation() async throws {
        await #expect(throws: CancellationError.self) {
            _ = try await StubFoodTransport(failure: URLError(.cancelled)).service.searchFoods(matching: "milk")
        }
    }

    // MARK: Wiring

    @MainActor
    @Test func liveAppUsesOpenFoodFactsAndItIsNotLabelledAsSamples() throws {
        let dependencies = AppDependencies.makeLive()
        #expect(dependencies.foodLookup is OpenFoodFactsService)
        #expect(!SettingsViewModel(dependencies: dependencies).usesSampleFoodData)

        let tracking = ManualTrackingViewModel(mode: .search, lookup: dependencies.foodLookup, permissions: MockCameraPermissionService())
        #expect(!tracking.usesSampleData)

        #expect(AppDependencies.makePreview().foodLookup is MockFoodLookupService)
    }
}

struct UPCETests {
    @Test(arguments: [
        ("04252614", "042100005264"),   // last digit 0–2
        ("01234531", "012300000451"),   // last digit 3
        ("01234543", "012340000053"),   // last digit 4
        ("01234565", "012345000065"),   // last digit 5–9
    ])
    func expandsToUPCA(upcE: String, upcA: String) {
        #expect(FoodBarcode.upcA(fromUPCE: upcE) == upcA)
        #expect(FoodBarcode.normalized(upcA) == upcA)
    }

    @Test(arguments: ["04252615", "123", "0425261", "042526140", "abcdefgh"])
    func rejectsInvalidCodes(code: String) {
        #expect(FoodBarcode.upcA(fromUPCE: code) == nil)
    }
}

struct BarcodeFocusTests {
    /// A main camera focusing no closer than 20 cm, with a 70° field of view.
    @Test func zoomsSoACodeFillsTheFrameFromWhereItCanFocus() {
        let zoom = BarcodeCameraController.recommendedZoom(minimumFocusDistanceMillimeters: 200, fieldOfViewDegrees: 70)
        #expect(zoom > 2 && zoom < 2.6)
    }

    @Test func camerasThatFocusCloseNeedNoZoom() {
        #expect(BarcodeCameraController.recommendedZoom(minimumFocusDistanceMillimeters: 60, fieldOfViewDegrees: 70) == 1)
    }

    @Test func zoomIsCappedSoItStaysUsableHandheld() {
        #expect(BarcodeCameraController.recommendedZoom(minimumFocusDistanceMillimeters: 2_000, fieldOfViewDegrees: 70) == 3)
    }

    @Test(arguments: [(-1, Float(70)), (0, 70), (200, 0)])
    func unknownCameraValuesLeaveZoomAlone(distance: Int, fieldOfView: Float) {
        #expect(BarcodeCameraController.recommendedZoom(minimumFocusDistanceMillimeters: distance, fieldOfViewDegrees: fieldOfView) == 1)
    }
}

/// Calls the real API, so it only runs when asked for:
/// `TEST_RUNNER_MACRODEPTH_LIVE_FOOD=1 xcodebuild test -only-testing:MacroDepthTests/OpenFoodFactsLiveTests …`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MACRODEPTH_LIVE_FOOD"] == "1"))
struct OpenFoodFactsLiveTests {
    @Test func realAPIAnswersBarcodeAndSearch() async throws {
        let service = OpenFoodFactsService()

        let product = try #require(try await service.product(forBarcode: "3017620422003"))
        print("Live OFF barcode:", product.name, product.brand ?? "-", product.macrosPer100Grams)
        #expect(product.macrosPer100Grams.energyKilocalories > 400)
        #expect(product.macrosPer100Grams.fatGrams > 20)

        #expect(try await service.product(forBarcode: "0000000000000") == nil)

        let results = try await service.searchFoods(matching: "greek yogurt")
        print("Live OFF search:", results.count, results.prefix(5).map(\.name))
        #expect(!results.isEmpty)
    }
}
