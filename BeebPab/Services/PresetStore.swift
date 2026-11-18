import Foundation
import Observation

/// Keeps the platform presets current without the user setting any sizes.
///
/// Load order: downloaded file (cached in Application Support) → bundled `presets.json`.
/// The remote file lives on GitHub; it's re-checked at launch and every 24 hours using ETag,
/// so editing that one file updates every installed copy without shipping a new build.
@MainActor
@Observable
final class PresetStore {
    enum Origin: String {
        case bundled, cache, remote

        var label: String {
            switch self {
            case .bundled: return "ค่าที่มากับแอป"
            case .cache: return "ฉบับที่ดาวน์โหลดไว้"
            case .remote: return "ออนไลน์ (ล่าสุด)"
            }
        }
    }

    static let refreshInterval: TimeInterval = 24 * 60 * 60

    private(set) var catalog: PresetCatalog
    private(set) var origin: Origin
    private(set) var lastChecked: Date?
    private(set) var lastError: String?
    private(set) var isRefreshing = false

    let remoteURL: URL?
    private let cacheDirectory: URL
    private let session: URLSession
    private var meta: CacheMeta

    private struct CacheMeta: Codable {
        var etag: String?
        var lastChecked: Date?
    }

    private var cacheFile: URL { cacheDirectory.appendingPathComponent("presets.json") }
    private var metaFile: URL { cacheDirectory.appendingPathComponent("presets-meta.json") }

    nonisolated static var defaultCacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("BeebPab", isDirectory: true)
    }

    init(remoteURL: URL? = AppConfig.presetsURL,
         cacheDirectory: URL = PresetStore.defaultCacheDirectory,
         session: URLSession = .shared,
         bundle: Bundle = .main) {
        self.remoteURL = remoteURL
        self.cacheDirectory = cacheDirectory
        self.session = session

        let bundled = Self.loadBundled(from: bundle)
        let cacheURL = cacheDirectory.appendingPathComponent("presets.json")
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? PresetCatalog.decodeValidated(from: data),
           cached.updatedAt > bundled.updatedAt {
            catalog = cached
            origin = .cache
        } else {
            // No usable cache, or the app update shipped newer numbers than the cache.
            catalog = bundled
            origin = .bundled
        }

        let metaURL = cacheDirectory.appendingPathComponent("presets-meta.json")
        meta = (try? Data(contentsOf: metaURL)).flatMap { try? JSONDecoder().decode(CacheMeta.self, from: $0) } ?? CacheMeta()
        lastChecked = meta.lastChecked
    }

    nonisolated static func loadBundled(from bundle: Bundle) -> PresetCatalog {
        guard let url = bundle.url(forResource: "presets", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? PresetCatalog.decodeValidated(from: data) else {
            return .emergencyFallback
        }
        return catalog
    }

    func refreshIfNeeded() async {
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.refreshInterval { return }
        await refresh()
    }

    func refresh() async {
        guard let remoteURL else {
            lastError = "ยังไม่ได้ตั้งที่อยู่ไฟล์ presets.json บน GitHub (AppConfig.swift)"
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var request = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        if origin != .bundled, let etag = meta.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            switch http?.statusCode ?? 0 {
            case 304:
                origin = .remote
            case 200:
                let downloaded = try PresetCatalog.decodeValidated(from: data)
                try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                try data.write(to: cacheFile, options: .atomic)
                catalog = downloaded
                origin = .remote
                meta.etag = http?.value(forHTTPHeaderField: "ETag")
            case let code:
                throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "เซิร์ฟเวอร์ตอบกลับ \(code)"])
            }
            lastError = nil
            meta.lastChecked = Date()
            lastChecked = meta.lastChecked
            saveMeta()
        } catch {
            // Keep whatever we already have; the app keeps working offline.
            lastError = error.localizedDescription
        }
    }

    private func saveMeta() {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metaFile, options: .atomic)
        }
    }
}
