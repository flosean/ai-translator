#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
cd "$script_dir"
swift build -c release --arch arm64
build_dir=$(swift build -c release --arch arm64 --show-bin-path)
app_dir="$script_dir/../dist-mac/NextAI 翻譯.app"

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
ditto "$build_dir/NextAITranslatorMac" "$app_dir/Contents/MacOS/NextAITranslatorMac"
ditto "$script_dir/Info.plist" "$app_dir/Contents/Info.plist"
icon_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$script_dir/Info.plist")
rm -f "$app_dir/Contents/Resources/AppIcon.icns"
ditto "$script_dir/Assets/AppIcon.icns" "$app_dir/Contents/Resources/$icon_name.icns"
codesign --force --sign - --timestamp=none "$app_dir"
print "已建立：$app_dir"
