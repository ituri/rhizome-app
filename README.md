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
- **Quick capture** — the `+` button in the Journal drops a note straight into
  today's Inbox, time-stamped like the `r` shell command.
- **Share sheet** — a Share Extension registers *Rhizome Inbox* as a share target,
  so you can send text or a link from any app into today's Inbox (see
  [Share sheet](#share-sheet)).
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

1. **Server URL** — the sign-in screen is prefilled with `https://rhizome.syslinx.org`
   (editable). To default a build to your own instance, change the fallback in
   `AppModel.init` (`serverURLString = saved ?? "…"`).
2. **Bundle ID** — change `bundleID` in `xtool.yml` from `org.syslinx.rhizome` to
   something under your own domain.
3. **Share extension** (optional) — set an API key + server URL in `Secrets.swift`
   (see [Share sheet](#share-sheet)).

### Linux notes

- xtool needs a working Swift toolchain on `PATH`; swiftly-installed toolchains
  work well. If your distro isn't auto-detected, install with an explicit
  `--platform` (e.g. `swiftly install <version> --platform ubuntu24.04`).
- **Arch:** the Swift Ubuntu build looks for `libncurses.so.6`, but Arch ships
  `libncursesw.so.6`. Symlink it into the toolchain's `usr/lib/swift/linux/`
  directory if the toolchain fails to load `libncurses`.

## Share sheet

A Share Extension (*Rhizome Inbox*) lets you send text or a link from any app into
today's journal Inbox, time-stamped like the `r` shell command. It runs in its own
process and can't see the app's login, so it authenticates with a **write-scoped
`rzk_…` API key** against a fixed server. Create a key in the web app under
*Account → API keys*, then fill both fields in `Sources/RhizomeKit/Secrets.swift`:

```swift
static let captureToken = "rzk_…"
static let captureServerURL = "https://rhizome.example.org"
```

`Secrets.swift` is committed empty; keep your values out of git with:

```sh
git update-index --skip-worktree Sources/RhizomeKit/Secrets.swift
```

(undo with `--no-skip-worktree`). Until both are set, the share sheet stays
disabled. This works with free personal-team signing — no paid account needed.

## Project layout

```
Package.swift                     SwiftPM manifest (app + Share Extension)
xtool.yml                         xtool manifest (bundle ID, icon, extension)
Info.plist                        app Info.plist (permission strings, iPhone-only)
RhizomeShare-Info.plist           Share Extension Info.plist (share-services)
Icon.png                          1024×1024 app icon
docs/TESTFLIGHT.md                guide for shipping to TestFlight

Sources/RhizomeKit/               shared, UI-independent core
  API.swift                       async HTTP client + wire models
  Capture.swift                   POSTs a line to /api/capture (like `r`)
  Secrets.swift                   share-extension key + server (git-skipped)
  Config.swift                    colours + share-extension config accessors
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

- Home-screen widget / App Shortcut for one-tap capture.
- Push notifications (needs a paid Apple Developer account).
- An iPad-optimised layout (the app is iPhone-only for now).
