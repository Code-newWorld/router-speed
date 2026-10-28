#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
bin=".build/release/RouterSpeedBar"
app="RouterSpeedBar.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/RouterSpeedBar"
cp Info.plist "$app/Contents/Info.plist"
echo "built $(pwd)/$app"
echo "open $(pwd)/$app"
