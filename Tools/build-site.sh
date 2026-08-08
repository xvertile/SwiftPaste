#!/bin/bash
# Collects everything web/index.html references into web/assets/, so web/ can be
# deployed on its own with no build step and no external requests.
#
#   Tools/build-site.sh
#
# Deploy by pointing Cloudflare Pages (or any static host) at the web/ directory.
set -uo pipefail

cd "$(dirname "$0")/.."

DEST=web/assets
mkdir -p "$DEST"
missing=0

echo "==> Brand"
for name in icon-128.png favicon-16.png favicon-32.png apple-touch-icon.png og.png; do
    if [ -f "assets/brand/$name" ]; then
        cp "assets/brand/$name" "$DEST/$name"
    else
        echo "  missing assets/brand/$name — run: swift Tools/make-brand.swift" >&2
        missing=1
    fi
done

echo "==> Stills"
if [ -f assets/screenshots/popup.png ]; then
    cp assets/screenshots/popup.png "$DEST/popup.png"
else
    echo "  missing assets/screenshots/popup.png — run Tools/screenshots.sh" >&2
    missing=1
fi

echo "==> Clips"
# The masters come out of Cap at maximum quality, which is right for keeping but far
# too heavy to put on a landing page — five of them is about 17 MB. These are
# re-encoded to a width that still looks sharp on a retina screen, with the moov atom
# moved to the front so playback can start before the file has finished arriving.
# Each ships with a poster frame from its own midpoint, so the page shows the app
# rather than an empty box while a clip loads.
for name in hero search preview filters quick-paste; do
    src="assets/video/$name.mp4"
    if [ ! -f "$src" ]; then
        echo "  missing $src — run Tools/record.sh" >&2
        missing=1
        continue
    fi

    ffmpeg -y -loglevel error -i "$src" \
        -vf "scale=1440:-2:flags=lanczos" \
        -c:v libx264 -profile:v high -crf 27 -preset slow \
        -pix_fmt yuv420p -movflags +faststart -an \
        "$DEST/$name.mp4" 2>/dev/null

    # Where in each clip the most representative frame sits. A blanket midpoint put
    # the preview card on a frame with the preview panel already dismissed, and the
    # quick-paste card on a page that was still nearly blank.
    case "$name" in
        hero)        fraction=0.45 ;;   # the image preview beat
        preview)     fraction=0.38 ;;   # while the preview panel is up
        quick-paste) fraction=0.88 ;;   # once all three pastes have landed
        filters)     fraction=0.48 ;;   # a filter other than All, while the panel is up
        *)           fraction=0.55 ;;
    esac

    duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$src" 2>/dev/null)
    stamp=$(python3 -c "print(round(max(0.4, float('${duration:-4}') * $fraction), 2))" 2>/dev/null || echo 2)
    ffmpeg -y -loglevel error -ss "$stamp" -i "$DEST/$name.mp4" -frames:v 1 "$DEST/$name-poster.png" 2>/dev/null

    printf '    %-12s %6s -> %-6s  poster @ %ss\n' "$name" \
        "$(du -h "$src" | cut -f1 | tr -d ' ')" \
        "$(du -h "$DEST/$name.mp4" | cut -f1 | tr -d ' ')" "$stamp"
done

# GitHub Pages reads this; Cloudflare Pages ignores it harmlessly.
echo "swiftpaste.app" > web/CNAME

echo
echo "==> web/ is ready — $(du -sh web | cut -f1 | tr -d ' '), $(find web -type f | wc -l | tr -d ' ') files"
[ "$missing" -eq 1 ] && echo "    (some assets are missing — capture them and re-run)"
exit 0
