import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Card images, stored once per content so a changed image changes the deck file too.
public struct MediaStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static let maxPixelSize = 1024
    public static let maxSourceBytes = 20 * 1024 * 1024

    public static func isValidName(_ name: String) -> Bool {
        name.range(of: #"^[0-9a-f]{16}\.jpg$"#, options: .regularExpression) != nil
    }

    /// Downscales and re-encodes any image ImageIO can read, saves it, and returns its file name.
    public func add(_ data: Data) throws -> String {
        let jpeg = try Self.normalized(data)
        let name = SHA256.hash(data: jpeg).prefix(8).map { String(format: "%02x", $0) }.joined() + ".jpg"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try jpeg.write(to: url, options: .atomic)
        }
        return name
    }

    public func data(named name: String) -> Data? {
        guard Self.isValidName(name) else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(name))
    }

    /// JPEG, longest side at most `maxPixelSize`, orientation applied, metadata dropped.
    public static func normalized(_ data: Data) throws -> Data {
        guard data.count <= maxSourceBytes else { throw DeckValidationError(description: "image is larger than 20 MB") }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            throw DeckValidationError(description: "not an image ImageIO can read")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw DeckValidationError(description: "could not decode the image")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw DeckValidationError(description: "could not encode the image")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw DeckValidationError(description: "could not encode the image") }
        return output as Data
    }
}
