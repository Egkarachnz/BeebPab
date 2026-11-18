import Foundation
import UniformTypeIdentifiers

/// Turns a mix of dropped files and folders into a flat list of image files.
enum FileCollector {
    static func imageURLs(from urls: [URL]) -> [URL] {
        var result: [URL] = []
        var seen = Set<URL>()

        func add(_ url: URL) {
            let key = url.standardizedFileURL
            if isImage(key), seen.insert(key).inserted { result.append(key) }
        }

        for url in urls {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { add(url); continue }
            guard let walker = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.contentTypeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            var found: [URL] = []
            for case let file as URL in walker where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                found.append(file)
            }
            found.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            found.forEach(add)
        }
        return result
    }

    static func isImage(_ url: URL) -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return false }
        return type.conforms(to: .image) && !type.conforms(to: .svg) && !type.conforms(to: .ico)
    }
}

enum OutputWriter {
    /// `photo.heic` → `photo_facebook-feed.jpg`, adding " (2)" etc. if the name is taken
    /// on disk or already reserved by another job in this run.
    static func outputURL(for input: URL, platform: Platform, target: OutputTarget,
                          in folder: URL, useSubfolder: Bool, reserved: inout Set<URL>) throws -> URL {
        var directory = folder
        if useSubfolder {
            directory = folder.appendingPathComponent(sanitize("\(platform.name) - \(target.name)"), isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let base = "\(input.deletingPathExtension().lastPathComponent)_\(platform.id)-\(target.id)"
        let ext = target.format == .png ? "png" : "jpg"

        var candidate = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while reserved.contains(candidate) || FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) (\(n))").appendingPathExtension(ext)
            n += 1
        }
        reserved.insert(candidate)
        return candidate
    }

    static func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }
}

/// Remembers the output folder between launches (the sandbox needs a security-scoped bookmark).
enum FolderBookmark {
    private static let key = "outputFolderBookmark"

    static func save(_ url: URL) {
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func restore() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale { save(url) }
        return url
    }
}
