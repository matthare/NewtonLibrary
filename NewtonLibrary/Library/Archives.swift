import Foundation

/// Opens archives (zip, StuffIt, BinHex, tar, gzip, 7-Zip, RAR…) so the
/// packages inside them can be added.
///
/// Everything is unpacked with `unar` (The Unarchiver's command-line tool, from
/// Homebrew: `brew install unar`), which reads nearly every old Mac and PC
/// archive format. Without it, only zip files can be opened (with macOS's own
/// `ditto`).
enum Archives {
    /// Where `unar` may be installed (Homebrew on Apple silicon, then Intel).
    static let unarPaths = ["/opt/homebrew/bin/unar", "/usr/local/bin/unar"]

    static var unar: URL? {
        unarPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Archives inside archives are opened too, this many deep.
    static let maximumDepth = 4

    /// Extensions archives commonly have, for formats with nothing telling at
    /// their start (self-extracting archives, Compact Pro, LHA…).
    private static let extensions: Set<String> = [
        "zip", "sit", "sitx", "sea", "hqx", "cpt", "bin", "gz", "tgz", "bz2", "tbz", "xz", "txz",
        "tar", "7z", "rar", "lha", "lzh", "arc", "arj", "z", "cab", "dd", "pit", "as",
    ]

    enum Format {
        case zip, other
        /// Only its name says it's an archive
        case byName
    }

    /// Whether a file looks like an archive, from its first bytes (or failing
    /// that its extension), and if so whether it's a zip file.
    static func format(of file: URL) -> Format? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 4096)) ?? Data()
        let bytes = [UInt8](head)
        func starts(_ magic: [UInt8], at offset: Int = 0) -> Bool {
            bytes.count >= offset + magic.count && Array(bytes[offset..<offset + magic.count]) == magic
        }
        func text(_ s: String, at offset: Int = 0) -> Bool { starts(Array(s.utf8), at: offset) }

        if starts([0x50, 0x4B, 0x03, 0x04]) || starts([0x50, 0x4B, 0x05, 0x06]) { return .zip }
        if text("SIT!") || text("StuffIt") || text("Rar!") || text("BZh")
            || starts([0x1F, 0x8B]) || starts([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])
            || starts([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) || text("ustar", at: 257)
            || text("-lh", at: 2) || text("MSCF") {
            return .other
        }
        // BinHex, perhaps after a mail header or a note
        if let string = String(data: head, encoding: .isoLatin1),
           string.contains("(This file must be converted with BinHex") {
            return .other
        }
        // A MacBinary file holding an archive (type SIT!, SITD, ZIP …)
        if bytes.count >= 128, bytes[0] == 0, (1...63).contains(bytes[1]), bytes[74] == 0, bytes[82] == 0 {
            let type = String(decoding: bytes[65..<69], as: UTF8.self)
            if type.hasPrefix("SIT") || ["ZIP ", "PACT", "SITD", "LHA "].contains(type) { return .other }
        }
        return extensions.contains(file.pathExtension.lowercased()) ? .byName : nil
    }

    enum Failure: Error {
        /// It needs `unar`, which isn't installed.
        case needsUnar
        /// The tool couldn't read it (damaged, or not an archive after all).
        case unreadable
    }

    /// Unpacks an archive into a new folder inside `folder`, returning that folder.
    static func extract(_ file: URL, format: Format, into folder: URL) throws -> URL {
        let destination = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let process = Process()
        if let unar = unar {
            process.executableURL = unar
            // Resource forks are left out: packages are data forks. (Keeping them
            // as ".rsrc" files makes unar write nothing at all for some BinHex files.)
            process.arguments = ["-quiet", "-force-rename", "-no-quarantine", "-forks", "skip",
                                 "-output-directory", destination.path, file.path]
        } else if format == .zip {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", file.path, destination.path]
        } else {
            throw Failure.needsUnar
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw Failure.unreadable
        }
        // unar reports any file it couldn't write (such as a resource fork it
        // was asked to leave out) as a failure, even when the rest came out:
        // judge by what's there. Nothing there is fine if the archive can be
        // listed (it holds only resource forks, such as old Mac programs).
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? []
        if contents.isEmpty && !canList(file) { throw Failure.unreadable }
        return destination
    }

    /// Whether `lsar` (installed with unar) can read an archive's list of files.
    private static func canList(_ file: URL) -> Bool {
        guard let lsar = unar?.deletingLastPathComponent().appendingPathComponent("lsar"),
              FileManager.default.isExecutableFile(atPath: lsar.path) else { return false }
        let process = Process()
        process.executableURL = lsar
        process.arguments = [file.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
