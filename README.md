# Rhizome iOS

A **fully native** iPhone client for [Rhizome](https://github.com/ituri/rhizome),
a self-hosted, Roam-flavoured outliner. Built with **SwiftUI** and packaged with
[**xtool**](https://github.com/xtool-org/xtool) — an Xcode-free, SwiftPM-based
toolchain that builds and signs iOS apps from Linux, Windows or macOS.

It talks to the Rhizome HTTP API directly — no web view, no embedded browser.
Point it at your own Rhizome instance (the server URL is editable on the sign-in
screen) and sign in with your account.

> **Heads up:** this is a personal project, not an App Store release. You need
> your own Rhizome server to sign in to, and you build the app yourself. It
> targets **iOS 26** and runs on iPhone only.

## Features

- **Native sign-in** — server URL + username/password → a Rhizome session cookie,
  persisted so relaunches resume silently; **offline resume** from the last
  cached session and document.
- **Four tabs + Settings** — *Journal* (daily notes grouped by day), *Pages* (all
  pages with fuzzy search, last-edited times, rename-on-swipe, delete), *Assets*
  (uploaded-file manager), *Search* (server-side full-text).
- **Live sync** — subscribes to the graph's server-sent event stream and folds in
  remote edits as they happen (except on the line you're actively editing).
- **Rich inline editor** — Markdown (**bold**, *italic*, `code`, links) plus
  Rhizome `[[page links]]`, `#tags` and `((block references))`, colour
  **highlights**, checkbox **todos**, and inline **images**. Return splits into a
  sibling, the keyboard bar indents/outdents, swipe to complete or delete.
  Edits post ops to `/api/g/:id/ops` optimistically.
- **Images & attachments** — upload from the camera or photo library, browse and
  rename/delete everything in the Asset manager, clean up orphaned files, and
  re-insert an existing upload into a note.
- **Page history** — view past versions of a page, see a diff, and restore.
- **Location** — attach your current coordinates to a note; addresses are
  reverse-geocoded and shown on an OpenStreetMap map.
- **Appearance & security** — light/dark theme, accent colour, font size and line
  spacing, image-downscale percentage, Face ID / Touch ID lock, haptics, change
  password, delete account. The *timestamp quick-capture* preference syncs across
  your devices (web ⇄ iOS).
- **Share Extension** — quick-capture text or a link from any app into today's
  Inbox (see below).
- **Privacy-friendly** — no analytics or tracking SDKs; your notes only ever go to
  the server you sign in to. Ships a `PrivacyInfo.xcprivacy` manifest.

## Requirements

- **An iPhone on iOS 26** (there's no iOS Simulator on Linux/Windows, so a real
  device — or a Mac — is needed to actually run it). The app is iPhone-only.
- **A Swift 6 toolchain** (`swift --version`). On Linux, [swiftly](https://www.swift.org/swiftly/)
  is the easiest way to install one in user space.
- **xtool** — follow its install guide for
  [Linux](https://github.com/xtool-org/xtool/blob/main/Documentation/xtool.docc/Installation-Linux.md),
  [Windows](https://github.com/xtool-org/xtool/blob/main/Documentation/xtool.docc/Installation-Windows.md)
  or [macOS](https://github.com/xtool-org/xtool/blob/main/Documentation/xtool.docc/Installation-macOS.md).
- **Xcode 26 `.xip`** from [Apple](https://developer.apple.com/download/all/?q=Xcode).
  xtool extracts it once to build the iOS SDK — this is the only piece gated
  behind an Apple ID and can't be scripted. (On macOS with Xcode installed, xtool
  can use it directly.)
- **An Apple ID for signing.** A free Apple ID gives 7-day personal-team signing;
  a paid Apple Developer account gives a 1-year profile and lets you ship via
  TestFlight / the App Store.
- **To deploy from Linux onto a device:** `usbmuxd` plus an iPhone that's plugged
  in and trusted.

## Build & run

```sh
xtool setup          # one-time: Apple ID auth + build the iOS SDK from your Xcode.xip
cd rhizome-app
xtool dev            # build, install and launch on a connected iPhone
xtool build          # just produce a .ipa
```

For shipping to TestFlight, see [`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md).

## Configure it for your own instance

1. **Server URL** — set it once on the sign-in screen, or change the default in
   `Sources/RhizomeKit/Config.swift` (`Config.serverURL`).
2. **Bundle ID** — change `bundleID` in `xtool.yml` (and the extension's) from
   `org.syslinx.rhizome` to something under your own domain.
3. **Share Extension token** — see below.

### Linux notes

- xtool needs a working Swift toolchain on `PATH`; swiftly-installed toolchains
  work well. If your distro isn't auto-detected, install with an explicit
  `--platform` (e.g. `swiftly install <version> --platform ubuntu24.04`).
- **Arch:** the Swift Ubuntu build looks for `libncurses.so.6`, but Arch ships
  `libncursesw.so.6`. Symlink it into the toolchain's `usr/lib/swift/linux/`
  directory if the toolchain fails to load `libncurses`.

## Native quick-capture (Share Extension)

Share text or a link from any app → **Rhizome Inbox** and it lands under today's
journal, time-stamped like the `r` shell command. To enable it, create a
**write-scoped `rzk_…` API key** in the web app (*Account → API keys*) and put it
in `Sources/RhizomeKit/Secrets.swift`:

```swift
static let captureToken = "rzk_…"
```

`Secrets.swift` is committed empty; keep your key out of git locally with:

```sh
git update-index --skip-worktree Sources/RhizomeKit/Secrets.swift
```

(undo with `--no-skip-worktree`). Until a key is set, the extension's *Post*
button stays disabled. Rebuild after editing.

## Project layout

```
Package.swift                     SwiftPM manifest (app + Share Extension)
xtool.yml                         xtool manifest (bundle ID, icon, extension)
Info.plist                        app Info.plist (permission strings, iPhone-only)
Icon.png                          1024×1024 app icon
docs/TESTFLIGHT.md                guide for shipping to TestFlight

Sources/RhizomeKit/               shared by the app + the Share Extension
  API.swift                       async HTTP client + wire models
  Config.swift                    default server URL, accent, capture token
  Capture.swift                   POSTs a line to /api/capture (like `r`)
  Secrets.swift                   the capture API key (git-skipped)
  Ops.swift  RichText.swift  Journal.swift  Highlight.swift  Accent.swift

Sources/Rhizome/                  the app
  RhizomeApp.swift                @main entry point
  AppModel.swift                  @Observable state: session, sync, ops, settings
  ContentView.swift               tab router + Face ID lock overlay
  SignInView.swift                native sign-in
  JournalView / Pages / AssetsView / SearchView / Settings
  OutlineView.swift  RichEditor.swift  Toolbars.swift   outline + editing
  PageHistory.swift  References.swift  Navigation.swift
  GeoMap.swift  Location.swift    coordinates + OpenStreetMap
  Attachments.swift  Haptics.swift  Fonts.swift  Theme.swift  LocalStore.swift

Sources/RhizomeShare/
  ShareViewController.swift       compose sheet → quick-capture into the Inbox
```

## Roadmap

- Move the capture token out of source into a Settings screen, shared to the
  extension via an App Group / Keychain (App Groups on device need a paid team).
- Home-screen widget / App Shortcut for one-tap capture.
- Push notifications (needs a paid Apple Developer account).
- An iPad-optimised layout (the app is iPhone-only for now).
