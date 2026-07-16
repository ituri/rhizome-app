# TestFlight from Linux (via a macOS CI runner)

You develop on Linux with xtool, but TestFlight needs a **distribution-signed build uploaded to
App Store Connect** — which only Apple's tooling does. The pipeline in
`.github/workflows/testflight.yml` runs that part on a **GitHub Actions macOS runner**, so you
still don't need to own a Mac. It:

1. `xtool dev generate-xcode-project` → an Xcode project,
2. `xcodebuild archive` + `-exportArchive` (App Store, manual signing),
3. `xcrun altool --upload-app` → TestFlight.

## Do I have to register anything first?

**No Mac app is needed — it's all in the browser.** But there is one-time Apple setup:

1. **Apple Developer Program** membership (99 €/$ a year). TestFlight is not available on the free tier.
2. **Register the App IDs** at [developer.apple.com → Certificates, IDs & Profiles → Identifiers]:
   - `org.syslinx.rhizome` (the app)
   - `org.syslinx.rhizome.Share` (the share extension)
   Give them the capabilities the app uses (e.g. none special beyond default; the extension is a share extension).
3. **Create the app record** in [App Store Connect → My Apps → +], pick bundle ID `org.syslinx.rhizome`.
   (You can add TestFlight testers only after the first build is uploaded.)

Everything below is generated in the browser or with a couple of CLI commands — you never open Xcode.

## The signing assets → GitHub secrets

Create each once, then add it as a **repository secret** (Settings → Secrets and variables → Actions).
Base64-encode files with `base64 -w0 FILE` on Linux (or `base64 -i FILE | pbcopy` on macOS).

| Secret | What it is / how to get it |
|---|---|
| `DIST_CERT_P12_BASE64` | An **Apple Distribution** certificate **with its private key**, exported as `.p12`. Create the cert in the portal (Certificates → +, "Apple Distribution"); you upload a CSR. On Linux you can make the CSR + key with `openssl req -new -newkey rsa:2048 -nodes -keyout dist.key -out dist.csr`, then combine the downloaded `.cer` with the key into a `.p12` via `openssl`. Base64 the `.p12`. |
| `DIST_CERT_PASSWORD` | The password you set on that `.p12`. |
| `APP_PROVISION_PROFILE_BASE64` | An **App Store** provisioning profile for `org.syslinx.rhizome` (portal → Profiles → +, "App Store"). Download the `.mobileprovision`, base64 it. |
| `EXT_PROVISION_PROFILE_BASE64` | Same, but for `org.syslinx.rhizome.Share`. |
| `APP_PROFILE_NAME` | The **exact name** of the app profile (as shown in the portal). |
| `EXT_PROFILE_NAME` | The exact name of the extension profile. |
| `APPLE_TEAM_ID` | Your 10-character Team ID (portal → Membership). |
| `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8_BASE64` | An **App Store Connect API key** (App Store Connect → Users and Access → Integrations → App Store Connect API → +, role **App Manager**). Note the Key ID and Issuer ID; download the `.p8` **once** and base64 it. This is what uploads the build — no Apple-ID password needed. |

## Running it

```
git tag v1.0.0
git push --tags
```

or trigger it manually from the Actions tab. The build appears in App Store Connect → TestFlight a
few minutes after the upload finishes (it goes through Apple "processing" first).

## Caveats (read before the first run)

- **Xcode 26 / iOS 26 SDK:** `Package.swift` targets `.iOS("26.0")`. The archive step needs an Xcode
  that ships the iOS 26 SDK. If the GitHub runner image doesn't have Xcode 26 yet, either pin a
  runner image that does, or temporarily lower the iOS platform in `Package.swift` for the CI build.
- **First run will likely need 1–2 tweaks** — I can't test this from Linux. The most common spots:
  the generated project's **scheme/name** (the workflow assumes `Rhizome.xcodeproj` / scheme
  `Rhizome` — adjust `PROJECT`/`SCHEME` if `xtool dev generate-xcode-project` names them
  differently), and the **manual-signing settings** if the archive complains it can't find a matching
  profile (make sure the two profile names + bundle IDs line up).
- **The share extension** must have its own App ID + App Store profile (the `EXT_*` secrets), or the
  export fails to sign it.
- **Encryption declaration:** App Store Connect asks about export compliance on the first build; set
  `ITSAppUsesNonExemptEncryption=false` in `Info.plist` (the app only uses HTTPS) to skip the prompt.
