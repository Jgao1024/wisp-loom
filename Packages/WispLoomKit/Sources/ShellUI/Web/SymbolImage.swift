import AppKit

/// SF Symbols rendered as black template PNGs. The page tints them with a CSS mask, so icons follow the
/// text colour, accent colour and dark mode without the page knowing anything about SF Symbols.
@MainActor
enum SymbolImage {
    private static var cache: [String: Data] = [:]

    static func png(named file: String) -> (Data, String)? {
        let name = (file as NSString).deletingPathExtension
        if let data = cache[name] { return (data, "image/png") }
        let config = NSImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        guard
            let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(
                config),
            let tiff = symbol.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        cache[name] = data
        return (data, "image/png")
    }
}
