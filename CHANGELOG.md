# Changelog

## Unreleased

- Reworked tracking to cover all visible application windows instead of only the frontmost window.
- Added WindowServer window-ID matching and high-frequency position synchronization during drags.
- Kept native button centers stable while a window is moving to avoid stale accessibility coordinates.
- Matched native activation behavior: the active window stays colored, while background windows use AppKit's inactive control color and regain color on hover.
- Rechecked window occlusion on every position sample so background overlays cannot remain above a quickly moved foreground window.
- Reconciled hover state against the live pointer position so a dragged panel cannot remain colored after moving away from the pointer.
- Applied occlusion per button so a foreground window hides only the traffic lights it actually covers.
- Added persistent per-button actions, including quitting or hiding the target application.
- Hid overlays before minimization begins and restored them only after the window leaves the Dock.
- Reduced idle WindowServer sampling to 10 Hz while using a 240 Hz boost during moves and resizes.
- Paused periodic accessibility rescans during active tracking and stopped redrawing unchanged panel contents on position-only updates.

## 1.0.0 - 2026-07-14

- Adjustable 18-48 pt macOS traffic-light controls.
- Optional edge-aligned square controls.
- Live settings preview and one-click reset.
- Multi-display and full-screen handling.
- Accessibility permission onboarding.
- Native menu bar operation with no network access.
