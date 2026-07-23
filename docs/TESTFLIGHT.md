# TestFlight from Linux (via a macOS CI runner)

You develop on Linux with xtool, but TestFlight needs a **distribution-signed build uploaded to
App Store Connect** — which only Apple's tooling does. The pipeline in
`.github/workflows/testflight.yml` runs that part on a **GitHub Actions `macos-26` runner** (it ships
Xcode 26 / the iOS 26 SDK the app targets), so you still don't need to own a Mac. It:

1. `xtool dev generate-xcode-project` → an Xcode project,
2. `xcodebuild archive` + `-exportArchive` with **automatic ("cloud") signing**,
3. `xcrun altool --upload-app` → TestFlight.

Signing is driven entirely by an **App Store Connect API key** with `-allowProvisioningUpdates`, so
Xcode creates and manages the distribution certificate and the two provisioning profiles for you —
no `.p12`/`.mobileprovision` to build by hand.

## One-time setup (all in the browser)

1. **Apple Developer Program** membership (you have this now). ✓
2. **App Store Connect API key** — App Store Connect → *Users and Access* → *Integrations* →
   *App Store Connect API* → **+**. Give it the **Admin** role — cloud-managed distribution
   signing needs it; App Manager gets a "Cloud signing permission error". Note the **Key ID**
   and **Issuer ID**, and download the `.p8` **once** (you can't re-download it).
3. **Create the app record** — App Store Connect → *Apps* → **+ New App**, platform iOS, bundle ID
   `org.syslinx.rhizome`, pick a name + primary language + SKU. The build won't appear under
   TestFlight until this record exists.
4. **App review info for TestFlight** — because sign-in is invite-only, add the demo account under
   the app's *TestFlight → Test Information* (or App Review notes):
   - Server: `https://rhizome.syslinx.org` · User: `appreview` · Password: `Review-Rhizome-2026`

You do **not** need to pre-create the App IDs or any certificate/profile — cloud signing registers
`org.syslinx.rhizome` and `org.syslinx.rhizome.Share` and issues the distribution assets on the
first run.

## The four repo secrets

Repo → *Settings → Secrets and variables → Actions* → **New repository secret**:

| Secret | What it is |
|---|---|
| `APPLE_TEAM_ID` | Your 10-character Team ID (developer.apple.com → *Membership*). |
| `ASC_KEY_ID` | The API **Key ID** from step 2 (Admin role). |
| `ASC_ISSUER_ID` | The API **Issuer ID** from step 2. |
| `ASC_KEY_P8_BASE64` | The `.p8` file, base64-encoded: `base64 -w0 AuthKey_XXXXXXXXXX.p8` |

## Persistent signing certificate (recommended — avoids the cert-limit problem)

With pure cloud signing, every ephemeral runner lets Xcode mint a **new** certificate; the private
key is thrown away with the runner but the cert stays in your account and counts against Apple's
limit (max 2–3 Apple Distribution certs). After enough builds you hit *"maximum number of
certificates"* and every build fails. The fix: create **one** distribution certificate, hand it to
CI as a secret, and the workflow imports it so signing reuses it forever. No Mac needed — do it all
on Linux with `openssl`.

1. **Make a private key + CSR:**
   ```sh
   openssl genrsa -out dist.key 2048
   openssl req -new -key dist.key -out dist.csr -subj "/CN=Rhizome Distribution/emailAddress=you@example.org/C=DE"
   ```
2. **Get the certificate:** developer.apple.com → *Certificates* → **+** → **Apple Distribution** →
   upload `dist.csr` → download `distribution.cer`.
3. **Bundle key + cert into a `.p12`** (choose any export password):
   ```sh
   openssl x509 -inform DER -in distribution.cer -out dist.pem
   openssl pkcs12 -export -inkey dist.key -in dist.pem -out dist.p12 -passout pass:CHOOSE_A_PASSWORD
   base64 -w0 dist.p12          # → the APPLE_DIST_CERT_P12_BASE64 secret
   ```
4. **Do the same for an *Apple Development* certificate.** xtool signs the *archive* for
   Development (the export re-signs for Distribution), so the CI needs a persistent dev cert too —
   otherwise each runner mints a development cert and you hit the limit again. Repeat steps 1–3 but
   pick **Apple Development** in step 2 (`dev.key` / `dev.csr` / `development.cer` / `dev.p12`).
5. **Add the secrets:**

| Secret | What it is |
|---|---|
| `APPLE_DIST_CERT_P12_BASE64` | The Distribution `dist.p12`, base64-encoded. |
| `APPLE_DIST_CERT_PASSWORD` | The Distribution `.p12` export password. |
| `APPLE_DEV_CERT_P12_BASE64` | The Development `dev.p12`, base64-encoded. |
| `APPLE_DEV_CERT_PASSWORD` | The Development `.p12` export password. |

Keep the `.key` / `.p12` files **safe and out of git** — they are your signing identities. Certs
are valid ~1 year; regenerate the same way when they expire. If the Distribution secret is absent
the workflow silently falls back to cloud signing.

## Running it

```
git tag v1.0.0
git push --tags
```

or run it from the **Actions** tab (*workflow_dispatch*), where you can set the marketing version.
The **build number** is the GitHub run number, so every run is unique (App Store Connect rejects
duplicate build numbers). The build appears under App Store Connect → *TestFlight* a few minutes
after upload (it goes through Apple "processing" first). Add testers there once it lands.

## Caveats (first run may need a tweak)

- **Cloud signing on CI:** the first archive asks Apple to create a distribution certificate + the
  two profiles. If it errors that the API key can't manage signing, confirm the key's role is
  **App Manager** (or Admin).
- **Scheme name:** the workflow discovers the `.xcodeproj` and scheme automatically (preferring one
  named `Rhizome`). If `xtool dev generate-xcode-project` names things differently, adjust the
  *Discover project & scheme* step.
- **Export compliance:** `Info.plist` sets `ITSAppUsesNonExemptEncryption=false` (the app only uses
  HTTPS), so App Store Connect won't prompt per build.
- **Share extension:** it's bundled and signed automatically alongside the app; no extra secret.
- I can't run this from Linux, so budget one iteration if a runner detail differs — the failing step
  and its log make it obvious.

## Fallback: manual signing

If cloud signing is blocked for your account, the alternative is to create an *Apple Distribution*
certificate + two *App Store* provisioning profiles by hand and switch the workflow to
`CODE_SIGN_STYLE=Manual`. The API-key route above avoids all of that, so try it first.
