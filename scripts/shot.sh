#!/bin/bash
# Screenshots one app window: launch WispLoom with the dev-only WISP_OPEN switch, find the window by owner,
# capture it with screencapture, then quit the app. The trigger, the window lookup and the capture all happen
# in this one process (AGENTS.md: a focused app hands over within about a second, and the launcher closes).
#
# Usage: scripts/shot.sh <app-id> <shot-name> [--settings] [--title TEXT] [--dark|--light]
#                                  [--owner TEXT] [--no-build] [--delay SECONDS]
#                                  [--click X,Y] [--type TEXT] [--key NAME]
# Output: build/shots/<shot-name>.png
#
# --click / --type / --key drive the page before the capture (coordinates are window-relative points), which is
# how the selected-row and settings-tab shots are taken. --delay waits after the window appears; actions run
# in the order given, then the capture follows after a short settle.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
    echo "usage: scripts/shot.sh <app-id> <shot-name> [--settings] [--title TEXT] [--dark|--light] [--owner TEXT] [--no-build] [--delay SECONDS] [--click X,Y] [--type TEXT] [--key NAME]" >&2
    exit 2
}

app_id=${1:-}
name=${2:-}
[ -n "$app_id" ] && [ -n "$name" ] || usage
shift 2

settings=0
appearance=""
owner="Wisp"
title=""
do_build=1
delay=1.0
app_path=${WISP_APP:-build/DerivedData/Build/Products/Debug/WispLoom.app}
actions=()
while [ $# -gt 0 ]; do
    case $1 in
        --settings) settings=1 ;;
        --dark) appearance=dark ;;
        --light) appearance=light ;;
        --title) title=${2:-}; shift ;;
        --owner) owner=${2:-}; shift ;;
        --no-build) do_build=0 ;;
        --delay) delay=${2:-}; shift ;;
        --click) actions+=("click ${2:-}"); shift ;;
        --type) actions+=("type ${2:-}"); shift ;;
        --key) actions+=("key ${2:-}"); shift ;;
        *) echo "shot.sh: unknown option $1" >&2; exit 2 ;;
    esac
    shift
done

app_path=$(cd "$(dirname "$app_path")" 2>/dev/null && pwd)/$(basename "$app_path")
bin=$app_path/Contents/MacOS/WispLoom
[ -x "$bin" ] || { echo "shot.sh: $bin is missing; run make build first" >&2; exit 1; }
bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Contents/Info.plist" 2>/dev/null || echo com.example.wisploom)
mkdir -p build/shots build/tools

window_helper=build/tools/window-id
if [ ! -x "$window_helper" ] || [ scripts/window-id.swift -nt "$window_helper" ]; then
    swiftc -O -module-cache-path build/tmp/modulecache -o "$window_helper" scripts/window-id.swift
fi
event_helper=build/tools/ui-event
if [ ! -x "$event_helper" ] || [ scripts/ui-event.swift -nt "$event_helper" ]; then
    swiftc -O -module-cache-path build/tmp/modulecache -o "$event_helper" scripts/ui-event.swift
fi

shot=build/shots/$name.png
log=build/shots/$name.log
pid=0
original_appearance=$(defaults read -g AppleInterfaceStyle 2>/dev/null || true)

set_dark_mode() {
    osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $1" >/dev/null 2>&1 || true
}

# The app reads the appearance when it launches, so wait until the preference actually flipped.
wait_for_appearance() {
    for _ in $(seq 1 30); do
        current=$(defaults read -g AppleInterfaceStyle 2>/dev/null || true)
        if [ "$1" = dark ] && [ "$current" = Dark ]; then sleep 2; return 0; fi
        if [ "$1" = light ] && [ -z "$current" ]; then sleep 2; return 0; fi
        sleep 0.1
    done
    echo "shot.sh: could not switch to $1 appearance" >&2
    return 1
}

cleanup() {
    if [ "$pid" != 0 ]; then
        kill -TERM "$pid" 2>/dev/null || true
        for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.05; done
        kill -KILL "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
    if [ "$appearance" = dark ] && [ "$original_appearance" != Dark ]; then
        set_dark_mode false
    elif [ "$appearance" = light ] && [ "$original_appearance" = Dark ]; then
        set_dark_mode true
    fi
}
trap cleanup EXIT

if [ "$do_build" = 1 ]; then
    node scripts/build-apps.mjs >"$log.apps" 2>&1 || { cat "$log.apps" >&2; exit 1; }
fi

case $appearance in
    dark) set_dark_mode true; wait_for_appearance dark ;;
    light) set_dark_mode false; wait_for_appearance light ;;
esac

env_args=(WISP_APPS="$PWD/build/apps" WISP_OPEN="$app_id")
if [ "$settings" = 1 ]; then env_args+=(WISP_OPEN_SETTINGS=1); fi
env "${env_args[@]}" "$bin" >"$log" 2>&1 &
pid=$!

find_args=(--owner "$owner")
if [ -n "$title" ]; then find_args+=(--title "$title"); fi

window=""
for _ in $(seq 1 100); do
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "shot.sh: WispLoom exited before opening a window" >&2
        tail -20 "$log" >&2 || true
        exit 1
    fi
    window=$("$window_helper" "${find_args[@]}" 2>/dev/null || true)
    [ -n "$window" ] && break
    sleep 0.1
done
[ -n "$window" ] || {
    echo "shot.sh: no window for owner '$owner'${title:+ title '$title'} after 10s" >&2
    tail -20 "$log" >&2 || true
    exit 1
}

# The window is up but WebKit may still be painting the first frame.
sleep "$delay"
# A script-launched app is not guaranteed to be frontmost, and an inactive window swallows the first click.
# Activate it, then click the empty sidebar strip left of the content (right of the traffic lights) so the
# window is key before the real actions; on settings windows that point is the native titlebar.
"$event_helper" activate "$bundle_id"
sleep 0.2
window=$("$window_helper" "${find_args[@]}" 2>/dev/null || true)
[ -n "$window" ] || { echo "shot.sh: window disappeared before activation" >&2; exit 1; }
IFS=$'\t' read -r _ window_x window_y _ _ _ <<<"$window"
"$event_helper" click $((window_x + 120)) $((window_y + 16))
sleep 0.3

if [ ${#actions[@]} -gt 0 ]; then
    window=$("$window_helper" "${find_args[@]}" 2>/dev/null || true)
    [ -n "$window" ] || { echo "shot.sh: window disappeared before the actions" >&2; exit 1; }
    IFS=$'\t' read -r _ window_x window_y _ _ _ <<<"$window"
    for action in "${actions[@]}"; do
        kind=${action%% *}
        value=${action#* }
        case $kind in
            click)
                x=${value%%,*}
                y=${value#*,}
                "$event_helper" click $((window_x + x)) $((window_y + y))
                ;;
            type) "$event_helper" type "$value" ;;
            key) "$event_helper" key "$value" ;;
        esac
        sleep 0.3
    done
    sleep 0.4
fi

window=$("$window_helper" "${find_args[@]}" 2>/dev/null || true)
[ -n "$window" ] || { echo "shot.sh: window disappeared before capture" >&2; exit 1; }
IFS=$'\t' read -r window_id window_x window_y window_width window_height _ <<<"$window"
# Park the pointer outside the window: hovering the close button or a row would show up in the image.
"$event_helper" away "$window_x" "$window_y" "$window_width" "$window_height"
sleep 0.2

if ! capture_error=$(screencapture -x -o -l "$window_id" "$shot" 2>&1); then
    echo "shot.sh: screencapture failed: $capture_error" >&2
    echo "shot.sh: 需要“屏幕录制”权限：系统设置 → 隐私与安全性 → 屏幕录制，允许终端/运行此脚本的程序后重试。" >&2
    exit 1
fi
if [ ! -s "$shot" ]; then
    echo "shot.sh: screencapture produced no image; 需要“屏幕录制”权限（系统设置 → 隐私与安全性 → 屏幕录制）。" >&2
    exit 1
fi

echo "wrote $shot (window $window_id, ${window#*$'\t'})"
