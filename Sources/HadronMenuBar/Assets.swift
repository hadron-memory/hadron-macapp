import AppKit

/// Logo assets bundled as loose PNGs under `Resources/` and loaded via
/// `Bundle.module`. Plain `swift build` copies these verbatim (it does not run
/// `actool`), so we load them as `NSImage` rather than through an asset catalog.
extension NSImage {
    private static func bundled(_ name: String, template: Bool = false) -> NSImage {
        let image: NSImage
        if let url = Bundle.module.url(
            forResource: name, withExtension: "png", subdirectory: "Resources"),
            let loaded = NSImage(contentsOf: url) {
            image = loaded
        } else {
            // Fallback keeps the app usable if a resource ever goes missing.
            image = NSImage(
                systemSymbolName: "brain", accessibilityDescription: "Hadron") ?? NSImage()
        }
        image.isTemplate = template
        return image
    }

    /// Monochrome menu-bar glyph. `isTemplate` lets macOS tint it for the menu
    /// bar appearance (dark in a light bar, light in a dark bar) and its states.
    static let hadronMenuBar: NSImage = {
        let image = bundled("MenuBarIcon", template: true)
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    /// Full-color round logo for the signed-out header, light and dark variants.
    static let hadronHeaderLight = bundled("HeaderLogo-light")
    static let hadronHeaderDark = bundled("HeaderLogo-dark")
}
