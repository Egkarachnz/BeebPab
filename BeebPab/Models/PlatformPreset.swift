import Foundation

/// The whole set of platform presets, loaded from `presets.json` (bundled, cached, or downloaded).
struct PresetCatalog: Codable, Equatable, Sendable {
    static let supportedSchemaVersion = 1

    var schemaVersion: Int
    /// ISO date (yyyy-MM-dd) of the last edit, so newer files win.
    var updatedAt: String
    var platforms: [Platform]

    func resolve(_ key: TargetKey) -> (platform: Platform, target: OutputTarget)? {
        guard let platform = platforms.first(where: { $0.id == key.platformID }),
              let target = platform.targets.first(where: { $0.id == key.targetID }) else { return nil }
        return (platform, target)
    }

    /// Keys in catalog order, filtered to the given selection.
    func orderedKeys(in selection: Set<TargetKey>) -> [TargetKey] {
        platforms.flatMap { p in p.targets.map { TargetKey(platformID: p.id, targetID: $0.id) } }
            .filter { selection.contains($0) }
    }
}

struct Platform: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var note: String?
    var targets: [OutputTarget]
}

struct OutputTarget: Codable, Equatable, Identifiable, Sendable {
    enum Format: String, Codable, Sendable { case jpeg, png }
    struct Canvas: Codable, Equatable, Sendable { var width: Int; var height: Int }
    struct Sharpen: Codable, Equatable, Sendable { var radius: Double; var intensity: Double }
    struct Quality: Codable, Equatable, Sendable { var min: Double; var max: Double }

    var id: String
    var name: String
    /// SF Symbol name shown on the target's card.
    var symbol: String?
    var detail: String?
    /// Longest edge of the output, in pixels.
    var maxLongEdge: Int
    /// Optional cap on total pixels (width × height). LINE limits images this way.
    var maxPixels: Int?
    /// When set, the image is scaled to cover this canvas and center-cropped to its aspect ratio.
    var canvas: Canvas?
    var format: Format
    var maxFileSizeKB: Int
    var quality: Quality?
    var sharpen: Sharpen?
    /// Official page the numbers came from; watched by the GitHub Action.
    var source: String?

    var effectiveQuality: Quality { quality ?? Quality(min: 0.80, max: 0.95) }

    var summary: String {
        let size: String
        if let canvas {
            size = "\(canvas.width)×\(canvas.height) px"
        } else if let maxPixels {
            let side = Int(Double(maxPixels).squareRoot().rounded())
            size = "ไม่เกิน \(side)×\(side) px (รวม)"
        } else {
            size = "ขอบยาว \(maxLongEdge) px"
        }
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(maxFileSizeKB) * 1024, countStyle: .file)
        return "\(size) · \(format.rawValue.uppercased()) ≤ \(bytes)"
    }
}

struct TargetKey: Hashable, Codable, Sendable {
    var platformID: String
    var targetID: String
}

enum PresetValidationError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let v): return "ไฟล์ presets รุ่น \(v) ใหม่กว่าที่แอปรองรับ กรุณาอัปเดตแอป"
        case .invalid(let reason): return "ไฟล์ presets ไม่ถูกต้อง: \(reason)"
        }
    }
}

extension PresetCatalog {
    static func decodeValidated(from data: Data) throws -> PresetCatalog {
        let catalog = try JSONDecoder().decode(PresetCatalog.self, from: data)
        try catalog.validate()
        return catalog
    }

    /// Rejects files with out-of-range numbers so a typo on GitHub can't break every install.
    func validate() throws {
        guard schemaVersion == Self.supportedSchemaVersion else { throw PresetValidationError.unsupportedSchema(schemaVersion) }
        guard !platforms.isEmpty else { throw PresetValidationError.invalid("ไม่มีแพลตฟอร์ม") }
        var platformIDs = Set<String>()
        for p in platforms {
            guard platformIDs.insert(p.id).inserted else { throw PresetValidationError.invalid("id ซ้ำ: \(p.id)") }
            guard !p.targets.isEmpty else { throw PresetValidationError.invalid("\(p.id) ไม่มีรูปแบบ") }
            var targetIDs = Set<String>()
            for t in p.targets {
                let where_ = "\(p.id).\(t.id)"
                guard targetIDs.insert(t.id).inserted else { throw PresetValidationError.invalid("id ซ้ำ: \(where_)") }
                guard (256...8192).contains(t.maxLongEdge) else { throw PresetValidationError.invalid("maxLongEdge ของ \(where_)") }
                guard (50...50_000).contains(t.maxFileSizeKB) else { throw PresetValidationError.invalid("maxFileSizeKB ของ \(where_)") }
                if let px = t.maxPixels, !(100_000...67_108_864).contains(px) { throw PresetValidationError.invalid("maxPixels ของ \(where_)") }
                if let c = t.canvas, !((64...8192).contains(c.width) && (64...8192).contains(c.height)) {
                    throw PresetValidationError.invalid("canvas ของ \(where_)")
                }
                if let q = t.quality, !(0.5...1.0).contains(q.min) || !(0.5...1.0).contains(q.max) || q.min > q.max {
                    throw PresetValidationError.invalid("quality ของ \(where_)")
                }
                if let s = t.sharpen, !(0...5).contains(s.radius) || !(0...2).contains(s.intensity) {
                    throw PresetValidationError.invalid("sharpen ของ \(where_)")
                }
            }
        }
    }

    /// Used only if the bundled file is somehow unreadable.
    static let emergencyFallback = PresetCatalog(
        schemaVersion: 1,
        updatedAt: "2000-01-01",
        platforms: [
            Platform(id: "facebook", name: "Facebook", note: nil, targets: [
                OutputTarget(id: "feed", name: "โพสต์ทั่วไป / อัลบั้ม", maxLongEdge: 2048, format: .jpeg, maxFileSizeKB: 1200),
            ]),
            Platform(id: "line", name: "LINE", note: nil, targets: [
                OutputTarget(id: "chat-hd", name: "ส่งในแชต (HD)", maxLongEdge: 4096, maxPixels: 4_194_304, format: .jpeg, maxFileSizeKB: 1500),
            ]),
        ]
    )
}
