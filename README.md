# Uninstaller

**Uninstaller for macOS.** Dragging an app to the Trash leaves a lot behind. Uninstaller scans your Mac for every leftover file an app scattered around and completely cleans up after it: the app itself, launch agents and daemons (what makes things start at login), privileged helpers, support files, preferences, containers, caches, logs, temp files, command-line tools, and installer receipts along with every file the installer put down. It works on apps you're about to remove and on apps you've already deleted.

**[Download the latest release](https://github.com/dancoya/Uninstaller/releases/latest)** (macOS 27, Apple Silicon).

## Build

Requires macOS 27 and Xcode 27 (or its Command Line Tools). To run on macOS 26 Tahoe as well, change `"27.0"` to `"26.0"` in `Package.swift` and `build-app.sh`.

```bash
cd Uninstaller
chmod +x build-app.sh
./build-app.sh
```

Move `Uninstaller.app` into /Applications. The first time, right-click it and choose Open.

To try it without building the app: `swift run`.

## Permissions (do this once)

System Settings → Privacy & Security:
- **Full Disk Access** → add Uninstaller (lets it see and clear other apps' containers)
- **App Management** → add Uninstaller (lets it delete other apps)

## Use

1. Drop an app on the window, click **Choose App…**, or, if the app is already deleted, type its name (for ASUS: `ASUS, DisplayWidget`).
2. Review the list. Everything is checked by default; uncheck anything you want to keep. The magnifying glass shows an item in Finder. A lock means it needs your password.
3. Pick **Move to Trash** (safe, undoable) or **Delete Permanently**, then **Remove**.
4. Click **Open Login Items Settings** and turn off any leftover entry under "Allow in the Background."

## Safety

- Names must match at the start of a word, so "asus" won't match "Pegasus."
- System folders and shared folders (/Library, /usr/local/bin, ~/Library, etc.) can never be deleted, only items inside them.
- For installer receipts, it removes the files the package installed but never a shared folder unless the folder is named after the vendor.
- System extensions are listed but not touched, since macOS only lets you remove those through System Settings.
- Short or generic search words (like "pro" or "video") will match a lot, so always review the list before removing.

## App icon

Art deco icon in `Icon/` — gold bin with fluting and a chevron band, sunburst rays, stepped double frame.

- `Icon/icns/` — `.icns` for light, dark and tinted. The build script ships the light one, so the app shows its icon in the Dock and Finder.
- `Assets.xcassets/AppIcon.appiconset` — every macOS size plus iOS 1024 slots, with Dark and Tinted appearance variants already declared in `Contents.json`.
- `Icon/source/` — the SVGs and 1024 px PNGs; `Icon/make_icons.py` regenerates everything.

### Liquid Glass icon (Icon Composer)

`Icon/icon-composer-layers/` has the design split into three transparent layers, ready for Apple's Icon Composer (ships with Xcode 26+, under Xcode → Open Developer Tool). About two minutes:

1. Open Icon Composer → New → macOS.
2. Drag in `1-rays.png`, `2-frame.png`, `3-bin.png` in that order (bottom to top). Each becomes a layer.
3. Set the background to a gradient using the colors in `background-colors.txt`.
4. Suggested per-layer settings: Rays — opacity 35 %, no glass. Frame — glass on, specular on. Bin — glass on, specular on, slight shadow. Icon Composer will preview Light, Dark, Clear and Tinted; tweak the Dark tab's background to the dark gradient.
5. Save as `Uninstaller.icon` into this folder.

To use it: the `.icon` file only compiles through Xcode, not the Swift package script. Make an Xcode project (File → New → Project → macOS App, bundle ID `com.dan.uninstaller`), add `Sources/Uninstaller`, delete the template's `ContentView.swift`/app file, drag `Uninstaller.icon` into the project, and set it as the App Icon in the target's General tab. Icon Composer can also export a flat `.icns` (File → Export) if you want to update `Icon/icns/` for the script build.

### Classic asset catalog

The project is a Swift package, which builds with the script above. If you turn it into an Xcode app project (File → New → Project → macOS App, then drag in `Sources/Uninstaller`), drag `Assets.xcassets` into the project navigator and Xcode will pick up the AppIcon set, including the Dark and Tinted variants, automatically.

Note on appearances: Xcode applies Dark and Tinted icon variants to iOS/iPadOS targets. On macOS Tahoe (26) and later, appearance-aware Mac icons use Apple's Icon Composer `.icon` format instead; the three 1024 px PNGs in `Icon/source/` are ready to drop into its Light, Dark and Tinted layers.

## Disclaimer

Uninstaller deletes files, and it can delete a lot of them. Always review the list before clicking Remove, and prefer **Move to Trash** over **Delete Permanently**. The software is provided as is, with no warranty (see [LICENSE](LICENSE)).

## Contributing

Issues and pull requests are welcome. If you find an app that leaves something behind, or a match that's too broad, open an issue with the app name and what was missed or wrongly listed.

## License

[MIT](LICENSE)
