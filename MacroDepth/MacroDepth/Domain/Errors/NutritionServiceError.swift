// Domain/Errors/NutritionServiceError.swift

import Foundation

enum NutritionServiceError: Error, Equatable, Sendable, LocalizedError {
    case missingAPIKey
    case invalidConfiguration(String)
    case invalidRequest(String)
    case imageTooLarge(byteCount: Int, limit: Int)
    case offline
    case timedOut
    case rateLimited(retryAfterSeconds: Double?)
    case httpStatus(code: Int, message: String?)
    case contentBlocked(reason: String)
    case emptyResponse
    case decodingFailed(String)
    case noFoodDetected

    var isRetryable: Bool {
        switch self {
        case .offline, .timedOut, .rateLimited, .emptyResponse, .noFoodDetected, .decodingFailed:
            true
        case .httpStatus(let code, _):
            code == 408 || (500...599).contains(code)
        case .missingAPIKey, .invalidConfiguration, .invalidRequest, .imageTooLarge, .contentBlocked:
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "No Gemini API key is configured."
        case .invalidConfiguration(let detail): "The nutrition service is misconfigured: \(detail)"
        case .invalidRequest(let detail): "The analysis request was invalid: \(detail)"
        case .imageTooLarge(let byteCount, let limit):
            "The photo is too large to analyze (\(byteCount / 1024) KB, limit \(limit / 1024) KB)."
        case .offline: "You appear to be offline."
        case .timedOut: "The nutrition service took too long to respond."
        case .rateLimited: "Too many requests to the nutrition service."
        case .httpStatus(let code, let message):
            "The nutrition service returned an error (\(code))\(message.map { ": \($0)" } ?? ".")"
        case .contentBlocked(let reason): "The photo couldn't be analyzed: \(reason)"
        case .emptyResponse: "The nutrition service returned no result."
        case .decodingFailed(let detail): "The nutrition result was malformed: \(detail)"
        case .noFoodDetected: "No food was found in the photo."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .missingAPIKey: "Add GEMINI_API_KEY to Config/Secrets.xcconfig and rebuild."
        case .invalidConfiguration: "Check GEMINI_API_KEY and GEMINI_MODEL_ID in Config/Secrets.xcconfig, then rebuild."
        case .invalidRequest, .decodingFailed: "Try again. Report this if it keeps happening."
        case .imageTooLarge: "Start over and retake the photo."
        case .offline: "Check your connection and try again."
        case .timedOut, .emptyResponse: "Try again in a moment."
        case .rateLimited(let retryAfter):
            retryAfter.map { "Wait about \(Int($0.rounded(.up))) seconds and try again." } ?? "Wait a moment and try again."
        case .httpStatus: "Try again later."
        case .contentBlocked: "Retake the photo showing only the food."
        case .noFoodDetected: "Center the plate in the frame with good lighting and try again."
        }
    }
}
