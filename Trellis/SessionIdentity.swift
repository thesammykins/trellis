import AppKit
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let sessionIdentityMaximumBytes = 8 * 1_024 * 1_024
private let sessionIdentityMaximumEntries = 128
private let sessionIdentityMaximumPNGBytes = 128 * 1_024
private let sessionIdentityMaximumInputBytes = 2 * 1_024 * 1_024

struct SessionIdentity: Codable, Equatable {
    var iconSFsymbol: String?
    var iconPNGData: Data?
    var accentHex: String?

    init(iconSFsymbol: String? = nil, iconPNGData: Data? = nil, accentHex: String? = nil) {
        self.iconSFsymbol = iconSFsymbol
        self.iconPNGData = iconPNGData
        self.accentHex = accentHex
    }

    var isDefault: Bool { iconSFsymbol == nil && iconPNGData == nil && accentHex == nil }
}

@MainActor
final class SessionIdentityStore: ObservableObject {
    @Published private(set) var error: String?
    private var identities: [UUID: SessionIdentity] = [:]
    private let file: URL

    init(workspaceID: UUID, storageFile: URL? = nil) {
        file = storageFile ?? Self.defaultFile(workspaceID: workspaceID)
        reload()
    }

    func identity(for sessionID: UUID) -> SessionIdentity { identities[sessionID] ?? SessionIdentity() }

    @discardableResult
    func setSymbol(_ symbol: String?, for sessionID: UUID) -> Bool {
        let trimmed = symbol?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == nil || ((1...128).contains(trimmed!.utf8.count)
            && !trimmed!.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)) else {
            error = "An SF Symbol name must be 1–128 bytes without control characters."
            return false
        }
        return replace(sessionID) { identity in
            identity.iconSFsymbol = trimmed
            identity.iconPNGData = nil
        }
    }

    @discardableResult
    func setAccent(_ hex: String?, for sessionID: UUID) -> Bool {
        if hex == nil { return replace(sessionID) { $0.accentHex = nil } }
        guard let hex = Self.normalizedHex(hex) else {
            error = "Choose a six-digit colour value."
            return false
        }
        return replace(sessionID) { $0.accentHex = hex }
    }

    @discardableResult
    func importImage(from url: URL, for sessionID: UUID) -> Bool {
        do {
            let png = try Self.thumbnailPNG(from: url)
            return replace(sessionID) { identity in
                identity.iconSFsymbol = nil
                identity.iconPNGData = png
            }
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func reset(_ sessionID: UUID) -> Bool {
        var updated = identities
        updated.removeValue(forKey: sessionID)
        return save(updated)
    }

    private func replace(_ sessionID: UUID, change: (inout SessionIdentity) -> Void) -> Bool {
        var updated = identities
        var identity = updated[sessionID] ?? SessionIdentity()
        change(&identity)
        if identity.isDefault { updated.removeValue(forKey: sessionID) }
        else { updated[sessionID] = identity }
        return save(updated)
    }

    private func reload() {
        do {
            guard FileManager.default.fileExists(atPath: file.path) else { return }
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= sessionIdentityMaximumBytes else {
                throw Failure("Session identity data must be a regular file under 8 MiB.")
            }
            let stored = try JSONDecoder().decode(Storage.self, from: Data(contentsOf: file, options: .mappedIfSafe))
            try stored.validated()
            identities = stored.identities
            error = nil
        } catch { self.error = "Could not load session identities: \(error.localizedDescription)" }
    }

    private func save(_ updated: [UUID: SessionIdentity]) -> Bool {
        do {
            let stored = Storage(identities: updated)
            try stored.validated()
            let data = try JSONEncoder().encode(stored)
            guard data.count <= sessionIdentityMaximumBytes else { throw Failure("Session identity data exceeds 8 MiB.") }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            identities = updated
            error = nil
            return true
        } catch { self.error = "Could not save session identities: \(error.localizedDescription)"; return false }
    }

    private static func defaultFile(workspaceID: UUID) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppStorageLocation.directoryName, isDirectory: true)
            .appendingPathComponent("SessionIdentities", isDirectory: true)
            .appendingPathComponent(workspaceID.uuidString.lowercased()).appendingPathExtension("json")
    }

    private static func thumbnailPNG(from url: URL) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= sessionIdentityMaximumInputBytes else {
            throw Failure("Choose a regular PNG, JPEG, or HEIC file under 2 MiB.")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) as String?,
              [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier].contains(type) else {
            throw Failure("Choose a PNG, JPEG, or HEIC image.")
        }
        let options: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 128
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
              image.width <= 128, image.height <= 128 else { throw Failure("Could not make a 128-pixel icon.") }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure("Could not create a PNG icon.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), data.length <= sessionIdentityMaximumPNGBytes else {
            throw Failure("The converted icon exceeds 128 KiB.")
        }
        return data as Data
    }

    private static func normalizedHex(_ value: String?) -> String? {
        guard let value else { return nil }
        let hex = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        return hex.uppercased()
    }

    private struct Storage: Codable {
        var version = 1
        var identities: [UUID: SessionIdentity] = [:]

        func validated() throws {
            guard version == 1, identities.count <= sessionIdentityMaximumEntries else {
                throw Failure("Invalid session identity data.")
            }
            for identity in identities.values {
                guard !(identity.iconSFsymbol != nil && identity.iconPNGData != nil),
                      identity.iconSFsymbol.map({ (1...128).contains($0.utf8.count) && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) ?? true,
                      identity.accentHex.map({ $0.count == 6 && $0.allSatisfy(\.isHexDigit) }) ?? true else {
                    throw Failure("Invalid session identity data.")
                }
                if let png = identity.iconPNGData {
                    guard png.count <= sessionIdentityMaximumPNGBytes,
                          let source = CGImageSourceCreateWithData(png as CFData, nil),
                          CGImageSourceGetType(source) as String? == UTType.png.identifier,
                          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                          let width = properties[kCGImagePropertyPixelWidth] as? Int,
                          let height = properties[kCGImagePropertyPixelHeight] as? Int,
                          width <= 128, height <= 128 else { throw Failure("Invalid saved PNG icon.") }
                }
            }
        }
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
