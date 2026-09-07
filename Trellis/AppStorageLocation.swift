import Foundation

/// Development rebuilds and fixture sessions must not share the personal archive.
enum AppStorageLocation {
    static var directoryName: String {
        Bundle.main.bundleIdentifier == "in.sammyk.trellis.m0" ? "Trellis Development" : "Trellis"
    }
}
