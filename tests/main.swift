// Command-line check of the package reader: prints what it finds in each file.
//   tests/run_inspect.sh FILE...
import Foundation

let df = DateFormatter()
df.dateStyle = .medium
for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url) else { print("UNREADABLE \(path)"); continue }
    do {
        let i = try PackageReader.inspect(data, fileName: url.lastPathComponent)
        let date = i.creationDate.map { df.string(from: $0) } ?? "-"
        let icon = i.icon.map { "\($0.width)x\($0.height)\(i.hasGreyIcon ? " grey" : "")" } ?? "none"
        print("\(url.lastPathComponent) | \(i.title) | pub: \(i.publisher ?? "-") | \(i.kind.label) | OS: \(i.detectedOS.shortLabel) (min \(i.minOS ?? "?"), max \((i.maxOS ?? "").isEmpty ? "-" : i.maxOS!)) | v\(i.version)\(i.versionText.map { " = \($0)" } ?? "") | \(date) | icon \(icon)")
        if let hosts = i.hostNames, !hosts.isEmpty { print("    looks up: \(hosts.joined(separator: ", "))") }
        for e in i.evidence { print("    \(e.requires.map { "[\($0.shortLabel)]" } ?? "[note]") \(e.text)") }
        for w in i.warnings { print("    WARNING \(w)") }
        // ICON_DIR=folder also saves each icon as a PGM image; see-through pixels are mid grey
        if let dir = ProcessInfo.processInfo.environment["ICON_DIR"], let b = i.icon {
            var pgm = Data("P5 \(b.width) \(b.height) 255\n".utf8)
            for (g, a) in zip(b.grey, b.alpha) { pgm.append(a == 0 ? 128 : g) }
            try? pgm.write(to: URL(fileURLWithPath: dir).appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".pgm"))
        }
    } catch {
        print("\(url.lastPathComponent) | ERROR \(error.localizedDescription)")
    }
}
