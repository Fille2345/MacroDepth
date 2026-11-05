// Services/FoodLookup/OpenFoodFactsService.swift

import Foundation

/// Looks up foods in the Open Food Facts database, which needs no key for reading.
///
/// It doesn't retry automatically, because retries count against its low rate limits
/// (10 searches and 15 product reads a minute per IP address).
struct OpenFoodFactsService: FoodLookupServiceProtocol {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let baseURL = URL(string: "https://world.openfoodfacts.org")!
    static let searchPageSize = 20
    static let requestTimeoutSeconds: TimeInterval = 15
    /// Only what's mapped below, to keep responses small.
    private static let fields = "code,product_name,generic_name,brands,nutriments,serving_quantity"

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// Open Food Facts asks every client to identify itself and give a way to reach its
    /// developer, in the form `AppName/Version (contact)`.
    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "MacroDepth/\(version) (iOS; github.com/Fille2345)"
    }()

    private let transport: Transport

    init(transport: @escaping Transport = { try await OpenFoodFactsService.session.data(for: $0) }) {
        self.transport = transport
    }

    // MARK: FoodLookupServiceProtocol

    func product(forBarcode barcode: String) async throws -> FoodProduct? {
        var components = URLComponents(
            url: Self.baseURL.appending(path: "api/v2/product/\(barcode).json"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "fields", value: Self.fields)]

        // A missing product is usually HTTP 200 with status 0, but can be a 404.
        guard let data = try await send(components, notFoundIsAnAnswer: true) else { return nil }
        let response = try Self.decode(OpenFoodFactsProductResponse.self, from: data)
        guard response.status?.value == 1, let product = response.product else { return nil }

        if let mapped = product.foodProduct(fallbackBarcode: barcode) {
            return mapped
        }
        throw FoodLookupError.missingNutrition(productName: product.displayName ?? "This product")
    }

    func searchFoods(matching query: String) async throws -> [FoodProduct] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Only this older endpoint offers full-text search. The v2 and v3 ones only filter.
        var components = URLComponents(
            url: Self.baseURL.appending(path: "cgi/search.pl"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: trimmed),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(Self.searchPageSize)),
            URLQueryItem(name: "fields", value: Self.fields),
        ]

        guard let data = try await send(components, notFoundIsAnAnswer: false) else { return [] }
        let response = try Self.decode(OpenFoodFactsSearchResponse.self, from: data)

        // Volunteers enter this data, so results without usable values are left out.
        var seen = Set<String>()
        return (response.products ?? []).compactMap { $0.foodProduct(fallbackBarcode: nil) }
            .filter { seen.insert($0.id).inserted }
    }

    // MARK: Private

    /// The response body, or `nil` for a 404 where that's a valid answer.
    private func send(_ components: URLComponents?, notFoundIsAnAnswer: Bool) async throws -> Data? {
        guard let url = components?.url else { throw FoodLookupError.serviceUnavailable }
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeoutSeconds)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .timedOut: throw FoodLookupError.serviceUnavailable
            default: throw FoodLookupError.offline
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FoodLookupError.serviceUnavailable
        }
        switch httpResponse.statusCode {
        case 200...299: return data
        case 404 where notFoundIsAnAnswer: return nil
        // Open Food Facts answers 503 when its limits are exceeded, as well as 429.
        case 429, 503: throw FoodLookupError.rateLimited
        default: throw FoodLookupError.serviceUnavailable
        }
    }

    private static func decode<Payload: Decodable>(_ type: Payload.Type, from data: Data) throws -> Payload {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw FoodLookupError.serviceUnavailable
        }
    }
}

// MARK: - Response

/// A number the database may send as JSON number or as a string like "12,5".
struct OpenFoodFactsNumber: Decodable, Sendable {
    let value: Double

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self),
                  let number = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) {
            value = number
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a number")
        }
    }
}

struct OpenFoodFactsProductResponse: Decodable, Sendable {
    let status: OpenFoodFactsNumber?
    let product: OpenFoodFactsProduct?

    private enum CodingKeys: String, CodingKey {
        case status, product
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try? container.decode(OpenFoodFactsNumber.self, forKey: .status)
        product = try? container.decode(OpenFoodFactsProduct.self, forKey: .product)
    }
}

struct OpenFoodFactsSearchResponse: Decodable, Sendable {
    let products: [OpenFoodFactsProduct]?
}

/// Every field is read leniently: one badly typed value shouldn't lose a product or a page.
struct OpenFoodFactsProduct: Decodable, Sendable {
    struct Nutriments: Decodable, Sendable {
        let energyKilocalories: Double?
        let energyKilojoules: Double?
        let protein: Double?
        let carbohydrate: Double?
        let fat: Double?
        let fiber: Double?

        private enum CodingKeys: String, CodingKey {
            case energyKilocalories = "energy-kcal_100g"
            case energyKilojoules = "energy-kj_100g"
            case protein = "proteins_100g"
            case carbohydrate = "carbohydrates_100g"
            case fat = "fat_100g"
            case fiber = "fiber_100g"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            func number(_ key: CodingKeys) -> Double? {
                (try? container.decode(OpenFoodFactsNumber.self, forKey: key))?.value
            }
            energyKilocalories = number(.energyKilocalories)
            energyKilojoules = number(.energyKilojoules)
            protein = number(.protein)
            carbohydrate = number(.carbohydrate)
            fat = number(.fat)
            fiber = number(.fiber)
        }
    }

    let code: String?
    let productName: String?
    let genericName: String?
    let brands: String?
    let nutriments: Nutriments?
    let servingQuantity: Double?

    private enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case genericName = "generic_name"
        case brands, nutriments
        case servingQuantity = "serving_quantity"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try? container.decode(String.self, forKey: .code)
        productName = try? container.decode(String.self, forKey: .productName)
        genericName = try? container.decode(String.self, forKey: .genericName)
        brands = try? container.decode(String.self, forKey: .brands)
        nutriments = try? container.decode(Nutriments.self, forKey: .nutriments)
        servingQuantity = (try? container.decode(OpenFoodFactsNumber.self, forKey: .servingQuantity))?.value
    }

    private static let kilojoulesPerKilocalorie = 4.184
    /// Suggested first when the database has no serving size.
    static let defaultServingGrams = 100.0

    var displayName: String? {
        [productName, genericName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// The domain value, or `nil` without a name, the three macros, or physically possible
    /// values. Missing fibre counts as 0. Missing energy comes from kJ, then from the macros.
    /// Stated energy far from the macros is corrected like Gemini's, since entries have typos.
    func foodProduct(fallbackBarcode: String?) -> FoodProduct? {
        guard let name = displayName,
              let nutriments,
              let protein = nutriments.protein,
              let carbohydrate = nutriments.carbohydrate,
              let fat = nutriments.fat else { return nil }

        let energy = nutriments.energyKilocalories
            ?? nutriments.energyKilojoules.map { $0 / Self.kilojoulesPerKilocalorie }
        let macros = MacroNutrients(
            proteinGrams: protein,
            carbohydrateGrams: carbohydrate,
            fatGrams: fat,
            fiberGrams: nutriments.fiber ?? 0,
            energyKilocalories: energy
        ).reconcilingEnergy()
        guard macros.isValid, macros.macronutrientMassGrams <= GeminiNutritionPayload.maximumMacroMassPer100Grams else {
            return nil
        }

        let barcode = code.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackBarcode
        let trimmedBrands = brands?.trimmingCharacters(in: .whitespacesAndNewlines)
        let serving = servingQuantity.flatMap { PortionCalculator.manualEntryRange.contains($0) ? $0 : nil }
        return FoodProduct(
            id: barcode ?? name,
            name: name,
            brand: trimmedBrands?.isEmpty == false ? trimmedBrands : nil,
            category: .other,
            macrosPer100Grams: macros,
            typicalServingGrams: serving ?? Self.defaultServingGrams,
            barcode: barcode
        )
    }
}
