import AppKit

enum Remover {
    static let fm = FileManager.default

    /// Removes the selected items. Call on the main thread (the admin prompt needs it).
    static func remove(_ items: [FoundItem], permanent: Bool, bundleID: String?) -> [String] {
        var log: [String] = []
        var adminCmds: [String] = []
        var adminPaths: [String] = []
        let uid = getuid()
        let q = Shell.q

        // 1. Quit the app and anything running from inside it
        let appPaths = items.filter { $0.kind == .app }.map(\.path)
        for app in NSWorkspace.shared.runningApplications {
            let p = app.bundleURL?.path ?? ""
            let sameID = bundleID != nil && app.bundleIdentifier == bundleID
            let inside = appPaths.contains { p == $0 || p.hasPrefix($0 + "/") }
            if sameID || inside {
                app.forceTerminate()
                log.append("Quit \(app.localizedName ?? p)")
            }
        }
        for p in appPaths { Shell.run("/usr/bin/pkill", ["-f", p]) }

        // 2. Stop launchd jobs so they can't respawn
        for item in items where item.kind == .launchItem {
            if item.isJobOnly, let label = item.launchLabel {
                Shell.run("/bin/launchctl", ["remove", label])
                log.append("Stopped job \(label)")
            } else if item.path.hasPrefix("/Library/LaunchDaemons/") {
                adminCmds.append("launchctl bootout system \(q(item.path)) 2>/dev/null")
            } else {
                Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)", item.path])
                if item.path.hasPrefix("/Library/LaunchAgents/") {
                    // Also unload it for the system session in case it was loaded there
                    adminCmds.append("launchctl bootout system \(q(item.path)) 2>/dev/null")
                }
            }
        }
        for item in items where item.kind == .helper {
            let name = (item.path as NSString).lastPathComponent
            adminCmds.append("launchctl bootout system/\(q(name)) 2>/dev/null")
            adminCmds.append("pkill -f \(q(item.path))")
        }

        // 3. Delete files, trying without a password first
        for item in items where item.isFile {
            guard Safety.isSafe(item.path) else {
                log.append("Skipped (protected): \(item.displayPath)")
                continue
            }
            if !item.needsAdmin {
                do {
                    if permanent {
                        try fm.removeItem(atPath: item.path)
                    } else {
                        try fm.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                    }
                    log.append("Removed \(item.displayPath)")
                    continue
                } catch {
                    // fall through to the admin pass
                }
            }
            if permanent {
                adminCmds.append("rm -rf \(q(item.path))")
            } else {
                let dest = trashDestination(for: item.path)
                adminCmds.append("mv -f \(q(item.path)) \(q(dest)) && chown -R \(uid) \(q(dest))")
            }
            adminPaths.append(item.path)
        }

        // 4. Installer receipts
        for item in items where item.kind == .receipt {
            adminCmds.append("pkgutil --forget \(q(item.path)) >/dev/null 2>&1")
        }

        // 5. One password prompt for everything that needs root
        if !adminCmds.isEmpty {
            let script = adminCmds.map { "(\($0)) || true" }.joined(separator: "; ")
            let result = Shell.runAsAdmin(script)
            if result.ok {
                for p in adminPaths { log.append("Removed (admin) \(display(p))") }
                let receipts = items.filter { $0.kind == .receipt }
                for r in receipts { log.append("Forgot receipt \(r.path)") }
            } else {
                log.append("Admin step cancelled or failed: \(result.message)")
            }
        }

        // 6. Verify
        var leftovers = 0
        for item in items where item.isFile && LeftoverScanner.exists(item.path) {
            leftovers += 1
            log.append("⚠️ Still there: \(item.displayPath)")
        }
        if leftovers > 0 {
            log.append("Some items couldn't be removed. Give Uninstaller Full Disk Access and App Management in System Settings → Privacy & Security, then scan again.")
        } else {
            log.append(permanent ? "✅ Done. Everything selected is deleted." : "✅ Done. Everything selected is in the Trash. Empty it to finish.")
        }
        return log
    }

    private static var usedTrashNames = Set<String>()

    static func trashDestination(for path: String) -> String {
        let trash = NSHomeDirectory() + "/.Trash"
        let name = (path as NSString).lastPathComponent
        var dest = (trash as NSString).appendingPathComponent(name)
        var n = 2
        while LeftoverScanner.exists(dest) || usedTrashNames.contains(dest) {
            dest = (trash as NSString).appendingPathComponent("\(name) \(n)")
            n += 1
        }
        usedTrashNames.insert(dest)
        return dest
    }

    static func display(_ p: String) -> String {
        let h = NSHomeDirectory()
        return p.hasPrefix(h) ? "~" + p.dropFirst(h.count) : p
    }
}
