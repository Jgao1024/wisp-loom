#!/bin/bash
# Screenshots one app window: launch WispLoom with the dev-only WISP_OPEN switch, find the window by owner,
# capture it with screencapture, then quit the app. The trigger, the window lookup and the capture all happen
# in this one process (AGENTS.md: a focused app hands over within about a second, and the launcher closes).
#
# Usage: scripts/shot.sh <app-id> <shot-name> [--settings] [--title TEXT] [--dark|--light]
#                                  [--owner TEXT] [--no-build] [--delay SECONDS]
# Output: build/shots/<shot-name>.png
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
    echo "usage: scripts/shot.sh <app-id> <shot-name> [--settings] [--title TEXT] [--dark|--light] [--owner TEXT] [--no-build] [--delay SECONDS]" >&2
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
while [ $# -gt 0 ]; do
    case $1 in
        --settings) settings=1 ;;
        --dark) appearance=dark ;;
        --light) appearance=light ;;
        --title) title=${2:-}; shift ;;
        --owner) owner=${2:-}; shift ;;
        --no-build) do_build=0 ;;
        --delay) delay=${2:-}; shift ;;
        *) echo "shot.sh: unknown option $1" >&2; exit 2 ;;
    esac
    shift
done

bin=$app_path/Contents/MacOS/WispLoom
[ -x "$bin" ] || { echo "shot.sh: $bin is missing; run make build first" >&2; exit 1; }
mkdir -p build/shots build/tools

helper=build/tools/window-id
if [ ! -x "$helper" ] || [ scripts/window-id.swift -nt "$helper" ]; then
    swiftc -O -module-cache-path build/tmp/modulecache -o "$helper" scripts/window-id.swift
fi

shot=build/shots/$name.png
log=build/shots/$name.log
pid=0
original_appearance=$(defaults read -g AppleInterfaceStyle 2>/dev/null || true)

cleanup() {
    if [ "$pid" != 0 ]; then
        kill -TERM "$pid" 2>/dev/null || true
        for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.05; done
        kill -KILL "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
    if [ "$appearance" = dark ] && [ "$original_appearance" != Dark ]; then
        defaults delete -g AppleInterfaceStyle 2>/dev/null || true
    elif [ "$appearance" = light ] && [ "$original_appearance" = Dark ]; then
        defaults write -g AppleInterfaceStyle -string Dark
    fi
}
trap cleanup EXIT

if [ "$do_build" = 1 ]; then
    node scripts/build-apps.mjs >"$log.apps" 2>&1 || { cat "$log.apps" >&2; exit 1; }
fi

case $appearance in
    dark) defaults write -g AppleInterfaceStyle -string Dark ;;
    light) defaults delete -g AppleInterfaceStyle 2>/dev/null || true ;;
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
    window=$("$helper" "${find_args[@]}" 2>/dev/null || true)
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
window=$("$helper" "${find_args[@]}" 2>/dev/null || true)
[ -n "$window" ] || { echo "shot.sh: window disappeared before capture" >&2; exit 1; }
window_id=${window%%$'\t'*}

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
