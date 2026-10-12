# IconDrop

A macOS menu bar utility for applying custom icons to folders in batches.

## Current stage: core logic

`IconDropCore` is a Swift Package library. It provides:

- Image preparation on a transparent 512 × 512 canvas, with the visible content normalized to a consistent size.
- Batch assignments: one image to several folders, or separate images to separate folders.
- Per-folder success and error results, duplicate-folder protection, and restoration of the default icon.
- A persistent backup of each folder's pre-IconDrop icon state. "Restore original" brings back a previous custom icon, or the system default when no custom icon existed.

The menu bar interface and automatic background removal are planned for later stages.

With a compatible Xcode toolchain, run `swift test` from this directory. Backups are stored in the user's Application Support directory and are removed after a successful restore. "Restore default" always sets the system icon; use "restore original" to recover the icon from before IconDrop's first edit.
