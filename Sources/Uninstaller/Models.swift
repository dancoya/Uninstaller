import Foundation

enum ItemKind: String, CaseIterable {
    case app = "Apps"
    case launchItem = "Launch agents & daemons (what starts at login)"
    case helper = "Privileged helpers"
    case support = "Application support"
    case prefs = "Preferences"
    case container = "Containers"
    case cache = "Caches, logs & temp files"
    case binary = "Command-line tools"
    case receipt = "Installer receipts"
    case other = "Other"
    case info = "Found, but must be removed manually"
}

struct FoundItem: Identifiable {
    let id = UUID()
    /// File path, or a launchd label / package ID for non-file items.
    let path: String
    let kind: ItemKind
    var needsAdmin: Bool
    var sizeBytes: Int64 = 0
    var selected: Bool = true
    var note: String? = nil
    var launchLabel: String? = nil
    /// A running launchd job with no plist on disk.
    var isJobOnly: Bool = false
    /// False for informational rows (e.g. system extensions).
    var actionable: Bool = true

    var isFile: Bool { actionable && !isJobOnly && kind != .receipt }

    var displayPath: String {
        if isJobOnly { return "launchd job: \(path)" }
        if kind == .receipt { return "Package receipt: \(path)" }
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

struct Target {
    var displayName: String
    var bundleID: String?
    var appPath: String?
    var terms: [String]
}

enum Safety {
    static let home = NSHomeDirectory()

    static let protectedPaths: Set<String> = {
        var s: Set<String> = [
            "/", "/Applications", "/Library", "/System", "/Users", "/usr", "/usr/local",
            "/usr/local/bin", "/usr/local/lib", "/usr/local/share", "/usr/local/etc",
            "/opt", "/opt/homebrew", "/opt/homebrew/bin", "/private", "/private/var",
            "/var", "/etc", "/bin", "/sbin", "/tmp", "/Volumes", "/cores",
            home, home + "/Library", home + "/Applications", home + "/Desktop",
            home + "/Documents", home + "/Downloads", home + "/.Trash",
        ]
        for d in LeftoverScanner.scanDirs() { s.insert(d.path) }
        return s
    }()

    /// Hard guard against deleting anything structural, no matter what the scan matched.
    static func isSafe(_ rawPath: String) -> Bool {
        let path = (rawPath as NSString).standardizingPath
        guard path.hasPrefix("/"), !protectedPaths.contains(path) else { return false }
        let comps = (path as NSString).pathComponents.filter { $0 != "/" }
        guard comps.count >= 2 else { return false }
        for bad in ["/System/", "/bin/", "/sbin/", "/private/etc/", "/etc/"] where path.hasPrefix(bad) {
            return false
        }
        if path.hasPrefix("/usr/") && !path.hasPrefix("/usr/local/") { return false }
        let me = Bundle.main.bundlePath
        if path == me || me.hasPrefix(path + "/") { return false }
        return true
    }
}
