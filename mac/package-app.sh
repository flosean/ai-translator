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
ditto "$script_dir/Assets/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - --timestamp=none "$app_dir"
print "已建立：$app_dir"
