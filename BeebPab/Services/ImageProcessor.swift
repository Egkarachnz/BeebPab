import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ProcessOptions: Sendable {
    /// Keep EXIF/TIFF camera info. GPS location is always removed.
    var keepCameraInfo = false
}

struct ProcessResult: Sendable, Equatable {
    var outputURL: URL
    var pixelWidth: Int
    var pixelHeight: Int
    var byteCount: Int
    var quality: Double?
    /// True when even the lowest allowed quality could not get under `maxFileSizeKB`.
    var exceedsSizeLimit: Bool
}

enum ImageProcessorError: LocalizedError {
    case unreadable
    case renderFailed
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: return "เปิดไฟล์ภาพนี้ไม่ได้"
        case .renderFailed: return "ประมวลผลภาพไม่สำเร็จ"
        case .encodeFailed: return "บันทึกไฟล์ภาพไม่สำเร็จ"
        }
    }
}

/// Resize pipeline tuned to keep detail after Facebook/LINE re-process the file:
/// orientation → Lanczos downscale (two passes for big reductions) → light unsharp mask
/// → sRGB → JPEG at the highest quality that fits the platform's size budget.
enum ImageProcessor {
    struct Geometry: Equatable {
        var scaledWidth: Int
        var scaledHeight: Int
        var cropWidth: Int
        var cropHeight: Int
    }

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    // CIContext is thread-safe; one shared instance keeps the GPU pipeline warm.
    private static let context = CIContext(options: [
        .cacheIntermediates: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
    ])

    /// Never upscales. With a canvas, scales to cover it and center-crops to its aspect ratio.
    static func geometry(sourceWidth w: Int, sourceHeight h: Int, target: OutputTarget) -> Geometry {
        let W = Double(w), H = Double(h)
        if let canvas = target.canvas {
            let cw = Double(canvas.width), ch = Double(canvas.height)
            let scale = min(1, max(cw / W, ch / H))
            let sw = max(1, Int((W * scale).rounded()))
            let sh = max(1, Int((H * scale).rounded()))
            let aspect = cw / ch
            var cropW = Double(sw), cropH = Double(sh)
            if cropW / cropH > aspect { cropW = cropH * aspect } else { cropH = cropW / aspect }
            return Geometry(scaledWidth: sw, scaledHeight: sh,
                            cropWidth: min(sw, canvas.width, max(1, Int(cropW.rounded()))),
                            cropHeight: min(sh, canvas.height, max(1, Int(cropH.rounded()))))
        }
        var scale = min(1, Double(target.maxLongEdge) / max(W, H))
        if let maxPixels = target.maxPixels {
            scale = min(scale, (Double(maxPixels) / (W * H)).squareRoot())
        }
        // Rounding up could push us one pixel over a pixel-count limit; floor instead.
        let sw = max(1, Int(W * scale + 1e-6))
        let sh = max(1, Int(H * scale + 1e-6))
        let (fw, fh) = scale >= 1 ? (w, h) : (sw, sh)
        return Geometry(scaledWidth: fw, scaledHeight: fh, cropWidth: fw, cropHeight: fh)
    }

    static func process(inputURL: URL, target: OutputTarget, outputURL: URL,
                        options: ProcessOptions = ProcessOptions()) throws -> ProcessResult {
        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var image = CIImage(contentsOf: inputURL, options: [.applyOrientationProperty: true]),
              !image.extent.isInfinite, !image.extent.isEmpty else {
            throw ImageProcessorError.unreadable
        }
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let w = Int(image.extent.width.rounded()), h = Int(image.extent.height.rounded())
        let hasAlpha = (props[kCGImagePropertyHasAlpha] as? Bool) ?? false

        let g = geometry(sourceWidth: w, sourceHeight: h, target: target)
        let downscaled = g.scaledWidth < w || g.scaledHeight < h
        if downscaled {
            image = lanczos(image, fromWidth: w, fromHeight: h, toWidth: g.scaledWidth, toHeight: g.scaledHeight)
        }

        if g.cropWidth != g.scaledWidth || g.cropHeight != g.scaledHeight {
            let x = (g.scaledWidth - g.cropWidth) / 2
            let y = (g.scaledHeight - g.cropHeight) / 2
            image = image
                .cropped(to: CGRect(x: x, y: y, width: g.cropWidth, height: g.cropHeight))
                .transformed(by: CGAffineTransform(translationX: CGFloat(-x), y: CGFloat(-y)))
        }

        let rect = CGRect(x: 0, y: 0, width: g.cropWidth, height: g.cropHeight)
        if downscaled, let s = target.sharpen, s.radius > 0, s.intensity > 0 {
            let f = CIFilter.unsharpMask()
            f.inputImage = image.clampedToExtent()
            f.radius = Float(s.radius)
            f.intensity = Float(s.intensity)
            if let out = f.outputImage { image = out.cropped(to: rect) }
        }

        if target.format == .jpeg && hasAlpha {
            image = image.composited(over: CIImage(color: .white).cropped(to: rect))
        }

        // Rendering into sRGB converts P3/Adobe RGB colours so they don't look washed out
        // after the platform strips the colour profile.
        guard let cgImage = context.createCGImage(image, from: rect, format: .RGBA8, colorSpace: sRGB) else {
            throw ImageProcessorError.renderFailed
        }

        let meta = metadata(from: props, keepCameraInfo: options.keepCameraInfo)
        let (data, quality, oversize) = try encode(cgImage, target: target, metadata: meta)
        try data.write(to: outputURL, options: .atomic)
        return ProcessResult(outputURL: outputURL, pixelWidth: g.cropWidth, pixelHeight: g.cropHeight,
                             byteCount: data.count, quality: quality, exceedsSizeLimit: oversize)
    }

    // MARK: - Steps

    static func lanczos(_ image: CIImage, fromWidth: Int, fromHeight: Int, toWidth: Int, toHeight: Int) -> CIImage {
        var current = image
        var cw = fromWidth, ch = fromHeight
        // Big reductions alias less when done in two passes.
        if Double(toWidth) / Double(fromWidth) < 0.5 {
            let midW = toWidth * 2, midH = toHeight * 2
            current = lanczosStep(current, fromWidth: cw, fromHeight: ch, toWidth: midW, toHeight: midH)
            cw = midW; ch = midH
        }
        return lanczosStep(current, fromWidth: cw, fromHeight: ch, toWidth: toWidth, toHeight: toHeight)
    }

    private static func lanczosStep(_ image: CIImage, fromWidth: Int, fromHeight: Int, toWidth: Int, toHeight: Int) -> CIImage {
        let sx = Double(toWidth) / Double(fromWidth)
        let sy = Double(toHeight) / Double(fromHeight)
        let f = CIFilter.lanczosScaleTransform()
        // Clamp so the filter doesn't pull transparent pixels in at the edges (dark fringe).
        f.inputImage = image.clampedToExtent()
        f.scale = Float(sy)
        f.aspectRatio = Float(sx / sy)
        return (f.outputImage ?? image).cropped(to: CGRect(x: 0, y: 0, width: toWidth, height: toHeight))
    }

    static func metadata(from props: [CFString: Any], keepCameraInfo: Bool) -> [CFString: Any] {
        var out: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        guard keepCameraInfo else { return out }
        if var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
            exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension)
            out[kCGImagePropertyExifDictionary] = exif
        }
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            out[kCGImagePropertyTIFFDictionary] = tiff
        }
        if let iptc = props[kCGImagePropertyIPTCDictionary] { out[kCGImagePropertyIPTCDictionary] = iptc }
        // GPS is intentionally never copied.
        return out
    }

    static func encode(_ image: CGImage, target: OutputTarget, metadata: [CFString: Any]) throws -> (Data, Double?, Bool) {
        let limit = target.maxFileSizeKB * 1024
        switch target.format {
        case .png:
            let data = try encodeOnce(image, type: .png, quality: nil, metadata: metadata)
            return (data, nil, data.count > limit)
        case .jpeg:
            let q = target.effectiveQuality
            let top = try encodeOnce(image, type: .jpeg, quality: q.max, metadata: metadata)
            if top.count <= limit { return (top, q.max, false) }

            // Highest quality that still fits the budget.
            var lo = q.min, hi = q.max
            var best: (Data, Double)?
            for _ in 0..<6 {
                let mid = (lo + hi) / 2
                let data = try encodeOnce(image, type: .jpeg, quality: mid, metadata: metadata)
                if data.count <= limit { best = (data, mid); lo = mid } else { hi = mid }
            }
            if let best { return (best.0, best.1, false) }

            // Still too big: step down below the preferred range, but not below 0.6.
            var quality = q.min
            while quality >= 0.6 {
                let data = try encodeOnce(image, type: .jpeg, quality: quality, metadata: metadata)
                if data.count <= limit { return (data, quality, false) }
                quality -= 0.05
            }
            let data = try encodeOnce(image, type: .jpeg, quality: 0.6, metadata: metadata)
            return (data, 0.6, data.count > limit)
        }
    }

    private static func encodeOnce(_ image: CGImage, type: UTType, quality: Double?, metadata: [CFString: Any]) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw ImageProcessorError.encodeFailed
        }
        var props = metadata
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageProcessorError.encodeFailed }
        return data as Data
    }

    // MARK: - Info for the grid

    static func thumbnail(for url: URL, maxPixel: Int = 320) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary)
    }

    /// Pixel size after applying EXIF orientation.
    static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        return orientation >= 5 ? (h, w) : (w, h)
    }
}
