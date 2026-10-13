#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$root_dir/build"
app_dir="$build_dir/IconDrop.app"
sdk_path="${ICONDROP_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
target="$(uname -m)-apple-macosx14.0"

mkdir -p "$build_dir/ModuleCache" "$app_dir/Contents/MacOS" "$app_dir/Contents/Frameworks"

# The selected Command Line Tools SDK can be newer than the installed Swift compiler.
sdk_works() {
  printf 'import AppKit\n' | swiftc -target "$target" -sdk "$1" \
    -module-cache-path "$build_dir/ModuleCache" -typecheck - >/dev/null 2>&1
}

if [[ -z "${ICONDROP_SDK_PATH:-}" ]] && ! sdk_works "$sdk_path"; then
  sdk_dir="$(dirname "$sdk_path")"
  found_sdk=""
  for candidate in "$sdk_dir"/MacOSX*.sdk; do
    [[ -d "$candidate" ]] || continue
    if sdk_works "$candidate"; then
      found_sdk="$candidate"
      break
    fi
  done
  if [[ -z "$found_sdk" ]]; then
    echo "No compatible macOS SDK found. Install or update Xcode Command Line Tools." >&2
    exit 1
  fi
  sdk_path="$found_sdk"
fi

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
