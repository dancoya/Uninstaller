import Foundation

struct ScanDir {
    let path: String
    let kind: ItemKind
    var isLaunchDir = false
}

enum LeftoverScanner {
    static let fm = FileManager.default

    // MARK: - Where leftovers live

    static func scanDirs() -> [ScanDir] {
        let h = NSHomeDirectory()
        var dirs: [ScanDir] = [
            .init(path: "/Applications", kind: .app),
            .init(path: h + "/Applications", kind: .app),

            .init(path: h + "/Library/LaunchAgents", kind: .launchItem, isLaunchDir: true),
            .init(path: "/Library/LaunchAgents", kind: .launchItem, isLaunchDir: true),
            .init(path: "/Library/LaunchDaemons", kind: .launchItem, isLaunchDir: true),
            .init(path: "/Library/PrivilegedHelperTools", kind: .helper),

            .init(path: h + "/Library/Application Support", kind: .support),
            .init(path: "/Library/Application Support", kind: .support),
            .init(path: h + "/Library/Application Scripts", kind: .support),
            .init(path: h + "/Library/Services", kind: .support),
            .init(path: h + "/Library/Internet Plug-Ins", kind: .other),
            .init(path: "/Library/Internet Plug-Ins", kind: .other),
            .init(path: h + "/Library/PreferencePanes", kind: .other),
            .init(path: "/Library/PreferencePanes", kind: .other),
            .init(path: "/Library/Audio/Plug-Ins/HAL", kind: .other),
            .init(path: "/Library/Extensions", kind: .other),
            .init(path: "/Library/ScriptingAdditions", kind: .other),
            .init(path: "/Library/StartupItems", kind: .launchItem),
            .init(path: "/Library/Frameworks", kind: .other),
            .init(path: "/Library/Screen Savers", kind: .other),
            .init(path: h + "/Library/Screen Savers", kind: .other),

            .init(path: h + "/Library/Preferences", kind: .prefs),
            .init(path: h + "/Library/Preferences/ByHost", kind: .prefs),
            .init(path: "/Library/Preferences", kind: .prefs),

            .init(path: h + "/Library/Containers", kind: .container),
            .init(path: h + "/Library/Group Containers", kind: .container),

            .init(path: h + "/Library/Caches", kind: .cache),
            .init(path: "/Library/Caches", kind: .cache),
            .init(path: h + "/Library/Logs", kind: .cache),
            .init(path: "/Library/Logs", kind: .cache),
            .init(path: "/Library/Logs/DiagnosticReports", kind: .cache),
            .init(path: h + "/Library/Logs/DiagnosticReports", kind: .cache),
            .init(path: h + "/Library/HTTPStorages", kind: .cache),
            .init(path: h + "/Library/WebKit", kind: .cache),
            .init(path: h + "/Library/Cookies", kind: .cache),
            .init(path: h + "/Library/Saved Application State", kind: .cache),
            .init(path: h + "/Library/Autosave Information", kind: .cache),

            .init(path: "/usr/local/bin", kind: .binary),
            .init(path: "/opt/homebrew/bin", kind: .binary),
            .init(path: h + "/.local/bin", kind: .binary),
        ]
        // Per-user temp and cache folders under /private/var/folders
        for key in ["DARWIN_USER_CACHE_DIR", "DARWIN_USER_TEMP_DIR"] {
            let out = Shell.run("/usr/bin/getconf", [key]).out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !out.isEmpty {
                dirs.append(.init(path: (out as NSString).standardizingPath, kind: .cache))
            }
        }
        return dirs
    }

    // MARK: - Building a target

    static func target(fromApp url: URL) -> Target {
        let bundle = Bundle(url: url)
        let fileName = url.deletingPathExtension().lastPathComponent
        let name = (bundle?.infoDictionary?["CFBundleName"] as? String) ?? fileName
        let bid = bundle?.bundleIdentifier
        var terms = [name, fileName]
        if let bid { terms.append(bid) }
        return Target(displayName: name, bundleID: bid, appPath: url.path, terms: unique(terms))
    }

    static func parseTerms(_ text: String) -> [String] {
        unique(text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 })
    }

    static func unique(_ a: [String]) -> [String] {
        var seen = Set<String>()
        return a.filter { seen.insert($0.lowercased()).inserted }
    }

    // MARK: - Matching

    static func squash(_ s: String) -> String {
        s.lowercased().filter { !" -_".contains($0) }
    }

    /// Term must start at a word boundary, so "asus" doesn't match "Pegasus".
    static func containsAtBoundary(_ hay: String, _ needle: String) -> Bool {
        var range = hay.startIndex..<hay.endIndex
        while let r = hay.range(of: needle, range: range) {
            if r.lowerBound == hay.startIndex || !hay[hay.index(before: r.lowerBound)].isLetter {
                return true
            }
            range = hay.index(after: r.lowerBound)..<hay.endIndex
        }
        return false
    }

    static func matches(_ text: String, _ terms: [String]) -> Bool {
        let lower = text.lowercased()
        let squashed = squash(text)
        for t in terms {
            let tl = t.lowercased()
            guard tl.count >= 3 else { continue }
            if containsAtBoundary(lower, tl) { return true }
            let st = squash(tl)
            if st.count >= 6 && squashed.contains(st) { return true }
        }
        return false
    }

    // MARK: - Scan

    static func scan(terms: [String], appPath: String?) -> [FoundItem] {
        var items: [FoundItem] = []
        var seenPaths = Set<String>()
        var plistLabels = Set<String>()

        func add(_ path: String, _ kind: ItemKind, note: String? = nil, label: String? = nil) {
            let p = (path as NSString).standardizingPath
            guard !seenPaths.contains(p), Safety.isSafe(p) else { return }
            seenPaths.insert(p)
            let parent = (p as NSString).deletingLastPathComponent
            var item = FoundItem(path: p, kind: kind,
                                 needsAdmin: !fm.isWritableFile(atPath: parent))
            item.note = note
            item.launchLabel = label
            item.sizeBytes = size(of: p)
            items.append(item)
        }

        if let appPath { add(appPath, .app) }

        // 1. Known folders
        for dir in scanDirs() {
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names {
                let full = (dir.path as NSString).appendingPathComponent(name)
                if dir.isLaunchDir {
                    if let label = launchPlistMatch(full, name: name, terms: terms, appPath: appPath) {
                        plistLabels.insert(label)
                        add(full, .launchItem, note: label.isEmpty ? nil : "Label: \(label)", label: label)
                    }
                } else if matches(name, terms) {
                    add(full, dir.kind)
                } else if dir.kind == .binary, let appPath,
                          let dest = try? fm.destinationOfSymbolicLink(atPath: full),
                          dest.hasPrefix(appPath) {
                    add(full, .binary, note: "Symlink into the app")
                }
            }
        }

        // 2. Installer receipts and every file they installed
        let pkgutil = "/usr/sbin/pkgutil"
        let pkgs = Shell.run(pkgutil, ["--pkgs"]).out
            .split(separator: "\n").map(String.init)
            .filter { matches($0, terms) }
        for pkg in pkgs {
            for f in receiptFiles(pkg) { add(f, classify(f), note: "Installed by \(pkg)") }
            var r = FoundItem(path: pkg, kind: .receipt, needsAdmin: true)
            r.note = "Forget this installer record"
            items.append(r)
        }

        // 3. Running launchd jobs that have no plist on disk (e.g. registered from inside the app)
        let list = Shell.run("/bin/launchctl", ["list"]).out
        for line in list.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            let label = String(cols[2])
            guard matches(label, terms), !plistLabels.contains(label) else { continue }
            var job = FoundItem(path: label, kind: .launchItem, needsAdmin: false)
            job.isJobOnly = true
            job.launchLabel = label
            job.note = "Loaded right now, will be stopped"
            items.append(job)
        }

        // 4. System extensions (informational — macOS only lets the owning app remove these)
        let sysext = Shell.run("/usr/bin/systemextensionsctl", ["list"]).out
        for line in sysext.split(separator: "\n") where matches(String(line), terms) {
            var info = FoundItem(path: line.trimmingCharacters(in: .whitespaces), kind: .info, needsAdmin: true)
            info.actionable = false
            info.selected = false
            info.note = "System extension. Remove it in System Settings → General → Login Items & Extensions → Extensions."
            items.append(info)
        }

        return dropNested(items)
    }

    /// If a folder is being removed, don't list its contents separately.
    static func dropNested(_ items: [FoundItem]) -> [FoundItem] {
        let filePaths = Set(items.filter(\.isFile).map(\.path))
        return items.filter { item in
            guard item.isFile else { return true }
            var p = (item.path as NSString).deletingLastPathComponent
            while p.count > 1 {
                if filePaths.contains(p) { return false }
                p = (p as NSString).deletingLastPathComponent
            }
            return true
        }
    }

    /// Returns the plist's Label if it belongs to the target, else nil.
    static func launchPlistMatch(_ path: String, name: String, terms: [String], appPath: String?) -> String? {
        let dict = NSDictionary(contentsOfFile: path)
        let label = dict?["Label"] as? String ?? ""
        var hay = name + " " + label
        if let prog = dict?["Program"] as? String { hay += " " + prog }
        if let args = dict?["ProgramArguments"] as? [String] { hay += " " + args.joined(separator: " ") }
        if let bp = dict?["BundleProgram"] as? String { hay += " " + bp }
        if let assoc = dict?["AssociatedBundleIdentifiers"] as? [String] { hay += " " + assoc.joined(separator: " ") }
        if matches(hay, terms) { return label }
        if let appPath, hay.contains(appPath) { return label }
        return nil
    }

    static let ownedDirExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "kext", "driver", "prefpane",
        "component", "systemextension", "dext", "saver", "qlgenerator", "mdimporter",
    ]

    /// Top-level files a package installed, without ever claiming a shared directory.
    static func receiptFiles(_ pkg: String) -> [String] {
        let pkgutil = "/usr/sbin/pkgutil"
        var volume = "/", location = ""
        for line in Shell.run(pkgutil, ["--pkg-info", pkg]).out.split(separator: "\n") {
            if line.hasPrefix("volume: ") { volume = String(line.dropFirst(8)) }
            if line.hasPrefix("location: ") { location = String(line.dropFirst(10)) }
        }
        let base = (volume as NSString).appendingPathComponent(location)
        let all = Shell.run(pkgutil, ["--files", pkg]).out
            .split(separator: "\n")
            .map { ((base as NSString).appendingPathComponent(String($0)) as NSString).standardizingPath }
            .sorted()

        var included: [String] = []
        var includedSet = Set<String>()
        for f in all {
            guard Safety.isSafe(f), exists(f) else { continue }
            // Skip if something above it is already being removed
            var p = (f as NSString).deletingLastPathComponent
            var covered = false
            while p.count > 1 {
                if includedSet.contains(p) { covered = true; break }
                p = (p as NSString).deletingLastPathComponent
            }
            if covered { continue }

            var isDir: ObjCBool = false
            fm.fileExists(atPath: f, isDirectory: &isDir)
            let isOwnedDir = ownedDirExtensions.contains((f as NSString).pathExtension.lowercased())
            if isDir.boolValue && !isOwnedDir {
                // Directories only count if they're clearly the vendor's own, e.g. ".../ASUS"
                let name = (f as NSString).lastPathComponent
                guard pkgNameMatches(name, pkg) else { continue }
            }
            included.append(f)
            includedSet.insert(f)
        }
        return included
    }

    /// A folder like "ASUS" or "DisplayWidget" is owned by package "com.asus.displaywidget".
    static func pkgNameMatches(_ dirName: String, _ pkg: String) -> Bool {
        let n = squash(dirName)
        guard n.count >= 3 else { return false }
        return pkg.lowercased().split(separator: ".").contains { squash(String($0)) == n }
    }

    static func classify(_ p: String) -> ItemKind {
        if p.contains("/LaunchDaemons/") || p.contains("/LaunchAgents/") { return .launchItem }
        if p.contains("/PrivilegedHelperTools/") { return .helper }
        if p.hasSuffix(".app") { return .app }
        if p.contains("/bin/") { return .binary }
        if p.contains("/Caches/") || p.contains("/Logs/") { return .cache }
        if p.contains("/Preferences/") { return .prefs }
        if p.contains("Containers/") { return .container }
        if p.contains("/Application Support/") { return .support }
        return .other
    }

    static func exists(_ p: String) -> Bool {
        // attributesOfItem also sees broken symlinks, which fileExists misses
        (try? fm.attributesOfItem(atPath: p)) != nil
    }

    static func size(of path: String) -> Int64 {
        let out = Shell.run("/usr/bin/du", ["-sk", path]).out
        let first = out.split(whereSeparator: { $0 == "\t" || $0 == " " }).first ?? ""
        return (Int64(first) ?? 0) * 1024
    }
}
