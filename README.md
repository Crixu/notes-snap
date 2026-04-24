# NotesSnap

A tiny macOS menu bar app: click the camera icon, snap a photo of your notes, it lands on your clipboard — ready to paste into Slack, Notes, Messages, anywhere.

No dock icon. No window clutter. Remembers which camera you used last time.

## Install

Grab the latest build from [Releases](https://github.com/Crixu/notes-snap/releases):

- **`NotesSnap-1.0.dmg`** — drag into `Applications`
- **`NotesSnap-1.0.zip`** — unzip and move the `.app` wherever you like

The binary is **universal** (Apple Silicon + Intel) and requires macOS 12 or newer.

### First launch

Builds are **ad-hoc signed, not notarized**, so Gatekeeper will block the first launch. Either:

- **Right-click** `NotesSnap.app` → **Open** → **Open** in the dialog, or
- System Settings → **Privacy & Security** → scroll down → **Open Anyway**

You'll only need to do this once. macOS will also ask for camera permission the first time you click the menu bar icon.

### Launch at login (optional)

System Settings → **General** → **Login Items** → drag `NotesSnap.app` into the list.

## Usage

- **Left-click** the camera icon in the menu bar → preview window opens
- Pick a camera from the dropdown (built-in, Continuity, external webcams)
- Press **Return** or click **Capture** → image is copied to the clipboard, window closes
- **Right-click** the icon → menu with Capture / Quit

## Build from source

```sh
git clone https://github.com/Crixu/notes-snap.git
cd notes-snap
./build.sh
open NotesSnap.app
```

Requires the Xcode Command Line Tools (`xcode-select --install`). No Xcode project, no dependencies — just `swiftc`, Cocoa, and AVFoundation.

`build.sh` produces:

- `NotesSnap.app` — the universal, ad-hoc signed bundle
- `dist/NotesSnap-<version>.zip` — zipped bundle (preserves signing via `ditto`)
- `dist/NotesSnap-<version>.dmg` — drag-to-Applications installer

## Project layout

```
main.swift     # whole app: menu bar item, camera window, capture + clipboard
Info.plist     # bundle metadata + NSCameraUsageDescription
build.sh       # compile → universal binary → ad-hoc sign → zip + dmg
```

## Notes

- Camera selection is persisted in `UserDefaults` under `NotesSnap.lastCameraUniqueID`.
- Photos are placed on `NSPasteboard.general` as `NSImage`, so any app that accepts pasted images will take them.
