#!/usr/bin/env swift
import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

// Reproduce the approved image's production assets without changing its artwork.
// Run from the repository root: swift docs/icon-redesign/apricot/export.swift
struct ExportFailure: Error, CustomStringConvertible {
    let description: String
}

let exportDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repository = exportDirectory.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let sourceURL = exportDirectory.appendingPathComponent("source.png")
let assetDirectory = repository.appendingPathComponent("Sources/QingLi/Assets.xcassets/AppIcon.appiconset")
let sizes = [16, 32, 64, 128, 256, 512, 1024]
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func loadSource(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw ExportFailure(description: "Cannot read source: \(url.path)")
    }
    return image
}

func largestComponent(_ alpha: [UInt8], width: Int, height: Int) -> [Bool] {
    var visited = [Bool](repeating: false, count: width * height)
    var largest: [Int] = []
    for start in alpha.indices where !visited[start] && alpha[start] > 32 {
        var component = [start]
        visited[start] = true
        var cursor = 0
        while cursor < component.count {
            let index = component[cursor]
            cursor += 1
            let x = index % width
            let y = index / width
            let neighbors = [x > 0 ? index - 1 : -1, x + 1 < width ? index + 1 : -1,
                             y > 0 ? index - width : -1, y + 1 < height ? index + width : -1]
            for neighbor in neighbors where neighbor >= 0 && !visited[neighbor] && alpha[neighbor] > 32 {
                visited[neighbor] = true
                component.append(neighbor)
            }
        }
        if component.count > largest.count { largest = component }
    }
    var retained = [Bool](repeating: false, count: alpha.count)
    for index in largest { retained[index] = true }
    return retained
}

func removeAttachedFringe(_ alpha: [UInt8], width: Int, height: Int) -> [UInt8] {
    // A 3-pixel disk opening removes thin attached alpha spikes while preserving
    // the image's actual silhouette, including its asymmetric paper curl.
    let offsets = (-3...3).flatMap { y in
        (-3...3).compactMap { x in x * x + y * y <= 9 ? (x, y) : nil }
    }
    func filtered(_ input: [UInt8], eroding: Bool) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: input.count)
        for y in 3..<(height - 3) {
            for x in 3..<(width - 3) {
                var value: UInt8 = eroding ? 255 : 0
                for (dx, dy) in offsets {
                    let neighbor = input[(y + dy) * width + x + dx]
                    value = eroding ? min(value, neighbor) : max(value, neighbor)
                }
                result[y * width + x] = value
            }
        }
        return result
    }
    return filtered(filtered(alpha, eroding: true), eroding: false)
}

func normalizedArtwork(_ image: CGImage) throws -> CGImage {
    // The checked-in generator output stores straight RGBA. Reading its original
    // channels avoids color loss from unpremultiplying its almost-opaque body.
    guard image.bitsPerComponent == 8, image.bitsPerPixel == 32,
          image.alphaInfo == .last, image.bitmapInfo.intersection(.byteOrderMask).isEmpty,
          let sourceData = image.dataProvider?.data,
          let bytes = CFDataGetBytePtr(sourceData) else {
        throw ExportFailure(description: "Source must be the approved 8-bit straight RGBA PNG")
    }
    let width = image.width
    let height = image.height
    let alpha = (0..<(width * height)).map { bytes[($0 / width) * image.bytesPerRow + ($0 % width) * 4 + 3] }
    let retained = largestComponent(alpha, width: width, height: height)
    // Remove faint generated fringe and make the body fully opaque. Smoothstep
    // keeps an antialiased transition along the original silhouette.
    let normalized = alpha.indices.map { index -> UInt8 in
        guard retained[index] else { return 0 }
        let transition = min(1, max(0, (Double(alpha[index]) - 32) / 192))
        return UInt8((255 * transition * transition * (3 - 2 * transition)).rounded())
    }
    let cleanAlpha = removeAttachedFringe(normalized, width: width, height: height)
    var output = [UInt8](repeating: 0, count: width * height * 4)
    for index in alpha.indices where cleanAlpha[index] > 0 {
        let normalizedAlpha = cleanAlpha[index]
        let sourceOffset = (index / width) * image.bytesPerRow + (index % width) * 4
        let outputOffset = index * 4
        for channel in 0..<3 {
            output[outputOffset + channel] = UInt8((Int(bytes[sourceOffset + channel]) * Int(normalizedAlpha) + 127) / 255)
        }
        output[outputOffset + 3] = normalizedAlpha
    }
    let provider = CGDataProvider(data: Data(output) as CFData)!
    guard let result = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: colorSpace,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
        throw ExportFailure(description: "Cannot create normalized artwork")
    }
    return result
}

func resized(_ image: CGImage, to size: Int) throws -> CGImage {
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw ExportFailure(description: "Cannot allocate \(size)-pixel render")
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let result = context.makeImage() else { throw ExportFailure(description: "Cannot render image") }
    return result
}

func savePNG(_ image: CGImage, at url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw ExportFailure(description: "Cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw ExportFailure(description: "PNG export failed: \(url.path)") }
}

func checksum(_ url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
}

let original = try loadSource(sourceURL)
let artwork = try normalizedArtwork(original)
var outputs: [[String: Any]] = []
for size in sizes {
    let outputURL = assetDirectory.appendingPathComponent("icon_\(size).png")
    try savePNG(try resized(artwork, to: size), at: outputURL)
    outputs.append(["size": size, "path": "Sources/QingLi/Assets.xcassets/AppIcon.appiconset/icon_\(size).png", "sha256": try checksum(outputURL)])
    print("Exported \(size) × \(size): \(outputURL.path)")
}
let productionURL = exportDirectory.appendingPathComponent("production-1024.png")
try savePNG(try resized(artwork, to: 1024), at: productionURL)
try savePNG(try resized(artwork, to: 512), at: exportDirectory.appendingPathComponent("production-preview.png"))
try savePNG(try resized(artwork, to: 22), at: exportDirectory.appendingPathComponent("production-small-preview.png"))
let documentationURL = repository.appendingPathComponent("docs/清历-App图标.png")
try Data(contentsOf: productionURL).write(to: documentationURL, options: .atomic)

let manifest: [String: Any] = [
    "status": "production-integrated",
    "name": "暖橙日历",
    "design_candidate_name": "杏橘翻页",
    "generator": "built-in image_gen",
    "reference_role": "Huaban screenshot as style reference; original design",
    "references": ["https://huaban.com/pins/6902442520/", "https://huaban.com/pins/7072718740/"],
    "master": "source.png",
    "source_sha256": try checksum(sourceURL),
    "source_size": [original.width, original.height],
    "export": "production-1024.png",
    "candidate_export": "qingli-apricot-1024.png",
    "preview": "production-preview.png",
    "small_preview": "production-small-preview.png",
    "candidate_preview": "preview.png",
    "candidate_small_preview": "qingli-apricot-22.png",
    "prompt": "prompt.txt",
    "app_icon_integrated": true,
    "export_script": "export.swift",
    "export_command": "swift docs/icon-redesign/apricot/export.swift",
    "export_method": "Original straight RGB preserved; retain largest alpha>32 component; normalize alpha with smoothstep(32,224); remove thin attached fringe with 3-source-pixel disk grayscale opening on alpha only; render each size directly from the normalized source with CoreGraphics high-quality interpolation; encode sRGB RGBA PNG.",
    "artwork": "Approved warm orange calendar, warm white paper, dark 31 and curled corner; no redrawing or creative regeneration.",
    "app_icon_catalog_slots": 10,
    "outputs": outputs,
    "production_sha256": try checksum(productionURL),
    "documentation_copy": "docs/清历-App图标.png"
]
let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try (manifestData + Data("\n".utf8)).write(to: exportDirectory.appendingPathComponent("manifest.json"), options: .atomic)
