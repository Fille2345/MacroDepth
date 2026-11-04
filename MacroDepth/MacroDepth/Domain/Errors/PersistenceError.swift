// Domain/Errors/PersistenceError.swift

import Foundation

enum PersistenceError: Error, Equatable, Sendable, LocalizedError {
    case storeUnavailable(String)
    case invalidDraft(String)
    case saveFailed(String)
    case fetchFailed(String)
    case deleteFailed(String)
    case imageWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .storeUnavailable(let detail): "Your meal log couldn't be opened: \(detail)"
        case .invalidDraft(let detail): detail
        case .saveFailed(let detail): "The meal couldn't be saved: \(detail)"
        case .fetchFailed(let detail): "Your meals couldn't be loaded: \(detail)"
        case .deleteFailed(let detail): "The meal couldn't be deleted: \(detail)"
        case .imageWriteFailed(let detail): "The meal photo couldn't be stored: \(detail)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .storeUnavailable: "Restart the app. If it persists, free up storage space."
        case .invalidDraft: nil
        case .saveFailed, .imageWriteFailed: "Check available storage and try again."
        case .fetchFailed, .deleteFailed: "Try again."
        }
    }
}
