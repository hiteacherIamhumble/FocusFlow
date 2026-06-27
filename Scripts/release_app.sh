#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="FocusFlow"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
RELEASE_DIR="$ROOT_DIR/dist/release"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/focusflow_release.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

read_plist_value() {
  local key="$1"
  /usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST"
}

VERSION="${FOCUSFLOW_RELEASE_VERSION:-$(read_plist_value CFBundleShortVersionString)}"
BUILD_NUMBER="${FOCUSFLOW_RELEASE_BUILD:-$(read_plist_value CFBundleVersion)}"
DMG_PATH="$RELEASE_DIR/${APP_NAME}-${VERSION}-build-${BUILD_NUMBER}.dmg"
APP_STAGING="$STAGING_DIR/dmg-root"
APP_PATH=""

clean_extended_attributes() {
  local target="$1"
  if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$target" 2>/dev/null || true
    while IFS= read -r -d '' path; do
      xattr -c "$path" 2>/dev/null || true
      xattr -d 'com.apple.fileprovider.fpfs#P' "$path" 2>/dev/null || true
      xattr -d com.apple.FinderInfo "$path" 2>/dev/null || true
      xattr -d com.apple.ResourceFork "$path" 2>/dev/null || true
      xattr -d com.apple.provenance "$path" 2>/dev/null || true
    done < <(find "$target" -depth -print0)
    xattr -c "$target" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "$target" 2>/dev/null || true
    xattr -d com.apple.FinderInfo "$target" 2>/dev/null || true
    xattr -d com.apple.ResourceFork "$target" 2>/dev/null || true
    xattr -d com.apple.provenance "$target" 2>/dev/null || true
  fi
}

mkdir -p "$RELEASE_DIR" "$APP_STAGING"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" && -z "${FOCUSFLOW_CODESIGN_IDENTITY:-}" ]]; then
  export FOCUSFLOW_CODESIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"
  export FOCUSFLOW_CODESIGN_RUNTIME=1
fi

APP_PATH="$("$ROOT_DIR/Scripts/package_app.sh" | tail -1)"

clean_extended_attributes "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH" 2>/tmp/focusflow_spctl.log || {
  echo "Gatekeeper assessment did not accept this build yet. This is expected for ad-hoc local builds." >&2
  cat /tmp/focusflow_spctl.log >&2 || true
}

ditto "$APP_PATH" "$APP_STAGING/$APP_NAME.app"
ln -s /Applications "$APP_STAGING/Applications"
clean_extended_attributes "$APP_STAGING"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$APP_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

if [[ -n "${FOCUSFLOW_DMG_CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$FOCUSFLOW_DMG_CODESIGN_IDENTITY" "$DMG_PATH"
elif [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --sign "$DEVELOPER_ID_APPLICATION" "$DMG_PATH"
fi

hdiutil verify "$DMG_PATH" >/dev/null

if [[ "${FOCUSFLOW_NOTARIZE:-0}" == "1" ]]; then
  if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG_PATH" \
      --keychain-profile "$NOTARYTOOL_PROFILE" \
      --wait
  else
    : "${APPLE_ID:?Set APPLE_ID for notarization.}"
    : "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID for notarization.}"
    : "${APPLE_APP_SPECIFIC_PASSWORD:?Set APPLE_APP_SPECIFIC_PASSWORD for notarization.}"
    xcrun notarytool submit "$DMG_PATH" \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --wait
  fi
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

shasum -a 256 "$DMG_PATH" >"$DMG_PATH.sha256"
echo "$DMG_PATH"
