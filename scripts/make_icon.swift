import Foundation
import ImageIO
import UniformTypeIdentifiers

// Regenerate the macOS icon set from its full-resolution artwork.
// Usage: swift scripts/make_icon.swift [output-directory] [source-png]
let assetDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Lookaway/Assets.xcassets/AppIcon.appiconset")
let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : assetDirectory
let sourceURL = CommandLine.arguments.count > 2
    ? URL(fileURLWithPath: CommandLine.arguments[2])
    : assetDirectory.appendingPathComponent("appicon-1024.png")

let sourceData = try Data(contentsOf: sourceURL)
guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
      let original = CGImageSourceCreateImageAtIndex(source, 0, nil),
      original.width == 1024, original.height == 1024 else {
    fatalError("Icon source must be a readable 1024 x 1024 image")
}
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let files: [(Int, String)] = [
    (16, "appicon-16.png"), (32, "appicon-16@2x.png"),
    (32, "appicon-32.png"), (64, "appicon-32@2x.png"),
    (128, "appicon-128.png"), (256, "appicon-128@2x.png"),
    (256, "appicon-256.png"), (512, "appicon-256@2x.png"),
    (512, "appicon-512.png"), (1024, "appicon-1024.png")
]

for (pixels, filename) in files {
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: pixels,
        kCGImageSourceCreateThumbnailWithTransform: true
    ]
    let outputURL = outputDirectory.appendingPathComponent(filename)
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
          let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Could not render \(filename)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Could not write \(filename)")
    }
    print("Wrote \(filename) (\(pixels)px)")
}
