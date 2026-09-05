import Foundation

/// English is the development language. Keep user-facing strings in Resources.
enum L10n {
    // Packaged apps load from Contents/Resources. SwiftPM's fallback is for
    // command-line builds and tests only, including older toolchain layouts.
    static let bundle: Bundle = {
        if let url = Bundle.main.url(forResource: "DotShelf_KonfigEditor", withExtension: "bundle"),
           let resources = Bundle(url: url) {
            return resources
        }
        return .module
    }()

    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}
