#!/usr/bin/env bash
# Idempotent AppIcon generator. Runs in CI when no real icon is present.
# Drop a real 1024x1024 PNG at OurFitness/Assets.xcassets/AppIcon.appiconset/icon.png
# and the workflow will leave it alone.
#
# Requires: ImageMagick (preinstalled on GitHub macOS runners).

set -euo pipefail

ICONSET="OurFitness/Assets.xcassets/AppIcon.appiconset"
ICON_PATH="$ICONSET/icon.png"
CONTENTS="$ICONSET/Contents.json"

if [ -f "$ICON_PATH" ]; then
  echo "[icon] $ICON_PATH already exists — leaving it alone."
else
  echo "[icon] generating placeholder 1024×1024 → $ICON_PATH"
  # Warm dark background + accent-orange "OF" wordmark. Flat, no alpha.
  magick -size 1024x1024 xc:'#0a0a0a' \
    -gravity center \
    -fill '#FF6B23' \
    -font Helvetica-Bold \
    -pointsize 520 \
    -annotate +0+30 'OF' \
    -alpha off \
    "$ICON_PATH"
fi

# Ensure Contents.json references the file (idempotent rewrite).
cat > "$CONTENTS" <<'EOF'
{
  "images" : [
    {
      "filename" : "icon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "[icon] done."
