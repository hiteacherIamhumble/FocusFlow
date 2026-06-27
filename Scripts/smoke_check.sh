#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cd "$ROOT_DIR"

clean_extended_attributes() {
  local target="$1"
  command -v xattr >/dev/null 2>&1 || return 0
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
}

verify_app_strict() {
  local app_path="$1"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    clean_extended_attributes "$app_path"
    if codesign --verify --deep --strict "$app_path" >/dev/null 2>&1; then
      codesign --verify --deep --strict --verbose=2 "$app_path"
      return 0
    fi
    sleep 0.2
  done
  clean_extended_attributes "$app_path"
  codesign --verify --deep --strict --verbose=2 "$app_path"
}

swift test
Scripts/package_app.sh >/tmp/focusflow_package_path.txt
APP_PATH="$(cat /tmp/focusflow_package_path.txt | tail -1)"
verify_app_strict "$APP_PATH"
plutil -lint "$APP_PATH/Contents/Info.plist"
Scripts/release_app.sh >/tmp/focusflow_release_path.txt
DMG_PATH="$(cat /tmp/focusflow_release_path.txt | tail -1)"
hdiutil verify "$DMG_PATH" >/dev/null
test -s "$DMG_PATH.sha256"

SECRET_PATTERN='sk-'
SECRET_SUFFIX='f5def'
if rg -n "${SECRET_PATTERN}|${SECRET_SUFFIX}" . -g '!.git/*' -g '!.build/*' -g '!dist/*' -g '!Scripts/smoke_check.sh'; then
  echo "Secret-like DeepSeek key found in tracked workspace files." >&2
  exit 1
fi

echo "FocusFlow smoke check passed: $APP_PATH"
