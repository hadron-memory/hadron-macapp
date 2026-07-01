# Hadron for Mac

A native macOS **menu bar** app for the [Hadron](https://hadronmemory.com) platform.
Once signed in it lets you:

- **Memories** — browse the memories you can access (`myMemories`).
- **Tasks** — browse runnable **task nodes** (`nodes(isRunnable: true)`).
- **Find** — keyword-search the knowledge graph (`nodes(search:)`).

Each row has an **Open in portal** button that deep-links to
`hadronmemory.com/app/u/<urn>`.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 6 toolchain (ships with recent Xcode / Command Line Tools)

## Build & run

```sh
swift build
swift run HadronMenuBar
```

The app has **no Dock icon** — look for the 🧠 brain icon in the menu bar. Click it,
then **Sign in with Hadron**.

## How sign-in works

Full OAuth 2.1 authorization-code flow with PKCE against Hadron's Authorization Server
(`srv.hadronmemory.com`):

1. Discovery — `GET /.well-known/oauth-authorization-server`.
2. Dynamic client registration — `POST /oauth/register` (the `client_id` is cached in
   the Keychain so we don't re-register on every launch).
3. Consent — `GET /oauth/authorize` opens in an `ASWebAuthenticationSession`; you sign
   in via GitHub and approve access.
4. Token exchange — `POST /oauth/token` returns a long-lived `hdr_user_*` key.

The key is stored in the macOS **Keychain** and sent as `Authorization: Bearer <key>` on
the GraphQL endpoint. There is no token refresh (v1) — if the key is revoked, the app
drops back to the sign-in screen. **Sign Out** deletes the key from the Keychain.

## Project layout

```
Sources/HadronMenuBar/
  HadronMenuBarApp.swift   @main; MenuBarExtra scene; accessory activation policy
  HadronConfig.swift       endpoints, redirect URI, portal deep-link builder
  PKCE.swift               PKCE S256 pair
  KeychainStore.swift      Keychain get/set/delete
  OAuthService.swift       discovery → DCR → ASWebAuthenticationSession → token
  GraphQLModels.swift      Codable models + GraphQL envelope
  HadronClient.swift       typed GraphQL client (me / myMemories / taskNodes / findNodes)
  AppState.swift           observable state + auth lifecycle
  MenuContentView.swift    root popover, header/footer, signed-out view
  ContentTabs.swift        Memories / Tasks / Find tabs
  RowViews.swift           memory & node rows, badges, portal link
```

## Packaging into a double-clickable `.app`

`swift run` is fine for development. To produce a real `HadronMenuBar.app`:

```sh
Scripts/make-app.sh            # release build → dist/HadronMenuBar.app (ad-hoc signed)
OPEN=1 Scripts/make-app.sh     # also launch it when done
```

The script does a `-c release` build, assembles the bundle with an `Info.plist`
(`LSUIElement = true` for menu-bar-only, `CFBundleIdentifier = com.hadron.macapp`,
version keys, and the `com.hadron.macapp` URL scheme), and code-signs it. `open
dist/HadronMenuBar.app` launches it; the app appears in the menu bar with no Dock icon.

## Cut a notarized release (distribute without building)

`Scripts/release.sh` produces a **notarized, stapled DMG** anyone can download and open
with no Gatekeeper warnings, and refreshes the Homebrew cask. It wraps the whole
pipeline: build → sign (Developer ID + hardened runtime) → notarize the app → staple →
package a DMG → sign + notarize + staple the DMG.

### One-time prerequisites

Team ID: `V2NXQ22BM9`.

1. **Create a Developer ID Application certificate** (enrolling in the Apple Developer
   Program does *not* create one for you). In Xcode: **Settings → Accounts →** select your
   Apple ID **→ Manage Certificates → + → Developer ID Application**. This installs it in
   your login Keychain. Verify:

   ```sh
   security find-identity -v -p codesigning   # expect: Developer ID Application: … (V2NXQ22BM9)
   ```

2. **Store notarytool credentials** once (uses an [app-specific password](https://appleid.apple.com/)):

   ```sh
   xcrun notarytool store-credentials "hadron-notary" \
     --apple-id "you@example.com" --team-id V2NXQ22BM9 \
     --password "<app-specific-password>"
   ```

### Cut a release

```sh
Scripts/release.sh 0.1.0             # build + notarize → dist/HadronMenuBar-0.1.0.dmg
PUBLISH=1 Scripts/release.sh 0.1.0   # also create the GitHub Release with the DMG
```

The script prints the DMG's `sha256` and rewrites `packaging/homebrew/hadron-menu-bar.rb`
with the new version + checksum.

### Publish the Homebrew cask

After a release, copy the updated `packaging/homebrew/hadron-menu-bar.rb` into your tap
repo (e.g. `hadron-memory/homebrew-tap` under `Casks/`) and commit. Users then install
with:

```sh
brew install --cask hadron-memory/tap/hadron-menu-bar
```

### Local ad-hoc build (no account needed)

`Scripts/make-app.sh` alone produces an **ad-hoc-signed** `dist/HadronMenuBar.app` — fine
for running locally or handing to a trusted tester, but unsigned/unnotarized apps trip
Gatekeeper on other machines (right-click → **Open**, or
`xattr -dr com.apple.quarantine <app>`). Use `release.sh` for real distribution.
