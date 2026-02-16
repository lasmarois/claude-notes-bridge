import Foundation

// Override SPM's auto-generated Bundle.module to also search
// Contents/Resources/ inside macOS .app bundles.
// SPM's accessor only checks Bundle.main.bundleURL (the .app root),
// but codesign requires resources to be in Contents/Resources/.

private class BundleFinder {}

extension Foundation.Bundle {
    static let notesLibBundle: Bundle = {
        let bundleName = "claude-notes-bridge_NotesLib"

        let candidates: [URL?] = [
            // Standard macOS .app bundle location
            Bundle.main.resourceURL,
            // SPM default: next to the executable / .app root
            Bundle.main.bundleURL,
            // Fallback: next to this framework's binary
            Bundle(for: BundleFinder.self).resourceURL,
        ]

        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
            if let bundlePath, let bundle = Bundle(path: bundlePath.path) {
                return bundle
            }
        }

        // Fall through to SPM's default (will fatalError if also not found)
        return Bundle.module
    }()
}
