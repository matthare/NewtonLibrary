import AppKit
import SwiftUI

extension NewtonBitmap {
    /// The bitmap as a Mac image (grey + alpha drawn as premultiplied RGBA).
    func makeImage() -> NSImage? {
        let count = width * height
        guard grey.count == count, alpha.count == count else { return nil }
        var rgba = [UInt8](repeating: 0, count: count * 4)
        for i in 0..<count {
            let a = Int(alpha[i])
            let g = UInt8(Int(grey[i]) * a / 255)
            rgba[i * 4] = g
            rgba[i * 4 + 1] = g
            rgba[i * 4 + 2] = g
            rgba[i * 4 + 3] = UInt8(a)
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false,
                                    intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}

/// Converted icons, kept so the list doesn't redraw them all the time.
final class IconCache {
    static let shared = IconCache()
    private var images: [String: NSImage] = [:]

    /// Forgets the converted icons (after packages are read again).
    func removeAll() {
        images.removeAll()
    }

    func image(for item: LibraryItem) -> NSImage? {
        if let cached = images[item.sha256] { return cached }
        guard let image = item.info.icon?.makeImage() else { return nil }
        images[item.sha256] = image
        return image
    }
}

/// A package's Newton icon, with its pixels kept sharp, or a symbol for its kind.
struct PackageIcon: View {
    let item: LibraryItem
    var size: CGFloat
    @AppStorage(IconBackground.key) private var background = IconBackground.standard

    var body: some View {
        if let image = IconCache.shared.image(for: item) {
            // Newton icons were drawn for a light screen: show them on a backlight-green tile
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(size * 0.08)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: max(2, size * 0.14))
                    .fill(IconBackground.color(from: background)))
        } else {
            Image(systemName: item.iconKind.symbolName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(size * 0.15)
                .frame(width: size, height: size)
                .foregroundColor(.secondary)
        }
    }
}

/// The colour behind Newton icons, set in Preferences. Stored as "red,green,blue"
/// (0-1, sRGB).
enum IconBackground {
    static let key = "IconBackgroundColor"
    /// Like the green of a MessagePad 2100's backlight.
    static let standard = "0.62,0.86,0.70"

    static func color(from stored: String) -> Color {
        let parts = stored.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 3 else { return color(from: standard) }
        return Color(.sRGB, red: parts[0], green: parts[1], blue: parts[2], opacity: 1)
    }

    static func string(from color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.62, green: 0.86, blue: 0.70, alpha: 1)
        return String(format: "%.3f,%.3f,%.3f", ns.redComponent, ns.greenComponent, ns.blueComponent)
    }
}
