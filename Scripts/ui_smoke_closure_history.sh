#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$("$ROOT_DIR/Scripts/package_app.sh" | tail -1)"
DATA_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/focusflow_ui_closure.XXXXXX")"
LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/focusflow_ui_closure.XXXXXX")"
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
click(0.52, 0.89)      // "Complete task now".
usleep(2_500_000)
scroll(-1_200)         // Reveal closure actions.
click(0.49, 0.91)      // "View history".
usleep(1_500_000)
'
}

open -n "$APP_PATH" --args --focusflow-data-root "$DATA_ROOT" >"$LOG_FILE" 2>&1

for _ in {1..80}; do
  if osascript -e 'tell application "System Events" to exists process "FocusFlow"' 2>/dev/null | grep -q true; then
    PID="$(pgrep -n -x FocusFlow 2>/dev/null || true)"
    break
  fi
  sleep 0.25
done

if [[ "${FOCUSFLOW_UI_STRICT_CLICK:-0}" != "1" ]]; then
  echo "FocusFlow closure/history UI smoke launched. Set FOCUSFLOW_UI_STRICT_CLICK=1 to click closure and history controls."
  exit 0
fi

if ! osascript <<'APPLESCRIPT'
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

on clickButton(buttonName, timeoutSeconds)
  tell application "System Events"
    tell process "FocusFlow"
      repeat with i from 1 to (timeoutSeconds * 4)
        set foundButton to my findButtonByName(window 1, buttonName)
        if foundButton is not missing value then
          click foundButton
          delay 0.9
          return
        end if
        delay 0.25
      end repeat
    end tell
  end tell
  error "Button not found: " & buttonName
end clickButton

tell application "System Events"
  if UI elements enabled is false then error "Accessibility permission is not enabled for UI scripting."
  tell process "FocusFlow"
    set frontmost to true
    repeat with i from 1 to 40
      if exists window 1 then exit repeat
      delay 0.25
    end repeat
  end tell
end tell

clickButton("Read one paper for class", 10)
clickButton("Make it smaller", 15)
clickButton("Start the first step", 20)
clickButton("Complete task now", 20)
clickButton("View history", 20)
clickButton("Apply", 15)
return "closure_history_smoke_clicked"
APPLESCRIPT
then
  echo "Named Closure/history Accessibility click automation could not run. Trying coordinate fallback with CGEvent..." >&2
  set +e
  COORDINATE_RESULT="$(run_coordinate_click_smoke 2>&1)"
  COORDINATE_STATUS=$?
  set -e
  if [[ "$COORDINATE_STATUS" -ne 0 ]]; then
    echo "Closure/history UI smoke could not click controls. Grant Accessibility/Input Monitoring permission and rerun with FOCUSFLOW_UI_STRICT_CLICK=1 for strict failure." >&2
    echo "$COORDINATE_RESULT" >&2
    exit 2
  fi
fi

if ! rg -q '"event_type":"taskCompleted"|"event_type" : "taskCompleted"' "$DATA_ROOT" 2>/dev/null; then
  echo "taskCompleted event was not written." >&2
  exit 2
fi
if ! rg -q '"event_type":"taskArchived"|"event_type" : "taskArchived"' "$DATA_ROOT" 2>/dev/null; then
  echo "taskArchived event was not written." >&2
  exit 2
fi

echo "FocusFlow closure/history UI smoke passed."
