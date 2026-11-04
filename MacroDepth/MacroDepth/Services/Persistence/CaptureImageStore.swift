// Services/Persistence/CaptureImageStore.swift

import Foundation

/// Stores meal photos as files in the app sandbox, outside the SwiftData store.
/// File I/O runs on this actor, off the main thread.
actor CaptureImageStore {
    nonisolated let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    /// `Application Support/Captures`, which is backed up and not user-visible.
    static func applicationSupportDirectory() throws -> URL {
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return base.appendingPathComponent("Captures", isDirectory: true)
        } catch {
            throw PersistenceError.storeUnavailable(error.localizedDescription)
        }
    }

    /// A unique scratch directory for previews and tests.
    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MacroDepthCaptures-\(UUID().uuidString)", isDirectory: true)
    }

    /// Writes the JPEG and returns its file name.
    func write(_ data: Data, id: UUID) throws -> String {
        let fileName = "\(id.uuidString).jpg"
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(
                to: url(for: fileName),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch {
            throw PersistenceError.imageWriteFailed(error.localizedDescription)
        }
        return fileName
    }

    func delete(fileName: String) throws {
        let fileURL = url(for: fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw PersistenceError.deleteFailed(error.localizedDescription)
        }
    }

    /// Only the last path component is used, so a stored name can't escape the directory.
    nonisolated func url(for fileName: String) -> URL {
        let safeName = URL(fileURLWithPath: fileName).lastPathComponent
        return directoryURL.appendingPathComponent(safeName, isDirectory: false)
    }
}
