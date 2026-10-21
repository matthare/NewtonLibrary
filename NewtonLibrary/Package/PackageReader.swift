import Foundation
import NaturalLanguage

/// Reads a Newton package (.pkg) file and works out what it is.
///
/// A package starts with a header ("package0" or "package1"), then a directory of
/// parts, then the parts themselves. Each NewtonScript part is a tree of objects
/// (frames, arrays, symbols, strings, binaries) whose references are file offsets
/// plus 1. Everything here is bounds-checked, so a damaged file gives warnings
/// instead of a crash.
struct PackageReader {
    enum ReadError: LocalizedError {
        case notAPackage
        case damaged(String)

        var errorDescription: String? {
            switch self {
            case .notAPackage: return "This isn't a Newton package."
            case .damaged(let why): return "The package is damaged (\(why))."
            }
        }
    }

    /// Package header flags
    static let kAutoRemoveFlag = 0x8000_0000
    static let kCopyProtectFlag = 0x4000_0000
    static let kNoCompressionFlag = 0x1000_0000
    static let kRelocationFlag = 0x0400_0000
    static let kUseFasterCompressionFlag = 0x0200_0000

    /// Is this a Newton package (or one wrapped in MacBinary)?
    static func isPackage(_ data: Data) -> Bool {
        package(in: data) != nil
    }

    /// The package itself: the data as it is, or the data fork of a MacBinary
    /// file (a 128-byte Mac header with the file's name and type, then its data
    /// fork, as Mac archives and downloads often left packages).
    static func package(in data: Data) -> Data? {
        func starts(_ d: Data) -> Bool {
            d.count >= 0x34 && (d.prefix(8) == Data("package0".utf8) || d.prefix(8) == Data("package1".utf8))
        }
        if starts(data) { return data }
        let bytes = [UInt8](data.prefix(128))
        guard bytes.count == 128, bytes[0] == 0, (1...63).contains(bytes[1]), bytes[74] == 0, bytes[82] == 0 else { return nil }
        let length = bytes[83..<87].reduce(0) { $0 << 8 | Int($1) }
        guard length > 0, 128 + length <= data.count else { return nil }
        let fork = data.subdata(in: data.startIndex + 128 ..< data.startIndex + 128 + length)
        return starts(fork) ? fork : nil
    }

    /// Goes up whenever the reader learns something new, so that packages read
    /// before are read again.
    static let version = 11

    static func inspect(_ data: Data, fileName: String) throws -> PackageInfo {
        guard let package = package(in: data) else { throw ReadError.notAPackage }
        return try Inspector(bytes: [UInt8](package), fileName: fileName).run()
    }
}

// MARK: - Object access

/// One object in a package: a 12-byte header (size and flags, a reserved word,
/// and the class or frame map), then either data (binaries) or reference slots.
private struct Obj {
    let offset: Int
    let size: Int
    let flags: Int
    let cls: Int

    var isSlotted: Bool { flags & 1 != 0 }
    var isFrame: Bool { flags & 2 != 0 }
    var slotCount: Int { max(0, (size - 12) / 4) }
    var dataStart: Int { offset + 12 }
    var dataLength: Int { max(0, size - 12) }
}

private let kSymbolClass = 0x55552
private let kNil = 0x2
private let kTrue = 0x1A

private final class Objects {
    let b: [UInt8]
    private var symbolCache: [Int: String?] = [:]
    private var tagCache: [Int: [String]] = [:]

    init(_ bytes: [UInt8]) { b = bytes }

    func u16(_ o: Int) -> Int? {
        guard o >= 0, o + 2 <= b.count else { return nil }
        return Int(b[o]) << 8 | Int(b[o + 1])
    }

    func s16(_ o: Int) -> Int? {
        guard let v = u16(o) else { return nil }
        return v >= 0x8000 ? v - 0x10000 : v
    }

    func u32(_ o: Int) -> Int? {
        guard o >= 0, o + 4 <= b.count else { return nil }
        return Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3])
    }

    func object(_ ref: Int) -> Obj? {
        guard ref & 3 == 1 else { return nil }
        let o = ref - 1
        guard o >= 0, o % 4 == 0, let header = u32(o), let cls = u32(o + 8) else { return nil }
        let size = header >> 8
        guard size >= 12, o + size <= b.count else { return nil }
        return Obj(offset: o, size: size, flags: header & 0xFF, cls: cls)
    }

    func slots(_ obj: Obj) -> [Int] {
        guard obj.isSlotted else { return [] }
        return (0..<obj.slotCount).compactMap { u32(obj.dataStart + 4 * $0) }
    }

    func symbol(_ ref: Int) -> String? {
        if let cached = symbolCache[ref] { return cached }
        var name: String?
        if let obj = object(ref), !obj.isSlotted, obj.cls == kSymbolClass, obj.dataLength > 4 {
            let start = obj.dataStart + 4
            var end = start
            while end < obj.dataStart + obj.dataLength, b[end] != 0 { end += 1 }
            name = String(bytes: b[start..<end], encoding: .macOSRoman)
        }
        symbolCache[ref] = name
        return name
    }

    /// The class of a binary or array object, as a symbol name.
    func className(_ obj: Obj) -> String? {
        symbol(obj.cls)
    }

    /// The slot names of a frame map, including those of its parent maps.
    func tags(map ref: Int, depth: Int = 0) -> [String] {
        if let cached = tagCache[ref] { return cached }
        guard depth < 32, let map = object(ref), map.isSlotted else { return [] }
        let s = slots(map)
        guard let parent = s.first else { return [] }
        // A map's class is normally an integer (its flags), but some packages use an
        // ordinary array as a map; its slots are laid out the same way.
        var tags = parent & 3 == 1 ? self.tags(map: parent, depth: depth + 1) : []
        tags += s.dropFirst().map { symbol($0) ?? "?" }
        tagCache[ref] = tags
        return tags
    }

    func frame(_ ref: Int) -> [(name: String, value: Int)]? {
        guard let obj = object(ref), obj.isFrame else { return nil }
        let names = tags(map: obj.cls)
        return Array(zip(names, slots(obj))).map { (name: $0.0, value: $0.1) }
    }

    /// A frame slot by name (NewtonScript slot names ignore case).
    func slot(_ ref: Int, _ name: String) -> Int? {
        frame(ref)?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    func array(_ ref: Int) -> [Int]? {
        guard let obj = object(ref), obj.isSlotted, !obj.isFrame else { return nil }
        return slots(obj)
    }

    func int(_ ref: Int?) -> Int? {
        guard let ref = ref, ref & 3 == 0 else { return nil }
        let v = ref >> 2
        return v >= 1 << 29 ? v - (1 << 30) : v
    }

    func string(_ ref: Int?) -> String? {
        guard let ref = ref, let obj = object(ref), !obj.isSlotted,
              let cls = className(obj), cls.lowercased().hasPrefix("string") else { return nil }
        return Objects.decodeUTF16(b, from: obj.dataStart, length: obj.dataLength)
    }

    /// Newton strings are UTF-16, big-endian, ending in a 0. Packages made by the
    /// first Newton Toolkit stored Mac characters above 127 sign-extended
    /// (© became U+FFA9), so those are turned back into Mac Roman characters.
    static func decodeUTF16(_ b: [UInt8], from start: Int, length: Int) -> String {
        var units: [UInt16] = []
        var o = start
        while o + 1 < start + length, o + 1 < b.count {
            let u = UInt16(b[o]) << 8 | UInt16(b[o + 1])
            if u == 0 { break }
            units.append(u)
            o += 2
        }
        var out = ""
        var run: [UInt16] = []
        func flush() {
            out += String(decoding: run, as: UTF16.self)
            run.removeAll()
        }
        for u in units {
            if u >= 0xFF80 {
                flush()
                out += String(bytes: [UInt8(u & 0xFF)], encoding: .macOSRoman) ?? "?"
            } else {
                run.append(u)
            }
        }
        flush()
        return out.replacingOccurrences(of: "\r", with: "\n")
    }
}

// MARK: - Bitmaps

private extension Objects {
    /// A Newton bitmap binary: 4 bytes, row bytes, 2 bytes, bounds (top, left,
    /// bottom, right), then the rows. Depth is 1 for 'bits' and given
    /// separately for colorData 'cbits'.
    struct Pixels {
        let width: Int
        let height: Int
        let depth: Int
        let rowBytes: Int
        let start: Int
    }

    func pixels(_ ref: Int?, depth: Int) -> Pixels? {
        guard let ref = ref, let obj = object(ref), !obj.isSlotted, obj.dataLength >= 16,
              let rowBytes = u16(obj.dataStart + 4),
              let top = s16(obj.dataStart + 8), let left = s16(obj.dataStart + 10),
              let bottom = s16(obj.dataStart + 12), let right = s16(obj.dataStart + 14) else { return nil }
        let rb = rowBytes & 0x3FFF
        let w = right - left, h = bottom - top
        guard w > 0, h > 0, w <= 2048, h <= 2048, rb * 8 >= w * depth,
              16 + rb * h <= obj.dataLength else { return nil }
        return Pixels(width: w, height: h, depth: depth, rowBytes: rb, start: obj.dataStart + 16)
    }

    /// The pixel value at x, y: 0 = white, the maximum = black, as on the Newton.
    func value(_ p: Pixels, _ x: Int, _ y: Int) -> Int {
        let bit = x * p.depth
        let byte = b[p.start + y * p.rowBytes + bit / 8]
        let shift = 8 - p.depth - bit % 8
        return Int(byte >> UInt8(shift)) & ((1 << p.depth) - 1)
    }

    /// Converts an icon frame, either {bits, mask, bounds, colorData} or a 2.1
    /// iconPro frame {unhilited, hilited}, to grey + alpha. Prefers the best
    /// grey version up to 8 bits.
    func bitmap(_ iconRef: Int) -> (NewtonBitmap, grey: Bool)? {
        var ref = iconRef
        if let unhilited = slot(ref, "unhilited") { ref = unhilited }

        var bits: Pixels?, mask: Pixels?, colour: Pixels?
        if frame(ref) != nil {
            bits = pixels(slot(ref, "bits"), depth: 1)
            mask = pixels(slot(ref, "mask"), depth: 1)
            if let colorData = slot(ref, "colorData") {
                let entries = array(colorData) ?? [colorData]
                for entry in entries {
                    guard let depth = int(slot(entry, "bitDepth")), [2, 4, 8].contains(depth),
                          let p = pixels(slot(entry, "cbits"), depth: depth) else { continue }
                    if colour == nil || depth > colour!.depth { colour = p }
                }
            }
        } else {
            bits = pixels(ref, depth: 1)
        }
        guard let main = colour ?? bits else { return nil }
        let w = main.width, h = main.height
        if let m = mask, m.width != w || m.height != h { mask = nil }
        if let b = bits, b.width != w || b.height != h { bits = nil }

        // Which pixels show. Many packages' masks don't match their pictures (some
        // are empty), yet their icons show on a Newton, so the mask can't hide
        // anything: every inked pixel is drawn. Pixels are white (rather than
        // see-through) where the mask says so, and anywhere enclosed by ink: a
        // fill from the edges of the image that can't reach them.
        let maxValue = (1 << main.depth) - 1
        var grey = [UInt8](repeating: 255, count: w * h)
        var ink = [Bool](repeating: false, count: w * h)
        var opaque = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let v = value(main, x, y)
                grey[i] = UInt8(255 - v * 255 / maxValue)
                ink[i] = v != 0 || (bits.map { value($0, x, y) != 0 } ?? false)
                opaque[i] = ink[i] || (mask.map { value($0, x, y) != 0 } ?? false)
            }
        }
        var outside = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        for x in 0..<w { stack += [x, (h - 1) * w + x] }
        for y in 0..<h { stack += [y * w, y * w + w - 1] }
        while let i = stack.popLast() {
            guard !outside[i], !ink[i] else { continue }
            outside[i] = true
            let x = i % w, y = i / w
            if x > 0 { stack.append(i - 1) }
            if x < w - 1 { stack.append(i + 1) }
            if y > 0 { stack.append(i - w) }
            if y < h - 1 { stack.append(i + w) }
        }
        let alpha = (0..<(w * h)).map { i -> UInt8 in opaque[i] || !outside[i] ? 255 : 0 }
        return (NewtonBitmap(width: w, height: h, grey: Data(grey), alpha: Data(alpha)), colour != nil)
    }
}

// MARK: - Inspection

private struct Inspector {
    let bytes: [UInt8]
    let fileName: String

    /// Protos added in Newton OS 2.0 (all of NewtApp, the 'newt' protos, plus these).
    static let protos20: Set<String> = [
        "protoTransport", "protoTransportHeader", "protoTransportPrefs", "protoRoutingFormat",
        "protoFrameFormat", "protoFullRouteSlip", "protoSendButton", "protoFormatPicker",
        "protoListPicker", "protoPeoplePicker", "protoPeoplePopup", "protoInfoButton",
        "protoNumberPicker", "protoPopupButton", "protoSoupOverview", "protoBasicEndpoint",
        "protoStreamingEndpoint", "protoStatusTemplate", "protoStatusBarber", "protoStatusClosebox",
        "protoStatusIcon", "protoStatusButton", "protoStatusGauge", "protoStatusProgress",
        "protoStatusText", "protoSoundChannel", "protoRichInputLine", "protoRichLabelInputLine",
        "protoPeopleDataDef", "protoNameRefDataDef",
    ]

    /// Global functions added in Newton OS 2.0. (Gestalt and GetAppParams look like
    /// 2.0 functions but were already in 1.x: 1994 packages call them.)
    static let functions20: Set<String> = [
        "RegUnionSoup", "UnRegUnionSoup", "GetUnionSoupAlways", "RegisterViewDef",
        "UnRegisterViewDef", "RegDataDef", "UnRegDataDef", "RegSoupChange", "UnRegSoupChange",
        "RegAuxButton", "UnRegAuxButton", "RegTransport", "UnRegTransport",
        "RegFormulas", "UnRegFormulas", "RegPrefs", "UnRegPrefs",
        "RegUserConfigChange", "UnRegUserConfigChange", "GetUserConfig", "SetUserConfig",
        "GetAppPrefs", "MakeRichString", "IsRichString",
    ]

    func run() throws -> PackageInfo {
        let o = Objects(bytes)
        guard let flags = o.u32(0x0C), let version = o.u32(0x10), let dirSize = o.u32(0x2C),
              let numParts = o.u32(0x30) else { throw PackageReader.ReadError.damaged("short header") }
        guard numParts > 0, numParts < 256, 0x34 + numParts * 32 <= dirSize, dirSize <= bytes.count else {
            throw PackageReader.ReadError.damaged("bad part directory")
        }
        let formatVersion = bytes[7] == UInt8(ascii: "1") ? 1 : 0
        let variableStart = 0x34 + numParts * 32

        func info(_ at: Int) -> String {
            guard let off = o.u16(at), let len = o.u16(at + 2), len > 0 else { return "" }
            return Objects.decodeUTF16(bytes, from: variableStart + off, length: len)
        }
        let copyright = info(0x14).trimmingCharacters(in: .whitespacesAndNewlines)
        let packageName = info(0x18).trimmingCharacters(in: .whitespacesAndNewlines)
        var creationDate: Date?
        if let secs = o.u32(0x20), secs > 0 {
            creationDate = Date(timeIntervalSince1970: TimeInterval(secs) - 2_082_844_800)  // since 1904
        }

        var dataStart = dirSize
        if flags & PackageReader.kRelocationFlag != 0, let relocSize = o.u32(dirSize + 4) {
            dataStart += relocSize
        }

        var warnings: [String] = []
        var evidence: [Evidence] = []
        var parts: [PartInfo] = []
        var title: String?, formTitle: String?, extrasName: String?, author: String?, appSymbol: String?, isbn: String?
        var icon: NewtonBitmap?, hasGreyIcon = false
        var symbols = Set<String>(), magic = Set<Int>(), hasNative = false, hostNames = Set<String>(), definedNames = Set<String>(), globalsRead = Set<String>()
        var audioBytes: [String: Int] = [:]
        var texts: [String] = [], versionSlots: [String] = []
        var isPatch = false

        if formatVersion == 1 {
            evidence.append(Evidence(requires: .os20, text: "Uses the newer package format (package1), which Newton OS 1.x can't read."))
        }

        for i in 0..<numParts {
            let e = 0x34 + i * 32
            guard let offset = o.u32(e), let size = o.u32(e + 4), let partFlags = o.u32(e + 20) else { continue }
            let typeBytes = Array(bytes[(e + 12)..<(e + 16)])
            let type = typeBytes.allSatisfy({ $0 >= 32 && $0 < 127 }) ? String(decoding: typeBytes, as: UTF8.self) : ""
            var kind = Inspector.kind(type: type, partFlags: partFlags)
            var flagNames: [String] = []
            switch partFlags & 3 {
            case 0: flagNames.append("Protocol")
            case 1: flagNames.append("NewtonScript")
            case 2: flagNames.append("Raw")
            default: break
            }
            if partFlags & 0x10 != 0 { flagNames.append("Auto Load") }
            if partFlags & 0x20 != 0 { flagNames.append("Auto Remove") }
            if partFlags & 0x80 != 0 { flagNames.append("Notify") }
            if partFlags & 0x100 != 0 { flagNames.append("Auto Copy") }

            if type == "soup" {
                evidence.append(Evidence(requires: .os20, text: "Contains a store part (soup data), which needs Newton OS 2.0."))
            }

            // NewtonScript parts start with an array whose first slot is the part's root frame
            let partStart = dataStart + offset
            if partFlags & 3 == 1 {
                if let root = o.u32(partStart + 12), o.frame(root) != nil {
                    let rootSlots = Set((o.frame(root) ?? []).map { $0.name.lowercased() })
                    if rootSlots.contains("patchdata") || rootSlots.contains("registerpatch") || rootSlots.contains("patchmunger") {
                        kind = .systemUpdate
                        isPatch = true
                    }
                    if type == "form" || type == "auto" {
                        if extrasName == nil, let text = o.string(o.slot(root, "text")), !text.isEmpty { extrasName = text }
                        if appSymbol == nil, let app = o.slot(root, "app"), let sym = o.symbol(app) { appSymbol = sym }
                        if formTitle == nil, let form = o.slot(root, "theForm"),
                           let t = o.string(o.slot(form, "title")), !t.trimmingCharacters(in: .whitespaces).isEmpty {
                            formTitle = t
                        }
                        if icon == nil {
                            for name in ["iconPro", "icon"] {
                                if let ref = o.slot(root, name), let found = o.bitmap(ref) {
                                    icon = found.0
                                    hasGreyIcon = found.grey
                                    break
                                }
                            }
                        }
                    }
                    if type == "book" {
                        let book = o.slot(root, "book") ?? root
                        if let t = o.string(o.slot(book, "title")), !t.isEmpty { title = t }
                        if let a = o.string(o.slot(book, "author")), !a.isEmpty { author = a }
                        if let s = o.string(o.slot(book, "isbn")), !s.isEmpty { isbn = s }
                    }
                    Inspector.scan(o, root: root, symbols: &symbols, magic: &magic, native: &hasNative,
                                   hostNames: &hostNames, definedNames: &definedNames, globalsRead: &globalsRead,
                                   audioBytes: &audioBytes, texts: &texts, versionSlots: &versionSlots)
                } else {
                    warnings.append("Part \(i) (\(type.isEmpty ? "untyped" : type)) couldn't be read.")
                }
            }
            parts.append(PartInfo(type: type, kind: kind, size: size, flags: flagNames))
        }

        // Package kind: the most important part decides
        let order: [PackageKind] = [.application, .book, .systemUpdate, .font, .dictionary, .driver, .extensionPart, .data, .other]
        var kind = order.first { k in parts.contains { $0.kind == k } } ?? .other

        // An application that's mostly one long text is an e-book with its own
        // reader (as made by Paperback and other book makers): a Book. In real
        // applications no string comes near this; in these it's usually most of
        // the package.
        if kind == .application, let longest = texts.map(\.count).max(), longest * 2 * 10 >= bytes.count * 4 {
            kind = .book
            evidence.append(Evidence(requires: nil, text: "Mostly one long text (\(min(100, longest * 200 / max(1, bytes.count)))% of the package), so it's a book with its own reader."))
        }

        // Mostly sound is a Sound: Newton sound data making up at least half of
        // an extension or data package, or nearly all (90%) of an application
        // (apps built around sound, like a tuner, stay applications); or a music
        // module making up at least half of any package
        let samples = audioBytes["samples"] ?? 0, music = audioBytes["modFile"] ?? 0
        if [.application, .extensionPart, .data, .other].contains(kind),
           music * 2 >= bytes.count || samples * 10 >= bytes.count * (kind == .application ? 9 : 5) {
            let share = min(100, (samples + music) * 100 / max(1, bytes.count))
            evidence.append(Evidence(requires: nil, text: music * 2 >= bytes.count
                ? "Mostly music (a music module, \(share)% of the package), so it's a Sound."
                : "Mostly Newton sound data (\(share)% of the package), so it's a Sound."))
            kind = .sound
        }

        // An application with strong signs of being a game is a Game
        if kind == .application {
            let signs = Inspector.gameSigns(texts: texts, symbols: symbols)
            if !signs.isEmpty {
                kind = .game
                evidence.append(Evidence(requires: nil, text: "Looks like a game: it has " + Inspector.list(signs) + "."))
            }
        }

        // Newton OS clues found inside the parts
        let protoNames = magic.compactMap { MagicPointers.names[$0] }
        let protos = protoNames.filter { $0.hasPrefix("proto") || $0.hasPrefix("newt") }.sorted()
        let protos20 = protos.filter { $0.hasPrefix("newt") || Inspector.protos20.contains($0) }
        if !protos20.isEmpty {
            evidence.append(Evidence(requires: .os20, text: "Uses " + Inspector.list(protos20) + ", added in Newton OS 2.0."))
        }
        let functions20 = symbols.filter { Inspector.functions20.contains($0) }.sorted()
        if !functions20.isEmpty {
            evidence.append(Evidence(requires: .os20, text: "Calls " + Inspector.list(functions20.map { $0 + "()" }) + ", added in Newton OS 2.0."))
        }
        if hasNative {
            evidence.append(Evidence(requires: .os20, text: "Contains native ARM code, which Newton OS 2.0 introduced."))
        }
        // A system update is made for exactly one version
        var updateFor: String?
        if let range = packageName.range(of: #"System Update (\d\.\d)"#, options: .regularExpression) {
            let v = String(packageName[range].suffix(3))
            updateFor = v
            if v == "2.1" { evidence.append(Evidence(requires: .os21, text: "A system update for Newton OS 2.1, and only 2.1.")) }
            if v == "2.0" { evidence.append(Evidence(requires: .os20, text: "A system update for Newton OS 2.0, and only 2.0.")) }
        }
        if isPatch {
            evidence.append(Evidence(requires: nil, text: "A ROM patch: it only installs on the exact ROM version it was made for."))
        }
        if hasGreyIcon {
            evidence.append(Evidence(requires: nil, text: "Has a greyscale icon for Newton OS 2.1 (MessagePad 2000/2100 and eMate 300)."))
        }
        let unnamed = magic.filter { MagicPointers.names[$0] == nil }.sorted()
        if !unnamed.isEmpty {
            evidence.append(Evidence(requires: nil, text: "Refers to system objects that Newton OS 2.1 doesn't name: " + Inspector.list(unnamed.map { "@\($0)" }) + "."))
        }
        if !warnings.isEmpty {
            evidence.append(Evidence(requires: nil, text: "Parts of the package couldn't be read, so this may be incomplete."))
        }

        let required = evidence.compactMap { $0.requires }.max { $0.rank < $1.rank }
        let detectedOS: NewtonOS
        if let r = required {
            detectedOS = r
        } else if parts.allSatisfy({ $0.flags.first != "NewtonScript" }) || warnings.count == parts.count {
            detectedOS = .unknown
        } else {
            detectedOS = .any
            evidence.append(Evidence(requires: nil, text: "Nothing found that needs Newton OS 2.0, so it should also work on 1.x."))
        }

        // Minimum and maximum versions
        var minOS: String
        switch detectedOS {
        case .os21: minOS = "2.1"
        case .os20: minOS = "2.0"
        case .any, .os1Only: minOS = "1.x"
        case .unknown: minOS = ""
        }
        var maxOS = ""
        if let v = updateFor, NewtonOSVersion.all.contains(v) {
            minOS = v
            maxOS = v
        }

        var packageFlags: [String] = []
        if flags & PackageReader.kAutoRemoveFlag != 0 { packageFlags.append("Auto Remove") }
        if flags & PackageReader.kCopyProtectFlag != 0 { packageFlags.append("Copy Protected") }
        if flags & PackageReader.kNoCompressionFlag != 0 { packageFlags.append("No Compression") }
        if flags & PackageReader.kRelocationFlag != 0 { packageFlags.append("Relocation") }
        if flags & PackageReader.kUseFasterCompressionFlag != 0 { packageFlags.append("Faster Compression") }

        let nameParts = packageName.split(separator: ":", maxSplits: 1).map(String.init)
        let signature = nameParts.count == 2 && !nameParts[1].isEmpty ? nameParts[1] : nil
        let fileBase = (fileName as NSString).deletingPathExtension
        let fallbackTitle = (nameParts.first ?? "").replacingOccurrences(of: "_", with: " ")
        // A book's title, else the app's name in the Extras drawer, else its window
        // title; but a window title that's a longer form of the Extras name
        // ("Silicon Casino" for "Casino") wins
        if title == nil, let form = formTitle, let extras = extrasName,
           form.count > extras.count, form.range(of: extras, options: .caseInsensitive) != nil {
            title = form
        }
        let finalTitle = title ?? extrasName ?? formTitle ?? (fallbackTitle.isEmpty ? fileBase : fallbackTitle)
        let versionText = Inspector.versionText(
            header: Int(version),
            names: [finalTitle, extrasName, formTitle, packageName,
                    Inspector.underscoreVersions(fileBase),
                    copyright].compactMap { $0 },
            ownNames: [finalTitle, extrasName, formTitle, nameParts.first].compactMap { $0 },
            versionSlots: versionSlots,
            texts: texts)

        return PackageInfo(
            title: Inspector.cleanTitle(finalTitle, signature: signature),
            extrasName: extrasName,
            publisher: Inspector.developer(signature: signature, author: author, copyright: copyright),
            author: author,
            copyright: copyright,
            packageName: packageName,
            signature: signature,
            appSymbol: appSymbol,
            isbn: isbn,
            version: version,
            versionText: versionText,
            language: Inspector.language(texts: texts),
            creationDate: creationDate,
            fileSize: bytes.count,
            formatVersion: formatVersion,
            packageFlags: packageFlags,
            copyProtected: flags & PackageReader.kCopyProtectFlag != 0,
            kind: kind,
            parts: parts,
            detectedOS: detectedOS,
            minOS: minOS,
            maxOS: maxOS,
            registeredNames: symbols.filter { $0.contains(":") }.sorted(),
            hostNames: hostNames.sorted(),
            definedNames: definedNames.sorted(),
            globalsRead: globalsRead.sorted(),
            evidence: evidence,
            protosUsed: protos,
            readerVersion: PackageReader.version,
            hasNativeCode: hasNative,
            hasGreyIcon: hasGreyIcon,
            icon: icon,
            warnings: warnings)
    }

    /// The version as the package writes it ("1.2.3", "1.1i", "v2.0b3"), from
    /// its names (title, Extras name, package name, file name, copyright), from
    /// slots the developer named for a version (`version`, `versionString`…),
    /// or from its other text (an About box, a help book).
    ///
    /// - When the header's number is more than 1, the text's digits must be that
    ///   number (123, 11, 203 or 20), give or take zeros at the end (120 for
    ///   "1.2", as 1.2.0; 2 for "2.0", though in other text only after a word
    ///   like "Version"): developers often put "1.2.3" in a title and 123 in
    ///   the header, which can only hold a whole number.
    /// - A header of 1 is usually just NTK's default, so the first version found
    ///   in the names, else in a version slot, else in other text where it
    ///   follows "Version", "ver", "v" or the package's name ("Scramble 1.1"),
    ///   is taken whatever its digits. Where the other text has several, the one
    ///   given most often wins.
    ///
    /// A Newton OS version (1.0 to 2.2) after "OS", "System" or "Newton" is left
    /// out: it's what the package needs ("for Newton 2.0"), not its own version.
    /// So is a number starting with 0 and another digit ("01.1 Nephi").
    static func versionText(header: Int, names: [String], ownNames: [String] = [],
                            versionSlots: [String] = [], texts: [String]) -> String? {
        guard header > 0 else { return nil }
        let digits = String(header)
        let pattern = #"(?<![\w.])([vV]?)(\d+(?:\.\d+)+(?:[a-zA-Z]+\d*)?)(?![\w.]*\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        /// The same digits, or with zeros after them (1.2 for 120, as 1.2.0);
        /// `orFewer`: also with zeros after the header's (2.0 for 2).
        func matchesHeader(_ candidate: String, orFewer: Bool) -> Bool {
            let all = candidate.filter(\.isNumber)
            let numeric = candidate.prefix { $0.isNumber || $0 == "." }.filter(\.isNumber)
            return [all, numeric].contains { found in
                !found.isEmpty && (digits.hasPrefix(found) && digits.dropFirst(found.count).allSatisfy { $0 == "0" }
                                   || orFewer && found.hasPrefix(digits) && found.dropFirst(digits.count).allSatisfy { $0 == "0" })
            }
        }
        let markers = ["version", "vers", "vers.", "ver", "ver.", "release", "rel."]
            + ownNames.map { $0.lowercased() }.filter { $0.count >= 3 }
        /// Versions in a text, in order, and whether each follows a marker word.
        func candidates(in text: String) -> [(version: String, marked: Bool)] {
            let ns = text as NSString
            return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
                let before = ns.substring(to: match.range.location).trimmingCharacters(in: .whitespaces).lowercased()
                let version = ns.substring(with: match.range(at: 2))
                if ["os", "system", "newton"].contains(where: { before.hasSuffix($0) }),
                   version.range(of: #"^(1\.[0-3]|2\.[0-2])(\.\d)?$"#, options: .regularExpression) != nil { return nil }
                // "01.1 Nephi": a chapter, not a version
                if version.range(of: #"^0\d"#, options: .regularExpression) != nil { return nil }
                let marked = match.range(at: 1).length > 0 || markers.contains { before.hasSuffix($0) }
                return (version, marked)
            }
        }
        let own = names + versionSlots
        if header > 1 {
            for text in own {
                if let found = candidates(in: text).first(where: { matchesHeader($0.version, orFewer: true) }) { return found.version }
            }
            for text in texts {
                if let found = candidates(in: text).first(where: { matchesHeader($0.version, orFewer: $0.marked) }) { return found.version }
            }
            return nil
        }
        for text in own {
            if let found = candidates(in: text).first { return found.version }
        }
        let found = texts.flatMap { candidates(in: $0).filter(\.marked).map(\.version) }
        guard !found.isEmpty else { return nil }
        let counts = Dictionary(found.map { ($0, 1) }, uniquingKeysWith: +)
        return found.max { counts[$0]! < counts[$1]! || (counts[$0]! == counts[$1]! && found.firstIndex(of: $0)! > found.firstIndex(of: $1)!) }
    }

    /// A file name with "_" for "." in its version ("heapsav 1_07", "QF Works_1_1_1")
    /// written with dots. Only numbers starting with one digit: "10_4 Nephi" isn't one.
    static func underscoreVersions(_ name: String) -> String {
        var s = name
        for range in name.matches(of: #"(?<!\d)\d(_\d{1,3})+(?!\d)"#).reversed() {
            s.replaceSubrange(range, with: name[range].replacingOccurrences(of: "_", with: "."))
        }
        return s
    }

    /// A title as people would write it: on one line ("Voice⏎Notes" in the
    /// Extras drawer), without decorations ("•  NanoCAD 1.0  •", "*QP*",
    /// quotation marks), a file extension ("GOETZE01.TXT", "Klisjepa.mod"),
    /// the developer's signature ("BikePower:Source") or underscores.
    static func cleanTitle(_ title: String, signature: String?) -> String {
        func replace(_ text: String, _ pattern: String, _ with: String) -> String {
            text.replacingOccurrences(of: pattern, with: with, options: .regularExpression)
        }
        var s = replace(title, #"\s+"#, " ").trimmingCharacters(in: .whitespaces)
        if let sig = signature, s.count > sig.count + 1, s.hasSuffix(":" + sig) { s = String(s.dropLast(sig.count + 1)) }
        s = replace(s, #"(?i)\.(pkg|txt|te?xt|html?|mod|doc|rtf|pdf|snd|aiff?|wav|np!)$"#, "")
        if s.contains("_") { s = replace(s, #"_+"#, " ") }
        // Decorations at both ends, or quotation marks around it
        let marks = "•*·=~#+-–—|"
        if let first = s.first, let last = s.last, marks.contains(first), marks.contains(last) {
            s = s.trimmingCharacters(in: CharacterSet(charactersIn: marks + " "))
        }
        for (open, close) in [("\"", "\""), ("“", "”"), ("'", "'"), ("‘", "’"), ("«", "»")]
        where s.count > 2 && s.hasPrefix(open) && s.hasSuffix(close) && !s.dropFirst().dropLast().contains(close) {
            s = String(s.dropFirst().dropLast())
        }
        s = replace(s, #"\s+"#, " ").trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? title.trimmingCharacters(in: .whitespacesAndNewlines) : s
    }

    /// The language a package is written in, as a language code ("en", "de",
    /// "ja"), or nil if it can't be told. Each sentence-like string (a few words,
    /// or 20 letters or more) is recognised on its own and, if the recogniser is
    /// fairly sure (75%), counts by its number of letters; a language needs a
    /// clear majority (60%) of at least 100 letters.
    /// Strings are judged one by one because packages often hold a few words in
    /// many languages (Avi's Backdrop has "Birthdays" in six, and a menu of
    /// language names), which would muddle a single guess for all of them.
    static func language(texts: [String]) -> String? {
        var letters: [String: Int] = [:], total = 0
        let recognizer = NLLanguageRecognizer()
        for text in texts {
            let sample = String(text.prefix(1000))
            let count = sample.filter(\.isLetter).count
            let words = sample.split(whereSeparator: { $0.isWhitespace }).count
            guard count >= 20 || (words >= 3 && count >= 10), count * 2 >= sample.count else { continue }
            // Not lists of names or places ("Allentown Altoona Bethlehem"): in
            // sentences most words are lower case, even in German
            let wordList = sample.split(whereSeparator: { !$0.isLetter }).filter { $0.count > 1 }
            guard wordList.filter({ $0.first!.isUppercase }).count * 10 <= wordList.count * 6 else { continue }
            recognizer.reset()
            recognizer.processString(sample)
            // Only strings it's sure of: lists of names, codes or places aren't
            guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
                  language != .undetermined, confidence >= 0.75 else { continue }
            letters[language.rawValue, default: 0] += count
            total += count
            if total > 20_000 { break }
        }
        guard let (best, count) = letters.max(by: { $0.value < $1.value }), count >= 100, count * 10 >= total * 6 else { return nil }
        return best
    }

    /// Whether a slot's name says it holds the package's own version, like
    /// `version`, `versionString` or `kAppVersion`, rather than a Newton OS,
    /// ROM or data-format version (`osVersion`, `minSystemVersion`).
    static func isVersionSlot(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard lower.contains("version") || lower == "vers" else { return false }
        return !["os", "rom", "sys", "min", "max", "req", "newton", "format", "data", "soup", "proto", "platform"]
            .contains { lower.contains($0) }
    }

    /// Signs of a game. Strong: phrases a game shows ("New Game", "Game Over",
    /// "High Scores", "Play Again") or names in its code (newGame, gameOver,
    /// highScores…). Weak: "You Win", "You Lose", "Your Turn", "Congratulations";
    /// it takes two of those, or one strong sign. Words like "score" or "player"
    /// alone aren't enough: help books and utilities use them too.
    ///
    /// Phrases only count in short strings, as on a button, a label or an alert:
    /// a book's text or a long help screen can say anything ("You won't need to…").
    static func gameSigns(texts: [String], symbols: Set<String>) -> [String] {
        let strong = #"(?i)\b(new game|game over|high ?scores?|hi-?scores?|play again)(?![\w'’])"#
        let weak = #"(?i)\b(you (win|won|lose|lost)|your turn|congratulations)(?![\w'’])"#
        var strongFound = Set<String>(), weakFound = Set<String>()
        for text in texts where text.count <= 80 {
            for (pattern, isStrong) in [(strong, true), (weak, false)] {
                var range = text.startIndex..<text.endIndex
                while let match = text.range(of: pattern, options: .regularExpression, range: range) {
                    let sign = "“" + text[match].capitalized + "”"
                    if isStrong { strongFound.insert(sign) } else { weakFound.insert(sign) }
                    range = match.upperBound..<text.endIndex
                }
            }
            if strongFound.count + weakFound.count >= 4 { break }
        }
        let names = #"(?i)^(new_?game|game_?over|high_?scores?|hi_?scores?)$"#
        for symbol in symbols where symbol.range(of: names, options: .regularExpression) != nil {
            strongFound.insert("‘" + symbol + "’")
        }
        guard !strongFound.isEmpty || weakFound.count >= 2 else { return [] }
        return (strongFound.union(weakFound)).sorted()
    }

    static func kind(type: String, partFlags: Int) -> PackageKind {
        switch type {
        case "form": return .application
        case "book": return .book
        case "auto": return .extensionPart
        case "font": return .font
        case "dict": return .dictionary
        case "soup": return .data
        case "prnt", "fax ", "comm": return .driver
        default: return partFlags & 3 == 0 ? .driver : .other
        }
    }

    /// Walks every object reachable from a part's root, collecting the symbols,
    /// system objects (magic pointers) and native code it uses.
    /// Also collects `hostNames`: registered names ("Name:Signature") that a
    /// function looks up with GetRoot or GetGlobals, as an add-on does to find
    /// the app it belongs to; `definedNames`, the ones it defines as globals
    /// (DefGlobalVar…); and `globalsRead`, the ones it reads as globals
    /// (GetGlobalVar…).
    /// Functions that read a global variable or function by name, and those
    /// that define one: an add-on can leave something there for its app
    /// (SoundPak defines `AddedSounds:ALLAN`, which AlarmPak reads).
    static let globalReaders: Set<String> = ["GetGlobalVar", "GetGlobalFn", "GlobalVarExists", "GlobalFnExists"]
    static let globalDefiners: Set<String> = ["DefGlobalVar", "DefGlobalFn"]
    /// Functions and messages that open a soup by name.
    static let soupFunctions: Set<String> = ["GetUnionSoup", "GetUnionSoupAlways", "GetSoup", "RegUnionSoup",
                                             "UnRegUnionSoup", "CreateSoup", "CreateSoupXmit"]

    /// Classes of binary data that are sound: Newton sounds' samples, and the
    /// music modules ModPlayer and others play.
    static let audioClasses: Set<String> = ["samples", "modFile"]

    static func scan(_ o: Objects, root: Int, symbols: inout Set<String>, magic: inout Set<Int>, native: inout Bool,
                     hostNames: inout Set<String>, definedNames: inout Set<String>, globalsRead: inout Set<String>,
                     audioBytes: inout [String: Int], texts: inout [String], versionSlots: inout [String]) {
        var stack = [root]
        var seen = Set<Int>()
        while let ref = stack.popLast() {
            if ref & 3 == 3 {
                magic.insert(ref >> 2)
                continue
            }
            guard ref & 3 == 1, !seen.contains(ref), seen.count < 1_000_000, let obj = o.object(ref) else { continue }
            seen.insert(ref)
            if obj.isSlotted {
                let values = o.slots(obj)
                if obj.isFrame {
                    let names = o.tags(map: obj.cls)
                    // Slots the developer named for the app's version
                    for (i, name) in names.enumerated() where i < values.count && isVersionSlot(name) {
                        if let text = o.string(values[i]) { versionSlots.append(text) }
                    }
                    if let i = names.firstIndex(of: "class"), i < values.count,
                       let cls = o.symbol(values[i]), cls == "BinCFunction" || cls == "NativeFunction" {
                        native = true
                    }
                    if names.contains("code") && names.contains("offset") && names.contains("numArgs") {
                        native = true
                    }
                    if let i = names.firstIndex(of: "literals"), i < values.count, let literals = o.array(values[i]) {
                        let used = literals.compactMap { o.symbol($0) }
                        if used.contains("GetRoot") || used.contains("GetGlobals") {
                            hostNames.formUnion(used.filter { $0.contains(":") })
                        }
                        if !globalReaders.isDisjoint(with: used) {
                            globalsRead.formUnion(used.filter { $0.contains(":") })
                        }
                        if !globalDefiners.isDisjoint(with: used) {
                            definedNames.formUnion(used.filter { $0.contains(":") })
                        }
                        // Soups named like registered names ("DELLCW:BBANDCO"): an add-on
                        // that fills an app's soup (puzzle packs, for instance) uses its name
                        if !soupFunctions.isDisjoint(with: used) {
                            for text in literals.compactMap({ o.string($0) })
                            where text.range(of: #"^[A-Za-z0-9_.' -]+:[A-Za-z0-9_]+$"#, options: .regularExpression) != nil {
                                hostNames.insert(text)
                                symbols.insert(text)
                            }
                        }
                    }
                }
                stack.append(contentsOf: values)
            } else if obj.size > 256, let cls = o.symbol(obj.cls), audioClasses.contains(cls) {
                audioBytes[cls, default: 0] += obj.size
            } else if obj.cls == kSymbolClass, let name = o.symbol(ref) {
                symbols.insert(name)
            } else if texts.count < 20_000, let text = o.string(ref) {
                texts.append(text)
            }
        }
    }

    static func list(_ items: [String]) -> String {
        if items.count <= 4 { return ListFormatter.localizedString(byJoining: items) }
        return ListFormatter.localizedString(byJoining: Array(items.prefix(3)) + ["\(items.count - 3) more"])
    }

    /// The developer: the signature in the package name ("Mahjongg:Scrawl" ->
    /// "Scrawl"), the name developers registered with Apple. When the copyright
    /// holder (or a book's author) is a fuller form of it, that's used instead:
    /// "Scrawl, LLC" for Scrawl, "Tactile Systems, Inc." for Tactile, "Stand
    /// Alone Software" for SAS, "Christopher Dopp" for ChrisDopp. Without a
    /// signature: the book's author, else the copyright holder. (If both are
    /// fuller forms, the shorter.)
    static func developer(signature: String?, author: String?, copyright: String) -> String? {
        let holder = publisher(fromCopyright: copyright)
        // The last part of a longer name ("Extras:ActionNames:IAMBIC")
        guard let sig = signature?.split(separator: ":").last.map({ $0.trimmingCharacters(in: .whitespaces) }),
              !sig.isEmpty else { return author ?? holder }
        let fuller = [holder, author].compactMap { $0 }.filter { isFullerName($0, of: sig) }
        return fuller.min { $0.count < $1.count } ?? sig
    }

    /// Whether a name is a fuller form of a signature: the signature is how the
    /// name starts from one of its words ("StandAlone", "Tactile"), its initials
    /// ("SAS" for Stand Alone Software), or contains one of its distinctive words
    /// ("ChrisDopp" has Christopher Dopp's "Dopp").
    static func isFullerName(_ name: String, of signature: String) -> Bool {
        let sig = signature.lowercased().filter { $0.isLetter || $0.isNumber }
        let words = name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard sig.count >= 2, !words.isEmpty else { return false }
        if sig.count >= 3, words.indices.contains(where: { words[$0...].joined().hasPrefix(sig) }) { return true }
        let endings: Set<String> = ["inc", "llc", "ltd", "corp", "corporation", "co", "gmbh", "incorporated", "sa", "ag"]
        let initials = String(words.compactMap(\.first)), initialsWithoutEnding = String(words.filter { !endings.contains($0) }.compactMap(\.first))
        if initials.count >= 2 && (sig == initials || sig == initialsWithoutEnding) { return true }
        // Initials of some of its words ("SAS": Ben Gottlieb & Stand Alone Software)
        if sig.count >= 3, initials.contains(sig) { return true }
        // Letters taken in order, starting a word: "CVis" (Coherent Visual), "JoBS"
        // (Joachim Bondo Schultz); each capital in the signature starts a word
        let folded = words.map { $0.folding(options: .diacriticInsensitive, locale: nil) }
        let capitals = signature.split(separator: ":").last.map { $0.filter(\.isUppercase).count } ?? 0
        if sig.count >= 4, sig.allSatisfy(\.isLetter), capitals >= 2 {
            for start in folded.indices where folded[start].first == sig.first {
                if Self.isAbbreviation(Array(sig), of: Array(folded[start...]), capitals: Array(signature.split(separator: ":").last ?? "")) { return true }
            }
        }
        let common: Set<String> = ["software", "systems", "system", "computer", "computers", "computing", "technologies",
                                   "technology", "design", "designs", "research", "labs", "group", "products", "productions",
                                   "solutions", "consulting", "international", "newton", "the", "and", "with", "from",
                                   "services", "media", "data", "development", "university", "company"]
        return words.contains { $0.count >= 4 && !common.contains($0) && !endings.contains($0) && sig.contains($0) }
    }

    /// Whether a signature's letters come in order from the words, each capital
    /// letter of it starting a new word and the lower-case ones following it.
    private static func isAbbreviation(_ sig: [Character], of words: [String], capitals original: [Character]) -> Bool {
        let shape = original.filter { $0.isLetter }
        guard shape.count == sig.count else { return false }
        var w = -1, pos = 0
        for (i, c) in sig.enumerated() {
            if shape[i].isUppercase {
                w += 1   // the next word must start with it
                guard w < words.count, words[w].first == c else { return false }
                pos = 1
            } else {
                guard w >= 0, let found = words[w].dropFirst(pos).firstIndex(of: c) else { return false }
                pos = words[w].distance(from: words[w].startIndex, to: found) + 1
            }
        }
        return true
    }

    /// Picks the publisher out of a copyright line such as
    /// "©1995-1997 Scrawl, LLC. All rights reserved." -> "Scrawl, LLC".
    ///
    /// - The holder is what follows the last ©, "(c)", "Copyright" or "Copyleft"
    ///   (with several holders, the last is usually the publisher), or what
    ///   follows the years when the line starts with them. "@1997" and "_1998"
    ///   are a © that didn't survive.
    /// - "All rights reserved" (or "Alle Rechte vorbehalten"…) ends it: credits
    ///   and serial numbers often follow. So do three spaces or a new line.
    /// - Years ("1995-7", "'96, '97"), versions, prices, phone numbers, e-mail
    ///   and web addresses are left out, and so are credits after the name
    ///   ("Netstrategy Software, by Les R. Titze"; "…, Portions Apple Computer";
    ///   "…. Based on sample code by…"). "Someone for Company" gives the company.
    /// - Without any of that, a credit gives the name ("Built by V. Rehorst,
    ///   code by…" -> "V. Rehorst"); other short text is taken as the name, and
    ///   anything long is a description, not a name.
    static func publisher(fromCopyright copyright: String) -> String? {
        func replace(_ text: String, _ pattern: String, _ with: String = " ") -> String {
            text.replacingOccurrences(of: pattern, with: with, options: .regularExpression)
        }
        let lower = copyright.lowercased()
        if lower.contains("created by pkgstuff") || lower.hasPrefix("generated by") { return nil }
        let years = #"(?<![\w.])'?(19|20)?\d{2}(\s*[-–/,&]\s*'?\d{1,4})*(?![\w.]*\d)"#
        let marker = #"(?i)©|\(c\)|\bcopy(right|left)\b"#
        let leadingYears = #"^\W*(19|20)\d{2}\b"#

        var s = replace(copyright, #"(^|\s)[@_](?=\s?(19|20)\d{2})"#, "$1©")
        // The line with the copyright on it
        let lines = s.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        s = lines.first { $0.range(of: marker, options: .regularExpression) != nil } ?? lines.first ?? ""

        let isCopyright = s.range(of: marker, options: .regularExpression) != nil
            || s.range(of: leadingYears, options: .regularExpression) != nil
            || s.range(of: #"(?i)all rights"#, options: .regularExpression) != nil
            || s.range(of: #"[,\s](19|20)\d{2}\W*$"#, options: .regularExpression) != nil
        if isCopyright {
            // After the last marker, unless the name comes first ("MobileSoft Copyright 1993")
            if let last = s.matches(of: marker).last {
                let after = replace(String(s[last.upperBound...]), years)
                s = after.contains(where: \.isLetter) ? String(s[last.upperBound...]) : String(s[..<last.lowerBound])
            }
            s = replace(s, #"(?i)\b(all rights?|alle rechte|tous droits|todos los derechos|used without permission)\b.*$"#, "")
            s = s.components(separatedBy: "   ").first { $0.contains { $0.isLetter } } ?? s
            s = replace(s, #"\d{3}[-.]\d{3}[-.]\d{4}"#)
            // With years before each of several holders, the last
            if let last = s.matches(of: years).last, s.matches(of: years).count > 1,
               s[last.upperBound...].contains(where: \.isLetter) {
                s = String(s[last.upperBound...])
            }
            s = replace(s, years)
        } else if let credit = s.range(of: #"(?i)\b(made|built|created|written|developed|programmed|modified|designed|compiled)\b.*?\bby\s+"#,
                                       options: .regularExpression) {
            s = String(s[credit.upperBound...])
            if let end = s.range(of: #"[,;($]"#, options: .regularExpression) { s = String(s[..<end.lowerBound]) }
        } else if s.count > 40 || s.contains("--") {
            return nil   // a description, not a name
        }

        // Addresses, prices and versions (though an address alone is the name)
        let email = s.range(of: #"[\w.+-]+@[\w-]+(\.[\w-]+)+"#, options: .regularExpression).map { String(s[$0]) }
        s = replace(s, #"[<(]?[\w.+-]+@[\w-]+(\.[\w-]+)+[>)]?"#)
        s = replace(s, #"\(?\b(https?://|www\.)\S+\)?"#)
        s = replace(s, #"(?i)\b(US)?\$\s?[\d.]*|\bshareware:?"#)
        s = replace(s, #"(?i)\((?=[^)]*\b(demo|version|beta)\b)[^)]*\)"#)
        s = replace(s, #"(?i)\b(version|vers?\.?|rev\.?)\s*\d[\w.]*"#)
        s = replace(s, #"\(?\bv?\d+\.\d+[\w.]*\)?"#)
        s = replace(s, #"\d{5,}"#)
        s = replace(s, #"\s+"#)
        s = replace(s, #"^[\s,;:\-–.'")]+|[\s,;:\-–'"(]+$"#, "")
        // "by Someone", "Company, by Someone", "Someone for Company"
        if s.lowercased().hasPrefix("by ") { s = String(s.dropFirst(3)) }
        s = replace(s, #"(?i)[,.;]?\s+(-\s+)?(with permission|portions|based on|modified|ported)\b.*$"#, "")
        if let by = s.range(of: #"(?i)[,.]?\s+((written|code|programmed|developed|designed)\s+)?by\s"#, options: .regularExpression),
           s[..<by.lowerBound].contains(where: \.isLetter) {
            s = String(s[..<by.lowerBound])
        }
        if let range = s.range(of: " for "), s[range.upperBound...].first?.isUppercase == true {
            s = String(s[range.upperBound...])
        }
        s = replace(s, #"^[\s,;:\-–.'")]+|[\s,;:\-–'"(]+$"#, "")
        // Drop a full stop at the end, unless it ends an abbreviation like "Inc."
        while s.hasSuffix(".") {
            let lastWord = s.dropLast().split(separator: " ").last.map(String.init) ?? ""
            if ["Inc", "Ltd", "Co", "Corp", "Jr", "Sr", "S.A", "GmbH"].contains(lastWord) && !s.hasSuffix("..") { break }
            s = String(s.dropLast())
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        return s.contains(where: \.isLetter) ? s : email
    }
}

private extension String {
    /// Where a regular expression matches, in order.
    func matches(of pattern: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: self, range: NSRange(startIndex..., in: self)).compactMap { Range($0.range, in: self) }
    }
}
