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

### Distributing outside your own machine

Ad-hoc signing is enough to run locally. To share it, sign with a Developer ID identity
and **notarize**:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" Scripts/make-app.sh
ditto -c -k --keepParent dist/HadronMenuBar.app dist/HadronMenuBar.zip
xcrun notarytool submit dist/HadronMenuBar.zip --keychain-profile "AC_PROFILE" --wait
xcrun stapler staple dist/HadronMenuBar.app
```

(An Xcode app target would also work, but the script keeps the plain-SPM workflow.)
