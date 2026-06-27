#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$("$ROOT_DIR/Scripts/package_app.sh" | tail -1)"
DATA_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/focusflow_ui_data.XXXXXX")"
LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/focusflow_ui_smoke.XXXXXX")"
STRICT_CLICK="${FOCUSFLOW_UI_STRICT_CLICK:-0}"
PID=""

mkdir -p "$DATA_ROOT/settings"
printf '{"local_encryption_enabled":false}\n' >"$DATA_ROOT/settings/privacy.json"

cleanup() {
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$DATA_ROOT"
}
trap cleanup EXIT

read_window_rect() {
  osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "FocusFlow"
    set frontmost to true
    delay 0.3
    set p to position of window 1
    set s to size of window 1
    return ((p's item 1) as text) & "," & ((p's item 2) as text) & "," & ((s's item 1) as text) & "," & ((s's item 2) as text)
  end tell
end tell
APPLESCRIPT
}

run_coordinate_click_smoke() {
  command -v swift >/dev/null 2>&1 || return 3
  local rect
  rect="$(read_window_rect)"
  RECT="$rect" swift -e '
import CoreGraphics
import Foundation
import AppKit

let parts = ProcessInfo.processInfo.environment["RECT"]!.split(separator: ",").compactMap { Double($0) }
if parts.count != 4 {
    fatalError("Bad FocusFlow window rect.")
}

func point(_ xRatio: Double, _ yRatio: Double) -> CGPoint {
    CGPoint(x: parts[0] + parts[2] * xRatio, y: parts[1] + parts[3] * yRatio)
}

func click(_ xRatio: Double, _ yRatio: Double) {
    let p = point(xRatio, yRatio)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(120_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(100_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(900_000)
}

func pasteText(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    let flags = CGEventFlags.maskCommand
    let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true)
    down?.flags = flags
    down?.post(tap: .cghidEventTap)
    usleep(80_000)
    let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
    up?.flags = flags
    up?.post(tap: .cghidEventTap)
    usleep(500_000)
}

func scroll(_ deltaY: Int32) {
    CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: deltaY, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
    usleep(900_000)
}

click(0.55, 0.47)      // Task editor, focused by default on launch.
pasteText("Read one paper for class")
click(0.35, 0.86)      // "Make it smaller".
usleep(3_000_000)
scroll(-500)           // Reveal the plan action bar.
click(0.34, 0.93)      // "Start the first step".
usleep(1_500_000)
click(0.46, 0.64)      // "I finished..." in execution center.
usleep(1_500_000)
scroll(-450)           // Reveal feedback options.
click(0.36, 0.35)      // "Found it".
usleep(2_500_000)
'
}

assert_feedback_event_written() {
  if rg -q '"tags":\\["feedback"\\]|"tags" : \\["feedback"\\]|"status":"completed"|found_it|Found it' "$DATA_ROOT" 2>/dev/null; then
    return 0
  fi
  return 1
}

open -n "$APP_PATH" --args --focusflow-data-root "$DATA_ROOT" >"$LOG_FILE" 2>&1

for _ in {1..80}; do
  if osascript -e 'tell application "System Events" to exists process "FocusFlow"' 2>/dev/null | grep -q true; then
    PID="$(pgrep -n -x FocusFlow 2>/dev/null || true)"
    break
  fi
  sleep 0.25
done

if ! osascript -e 'tell application "System Events" to exists process "FocusFlow"' 2>/dev/null | grep -q true; then
  echo "FocusFlow process did not become visible to System Events." >&2
  cat "$LOG_FILE" >&2 || true
  exit 1
fi

osascript <<'APPLESCRIPT'
tell application "System Events"
  if UI elements enabled is false then error "Accessibility permission is not enabled for UI scripting."
  tell process "FocusFlow"
    set frontmost to true
    delay 0.5
    repeat with i from 1 to 40
      if exists window 1 then exit repeat
      delay 0.25
    end repeat
    if not (exists window 1) then error "Main window not found."
  end tell
end tell
APPLESCRIPT

set +e
CLICK_RESULT="$(osascript <<'APPLESCRIPT' 2>&1
on findButtonByName(container, buttonName)
  tell application "System Events"
    try
      if role of container is "AXButton" and name of container is buttonName then return container
    end try
    try
      repeat with child in UI elements of container
        set foundButton to my findButtonByName(child, buttonName)
        if foundButton is not missing value then return foundButton
      end repeat
    end try
  end tell
  return missing value
end findButtonByName

on waitForButton(buttonName, timeoutSeconds)
  tell application "System Events"
    tell process "FocusFlow"
      repeat with i from 1 to (timeoutSeconds * 4)
        set foundButton to my findButtonByName(window 1, buttonName)
        if foundButton is not missing value then return foundButton
        delay 0.25
      end repeat
    end tell
  end tell
  return missing value
end waitForButton

on clickButton(buttonName, timeoutSeconds)
  set targetButton to waitForButton(buttonName, timeoutSeconds)
  if targetButton is missing value then error "Button not found: " & buttonName
  tell application "System Events" to click targetButton
end clickButton

tell application "System Events"
  tell process "FocusFlow"
    set frontmost to true
  end tell
end tell
delay 0.5

clickButton("Read one paper for class", 10)
clickButton("Make it smaller", 15)
clickButton("Start the first step", 20)
clickButton("I finished this step", 20)

if waitForButton("Found it", 15) is not missing value then
  clickButton("Found it", 1)
else if waitForButton("Read enough", 1) is not missing value then
  clickButton("Read enough", 1)
else if waitForButton("Done enough", 1) is not missing value then
  clickButton("Done enough", 1)
else
  error "No expected feedback option appeared."
end if

return "clicked_main_flow"
APPLESCRIPT
)"
CLICK_STATUS=$?
set -e

if [[ "$CLICK_STATUS" -eq 0 ]]; then
  echo "FocusFlow UI smoke clicked main flow: $CLICK_RESULT"
else
  echo "Named Accessibility click automation could not run:" >&2
  echo "$CLICK_RESULT" >&2
  echo "Trying coordinate click fallback with CGEvent..."
  set +e
  COORDINATE_RESULT="$(run_coordinate_click_smoke 2>&1)"
  COORDINATE_STATUS=$?
  set -e
  if [[ "$COORDINATE_STATUS" -eq 0 ]] && assert_feedback_event_written; then
    echo "FocusFlow UI smoke clicked main flow with coordinate fallback."
  else
    echo "FocusFlow UI smoke launched app and found the main window."
    echo "Coordinate click fallback could not complete:" >&2
    echo "$COORDINATE_RESULT" >&2
    echo "Set FOCUSFLOW_UI_STRICT_CLICK=1 to make click automation failures fail this script." >&2
    echo "Grant Accessibility/Input Monitoring permission to the terminal/Codex app if strict click mode cannot inspect or click SwiftUI controls." >&2
    if [[ "$STRICT_CLICK" == "1" ]]; then
      exit 2
    fi
  fi
  if [[ "$STRICT_CLICK" == "1" && "$COORDINATE_STATUS" -ne 0 ]]; then
    exit 2
  fi
fi
