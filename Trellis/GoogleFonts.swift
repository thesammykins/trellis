import AppKit
import CoreText
import SwiftUI

struct GoogleFont: Identifiable, Sendable, Equatable {
    let family: String
    let note: String
    var id: String { family }
    var specimenURL: URL { URL(string: "https://fonts.google.com/specimen/" + family.replacingOccurrences(of: " ", with: "+"))! }
}

enum GoogleFontsCatalog {
    /// Curated because Google's complete catalogue API requires an API key.
    static let fonts = [
        GoogleFont(family: "JetBrains Mono", note: "Clear punctuation and coding ligatures"),
        GoogleFont(family: "Roboto Mono", note: "Neutral and compact"),
        GoogleFont(family: "IBM Plex Mono", note: "Technical, readable shapes"),
        GoogleFont(family: "Inconsolata", note: "Humanist and space efficient"),
        GoogleFont(family: "Space Mono", note: "Wide, distinctive forms"),
    ]

    static let cssDocumentation = URL(string: "https://developers.google.com/fonts/docs/css2")!
    static let licensing = URL(string: "https://developers.google.com/fonts")!
}

struct GoogleFontRegistrationReport: Sendable {
    let registeredFamilies: [String]
    let failures: [String]
}

enum GoogleFontsStore {
    static let maximumStylesheetBytes = 256 * 1024
    static let maximumFontBytes = 20 * 1024 * 1024

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppStorageLocation.directoryName, isDirectory: true)
            .appendingPathComponent("Google Fonts", isDirectory: true)
    }

    static func cssURL(for font: GoogleFont) -> URL {
        var components = URLComponents(string: "https://fonts.googleapis.com/css2")!
        components.queryItems = [
            URLQueryItem(name: "family", value: font.family + ":wght@400"),
            URLQueryItem(name: "display", value: "swap"),
        ]
        return components.url!
    }

    static func isTrusted(_ url: URL?, host: String) -> Bool {
        url?.scheme == "https" && url?.host?.lowercased() == host && url?.user == nil && url?.password == nil
    }

    static func fontURL(from stylesheet: Data) throws -> URL {
        guard stylesheet.count <= maximumStylesheetBytes,
              let css = String(data: stylesheet, encoding: .utf8) else { throw GoogleFontsError.invalidStylesheet }
        let range = NSRange(css.startIndex..., in: css)
        let blockExpression = try NSRegularExpression(pattern: #"@font-face\s*\{[^}]*\}"#)
        let blocks = blockExpression.matches(in: css, range: range).compactMap { match in
            Range(match.range, in: css).map { String(css[$0]) }
        }
        guard let block = blocks.first(where: { $0.localizedCaseInsensitiveContains("U+0000-00FF") }) ?? (blocks.count == 1 ? blocks[0] : nil) else {
            throw GoogleFontsError.invalidStylesheet
        }
        let expression = try NSRegularExpression(pattern: #"url\(['\"]?(https://fonts\.gstatic\.com/[^)'\"\s]+)['\"]?\)"#)
        let blockRange = NSRange(block.startIndex..., in: block)
        guard let match = expression.firstMatch(in: block, range: blockRange),
              let urlRange = Range(match.range(at: 1), in: block),
              let url = URL(string: String(block[urlRange])), isTrusted(url, host: "fonts.gstatic.com") else {
            throw GoogleFontsError.invalidStylesheet
        }
        return url
    }

    static func validateFont(_ data: Data, expectedFamily: String) throws -> String {
        guard !data.isEmpty, data.count <= maximumFontBytes,
              let provider = CGDataProvider(data: data as CFData),
              let graphicsFont = CGFont(provider) else { throw GoogleFontsError.invalidFont }
        let font = CTFontCreateWithGraphicsFont(graphicsFont, 12, nil, nil)
        let actual = CTFontCopyFamilyName(font) as String
        guard normalized(actual) == normalized(expectedFamily) else {
            throw GoogleFontsError.wrongFamily(expected: expectedFamily, actual: actual)
        }
        let characters = Array("A0{}[]".utf16)
        var glyphs = Array(repeating: CGGlyph(), count: characters.count)
        guard CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count),
              glyphs.allSatisfy({ $0 != 0 }) else { throw GoogleFontsError.missingTerminalGlyphs }
        var advances = Array(repeating: CGSize.zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
        guard let first = advances.first?.width, first > 0,
              advances.allSatisfy({ abs($0.width - first) < 0.01 }) else { throw GoogleFontsError.notMonospace }
        return actual
    }

    static func install(_ data: Data, font: GoogleFont, directory: URL = defaultDirectory) throws -> URL {
        guard GoogleFontsCatalog.fonts.contains(font) else { throw GoogleFontsError.unknownFont }
        _ = try validateFont(data, expectedFamily: font.family)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let directoryValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else { throw GoogleFontsError.unsafeStorage }
        let destination = directory.appendingPathComponent(safeFilename(font.family) + ".woff")
        if FileManager.default.fileExists(atPath: destination.path) {
            guard try destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw GoogleFontsError.unsafeStorage
            }
        }
        try data.write(to: destination, options: [.atomic])
        try register(destination, expectedFamily: font.family)
        return destination
    }

    static func registerInstalled(directory: URL = defaultDirectory) -> GoogleFontRegistrationReport {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return .init(registeredFamilies: [], failures: [])
        }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            var families: [String] = [], failures: [String] = []
            for file in files.prefix(GoogleFontsCatalog.fonts.count) where file.pathExtension == "woff" {
                do {
                    let data = try boundedData(at: file, maximumBytes: maximumFontBytes)
                    let family = try validateFont(data, expectedFamily: file.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " "))
                    try register(file, expectedFamily: family)
                    families.append(family)
                } catch { failures.append(file.lastPathComponent + ": " + error.localizedDescription) }
            }
            return .init(registeredFamilies: families.sorted(), failures: failures)
        } catch {
            return .init(registeredFamilies: [], failures: [error.localizedDescription])
        }
    }

    static func boundedData(at url: URL, maximumBytes: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximumBytes else {
            throw GoogleFontsError.invalidFont
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func register(_ url: URL, expectedFamily: String) throws {
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return }
        if NSFontManager.shared.availableFontFamilies.contains(where: { normalized($0) == normalized(expectedFamily) }) { return }
        throw GoogleFontsError.registrationFailed(error?.takeRetainedValue().localizedDescription ?? "Core Text rejected the font.")
    }

    private static func safeFilename(_ family: String) -> String { family.replacingOccurrences(of: " ", with: "_") }
    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

actor GoogleFontsDownloader {
    private let directory: URL
    private let session: URLSession

    init(directory: URL = GoogleFontsStore.defaultDirectory) {
        self.directory = directory
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 Firefox/128.0"]
        session = URLSession(configuration: configuration, delegate: GoogleFontsRedirectDelegate(), delegateQueue: nil)
    }

    func download(_ font: GoogleFont) async throws -> URL {
        let cssURL = GoogleFontsStore.cssURL(for: font)
        let stylesheet = try await boundedData(from: cssURL, expectedHost: "fonts.googleapis.com",
                                               maximumBytes: GoogleFontsStore.maximumStylesheetBytes)
        let fontURL = try GoogleFontsStore.fontURL(from: stylesheet)
        let data = try await boundedData(from: fontURL, expectedHost: "fonts.gstatic.com",
                                         maximumBytes: GoogleFontsStore.maximumFontBytes)
        try Task.checkCancellation()
        return try GoogleFontsStore.install(data, font: font, directory: directory)
    }

    private func boundedData(from url: URL, expectedHost: String, maximumBytes: Int) async throws -> Data {
        let (bytes, response) = try await session.bytes(from: url)
        try validate(response, expectedHost: expectedHost, maximumBytes: maximumBytes)
        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(response.expectedContentLength), maximumBytes))
        }
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw GoogleFontsError.invalidResponse }
            data.append(byte)
        }
        guard !data.isEmpty else { throw GoogleFontsError.invalidResponse }
        return data
    }

    private func validate(_ response: URLResponse, expectedHost: String, maximumBytes: Int) throws {
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
              GoogleFontsStore.isTrusted(response.url, host: expectedHost),
              response.expectedContentLength <= 0 || response.expectedContentLength <= maximumBytes else {
            throw GoogleFontsError.invalidResponse
        }
    }
}

private final class GoogleFontsRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let host = task.originalRequest?.url?.host?.lowercased()
        completionHandler(host.map { GoogleFontsStore.isTrusted(request.url, host: $0) } == true ? request : nil)
    }
}

@MainActor
private final class GoogleFontsModel: ObservableObject {
    @Published var query = ""
    @Published var busyFamily: String?
    @Published var installed = Set<String>()
    @Published var error: String?
    private let downloader = GoogleFontsDownloader()
    private var task: Task<Void, Never>?
    private var operationID = UUID()

    init() {
        let report = GoogleFontsStore.registerInstalled()
        installed = Set(report.registeredFamilies)
        error = report.failures.isEmpty ? nil : report.failures.joined(separator: "\n")
    }

    var filteredFonts: [GoogleFont] {
        query.isEmpty ? GoogleFontsCatalog.fonts : GoogleFontsCatalog.fonts.filter {
            $0.family.localizedCaseInsensitiveContains(query) || $0.note.localizedCaseInsensitiveContains(query)
        }
    }

    func download(_ font: GoogleFont, onSelect: @escaping (String) -> Void) {
        task?.cancel(); busyFamily = font.family; error = nil; operationID = UUID()
        let operationID = operationID
        task = Task { [weak self] in
            do {
                guard let self else { return }
                _ = try await self.downloader.download(font)
                try Task.checkCancellation()
                guard self.operationID == operationID else { return }
                self.installed.insert(font.family); self.busyFamily = nil; onSelect(font.family)
            } catch is CancellationError { if self?.operationID == operationID { self?.busyFamily = nil } }
            catch where Task.isCancelled { if self?.operationID == operationID { self?.busyFamily = nil } }
            catch { if self?.operationID == operationID { self?.busyFamily = nil; self?.error = error.localizedDescription } }
        }
    }

    func cancel() { task?.cancel(); task = nil }
}

struct GoogleFontsView: View {
    let selectedFamily: String
    let onSelect: (String) -> Void
    @StateObject private var model = GoogleFontsModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search curated monospace fonts", text: $model.query)
                if let busyFamily = model.busyFamily {
                    Button("Cancel") { model.cancel() }
                        .accessibilityLabel("Cancel " + busyFamily + " download")
                }
            }.padding()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.filteredFonts) { font in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(font.family).font(model.installed.contains(font.family) ? .custom(font.family, size: 16) : .headline)
                                Text(font.note).font(.caption).foregroundStyle(.secondary)
                                Link("Specimen and license", destination: font.specimenURL)
                                    .font(.caption)
                                    .accessibilityLabel(font.family + " specimen and license")
                            }
                            Spacer()
                            if model.busyFamily == font.family {
                                ProgressView().controlSize(.small)
                                    .accessibilityLabel("Downloading " + font.family)
                            } else if model.installed.contains(font.family) {
                                Button(selectedFamily == font.family ? "Selected" : "Use") { onSelect(font.family) }
                                    .disabled(selectedFamily == font.family || model.busyFamily != nil)
                                    .accessibilityLabel(selectedFamily == font.family ? font.family + " selected" : "Use " + font.family)
                            } else {
                                Button("Download") { model.download(font, onSelect: onSelect) }
                                    .disabled(model.busyFamily != nil)
                                    .accessibilityLabel("Download " + font.family)
                            }
                        }
                        .padding(.horizontal).padding(.vertical, 8)
                        .accessibilityElement(children: .contain)
                        if font.id != model.filteredFonts.last?.id { Divider().padding(.leading) }
                    }
                }
            }
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            HStack {
                Text("Curated Google Fonts catalogue")
                Spacer()
                Link("CSS API", destination: GoogleFontsCatalog.cssDocumentation)
                Link("Licensing", destination: GoogleFontsCatalog.licensing)
            }.font(.caption).foregroundStyle(.secondary).padding()
        }
        .frame(minWidth: 520, minHeight: 420)
        .onDisappear { model.cancel() }
    }
}

enum GoogleFontsError: LocalizedError {
    case invalidStylesheet, invalidResponse, invalidFont, notMonospace, missingTerminalGlyphs, unknownFont, unsafeStorage
    case wrongFamily(expected: String, actual: String)
    case registrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidStylesheet: "Google Fonts returned an invalid stylesheet."
        case .invalidResponse: "Google Fonts returned an invalid or oversized response."
        case .invalidFont: "The downloaded file is not a valid bounded font."
        case .notMonospace: "The downloaded font is not fixed pitch."
        case .missingTerminalGlyphs: "The downloaded font is missing basic terminal glyphs."
        case .unknownFont: "Choose a font from Trellis’s curated Google Fonts catalogue."
        case .unsafeStorage: "The managed font folder contains an unsafe symbolic link."
        case let .wrongFamily(expected, actual): "Expected \(expected), but the font identifies itself as \(actual)."
        case let .registrationFailed(message): "The font could not be registered: \(message)"
        }
    }
}
