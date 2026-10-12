#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$root_dir/build"
app_dir="$build_dir/IconDrop.app"
sdk_path="${ICONDROP_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
target="$(uname -m)-apple-macosx14.0"

mkdir -p "$build_dir/ModuleCache" "$app_dir/Contents/MacOS" "$app_dir/Contents/Frameworks"

swiftc -target "$target" -sdk "$sdk_path" \
  -module-cache-path "$build_dir/ModuleCache" \
  -emit-library -emit-module -module-name IconDropCore \
  "$root_dir"/Sources/IconDropCore/*.swift \
  -emit-module-path "$build_dir/IconDropCore.swiftmodule" \
  -o "$build_dir/libIconDropCore.dylib"

swiftc -target "$target" -sdk "$sdk_path" \
  -module-cache-path "$build_dir/ModuleCache" \
  -I "$build_dir" -L "$build_dir" -lIconDropCore \
  "$root_dir"/Sources/IconDropApp/*.swift \
  -o "$app_dir/Contents/MacOS/IconDropApp"

cp "$build_dir/libIconDropCore.dylib" "$app_dir/Contents/Frameworks/libIconDropCore.dylib"
cp "$root_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
install_name_tool -change "$build_dir/libIconDropCore.dylib" \
  '@executable_path/../Frameworks/libIconDropCore.dylib' \
  "$app_dir/Contents/MacOS/IconDropApp"
codesign --force --deep --sign - "$app_dir"

printf 'Built %s\n' "$app_dir"
