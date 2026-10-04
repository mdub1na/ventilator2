#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
cd "$repo_dir"

export SWIFTPM_MODULECACHE_OVERRIDE="$repo_dir/.build/swift-module-cache"
swift build --disable-sandbox --scratch-path .build

app_dir="$repo_dir/.build/Ventilator.app"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Library/LaunchDaemons"
# Retire only the obsolete generated plist in this development bundle.
rm -f "$app_dir/Contents/Library/LaunchDaemons/dev.ventilator.helper.plist"
cp "$repo_dir/.build/out/Products/Debug/Ventilator" "$app_dir/Contents/MacOS/Ventilator"
cp "$repo_dir/.build/out/Products/Debug/VentilatorHelper" "$app_dir/Contents/MacOS/VentilatorHelper"
cp "$repo_dir/Resources/dev.ventilator.app.helper.plist" "$app_dir/Contents/Library/LaunchDaemons/dev.ventilator.app.helper.plist"
cp "$repo_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
plutil -lint "$app_dir/Contents/Info.plist"
plutil -lint "$app_dir/Contents/Library/LaunchDaemons/dev.ventilator.app.helper.plist"
sign_identity="${VENTILATOR_SIGN_IDENTITY:--}"
codesign --force --sign "$sign_identity" --identifier dev.ventilator.app.helper --timestamp=none "$app_dir/Contents/MacOS/VentilatorHelper"
codesign --force --sign "$sign_identity" --timestamp=none "$app_dir"
codesign --verify --strict "$app_dir/Contents/MacOS/VentilatorHelper"
codesign --verify --strict "$app_dir"
echo "$app_dir"
