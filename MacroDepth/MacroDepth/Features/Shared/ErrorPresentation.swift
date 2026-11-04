// Features/Shared/ErrorPresentation.swift

import Foundation

/// A user-facing error with an optional recovery action.
struct ErrorPresentation: Equatable, Sendable {
    enum RecoveryAction: Equatable, Sendable {
        case retry
        case openSettings
        case none
    }

    let title: String
    let message: String
    let action: RecoveryAction

    init(title: String, message: String, action: RecoveryAction) {
        self.title = title
        self.message = message
        self.action = action
    }

    init(_ error: any Error) {
        switch error {
        case let scannerError as ScannerError:
            self.init(
                title: "Scanner problem",
                message: scannerError.fullDescription,
                action: scannerError.isPermissionError ? .openSettings : .retry
            )
        case let nutritionError as NutritionServiceError:
            self.init(
                title: "Analysis failed",
                message: nutritionError.fullDescription,
                action: nutritionError.isRetryable ? .retry : .none
            )
        case let persistenceError as PersistenceError:
            self.init(title: "Storage problem", message: persistenceError.fullDescription, action: .retry)
        case let configurationError as ConfigurationError:
            self.init(title: "Configuration problem", message: configurationError.fullDescription, action: .none)
        default:
            self.init(title: "Something went wrong", message: error.localizedDescription, action: .retry)
        }
    }
}
