import Foundation

/// Which packages belong together: add-ons (sounds, card decks, game data…) and
/// the main package they're for.
///
/// Newton packages name the app they add to by its registered name
/// ("Name:Signature"). NewtHack Sounds, for example, puts its sounds in the
/// global `NewtHack:ChrisDopp`, which is NewtHack's app symbol. So:
///
/// - **Linked:** a package mentions another package's package name or app
///   symbol (also as the end of a longer name, like `Extras:SoloDx:Tactile`
///   for Solito DX's `SoloDx:Tactile`).
/// - **Also linked:** an add-on that looks up (with GetRoot or GetGlobals) a
///   name that exactly one app also looks up: it leaves its data there for that
///   app. The Infocom games and YAZI, the Z-machine interpreter, share
///   "zparse:Gmad".
///   The same goes for a soup both use by a registered-style name: the Dell
///   puzzle packs add their puzzles to the soup "DELLCW:BBANDCO", which Dell
///   Crosswords reads.
/// - **Also linked:** a package that defines a global (DefGlobalVar,
///   DefGlobalFn) under its developer's registered name that one of the same
///   developer's apps reads, even if it's an app itself: SoundPak defines
///   "AddedSounds:ALLAN", which AlarmPak reads. (Not a name an app defines
///   too: that's the app's own registry.)
/// - **Probably linked** (when there's no such link): an add-on whose name
///   starts with an app's name under the same signature ("Columns Sound:Tactile"
///   and "Columns:Tactile"), or that shares a registered name with exactly one
///   app and nothing else ("MoData:Tactile" in Demo and Motile).
/// - **Needs:** an add-on that looks up a registered name that no package in
///   the library is named after and no application mentions: probably an app
///   you don't have (the Infocom games need `zparse:Gmad`).
///
/// When the choice is between versions of the same package, the one made
/// nearest in time is chosen. Versions of a package (the same package name
/// and kind) never belong to each other, and nor do two applications from
/// different developers that name each other: that's working together (Avi's
/// Backdrop shows MoreInfo's data), not an add-on.
///
/// Where two packages are linked, the main one is an application rather than
/// an add-on, else the one with more links; of two applications that name
/// each other, the bigger; else the one that's mentioned.
struct Relations {
    /// Add-on -> the package it belongs to (one step; see `root`).
    var main: [Int64: Int64] = [:]
    /// Add-ons whose link is only probable.
    var probable: Set<Int64> = []
    /// Registered names an add-on looks up that nothing in the library provides.
    var needs: [Int64: [String]] = [:]

    /// The package an item belongs to, following add-ons of add-ons, or nil.
    func root(of id: Int64) -> Int64? {
        var current = id
        var visited: Set<Int64> = [id]
        while let next = main[current], !visited.contains(next) {
            visited.insert(next)
            current = next
        }
        return current == id ? nil : current
    }

    /// The add-ons that belong to a package (one step).
    func addOns(of id: Int64) -> [Int64] {
        main.filter { $0.value == id }.map(\.key)
    }

    // MARK: Working them out

    static func compute(_ items: [LibraryItem]) -> Relations {
        var result = Relations()
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        // Each package's identities: its package name and app symbol
        func identities(_ item: LibraryItem) -> Set<String> {
            Set([item.value(.packageName), item.value(.appSymbol)]
                .map { $0.lowercased() }
                .filter { $0.contains(":") })
        }
        // Who has each identity (several packages when the library has several
        // versions of one, like PocketMoney 2.16 and 3.05)
        var owners: [String: [Int64]] = [:]
        for item in items {
            for name in identities(item) { owners[name, default: []].append(item.id) }
        }
        /// The packages a mentioned name points to: an exact identity, or the end
        /// of the name after any colon ("extras:solodx:tactile" -> "solodx:tactile").
        func candidates(_ name: String) -> [Int64] {
            if let ids = owners[name] { return ids }
            var rest = Substring(name)
            while let colon = rest.firstIndex(of: ":") {
                rest = rest[rest.index(after: colon)...]
                if rest.contains(":"), let ids = owners[String(rest)] { return ids }
            }
            return []
        }
        /// Whether a name is some package's.
        func isSomeonesName(_ name: String) -> Bool { !candidates(name).isEmpty }
        /// The package a name in `item` points to. With several versions of it in
        /// the library, the one made nearest in time to `item` (so PocketMoney
        /// 2.16's reports go with PocketMoney 2.16, not 3.05), never `item` itself
        /// or another version of `item`.
        func resolve(_ name: String, from item: LibraryItem) -> Int64? {
            let found = candidates(name).compactMap { byID[$0] }
                .filter { $0.id != item.id && !sameName(item, $0) }
            guard found.count > 1 else { return found.first?.id }
            let date = item.creationDate ?? .distantPast
            return found.min { a, b in
                abs((a.creationDate ?? .distantFuture).timeIntervalSince(date))
                    < abs((b.creationDate ?? .distantFuture).timeIntervalSince(date))
            }?.id
        }

        /// Whether two packages are versions of the same one (the same package
        /// name and kind): they never belong to each other. (An extension and an
        /// app with one name, like TapBar's core and its settings app, can.)
        func sameName(_ a: LibraryItem, _ b: LibraryItem?) -> Bool {
            guard let b = b else { return false }
            let name = a.value(.packageName).lowercased()
            return !name.isEmpty && name == b.value(.packageName).lowercased() && a.info.kind == b.info.kind
        }
        /// A package's signature: the last part ("Extras:SoloDx:Tactile" -> "tactile").
        /// (Worked out once for each: it's compared for every add-on with every app.)
        let signatures = Dictionary(uniqueKeysWithValues: items.map {
            ($0.id, String($0.value(.signature).lowercased().split(separator: ":").last ?? ""))
        })
        func signature(_ item: LibraryItem) -> String { signatures[item.id] ?? "" }
        /// The developer part of a registered name: "addedsounds:allan" -> "allan".
        func nameSignature(_ name: String) -> String { String(name.split(separator: ":").last ?? "") }

        /// Whether two packages are applications from different developers: one
        /// naming the other is working with it (Avi's Backdrop shows MoreInfo's
        /// data if it's there), not an add-on for it.
        func isIntegration(_ a: LibraryItem, _ b: LibraryItem?) -> Bool {
            guard let b = b, a.info.kind.isApplication, b.info.kind.isApplication else { return false }
            // (Packages without a signature, like the songs for ModPlayer, can't tell)
            let sa = signature(a), sb = signature(b)
            return !sa.isEmpty && !sb.isEmpty && sa != sb
        }

        // Strong links, as undirected pairs, remembering who mentioned whom
        var mentions: [Int64: Set<Int64>] = [:]
        for item in items {
            let own = identities(item)
            for name in item.info.registeredNames ?? [] {
                let lower = name.lowercased()
                guard !own.contains(lower), let other = resolve(lower, from: item),
                      !isIntegration(item, byID[other]) else { continue }
                mentions[item.id, default: []].insert(other)
            }
        }
        var neighbours: [Int64: Set<Int64>] = [:]
        for (a, targets) in mentions {
            for b in targets {
                neighbours[a, default: []].insert(b)
                neighbours[b, default: []].insert(a)
            }
        }
        let appIDs = Set(items.filter { $0.kind.isApplication || $0.info.kind.isApplication }.map(\.id))
        func isApp(_ id: Int64) -> Bool { appIDs.contains(id) }
        /// Which of two linked packages is the main one.
        func mainOf(_ a: Int64, _ b: Int64) -> Int64 {
            if isApp(a) != isApp(b) { return isApp(a) ? a : b }
            let da = neighbours[a]?.count ?? 0, db = neighbours[b]?.count ?? 0
            if da != db { return da > db ? a : b }
            // Two apps that name each other, equally linked (PocketMoney and its
            // ExCHANGE): the bigger one is the main app, the other its helper
            let aMentions = mentions[a]?.contains(b) ?? false, bMentions = mentions[b]?.contains(a) ?? false
            if isApp(a), aMentions, bMentions, let sa = byID[a]?.info.fileSize, let sb = byID[b]?.info.fileSize, sa != sb {
                return sa > sb ? a : b
            }
            let aMentionsB = mentions[a]?.contains(b) ?? false, bMentionsA = mentions[b]?.contains(a) ?? false
            if aMentionsB != bMentionsA { return aMentionsB ? b : a }
            return min(a, b)
        }
        for (a, others) in neighbours {
            // The best main among this package's links that aren't add-ons of it
            var mains = others.filter { mainOf(a, $0) == $0 }
            // Preferably one it names itself, not a package that names it among many
            // others (gesture scripts naming every app they launch)
            let named = mains.filter { mentions[a]?.contains($0) == true }
            if !named.isEmpty { mains = named }
            if let best = mains.max(by: { (neighbours[$0]?.count ?? 0, -$0) < (neighbours[$1]?.count ?? 0, -$1) }) {
                result.main[a] = best
            }
        }

        /// The one of several candidates to link to: the only one, or, when they're
        /// versions of the same package, the one made nearest in time to `item`
        /// (AlarmPak 2.0b9's manual goes with AlarmPak 2.0b9, not 1.4.2).
        func nearest(_ candidates: [LibraryItem], to item: LibraryItem) -> LibraryItem? {
            guard candidates.count > 1 else { return candidates.first }
            guard Set(candidates.map { $0.value(.packageName).lowercased() }).count == 1 else { return nil }
            let date = item.creationDate ?? .distantPast
            return candidates.min { a, b in
                abs((a.creationDate ?? .distantFuture).timeIntervalSince(date))
                    < abs((b.creationDate ?? .distantFuture).timeIntervalSince(date))
            }
        }

        // A package that defines a global (DefGlobalVar, DefGlobalFn) that one app
        // reads: it's there for that app. SoundPak defines "AddedSounds:ALLAN",
        // the extra sounds AlarmPak reads. (Even when it's an app itself.)
        // Only names under the developer's own signature count ("PatchedAlphaKeyboard:
        // Newton" is shared by anyone's keyboards), and not a name an app defines
        // too: that's the app's own registry (NetHopper's "NH3RegMgr:ALLPEN").
        var readers: [String: [Int64]] = [:], definers: [String: [Int64]] = [:]
        for item in items {
            let defines = Set((item.info.definedNames ?? []).map { $0.lowercased() }), own = identities(item)
            for name in defines { definers[name, default: []].append(item.id) }
            for name in Set((item.info.globalsRead ?? []).map { $0.lowercased() }) where !defines.contains(name) && !own.contains(name) {
                readers[name, default: []].append(item.id)
            }
        }
        for item in items where result.main[item.id] == nil && !signature(item).isEmpty {
            let own = identities(item)
            for name in Set((item.info.definedNames ?? []).map { $0.lowercased() }).sorted()
            where !own.contains(name) && !isSomeonesName(name) && nameSignature(name) == signature(item)
                && !(definers[name] ?? []).contains(where: { $0 != item.id && isApp($0) }) {
                var candidates = (readers[name] ?? []).compactMap { byID[$0] }
                    .filter { $0.id != item.id && signature($0) == signature(item) && !sameName(item, $0) }
                let apps = candidates.filter { isApp($0.id) }
                if !apps.isEmpty { candidates = apps }
                if let main = nearest(candidates, to: item), result.main[main.id] != item.id {
                    result.main[item.id] = main.id
                    break
                }
            }
        }

        // An add-on and exactly one app that both look up the same name: the add-on
        // leaves its data there for the app (the Infocom games and YAZI share
        // "zparse:Gmad", though their publishers differ)
        let apps = items.filter { isApp($0.id) }
        var appsLookingUp: [String: [Int64]] = [:]
        for app in apps {
            for name in Set((app.info.hostNames ?? []).map { $0.lowercased() }) where !identities(app).contains(name) {
                appsLookingUp[name, default: []].append(app.id)
            }
        }
        for item in items where !isApp(item.id) && result.main[item.id] == nil {
            for name in (item.info.hostNames ?? []).map({ $0.lowercased() }) {
                if let lookers = appsLookingUp[name], lookers.count == 1, lookers[0] != item.id {
                    result.main[item.id] = lookers[0]
                    break
                }
            }
        }

        // Probable links, for add-ons without a strong one
        let nameBases = Dictionary(uniqueKeysWithValues: items.map {
            ($0.id, String($0.value(.packageName).split(separator: ":").first ?? "").lowercased())
        })
        func nameBase(_ item: LibraryItem) -> String { nameBases[item.id] ?? "" }
        var holders: [String: [Int64]] = [:]
        for item in items {
            for name in Set((item.info.registeredNames ?? []).map { $0.lowercased() }) {
                holders[name, default: []].append(item.id)
            }
        }
        for item in items where !isApp(item.id) && result.main[item.id] == nil {
            let sig = signature(item), base = nameBase(item)
            guard !sig.isEmpty else { continue }
            // "Columns Sound:Tactile" goes with "Columns:Tactile"
            let named = apps.filter { signature($0) == sig && nameBase($0).count >= 3 && base.hasPrefix(nameBase($0)) }
            let longest = named.map { nameBase($0).count }.max() ?? 0
            if let app = nearest(named.filter { nameBase($0).count == longest }, to: item) {
                result.main[item.id] = app.id
                result.probable.insert(item.id)
                continue
            }
            // A registered name shared with exactly one app, and nothing else
            for name in (item.info.registeredNames ?? []).map({ $0.lowercased() }) {
                guard let both = holders[name], both.count == 2, let other = both.first(where: { $0 != item.id }),
                      let app = byID[other], isApp(other), signature(app) == sig else { continue }
                result.main[item.id] = other
                result.probable.insert(item.id)
                break
            }
        }

        // Apps that add-ons look up but that aren't in the library
        let mentionedByApps = Set(apps.flatMap { ($0.info.registeredNames ?? []).map { $0.lowercased() } })
        for item in items where !isApp(item.id) {
            let own = identities(item)
            let missing = (item.info.hostNames ?? []).filter { name in
                let lower = name.lowercased()
                return !own.contains(lower) && !isSomeonesName(lower) && !mentionedByApps.contains(lower)
            }
            if !missing.isEmpty { result.needs[item.id] = missing }
        }
        return result
    }
}
