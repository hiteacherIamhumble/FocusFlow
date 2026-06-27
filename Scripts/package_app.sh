#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="FocusFlow"
FINAL_APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/focusflow_app.XXXXXX")"
trap 'rm -rf "$STAGING_ROOT"' EXIT
APP_DIR="$STAGING_ROOT/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUILD_DIR="$ROOT_DIR/.build/release"
CODESIGN_IDENTITY="${FOCUSFLOW_CODESIGN_IDENTITY:--}"
ENABLE_RUNTIME="${FOCUSFLOW_CODESIGN_RUNTIME:-0}"

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

sign_and_verify_app() {
  local target="$1"
  command -v codesign >/dev/null 2>&1 || return 0

  local codesign_args=(--force --deep --sign "$CODESIGN_IDENTITY")
  if [[ "$ENABLE_RUNTIME" == "1" ]]; then
    codesign_args+=(--options runtime)
  fi
  codesign_args+=(--entitlements "$ROOT_DIR/Resources/FocusFlow.entitlements")

  for _ in 1 2 3; do
    clean_extended_attributes "$target"
    codesign "${codesign_args[@]}" "$target"
    clean_extended_attributes "$target"
    if codesign --verify --deep --strict "$target" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done

  codesign --verify --deep --strict --verbose=2 "$target"
}

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$FINAL_APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/FocusFlow.entitlements" "$RESOURCES_DIR/FocusFlow.entitlements"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
chmod +x "$MACOS_DIR/$APP_NAME"

clean_extended_attributes "$APP_DIR"
sign_and_verify_app "$APP_DIR"

mkdir -p "$ROOT_DIR/dist"
if command -v ditto >/dev/null 2>&1; then
  ditto "$APP_DIR" "$FINAL_APP_DIR"
else
  cp -R "$APP_DIR" "$FINAL_APP_DIR"
fi

clean_extended_attributes "$FINAL_APP_DIR"
sign_and_verify_app "$FINAL_APP_DIR"

echo "$FINAL_APP_DIR"
