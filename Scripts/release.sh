#!/usr/bin/env bash
#
# Cut a notarized, distributable release of Hadron for Mac.
#
# Pipeline: build → sign (Developer ID + hardened runtime) → notarize the app
# → staple → package a DMG → sign + notarize + staple the DMG → refresh the
# Homebrew cask → (optionally) publish a GitHub Release.
#
# Prerequisites (one-time — see README "Cut a notarized release"):
#   1. A "Developer ID Application" certificate in your Keychain.
#   2. A stored notarytool credential profile (default name: hadron-notary):
#        xcrun notarytool store-credentials "hadron-notary" \
#          --apple-id "you@example.com" --team-id V2NXQ22BM9 \
#          --password "<app-specific-password>"
#
# Usage:
#   Scripts/release.sh 0.1.0            # build + notarize locally
#   PUBLISH=1 Scripts/release.sh 0.1.0  # also create the GitHub Release
#
# Overrides: SIGN_IDENTITY, NOTARY_PROFILE, TEAM_ID.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="HadronMenuBar"
DISPLAY_NAME="Hadron for Mac"
TEAM_ID="${TEAM_ID:-V2NXQ22BM9}"
NOTARY_PROFILE="${NOTARY_PROFILE:-hadron-notary}"
DIST="dist"
CASK="packaging/homebrew/hadron-menu-bar.rb"

VERSION="${1:-${VERSION:-}}"
if [[ -z "${VERSION}" ]]; then
  VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
fi
if [[ -z "${VERSION}" ]]; then
  echo "usage: Scripts/release.sh <version>   e.g. Scripts/release.sh 0.1.0" >&2
  exit 1
fi
VERSION="${VERSION#v}"

# 1. Resolve the Developer ID Application signing identity.
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "${IDENTITY}" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | grep "${TEAM_ID}" \
    | head -1 | grep -oE '"[^"]+"' | tr -d '"' || true)"
fi
if [[ -z "${IDENTITY}" ]]; then
  cat >&2 <<EOF
error: no "Developer ID Application" identity for team ${TEAM_ID} in your Keychain.
       Create one in Xcode (Settings > Accounts > Manage Certificates >
       + > Developer ID Application), or via the developer portal, then
       verify with:  security find-identity -v -p codesigning
EOF
  exit 1
fi
echo "==> Version:  ${VERSION}"
echo "==> Identity: ${IDENTITY}"

# 2. Build + sign the .app (hardened runtime) via the bundling script.
SIGN_IDENTITY="${IDENTITY}" SHORT_VERSION="${VERSION}" Scripts/make-app.sh
APP="${DIST}/${APP_NAME}.app"

# 3. Notarize the app, then staple the ticket into the bundle so it passes
#    Gatekeeper even when copied out of the DMG.
echo "==> Notarizing the app (this can take a few minutes)"
APP_ZIP="${DIST}/${APP_NAME}-app.zip"
ditto -c -k --keepParent "${APP}" "${APP_ZIP}"
xcrun notarytool submit "${APP_ZIP}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${APP}"
rm -f "${APP_ZIP}"

# 4. Package a DMG (app + drag-to-Applications shortcut) from the stapled app.
echo "==> Building DMG"
DMG="${DIST}/${APP_NAME}-${VERSION}.dmg"
STAGE="$(mktemp -d)"
cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"
rm -f "${DMG}"
hdiutil create -volname "${DISPLAY_NAME}" -srcfolder "${STAGE}" \
  -ov -format UDZO "${DMG}" >/dev/null
rm -rf "${STAGE}"

# 5. Sign, notarize, and staple the DMG itself so the download is clean too.
echo "==> Signing and notarizing the DMG"
codesign --force --sign "${IDENTITY}" "${DMG}"
xcrun notarytool submit "${DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${DMG}"

SHA="$(shasum -a 256 "${DMG}" | awk '{print $1}')"
echo "==> Built ${DMG}"
echo "    sha256: ${SHA}"

# 6. Refresh the Homebrew cask with this version + checksum.
if [[ -f "${CASK}" ]]; then
  /usr/bin/sed -i '' -E "s/^  version \".*\"/  version \"${VERSION}\"/" "${CASK}"
  /usr/bin/sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"${SHA}\"/" "${CASK}"
  echo "==> Updated ${CASK} (copy it into your Homebrew tap repo and commit)"
fi

# 7. Optionally publish the GitHub Release.
if [[ "${PUBLISH:-0}" == "1" ]]; then
  echo "==> Publishing GitHub release v${VERSION}"
  gh release create "v${VERSION}" "${DMG}" \
    --title "Hadron for Mac ${VERSION}" \
    --notes "Notarized build. Download the DMG and drag HadronMenuBar.app to Applications, or \`brew install --cask hadron-menu-bar\` once the cask is published."
else
  echo "==> Skipped GitHub release (set PUBLISH=1 to create it)."
fi

echo "==> Done."
