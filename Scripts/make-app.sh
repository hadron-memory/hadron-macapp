#!/usr/bin/env bash
#
# Assemble a double-clickable HadronMenuBar.app from the SPM executable.
#
# Usage:
#   Scripts/make-app.sh                 # release build, ad-hoc signed
#   SIGN_IDENTITY="Developer ID Application: …" Scripts/make-app.sh
#   OPEN=1 Scripts/make-app.sh          # also launch the app when done
#
# Output: dist/HadronMenuBar.app
#
# To distribute outside your machine you still need to sign with a Developer ID
# identity (SIGN_IDENTITY) and notarize the result — see the notes at the end.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="HadronMenuBar"
DISPLAY_NAME="Hadron for Mac"
BUNDLE_ID="com.hadron.macapp"
URL_SCHEME="com.hadron.macapp"
SHORT_VERSION="${SHORT_VERSION:-0.1.0}"
BUILD_VERSION="${BUILD_VERSION:-1}"
MIN_MACOS="14.0"

DIST="dist"
APP="${DIST}/${APP_NAME}.app"
CONTENTS="${APP}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RES_DIR="${CONTENTS}/Resources"

echo "==> Building release binary"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
  echo "error: built binary not found at ${BIN_PATH}" >&2
  exit 1
fi

echo "==> Assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${MACOS_DIR}" "${RES_DIR}"
cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"

# Copy the SwiftPM resource bundle (menu-bar and header logos) into Resources so
# Bundle.module resolves it at runtime. It must live under Contents/Resources —
# a nested bundle in Contents/MacOS breaks codesign's bundle-format check.
BIN_DIR="$(dirname "${BIN_PATH}")"
for bundle in "${BIN_DIR}"/*.bundle; do
  [[ -e "${bundle}" ]] || continue
  cp -R "${bundle}" "${RES_DIR}/"
done

# Build the app icon (AppIcon.icns) from the 1024px source logo.
ICON_SRC="Scripts/AppIcon/AppIcon-1024.png"
if [[ -f "${ICON_SRC}" ]]; then
  echo "==> Building AppIcon.icns"
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "${ICONSET}"
  for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
              "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
              "512 512x512" "1024 512x512@2x"; do
    px="${spec%% *}"; name="${spec##* }"
    sips -z "${px}" "${px}" "${ICON_SRC}" --out "${ICONSET}/icon_${name}.png" >/dev/null
  done
  iconutil -c icns "${ICONSET}" -o "${RES_DIR}/AppIcon.icns"
  rm -rf "$(dirname "${ICONSET}")"
else
  echo "warning: ${ICON_SRC} not found; app will use the generic icon" >&2
fi

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Hadron</string>
    <key>CFBundleDisplayName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${SHORT_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <!-- Menu-bar-only: no Dock icon, no app-switcher entry. -->
    <key>LSUIElement</key>
    <true/>
    <!-- Register the OAuth callback scheme (hygiene; ASWebAuthenticationSession
         intercepts it internally, so it is not strictly required). -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>${BUNDLE_ID}</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>${URL_SCHEME}</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# PkgInfo is optional but conventional.
printf 'APPL????' > "${CONTENTS}/PkgInfo"

echo "==> Code signing"
IDENTITY="${SIGN_IDENTITY:--}"   # default: ad-hoc ("-")
codesign --force --deep --options runtime --sign "${IDENTITY}" "${APP}"
codesign --verify --verbose "${APP}" || true

echo "==> Done: ${APP}"
if [[ "${OPEN:-0}" == "1" ]]; then
  echo "==> Launching"
  open "${APP}"
fi

cat <<'NOTE'

Next steps for distribution (outside your own machine):
  1. Re-run with a Developer ID identity:
       SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" Scripts/make-app.sh
  2. Notarize the app:
       ditto -c -k --keepParent dist/HadronMenuBar.app dist/HadronMenuBar.zip
       xcrun notarytool submit dist/HadronMenuBar.zip --keychain-profile "AC_PROFILE" --wait
       xcrun stapler staple dist/HadronMenuBar.app
NOTE
