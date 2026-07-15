# Rhizome iOS

A native iPhone shell for [Rhizome](https://rhizome.syslinx.org), built with
**SwiftUI** and packaged with [**xtool**](https://github.com/xtool-org/xtool) —
an Xcode-free, SwiftPM-based toolchain that builds and deploys iOS apps from
Linux, Windows or macOS.

## What it is (v1)

A thin native wrapper around the existing Rhizome PWA: a full-screen `WKWebView`
pointed at your instance, with

- a **persistent data store** — the login session and the web app's IndexedDB
  offline cache survive relaunches, so the app opens straight into your outline
  (and works offline, since the PWA already cold-boots from its cache);
- **pull-to-refresh** and back/forward swipe gestures;
- **external links** (share cards, references to other sites) open in Safari
  instead of trapping you inside the app.

Point it at a different server by editing `Config.serverURL` in
`Sources/Rhizome/Config.swift`.

## Prerequisites

- A Swift 6.3 toolchain (`swift --version`).
- xtool installed — see xtool's *Installation* guide for
  [Linux](https://github.com/xtool-org/xtool/blob/main/Documentation/xtool.docc/Installation-Linux.md)
  or [macOS](https://github.com/xtool-org/xtool/blob/main/Documentation/xtool.docc/Installation-macOS.md).
- An Apple ID for signing (xtool handles the free 7-day personal-team signing;
  a paid Apple Developer account gives a 1-year profile and lets you ship via
  TestFlight / the App Store).
- **Xcode 26 `.xip`** downloaded from
  [Apple](https://developer.apple.com/download/all/?q=Xcode) — xtool extracts it
  to generate the iOS Swift SDK. This is the one piece Apple gates behind an
  Apple ID; it can't be scripted.

## Environment already set up on this Linux (Arch) box

The toolchain is installed and on `PATH` (in fish, via `~/.config/fish/conf.d/swift.fish`):

- **xtool 1.17** — AppImage at `~/.local/bin/xtool`.
- **Swift 6.3.3** — installed with [swiftly](https://www.swift.org/swiftly/) in
  user space (`swiftly install 6.3.3`, initialised with `--platform ubuntu24.04`
  because Arch isn't auto-detected).
- **libncurses shim** — Arch ships `libncursesw.so.6` but the Swift Ubuntu build
  wants `libncurses.so.6`, so there's a symlink at
  `…/swiftly/toolchains/6.3.3/usr/lib/swift/linux/libncurses.so.6 → /usr/lib/libncursesw.so.6`
  (on the toolchain RUNPATH, so no global `LD_LIBRARY_PATH` is needed).
  ⚠️ If you reinstall/upgrade the 6.3.3 toolchain, recreate this symlink.

**Remaining, Apple-gated steps (need your Apple ID):** see *Build & run* below.
To deploy onto a physical iPhone from Linux you also need `usbmuxd`
(`sudo pacman -S usbmuxd`) and the phone plugged in + trusted — Linux has no iOS
Simulator, so a real device (or a Mac) is required to actually run it.

## Build & run

```sh
xtool setup          # one-time: Apple ID auth + build the iOS SDK from your Xcode.xip
cd ~/dev/rhizome-app
xtool dev            # build, install and launch on a connected iPhone
xtool build          # just produce a .ipa
```

The project layout is the standard xtool template:

```
Package.swift                     SwiftPM manifest (one library product = the app)
xtool.yml                         xtool manifest (bundle ID: org.syslinx.rhizome)
.sourcekit-lsp/config.json        LSP → iOS SDK, for editor support
Sources/Rhizome/
  RhizomeApp.swift                @main App entry point
  ContentView.swift               root view (hosts the web view + loading state)
  WebView.swift                   UIViewRepresentable around WKWebView (iOS only)
  Config.swift                    server URL + theme
```

## Roadmap

- **App icon & launch screen** (reuse the sprout mark from the web favicon).
- **Native quick-capture**: a Share Extension + a home-screen widget / Shortcut
  that POST to `/api/capture` with a write-scoped `rzk_` API key — the native
  equivalent of the `r` command.
- **Safe-area polish** for `viewport-fit=cover` (pass the notch/home-indicator
  insets into the web view so the CSS `env(safe-area-*)` lines up).
- **Push notifications** (needs a paid Apple Developer account).
- Evaluate a fuller native client (offline op queue in Swift) if the web shell
  proves limiting.
