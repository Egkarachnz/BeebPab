import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import BeebPab

final class ImageProcessorTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Writes a noisy test image (noise makes JPEG size realistic).
    private func makeImage(width: Int, height: Int, colorSpace: CFString = CGColorSpace.displayP3,
                           type: UTType = .png, orientation: Int? = nil, name: String = "in") throws -> URL {
        let space = CGColorSpace(name: colorSpace)!
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let buffer = ctx.data!.assumingMemoryBound(to: UInt8.self)
        var seed: UInt32 = 12345
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 1_103_515_245 &+ 12345
                let i = y * ctx.bytesPerRow + x * 4
                buffer[i] = UInt8((x * 255) / width)
                buffer[i + 1] = UInt8((y * 255) / height)
                buffer[i + 2] = UInt8(truncatingIfNeeded: seed >> 16)
            }
        }
        let image = ctx.makeImage()!
        let url = dir.appendingPathComponent(name).appendingPathExtension(type.preferredFilenameExtension!)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        var props: [CFString: Any] = [:]
        if let orientation { props[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    private func target(_ platform: String, _ id: String) throws -> OutputTarget {
        let catalog = PresetStore.loadBundled(from: Bundle(for: PresetStore.self))
        return try XCTUnwrap(catalog.resolve(TargetKey(platformID: platform, targetID: id))?.target)
    }

    private func info(_ url: URL) -> (Int, Int, String?) {
        let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
        let image = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        return (props[kCGImagePropertyPixelWidth] as! Int, props[kCGImagePropertyPixelHeight] as! Int,
                image.colorSpace?.name as String?)
    }

    func testFacebookFeedDownscalesToSRGBWithinBudget() throws {
        let input = try makeImage(width: 6000, height: 4000)
        let t = try target("facebook", "feed")
        let out = dir.appendingPathComponent("out.jpg")
        let r = try ImageProcessor.process(inputURL: input, target: t, outputURL: out)
        let (w, h, space) = info(out)
        XCTAssertEqual(w, 2048)
        XCTAssertEqual(h, 1365)
        XCTAssertEqual(space, CGColorSpace.sRGB as String)
        XCTAssertEqual(r.byteCount, try Data(contentsOf: out).count)
        XCTAssertLessThanOrEqual(r.byteCount, t.maxFileSizeKB * 1024)
        XCTAssertFalse(r.exceedsSizeLimit)
    }

    func testSmallImageIsNotUpscaled() throws {
        let input = try makeImage(width: 800, height: 600)
        let out = dir.appendingPathComponent("small.jpg")
        _ = try ImageProcessor.process(inputURL: input, target: try target("facebook", "feed"), outputURL: out)
        let (w, h, _) = info(out)
        XCTAssertEqual(w, 800)
        XCTAssertEqual(h, 600)
    }

    func testOrientationIsApplied() throws {
        // Stored landscape 400×200 with "rotate 90°" → upright portrait 200×400.
        let input = try makeImage(width: 400, height: 200, type: .jpeg, orientation: 6)
        let out = dir.appendingPathComponent("rot.jpg")
        _ = try ImageProcessor.process(inputURL: input, target: try target("facebook", "feed"), outputURL: out)
        let (w, h, _) = info(out)
        XCTAssertEqual(w, 200)
        XCTAssertEqual(h, 400)
    }

    func testStoryCanvasIsCroppedToExactSize() throws {
        let input = try makeImage(width: 4000, height: 3000)
        let out = dir.appendingPathComponent("story.jpg")
        _ = try ImageProcessor.process(inputURL: input, target: try target("facebook", "story"), outputURL: out)
        let (w, h, _) = info(out)
        XCTAssertEqual(w, 1080)
        XCTAssertEqual(h, 1920)
    }

    func testLinePixelCountLimit() throws {
        let t = try target("line", "chat")
        let g = ImageProcessor.geometry(sourceWidth: 4032, sourceHeight: 3024, target: t)
        XCTAssertLessThanOrEqual(g.cropWidth * g.cropHeight, t.maxPixels!)
        XCTAssertEqual(g.cropWidth, 1478)
        XCTAssertEqual(g.cropHeight, 1108)
    }

    func testOutputNamesAreUnique() throws {
        let platform = Platform(id: "facebook", name: "Facebook", note: nil, targets: [])
        let t = try target("facebook", "feed")
        var reserved = Set<URL>()
        let a = try OutputWriter.outputURL(for: URL(fileURLWithPath: "/x/IMG_1.HEIC"), platform: platform, target: t,
                                           in: dir, useSubfolder: false, reserved: &reserved)
        let b = try OutputWriter.outputURL(for: URL(fileURLWithPath: "/y/IMG_1.jpg"), platform: platform, target: t,
                                           in: dir, useSubfolder: false, reserved: &reserved)
        XCTAssertEqual(a.lastPathComponent, "IMG_1_facebook-feed.jpg")
        XCTAssertEqual(b.lastPathComponent, "IMG_1_facebook-feed (2).jpg")
    }
}

@MainActor
final class PresetStoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var bundle: Bundle { Bundle(for: PresetStore.self) }

    func testBundledPresetsAreValid() throws {
        let url = try XCTUnwrap(bundle.url(forResource: "presets", withExtension: "json"))
        let catalog = try PresetCatalog.decodeValidated(from: Data(contentsOf: url))
        XCTAssertEqual(Set(catalog.platforms.map(\.id)), ["facebook", "line"])
    }

    func testRejectsOutOfRangeValues() throws {
        let bad = #"{"schemaVersion":1,"updatedAt":"2030-01-01","platforms":[{"id":"facebook","name":"Facebook","targets":[{"id":"feed","name":"x","maxLongEdge":20,"format":"jpeg","maxFileSizeKB":500}]}]}"#
        XCTAssertThrowsError(try PresetCatalog.decodeValidated(from: Data(bad.utf8)))
    }

    func testRejectsNewerSchema() {
        let future = #"{"schemaVersion":99,"updatedAt":"2030-01-01","platforms":[]}"#
        XCTAssertThrowsError(try PresetCatalog.decodeValidated(from: Data(future.utf8))) { error in
            XCTAssertEqual(error as? PresetValidationError, .unsupportedSchema(99))
        }
    }

    func testCorruptCacheFallsBackToBundled() throws {
        try Data("not json".utf8).write(to: dir.appendingPathComponent("presets.json"))
        let store = PresetStore(remoteURL: nil, cacheDirectory: dir, bundle: bundle)
        XCTAssertEqual(store.origin, .bundled)
    }

    func testNewerCacheWins() throws {
        var catalog = PresetStore.loadBundled(from: bundle)
        catalog.updatedAt = "2999-01-01"
        catalog.platforms[0].targets[0].maxLongEdge = 1500
        try JSONEncoder().encode(catalog).write(to: dir.appendingPathComponent("presets.json"))
        let store = PresetStore(remoteURL: nil, cacheDirectory: dir, bundle: bundle)
        XCTAssertEqual(store.origin, .cache)
        XCTAssertEqual(store.catalog.platforms[0].targets[0].maxLongEdge, 1500)
    }

    func testRemoteDownloadIsValidatedAndCached() async throws {
        var catalog = PresetStore.loadBundled(from: bundle)
        catalog.updatedAt = "2999-02-02"
        StubProtocol.responseData = try JSONEncoder().encode(catalog)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let store = PresetStore(remoteURL: URL(string: "https://example.test/presets.json")!,
                                cacheDirectory: dir, session: URLSession(configuration: config), bundle: bundle)
        await store.refresh()
        XCTAssertNil(store.lastError)
        XCTAssertEqual(store.origin, .remote)
        XCTAssertEqual(store.catalog.updatedAt, "2999-02-02")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("presets.json").path))
    }
}

final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["ETag": "\"abc\""])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class RerunTests: XCTestCase {
    private var dir: URL!
    private var out: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        out = dir.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeJPEG(_ name: String) throws -> URL {
        let ctx = CGContext(data: nil, width: 3000, height: 2000, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        let url = dir.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    private func run(_ model: AppModel, _ catalog: PresetCatalog) async throws {
        model.process(catalog: catalog, options: ProcessOptions())
        for _ in 0..<400 where model.isProcessing { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertFalse(model.isProcessing)
    }

    private func outputNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
    }

    func testRerunOnlyProcessesNewImagesAndRedoOverwrites() async throws {
        let catalog = PresetStore.loadBundled(from: Bundle(for: PresetStore.self))
        let model = AppModel()
        model.selectedTargets = [TargetKey(platformID: "facebook", targetID: "feed")]
        model.setOutputFolder(out)

        let first = ImageJob(url: try makeJPEG("a.jpg"))
        model.jobs = [first]
        try await run(model, catalog)
        XCTAssertEqual(try outputNames(), ["a_facebook-feed.jpg"])
        XCTAssertFalse(model.canProcess(with: catalog), "nothing left to do")

        // Adding a new image processes only that one.
        model.jobs.append(ImageJob(url: try makeJPEG("b.jpg")))
        XCTAssertEqual(model.pendingImageCount(with: catalog), 1)
        try await run(model, catalog)
        XCTAssertEqual(try outputNames(), ["a_facebook-feed.jpg", "b_facebook-feed.jpg"])

        // Redo overwrites the same file instead of making a "(2)" copy.
        model.requestRedo(first)
        XCTAssertEqual(model.pendingImageCount(with: catalog), 1)
        try await run(model, catalog)
        XCTAssertEqual(try outputNames(), ["a_facebook-feed.jpg", "b_facebook-feed.jpg"])

        // A deleted output counts as not done.
        try FileManager.default.removeItem(at: out.appendingPathComponent("b_facebook-feed.jpg"))
        XCTAssertEqual(model.pendingImageCount(with: catalog), 1)
    }
}
