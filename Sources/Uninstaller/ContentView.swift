import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class ViewModel: ObservableObject {
    @Published var termsText = ""
    @Published var targetName = ""
    @Published var items: [FoundItem] = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var permanent = false
    @Published var log: [String] = []
    @Published var confirming = false

    var appPath: String?
    var bundleID: String?

    var selected: [FoundItem] { items.filter { $0.selected && $0.actionable } }
    var selectedSize: Int64 { selected.reduce(0) { $0 + $1.sizeBytes } }

    func load(app url: URL) {
        let t = LeftoverScanner.target(fromApp: url)
        appPath = t.appPath
        bundleID = t.bundleID
        targetName = t.displayName
        termsText = t.terms.joined(separator: ", ")
        scan()
    }

    func scan() {
        let terms = LeftoverScanner.parseTerms(termsText)
        guard !terms.isEmpty else { return }
        if targetName.isEmpty { targetName = terms[0] }
        isScanning = true
        log = []
        let appPath = self.appPath
        Task.detached(priority: .userInitiated) {
            let found = LeftoverScanner.scan(terms: terms, appPath: appPath)
            await MainActor.run {
                self.items = found
                self.isScanning = false
                self.hasScanned = true
            }
        }
    }

    func reset() {
        appPath = nil
        bundleID = nil
        targetName = ""
        termsText = ""
        items = []
        log = []
        hasScanned = false
    }

    func setSelected(_ id: UUID, _ on: Bool) {
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].selected = on }
    }

    func setAll(_ on: Bool) {
        for i in items.indices where items[i].actionable { items[i].selected = on }
    }

    func removeSelected() {
        log = Remover.remove(selected, permanent: permanent, bundleID: bundleID)
        let removed = Set(selected.map(\.id))
        items.removeAll { removed.contains($0.id) && (!$0.isFile || !LeftoverScanner.exists($0.path)) }
    }

    func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { load(app: url) }
    }
}

struct ContentView: View {
    @StateObject private var vm = ViewModel()
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if vm.isScanning {
                Spacer()
                ProgressView("Scanning your Mac…")
                Spacer()
            } else if vm.hasScanned {
                results
            } else {
                dropZone
            }
            if !vm.log.isEmpty { logView }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if vm.hasScanned {
                    Button("Start Over", systemImage: "arrow.counterclockwise") { vm.reset() }
                }
                Button("Choose App…", systemImage: "folder") { vm.chooseApp() }
            }
        }
        .confirmationDialog(
            "Remove \(vm.selected.count) items (\(fmt(vm.selectedSize)))?",
            isPresented: $vm.confirming
        ) {
            Button(vm.permanent ? "Delete Permanently" : "Move to Trash", role: .destructive) {
                vm.removeSelected()
            }
        } message: {
            Text(vm.permanent
                 ? "This can't be undone. You may be asked for your password for system files."
                 : "You may be asked for your password for system files.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(vm.targetName.isEmpty ? "Uninstaller" : "Uninstall \(vm.targetName)")
                    .font(.title2.bold())
                Spacer()
            }
            HStack {
                TextField("Or type names to hunt for, comma-separated (e.g. ASUS, DisplayWidget)",
                          text: $vm.termsText)
                    .textFieldStyle(.roundedBorder)
                Button("Scan") { vm.scan() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(LeftoverScanner.parseTerms(vm.termsText).isEmpty || vm.isScanning)
            }
            Text("Tip: add the company name too (like “ASUS”) to catch helpers named after the vendor. Already deleted the app? Just type its name.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: Empty state

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash.square")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Drop an app here")
                .font(.title3)
            Text("or choose one, or type a name above")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
                .padding(24)
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.pathExtension == "app" else { return false }
            vm.load(app: url)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    // MARK: Results

    private var results: some View {
        VStack(spacing: 0) {
            if vm.items.isEmpty {
                Spacer()
                Text("Nothing found. 🎉").font(.title3)
                Text("Try adding another name, like the company name.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(ItemKind.allCases, id: \.self) { kind in
                        let group = vm.items.filter { $0.kind == kind }
                        if !group.isEmpty {
                            Section(kind.rawValue) {
                                ForEach(group) { item in row(item) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            footer
        }
    }

    private func row(_ item: FoundItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { item.selected },
                set: { vm.setSelected(item.id, $0) }
            ))
            .labelsHidden()
            .disabled(!item.actionable)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayPath)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                if let note = item.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if item.needsAdmin && item.actionable {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .help("Needs your admin password")
            }
            if item.sizeBytes > 0 {
                Text(fmt(item.sizeBytes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if item.isFile {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            Button("Select All") { vm.setAll(true) }
            Button("Select None") { vm.setAll(false) }
            Button("Rescan") { vm.scan() }
            Spacer()
            Picker("", selection: $vm.permanent) {
                Text("Move to Trash").tag(false)
                Text("Delete Permanently").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            Button("Remove \(vm.selected.count) Items") { vm.confirming = true }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(vm.selected.isEmpty)
        }
        .padding()
    }

    // MARK: Log

    private var logView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Results").font(.headline)
                Spacer()
                Button("Open Login Items Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .help("Clear any leftover toggle under “Allow in the Background”")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(vm.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 140)
        }
        .padding()
        .background(.bar)
    }

    private func fmt(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
