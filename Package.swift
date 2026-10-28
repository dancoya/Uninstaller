// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Uninstaller",
    // Current macOS only. Lower to "26.0" if you also want it on Tahoe.
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(
            name: "Uninstaller",
            path: "Sources/Uninstaller",
            resources: [.copy("AppIcon.icns")]
        )
    ]
)
