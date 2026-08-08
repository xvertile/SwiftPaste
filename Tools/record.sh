#!/bin/bash
# Records the demo clips with Cap, applies the brand render settings, and exports
# an MP4 plus a README-sized GIF for each one.
#
#   Tools/record.sh                 record every scene
#   Tools/record.sh hero            record one scene
#   Tools/record.sh --calibrate     3s test clip, to check the crop lines up
#
# The capture is cropped to the TextEdit window, so nothing else that happens to be
# on the screen ends up in a published clip. TextEdit is sized to fill that crop and
# the popup is anchored inside it, which means the frame only ever contains the demo.
#
# Takes over the machine. Swift Paste must be running with the demo history
# (Tools/demo.sh on).
#
# Not `set -e`: a clip that fails should be reported with the rest still attempted.
set -uo pipefail

cd "$(dirname "$0")/.."

CAP=/Applications/Cap.app/Contents/MacOS/cap-cli
DRIVER=build/uidriver
WORK=build/recordings
OUT=assets/video
CONFIG=Tools/cap-config.json

# The stage is the TextEdit window, and the capture is cropped to exactly it. Each
# scene picks its own size, because framing that suits one shot ruins another: the
# preview needs room for a second panel beside the list, while a scene showing only
# the list wants to be tight around it or the panel ends up unreadable once the clip
# is scaled into a card on the site.
#
#   wide  — list plus preview panel side by side
#   tight — the list alone, filling the frame
#   doc   — no panel at all, just text landing in the document
STAGE_L=280; STAGE_T=180; STAGE_R=1420; STAGE_B=860
ANCHOR_X=330; ANCHOR_Y=240

stage_wide()  { STAGE_L=280; STAGE_T=180; STAGE_R=1420; STAGE_B=860; ANCHOR_X=330; ANCHOR_Y=240; }
stage_tight() { STAGE_L=400; STAGE_T=200; STAGE_R=1160; STAGE_B=840; ANCHOR_X=562; ANCHOR_Y=232; }
stage_doc()   { STAGE_L=400; STAGE_T=220; STAGE_R=1160; STAGE_B=700; ANCHOR_X=562; ANCHOR_Y=232; }

# Backing-store scale of the display. The crop is expressed in recorded pixels,
# which on a retina screen is twice the point value.
SCALE=2

CALIBRATE=0
if [ "${1:-}" = "--calibrate" ]; then CALIBRATE=1; shift; fi

mkdir -p "$WORK" "$OUT"

if [ ! -x "$DRIVER" ] || [ Tools/uidriver.swift -nt "$DRIVER" ]; then
    echo "==> Building uidriver"
    swiftc -O Tools/uidriver.swift -o "$DRIVER" || exit 1
fi

[ -x "$CAP" ] || { echo "Cap is not installed at $CAP" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg is required for the GIFs" >&2; exit 1; }
pgrep -x SwiftPaste >/dev/null || { echo "Swift Paste is not running — Tools/demo.sh on" >&2; exit 1; }

SCREEN_ID=$($CAP record screens --json 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["id"])' 2>/dev/null || echo 1)

# ---------------------------------------------------------------- appearance

# The brand is white, so the clips are shot in Light appearance regardless of how
# the Mac is set. Whatever it was before is restored on the way out, including on
# a failure or a Ctrl-C.
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
    echo "==> Switching to Light appearance for the capture (restored afterwards)"
    set_appearance false
    sleep 1.5
fi

# ---------------------------------------------------------------- helpers

say() { printf '    %s\n' "$*"; }

# The crop Cap applies before compositing, in recorded pixels. Taken from the
# window's real frame rather than the requested one: AppleScript bounds are a
# request, and a window that lands even slightly off would drag whatever is behind
# it into the shot.
crop_json() {
    python3 - "$1" "$2" "$3" "$4" "$SCALE" "$CONFIG" <<'PY'
import json, sys
left, top, right, bottom, scale = (int(v) for v in sys.argv[1:6])
config = json.load(open(sys.argv[6]))
config['background']['crop'] = {
    'position': {'x': left * scale, 'y': top * scale},
    'size': {'x': (right - left) * scale, 'y': (bottom - top) * scale},
}
print(json.dumps(config))
PY
}

CROP_CONFIG=""

# Anything that talks to another app can wedge — `defaults write` in particular
# blocks indefinitely when cfprefsd is busy. Nothing here is allowed to hang the
# whole capture.
with_timeout() {
    local seconds="$1"; shift
    perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"
}


# The crop is always exactly the TextEdit window — never a point beyond it. Growing
# it to take in a panel that overhangs the window sounds reasonable and is not: the
# strip it adds is desktop, and that is how someone's other windows end up in a
# published clip. The panel is made to fit the window instead of the other way round.
CROP_L=0; CROP_T=0; CROP_R=0; CROP_B=0

reset_crop() { CROP_L=$STAGE_L; CROP_T=$STAGE_T; CROP_R=$STAGE_R; CROP_B=$STAGE_B; }

# Moves and resizes the window, then reports where it actually landed.
place_window() { # left top right bottom
    local bounds
    bounds=$(with_timeout 20 osascript 2>/dev/null <<APPLESCRIPT
tell application "TextEdit"
    set bounds of front window to {$1, $2, $3, $4}
    delay 0.35
    set b to bounds of front window
    return ((item 1 of b) as text) & " " & ((item 2 of b) as text) & " " & \
           ((item 3 of b) as text) & " " & ((item 4 of b) as text)
end tell
APPLESCRIPT
)
    if [ -z "$bounds" ]; then return 1; fi
    read -r STAGE_L STAGE_T STAGE_R STAGE_B <<<"$bounds"
    reset_crop
    return 0
}

# Opens the panels once before recording, measures them, and grows the window until
# it contains them with a margin. Everything the camera sees is then window.
calibrate_stage() { # "preview" to include the preview panel in the measurement
    local want_preview="${1:-}"
    local line px py pw ph
    $DRIVER mouse "$ANCHOR_X" "$ANCHOR_Y" >/dev/null 2>&1; sleep 0.35
    if ! $DRIVER ensure-open >/dev/null 2>&1; then
        say "could not open the panel to measure it — using the nominal stage"
        return 0
    fi
    sleep 0.4
    if [ "$want_preview" = "preview" ]; then
        $DRIVER key down 3 >/dev/null 2>&1; sleep 0.4
        $DRIVER key space >/dev/null 2>&1; sleep 1.1
    fi

    line=$($DRIVER union 2>/dev/null) || line=""
    $DRIVER ensure-closed >/dev/null 2>&1
    sleep 0.4
    if [ -z "$line" ] || [ "$line" = "none" ]; then return 0; fi
    read -r px py pw ph <<<"$line"

    local m=30
    local nl=$STAGE_L nt=$STAGE_T nr=$STAGE_R nb=$STAGE_B
    if [ $((px - m)) -lt "$nl" ]; then nl=$((px - m)); fi
    if [ $((py - m)) -lt "$nt" ]; then nt=$((py - m)); fi
    if [ $((px + pw + m)) -gt "$nr" ]; then nr=$((px + pw + m)); fi
    if [ $((py + ph + m)) -gt "$nb" ]; then nb=$((py + ph + m)); fi

    if [ "$nl" != "$STAGE_L" ] || [ "$nt" != "$STAGE_T" ] || \
       [ "$nr" != "$STAGE_R" ] || [ "$nb" != "$STAGE_B" ]; then
        say "growing the stage to fit the panel"
        place_window "$nl" "$nt" "$nr" "$nb" || true
    fi
    return 0
}

# One blank window, parked on the stage, with the crop recomputed from where it
# actually landed.
setup_textedit() {
    with_timeout 10 osascript >/dev/null 2>&1 <<'APPLESCRIPT' || true
tell application "TextEdit"
    repeat with d in documents
        try
            close d saving no
        end try
    end repeat
    quit saving no
end tell
APPLESCRIPT
    sleep 0.6
    pkill -x TextEdit >/dev/null 2>&1
    sleep 0.5

    # TextEdit reopens whatever was on screen when it last quit, which is how a
    # stale document turned up mid-capture. Removing the saved state guarantees a
    # blank page, and unlike `defaults write` it cannot block.
    rm -rf "$HOME/Library/Saved Application State/com.apple.TextEdit.savedState" 2>/dev/null

    local bounds
    bounds=$(with_timeout 25 osascript 2>/dev/null <<APPLESCRIPT
tell application "TextEdit"
    activate
    delay 0.6
    repeat with d in documents
        try
            close d saving no
        end try
    end repeat
    make new document
    delay 0.5
    set bounds of front window to {$STAGE_L, $STAGE_T, $STAGE_R, $STAGE_B}
    delay 0.4
    set b to bounds of front window
    return ((item 1 of b) as text) & " " & ((item 2 of b) as text) & " " & \
           ((item 3 of b) as text) & " " & ((item 4 of b) as text)
end tell
APPLESCRIPT
)
    sleep 0.8

    if [ -z "$bounds" ]; then
        say "could not position TextEdit"
        return 1
    fi

    read -r wl wt wr wb <<<"$bounds"
    STAGE_L=$wl; STAGE_T=$wt; STAGE_R=$wr; STAGE_B=$wb
    reset_crop
    say "stage $((wr - wl))×$((wb - wt)) at $wl,$wt"
    return 0
}

close_textedit() {
    with_timeout 10 osascript >/dev/null 2>&1 <<'APPLESCRIPT' || true
tell application "TextEdit"
    repeat with d in documents
        try
            close d saving no
        end try
    end repeat
    quit saving no
end tell
APPLESCRIPT
    sleep 0.4
}

# Confirms the keystrokes are landing in the document and not somewhere else.
doc_text() {
    with_timeout 10 osascript -e 'tell application "TextEdit" to get text of document 1' 2>/dev/null
}

start_recording() {
    local name="$1"
    rm -rf "$WORK/$name.cap"
    $CAP record start --detach --screen "$SCREEN_ID" --fps 60 \
        --mode studio --path "$WORK/$name.cap" --json >"$WORK/$name.start.json" 2>&1 || {
        say "could not start the recording"; return 1
    }
    sleep 1.6   # let the first frames settle before anything moves
}

stop_recording() {
    local name="$1"
    sleep 1.2   # a beat of stillness at the end reads better than a hard cut
    $CAP record stop --path "$WORK/$name.cap" --json >"$WORK/$name.stop.json" 2>&1 \
        || $CAP record stop --json >"$WORK/$name.stop.json" 2>&1
    sleep 1.0
}

# Seconds of settling time at the head of every recording, dropped on export. The
# pause exists so the first frames are not mid-animation; leaving it in means every
# clip opens on a motionless window, which is what made the first cut look dead.
LEAD_TRIM=2.2

# Applies the brand look and the crop, then renders the MP4.
export_scene() {
    local name="$1"
    CROP_CONFIG=$(crop_json "$CROP_L" "$CROP_T" "$CROP_R" "$CROP_B")
    say "crop $((CROP_R - CROP_L))×$((CROP_B - CROP_T)) at $CROP_L,$CROP_T"
    $CAP project config set "$WORK/$name.cap" --settings-json "$CROP_CONFIG" >/dev/null 2>&1 || {
        say "could not apply the render settings"; return 1
    }
    $CAP export "$WORK/$name.cap" "$WORK/$name-full.mp4" \
        --format mp4 --fps 60 --quality maximum --json >/dev/null 2>&1 || {
        say "export failed"; return 1
    }
    # Re-encoded rather than stream-copied: a copy can only cut on a keyframe, which
    # would leave the trim up to a second off.
    ffmpeg -y -loglevel error -ss "$LEAD_TRIM" -i "$WORK/$name-full.mp4" \
        -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p -an "$OUT/$name.mp4" 2>/dev/null || {
        say "trim failed"; return 1
    }
    rm -f "$WORK/$name-full.mp4"
    local dims
    dims=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
        -of csv=p=0:s=x "$OUT/$name.mp4" 2>/dev/null)
    say "wrote $OUT/$name.mp4 ($dims, $(du -h "$OUT/$name.mp4" | cut -f1 | tr -d ' '))"
}

make_gif() {
    local name="$1" width="${2:-900}" fps="${3:-16}"
    if [ ! -f "$OUT/$name.mp4" ]; then
        say "no $name.mp4 to convert — skipping the GIF"
        return 1
    fi
    ffmpeg -y -loglevel error -i "$OUT/$name.mp4" \
        -vf "fps=$fps,scale=$width:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" \
        "$OUT/$name.gif" 2>/dev/null
    say "wrote $OUT/$name.gif ($(du -h "$OUT/$name.gif" | cut -f1 | tr -d ' '))"
}

# Opens the history, verified. Returns non-zero so a scene can bail cleanly.
open_popup() {
    local x="${1:-$ANCHOR_X}" y="${2:-$ANCHOR_Y}"
    $DRIVER mouse "$x" "$y"; sleep 0.4
    if ! $DRIVER ensure-open >/dev/null 2>&1; then
        say "the history did not open — skipping this scene"
        return 1
    fi
    sleep 0.5
    return 0
}

# Drops text into the document instantly. A blank page under the panel reads as an
# empty app; a page with something already on it reads as work in progress.
prefill_doc() {
    with_timeout 10 osascript >/dev/null 2>&1 <<APPLESCRIPT || true
tell application "TextEdit"
    set text of front document to "$1"
end tell
APPLESCRIPT
    sleep 0.4
}

# Confirms the panel survived whatever was just typed into it.
check_popup() {
    if ! $DRIVER popup-visible; then
        say "the history closed unexpectedly"
        return 1
    fi
    return 0
}

click_into_doc() {
    $DRIVER click $((STAGE_L + (STAGE_R - STAGE_L) / 2)) $((STAGE_B - 90))
    sleep 0.5
}

SCENES=("$@")
scene() {
    [ ${#SCENES[@]} -eq 0 ] && return 0
    for requested in "${SCENES[@]}"; do
        [ "$requested" = "$1" ] && return 0
    done
    return 1
}

FAILED=()

# ---------------------------------------------------------------- calibration

if [ "$CALIBRATE" -eq 1 ]; then
    echo "==> Calibration clip"
    stage_tight
    setup_textedit || exit 1
    click_into_doc
    $DRIVER type "Calibration line — typed into the document." 0.03
    sleep 0.5

    typed=$(doc_text)
    if [ -z "$typed" ]; then
        say "nothing reached the document — keystrokes are going elsewhere"
        close_textedit
        exit 1
    fi
    say "document contains: ${typed}"

    start_recording calibrate || exit 1
    open_popup
    sleep 2.0
    $DRIVER ensure-closed >/dev/null 2>&1
    stop_recording calibrate
    export_scene calibrate
    # Sampled while the popup is up, so the frame proves both the crop and the panel.
    ffmpeg -y -loglevel error -ss 2.6 -i "$OUT/calibrate.mp4" -frames:v 1 \
        build/calibrate-frame.png 2>/dev/null
    close_textedit
    echo
    echo "Check build/calibrate-frame.png — only the TextEdit window and the popup."
    exit 0
fi

# ---------------------------------------------------------------- scenes

# The main one: search the history and paste the result into a real document.
if scene hero; then
    echo "==> hero"
    stage_wide
    setup_textedit || FAILED+=("setup")
    # Opens on a page that already has something on it, then moves through four
    # distinct beats — full list, image preview, search, paste — so the clip is
    # never showing the same still for more than about two seconds.
    calibrate_stage preview
    prefill_doc "Release notes — v1.0\\n\\nHighlights\\n"
    click_into_doc
    $DRIVER chord cmd down; sleep 0.4
    if start_recording hero; then
        if open_popup; then
            say "showing the list"
            sleep 1.1
            say "arrowing to an image"
            $DRIVER key down 3; sleep 0.7
            say "previewing"
            $DRIVER key space; sleep 1.9
            $DRIVER key escape; sleep 0.6
            if check_popup; then
                say "searching"
                $DRIVER type "rel" 0.13; sleep 1.1
                say "pasting"
                $DRIVER key down; sleep 0.6
                $DRIVER key return; sleep 1.8
            fi
        fi
        stop_recording hero
        export_scene hero && make_gif hero 900 15 || FAILED+=(hero)
    else
        FAILED+=(hero)
    fi
    close_textedit
fi

# ⌥⌘V with no interface at all — the thing that is hard to explain in text.
if scene quick-paste; then
    echo "==> quick-paste"
    stage_doc
    setup_textedit || FAILED+=("setup")
    prefill_doc "Deploy log\\n"
    click_into_doc
    $DRIVER chord cmd down; sleep 0.3
    if start_recording quick-paste; then
        for _ in 1 2 3; do
            $DRIVER chord cmd+opt v; sleep 1.2
            $DRIVER key return; sleep 0.5
        done
        sleep 0.9
        stop_recording quick-paste
        export_scene quick-paste && make_gif quick-paste 1000 18 || FAILED+=(quick-paste)
    else
        FAILED+=(quick-paste)
    fi
    close_textedit
fi

# Space to preview, the way Finder does it.
if scene preview; then
    echo "==> preview"
    stage_wide
    setup_textedit || FAILED+=("setup")
    calibrate_stage preview
    prefill_doc "Design review\\n"
    if start_recording preview; then
        if open_popup; then
            $DRIVER key down 3; sleep 0.8
            $DRIVER key space; sleep 2.2
            $DRIVER key down; sleep 1.3
            $DRIVER key down; sleep 1.3
        fi
        $DRIVER ensure-closed >/dev/null 2>&1
        sleep 0.5
        stop_recording preview
        export_scene preview && make_gif preview 1000 16 || FAILED+=(preview)
    else
        FAILED+=(preview)
    fi
    close_textedit
fi

# Arrow keys walking the type filter.
if scene filters; then
    echo "==> filters"
    stage_tight
    setup_textedit || FAILED+=("setup")
    calibrate_stage
    prefill_doc "Notes\\n"
    if start_recording filters; then
        if open_popup; then
            for _ in 1 2 3 4; do $DRIVER key right; sleep 1.1; done
        fi
        $DRIVER ensure-closed >/dev/null 2>&1
        sleep 0.4
        stop_recording filters
        export_scene filters && make_gif filters 900 16 || FAILED+=(filters)
    else
        FAILED+=(filters)
    fi
    close_textedit
fi

# Search-as-you-type on its own, for the feature grid.
if scene search; then
    echo "==> search"
    stage_tight
    setup_textedit || FAILED+=("setup")
    calibrate_stage
    prefill_doc "Notes\\n"
    if start_recording search; then
        if open_popup; then
            $DRIVER type "swift" 0.14; sleep 1.3
            check_popup && $DRIVER key delete 5; sleep 0.9
            check_popup && $DRIVER type "figma" 0.14; sleep 1.5
        fi
        $DRIVER ensure-closed >/dev/null 2>&1
        sleep 0.4
        stop_recording search
        export_scene search && make_gif search 900 16 || FAILED+=(search)
    else
        FAILED+=(search)
    fi
    close_textedit
fi

echo
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "==> Scenes that did not produce output: ${FAILED[*]}"
else
    echo "==> All scenes produced output"
fi
ls -1 "$OUT" 2>/dev/null | sed 's/^/    /'
