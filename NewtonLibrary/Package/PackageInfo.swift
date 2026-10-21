import Foundation

/// Which versions of the Newton OS a package works with.
enum NewtonOS: String, Codable, CaseIterable, Identifiable {
    /// Nothing in the package needs Newton OS 2.0, so it should work on 1.x and 2.x.
    case any = "any"
    /// Only works on Newton OS 1.x (never detected; set by hand).
    case os1Only = "1.x"
    case os20 = "2.0"
    case os21 = "2.1"
    case unknown = "unknown"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: return "Newton OS 1.x and 2.x"
        case .os1Only: return "Newton OS 1.x only"
        case .os20: return "Newton OS 2.0 and later"
        case .os21: return "Newton OS 2.1"
        case .unknown: return "Unknown"
        }
    }

    var sidebarLabel: String {
        switch self {
        case .any: return "1.x and 2.x"
        case .os1Only: return "1.x Only"
        case .os20: return "2.0 and Later"
        case .os21: return "2.1"
        case .unknown: return "Unknown"
        }
    }

    var shortLabel: String {
        switch self {
        case .any: return "1.x and 2.x"
        case .os1Only: return "1.x only"
        case .os20: return "2.0+"
        case .os21: return "2.1"
        case .unknown: return "Unknown"
        }
    }

    /// For sorting, oldest first.
    var rank: Int {
        switch self {
        case .os1Only: return 0
        case .any: return 1
        case .os20: return 2
        case .os21: return 3
        case .unknown: return 4
        }
    }
}

/// Newton OS version numbers, for a package's minimum and maximum. "1.x" means
/// some 1.x version: it runs on 1.x, but nothing shows which one it needs.
enum NewtonOSVersion {
    static let all = ["1.x", "1.0", "1.1", "1.2", "1.3", "2.0", "2.1", "2.2"]

    /// For comparing: "1.x" counts as 1.0. Nil for "" (not known).
    static func rank(_ version: String) -> Double? {
        version == "1.x" ? 1.0 : Double(version)
    }

    static func label(_ version: String) -> String {
        switch version {
        case "": return "Not known"
        case "1.x": return "1.x (any)"
        default: return version
        }
    }

    /// The sidebar group for a minimum and maximum, or nil if the minimum isn't known.
    static func group(min: String, max: String) -> NewtonOS? {
        guard let low = rank(min) else { return nil }
        if let high = rank(max), high < 2.0 { return .os1Only }
        if low >= 2.1 { return .os21 }
        if low >= 2.0 { return .os20 }
        return .any
    }

    /// The minimum and maximum that put a package in a sidebar group.
    static func range(for group: NewtonOS) -> (min: String, max: String) {
        switch group {
        case .any: return ("1.x", "")
        case .os1Only: return ("1.x", "1.3")
        case .os20: return ("2.0", "")
        case .os21: return ("2.1", "")
        case .unknown: return ("", "")
        }
    }
}

enum PackageKind: String, Codable, CaseIterable, Identifiable {
    case application, game, book, sound, extensionPart, font, dictionary, systemUpdate, driver, data, other

    /// An application of any sort (a game is an application too).
    var isApplication: Bool { self == .application || self == .game }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .application: return "Application"
        case .game: return "Game"
        case .book: return "Book"
        case .sound: return "Sound"
        case .extensionPart: return "Extension"
        case .font: return "Font"
        case .dictionary: return "Dictionary"
        case .systemUpdate: return "System Update"
        case .driver: return "Driver"
        case .data: return "Data"
        case .other: return "Other"
        }
    }

    var pluralLabel: String {
        switch self {
        case .application: return "Applications"
        case .game: return "Games"
        case .book: return "Books"
        case .sound: return "Sounds"
        case .extensionPart: return "Extensions"
        case .font: return "Fonts"
        case .dictionary: return "Dictionaries"
        case .systemUpdate: return "System Updates"
        case .driver: return "Drivers"
        case .data: return "Data"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .application: return "app"
        case .game: return "gamecontroller"
        case .book: return "book.closed"
        case .sound: return "speaker.wave.2"
        case .extensionPart: return "puzzlepiece"
        case .font: return "textformat"
        case .dictionary: return "character.book.closed"
        case .systemUpdate: return "gearshape"
        case .driver: return "cable.connector"
        case .data: return "tray.full"
        case .other: return "shippingbox"
        }
    }
}

/// One reason for the Newton OS verdict, or a note worth showing.
struct Evidence: Codable, Hashable {
    /// The Newton OS version this shows the package needs, or nil for a note.
    var requires: NewtonOS?
    var text: String
}

struct PartInfo: Codable, Hashable {
    var type: String        // four-character part type, e.g. "form"
    var kind: PackageKind
    var size: Int
    var flags: [String]
}

/// A Newton bitmap converted to 8-bit grey (0 = black, 255 = white) plus alpha.
struct NewtonBitmap: Codable, Hashable {
    var width: Int
    var height: Int
    var grey: Data
    var alpha: Data
}

/// Everything learned from one package file.
struct PackageInfo: Codable, Hashable {
    var title: String
    /// The name shown in the Extras drawer, if the package has one.
    var extrasName: String?
    /// The developer (shown as "Developer"; stored under this older name).
    var publisher: String?
    var author: String?
    var copyright: String
    /// The package's own name, e.g. "Mahjongg:Scrawl".
    var packageName: String
    /// The part after the colon in the package name, the developer's registered signature.
    var signature: String?
    var appSymbol: String?
    var isbn: String?
    /// The version number in the package's header: a whole number.
    var version: Int
    /// The version as the package itself writes it, like "1.2.3" for 123, when
    /// some text in it matches the header's number (nil if none, or in libraries
    /// made before this existed).
    var versionText: String?
    /// The language it's written in, as a language code ("en", "de"), if it
    /// could be told from its text (nil if not, or in libraries made before this
    /// existed).
    var language: String?
    var creationDate: Date?
    var fileSize: Int
    /// 0 for "package0", 1 for "package1".
    var formatVersion: Int
    var packageFlags: [String]
    var copyProtected: Bool
    var kind: PackageKind
    var parts: [PartInfo]
    var detectedOS: NewtonOS
    /// The oldest and newest Newton OS versions it works with, as far as the
    /// package shows ("" or nil: not known). Nil in libraries made before these
    /// existed, until the package is read again.
    var minOS: String?
    var maxOS: String?
    /// Every registered name ("Name:Signature", like "NewtHack:ChrisDopp") the
    /// package mentions, its own included. Used to find packages that belong
    /// together. Nil in libraries made before this existed.
    var registeredNames: [String]?
    /// The registered names it looks up with GetRoot or GetGlobals: usually the
    /// app it's an add-on for.
    var hostNames: [String]?
    /// The registered names it defines as globals (DefGlobalVar, DefGlobalFn):
    /// something it provides, often for one app to read.
    var definedNames: [String]?
    /// The registered names it reads as globals (GetGlobalVar, GlobalVarExists…).
    var globalsRead: [String]?
    var evidence: [Evidence]
    /// The Newton protos (built-in view templates) the package uses.
    var protosUsed: [String]
    /// The version of this app's package reader that read it; packages read by
    /// an older one are read again when the library opens.
    var readerVersion: Int?
    var hasNativeCode: Bool
    var hasGreyIcon: Bool
    var icon: NewtonBitmap?
    /// Problems found while reading the package.
    var warnings: [String]
}
