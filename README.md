# Rhizome iOS

A **fully native** iPhone client for [Rhizome](https://rhizome.syslinx.org), built
with **SwiftUI** and packaged with [**xtool**](https://github.com/xtool-org/xtool) —
an Xcode-free, SwiftPM-based toolchain that builds and deploys iOS apps from
Linux, Windows or macOS.

## What it is

A native SwiftUI app that talks to the Rhizome HTTP API directly — no web view,
no embedded browser. Current state:

- **Native sign-in** (server URL + username/password → a Rhizome session cookie,
  persisted so relaunches resume silently).
- **Native outline view** — the graph is fetched from the API and rendered as an
  indented SwiftUI list with collapse/expand and done styling. Multi-graph
  switcher + reload + sign-out in the toolbar.
- A **Share Extension** for quick-capture into the Inbox (see below).

**In progress** (the tree renders read-only for now): inline text editing and
structural ops (enter / tab / move / delete → `/api/g/:id/ops`), live SSE sync,
and rich rendering of `[[links]]` / `#tags` / attributes. See the roadmap.

The server URL is set on the sign-in screen (defaults to `Config.serverURL`).

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

Project layout:

```
Package.swift                     SwiftPM manifest (app + Share Extension products)
xtool.yml                         xtool manifest (bundle ID, icon, extensions)
Icon.png                          1024×1024 app icon (rendered from the web sprout)
RhizomeShare-Info.plist           Share Extension Info.plist (share-services)
.sourcekit-lsp/config.json        LSP → iOS SDK, for editor support
Sources/RhizomeKit/               shared by the app + extension
  Config.swift                    default server URL, capture token, theme
  Capture.swift                   POSTs a line to /api/capture (like the `r` command)
  API.swift                       async HTTP client + wire models (login, me, doc)
Sources/Rhizome/                  the app
  RhizomeApp.swift                @main App entry point
  AppModel.swift                  @Observable state: session, graphs, active doc
  ContentView.swift               router: loading / sign-in / outline
  SignInView.swift                native sign-in form
  OutlineView.swift               native indented outline list
Sources/RhizomeShare/             the Share Extension
  ShareViewController.swift       compose sheet → quick-capture into the Inbox
```

## Native quick-capture (Share Extension)

Share text or a link from any app → **Rhizome Inbox** and it lands under today's
journal (time-stamped, exactly like the `r` shell command). To enable it, paste a
**write-scoped `rzk_…` API key** into `Config.captureToken`
(`Sources/RhizomeKit/Config.swift`) — create one in the web app under
*Account → API keys* — then rebuild. Until a key is set, the extension's *Post*
button stays disabled. (The key is compiled in for now; a Settings screen + a
shared App Group is the planned hardening — see the roadmap.)

## Roadmap

- **Editing** — inline text editing and structural ops (enter / tab+shift-tab /
  move / delete / toggle-done) posted to `/api/g/:id/ops`, with an on-device undo.
- **Live sync** — subscribe to `/api/g/:id/events` (SSE) so remote edits stream in.
- **Rich rendering** — `[[links]]`, `#tags`, `((block refs))`, attributes and
  Markdown styling in the native rows (tappable links / zoom).
- **Offline** — cache the doc + queue ops locally, replay on reconnect.
- **Move the capture token out of source** — a Settings screen that stores the
  key, shared to the extension via an App Group / Keychain (App Groups on device
  need a paid team).
- **Home-screen widget / Shortcut** for one-tap capture.
- **Push notifications** (needs a paid Apple Developer account).

*Done: native sign-in, native read-only outline, app icon, Share-Extension quick-capture.*

*Done: native SwiftUI web shell, app icon, Share-Extension quick-capture.*
