#!/bin/bash
# Captures every screenshot the README and the site use, then frames each one on
# the brand backdrop.
#
#   Tools/screenshots.sh              capture everything
#   Tools/screenshots.sh popup search only these scenes
#
# Takes over the pointer and the keyboard for about a minute. Swift Paste must be
# running with the demo history loaded (Tools/demo.sh on).
#
# Deliberately not `set -e`: a scene that fails to capture should be reported and
# skipped, not take the other eight down with it.
set -uo pipefail

cd "$(dirname "$0")/.."

DRIVER=build/uidriver
FRAME=build/frame-shot
RAW=build/screenshots-raw
OUT=assets/screenshots

# Where the popup gets anchored. The panel is 420×524 points and opens below-right
# of the pointer, so this keeps it clear of both screen edges.
ANCHOR_X=620
ANCHOR_Y=300

mkdir -p "$RAW" "$OUT"
# Clear the scratch captures so a scene that fails this time cannot be framed from
# whatever the last run left behind.
rm -f "$RAW"/*.png

if [ ! -x "$DRIVER" ] || [ Tools/uidriver.swift -nt "$DRIVER" ]; then
    echo "==> Building uidriver"
    swiftc -O Tools/uidriver.swift -o "$DRIVER"
fi
if [ ! -x "$FRAME" ] || [ Tools/frame-shot.swift -nt "$FRAME" ]; then
    echo "==> Building frame-shot"
    swiftc -O Tools/frame-shot.swift -o "$FRAME"
fi

if ! pgrep -x SwiftPaste >/dev/null; then
    echo "Swift Paste is not running. Run Tools/demo.sh on first." >&2
    exit 1
fi

# ---------------------------------------------------------------- appearance

# The brand is white, so the stills are shot in Light appearance whatever the Mac
# is set to. Restored on the way out, including on failure or Ctrl-C. Harmless when
# capture-all.sh has already switched it.
ORIGINAL_APPEARANCE=$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo "Light")

set_appearance() {
    osascript -e "tell application \"System Events\" to tell appearance preferences \
        to set dark mode to $1" >/dev/null 2>&1
}

restore_appearance() {
    if [ "$ORIGINAL_APPEARANCE" = "Dark" ]; then set_appearance true; else set_appearance false; fi
}
trap restore_appearance EXIT INT TERM

if [ "$ORIGINAL_APPEARANCE" = "Dark" ]; then
    set_appearance false
    sleep 1.5
fi

# ---------------------------------------------------------------- helpers

# Both of these verify the panel actually reached the state asked for and retry if
# it did not. Firing the shortcut blind is what silently produced empty scenes:
# a double tap that gets missed leaves the panel shut, and one aimed at an already
# open panel toggles it closed.
reset_ui() {
    $DRIVER ensure-closed >/dev/null 2>&1
    sleep 0.2
}

open_popup() {
    $DRIVER mouse "$ANCHOR_X" "$ANCHOR_Y"
    sleep 0.35
    if ! $DRIVER ensure-open >/dev/null 2>&1; then
        echo "  !! the history did not open" >&2
        return 1
    fi
    sleep 0.6
    return 0
}

# Confirms the panel survived whatever was just typed into it, so a scene never
# gets framed from a stale capture.
check_popup() {
    if ! $DRIVER popup-visible; then
        echo "  !! the history closed unexpectedly" >&2
        return 1
    fi
    return 0
}

# Captures the app's largest on-screen window.
shoot_window() {
    local name="$1"
    local line id
    # Assigning on its own line keeps the command's exit status; `local id=$(...)`
    # would always report success and hide a missing window.
    line=$($DRIVER windows 2>/dev/null | head -1) || line=""
    id=${line%% *}
    if [ -z "$id" ] || [ "$id" = "none" ]; then
        echo "  !! no window on screen for $name" >&2
        return 1
    fi
    screencapture -x -o -l"$id" "$RAW/$name.png"
}

# Captures the rectangle covering every visible panel — used when the preview sits
# next to the list.
shoot_union() {
    local name="$1" padding="${2:-0}"
    local line x y w h
    line=$($DRIVER union 2>/dev/null) || line=""
    if [ -z "$line" ] || [ "$line" = "none" ]; then
        echo "  !! no windows on screen for $name" >&2
        return 1
    fi
    read -r x y w h <<<"$line"
    x=$((x - padding)); y=$((y - padding))
    w=$((w + padding * 2)); h=$((h + padding * 2))
    screencapture -x -o -R"$x,$y,$w,$h" "$RAW/$name.png"
}

shoot_region() {
    local name="$1" x="$2" y="$3" w="$4" h="$5"
    screencapture -x -o -R"$x,$y,$w,$h" "$RAW/$name.png"
}


# Captures every visible panel as its own window and lays them out at their real
# offsets. Used where two panels sit side by side: capturing the rectangle that
# encloses them would photograph the desktop visible in between.
shoot_composed() {
    local name="$1" pad="${2:-0.07}"
    local specs=() index=0 id x y w h rest
    while read -r id x y w h rest; do
        [ -z "$id" ] && continue
        [ "$id" = "none" ] && continue
        screencapture -x -o -l"$id" "$RAW/$name-$index.png" || continue
        specs+=("$RAW/$name-$index.png:$x,$y,$w,$h")
        index=$((index + 1))
    done < <($DRIVER windows 2>/dev/null)

    if [ ${#specs[@]} -eq 0 ]; then
        echo "  !! no windows on screen for $name" >&2
        return 1
    fi
    $FRAME --compose "$OUT/$name.png" "${specs[@]}" \
        --pad "$pad" --bg light --max-width 2400
}

# pad and background are per-scene so tall panels and wide strips both sit well.
# Silently does nothing when the capture before it failed, so one bad scene never
# leaves a stale frame from a previous run in place.
frame() {
    local name="$1" pad="${2:-0.09}" bg="${3:-light}" radius="${4:-0}"
    if [ ! -f "$RAW/$name.png" ]; then
        echo "  !! nothing captured for $name — skipping" >&2
        rm -f "$OUT/$name.png"
        return 1
    fi
    $FRAME "$RAW/$name.png" "$OUT/$name.png" \
        --pad "$pad" --bg "$bg" --max-width 2400 --radius "$radius"
}

# With no arguments every scene runs; otherwise only the named ones.
SCENES=("$@")
scene() {
    [ ${#SCENES[@]} -eq 0 ] && return 0
    for requested in "${SCENES[@]}"; do
        [ "$requested" = "$1" ] && return 0
    done
    return 1
}

# ---------------------------------------------------------------- scenes

echo "==> Capturing"

if scene popup; then
    echo "  popup"
    reset_ui
    if open_popup; then
        shoot_window popup && frame popup 0.10 light
    fi
    reset_ui
fi

if scene search; then
    echo "  search"
    reset_ui
    if open_popup; then
        $DRIVER type "release" 0.05
        sleep 0.8
        check_popup && shoot_window search && frame search 0.10 light
    fi
    reset_ui
fi

if scene filter-images; then
    echo "  filter-images"
    reset_ui
    if open_popup; then
        $DRIVER key right; sleep 0.35
        $DRIVER key right; sleep 0.8
        check_popup && shoot_window filter-images && frame filter-images 0.10 light
    fi
    reset_ui
fi

if scene filter-files; then
    echo "  filter-files"
    reset_ui
    if open_popup; then
        $DRIVER key right 3; sleep 0.8
        check_popup && shoot_window filter-files && frame filter-files 0.10 light
    fi
    reset_ui
fi

if scene preview; then
    echo "  preview"
    reset_ui
    if open_popup; then
        $DRIVER key down 3; sleep 0.6
        $DRIVER key space; sleep 1.4
        shoot_composed preview 0.07 || echo "  !! preview capture failed" >&2
    fi
    reset_ui
fi

if scene settings-general; then
    echo "  settings-general"
    reset_ui
    if open_popup; then
        $DRIVER chord cmd comma
        $DRIVER wait-window 480 458 5 >/dev/null 2>&1 || sleep 1.4
        sleep 0.6
        shoot_window settings-general && frame settings-general 0.09 light
    fi
fi

if scene settings-history; then
    echo "  settings-history"
    $DRIVER press History || echo "  !! could not find the History tab" >&2
    sleep 0.9
    shoot_window settings-history
    frame settings-history 0.09 light
fi

if scene settings-about; then
    echo "  settings-about"
    $DRIVER press About || echo "  !! could not find the About tab" >&2
    sleep 0.9
    shoot_window settings-about
    frame settings-about 0.09 light
    $DRIVER chord cmd w; sleep 0.5
fi


echo
echo "==> Framed screenshots in $OUT/"
ls -1 "$OUT" | sed 's/^/    /'
