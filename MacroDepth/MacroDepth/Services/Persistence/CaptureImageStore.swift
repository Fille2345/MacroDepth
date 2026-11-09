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

    /// Copies a stored image to a new file owned by `id`, and returns its file name.
    /// Returns `nil` if the source no longer exists, because photos are optional.
    func copy(fileName: String, toID id: UUID) throws -> String? {
        let source = url(for: fileName)
        guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: source)
        } catch {
            throw PersistenceError.imageWriteFailed(error.localizedDescription)
        }
        return try write(data, id: id)
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

    /// Deletes each file that exists and returns how many were removed. A file that
    /// can't be deleted is skipped; the next cleanup's orphan sweep tries again.
    func delete(fileNames: [String]) -> Int {
        fileNames.reduce(0) { count, fileName in
            let fileURL = url(for: fileName)
            guard (try? FileManager.default.removeItem(at: fileURL)) != nil else { return count }
            return count + 1
        }
    }

    /// Deletes files no record refers to, such as one left behind when deleting it
    /// failed. Files changed after `modifiedBefore` are kept, because a save in
    /// progress writes its photo before the record that refers to it.
    func deleteFiles(notIn referencedFileNames: Set<String>, modifiedBefore cutoff: Date) -> Int {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }   // No directory yet means no photos.

        let orphans = urls.filter { fileURL in
            guard !referencedFileNames.contains(fileURL.lastPathComponent),
                  let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate else { return false }
            return modified < cutoff
        }
        return delete(fileNames: orphans.map(\.lastPathComponent))
    }

    /// Only the last path component is used, so a stored name can't escape the directory.
    nonisolated func url(for fileName: String) -> URL {
        let safeName = URL(fileURLWithPath: fileName).lastPathComponent
        return directoryURL.appendingPathComponent(safeName, isDirectory: false)
    }
}
