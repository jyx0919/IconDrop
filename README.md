# IconDrop

A macOS menu bar utility for applying custom icons to folders in batches.

## Current stage: menu bar prototype

`IconDropCore` is a Swift Package library. It provides:

- Image preparation on a transparent 512 × 512 canvas, with the visible content normalized to a consistent size.
- Batch assignments: one image to several folders, or separate images to separate folders.
- Per-folder success and error results, duplicate-folder protection, and restoration of the default icon.
- A persistent backup of each folder's pre-IconDrop icon state. "Restore original" brings back a previous custom icon, or the system default when no custom icon existed.

The prototype menu bar panel supports one image and multiple folders per task. Add several tasks to use different images for different folders, preview their normalized sizes, then apply all tasks. Turn on “移除背景” for the current image to use macOS Vision foreground detection before normalizing its size. Each queued task remembers its own background-removal setting. The app can also restore selected folders to their pre-IconDrop icons.

With a compatible Xcode toolchain, run `swift test` and `swift run IconDropApp` from this directory. To create a local `.app` bundle with a menu bar only appearance, run `scripts/build-app.sh` and open `build/IconDrop.app`. If the selected Command Line Tools SDK is newer than the Swift compiler, set `ICONDROP_SDK_PATH` to a compatible macOS SDK before running the script.

Backups are stored in the user's Application Support directory and removed after a successful restore. "Restore default" always sets the system icon; use "restore original" to recover the icon from before IconDrop's first edit.
