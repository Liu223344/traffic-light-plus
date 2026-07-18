# Changelog

## Unreleased

- Added an option to minimize the active window when its already-frontmost application's Dock icon is clicked again.
- Worked around the macOS Dock restore flash by intercepting minimized-app icon clicks and restoring the window directly through Accessibility.
- Fixed overlay suppression recovery when Stage Manager omits the window deminiaturized accessibility notification.

## 1.2.0 - 2026-07-17

- Added native Intel (`x86_64`) builds while retaining Apple Silicon (`arm64`) support.
- Added architecture-specific DMG and ZIP release artifacts.
- Added native CI coverage for both Apple Silicon and Intel macOS runners.
- Added the native macOS zoom and tiling menu when hovering an enlarged zoom control in the active window.
- Fixed green-button clicks being ignored when the native zoom menu had just been requested.
- Marked full-screen overlay support as in development and disabled its settings toggle.

## 1.1.0 - 2026-07-16

- Reworked tracking to cover all visible application windows instead of only the frontmost window.
- Added WindowServer window-ID matching and high-frequency position synchronization during drags.
- Kept native button centers stable while a window is moving to avoid stale accessibility coordinates.
- Matched native activation behavior: the active window stays colored, while background windows use AppKit's inactive control color and regain color on hover.
- Rechecked each traffic light's occlusion on every 120 Hz position sample so covered controls disappear during window movement.
- Reconciled hover state against the live pointer position so a dragged panel cannot remain colored after moving away from the pointer.
- Applied occlusion per button so a foreground window hides only the traffic lights it actually covers.
- Added persistent per-button actions, including quitting or hiding the target application.
- Hid overlays before minimization begins and restored them only after the window leaves the Dock.
- Kept WindowServer position and occlusion sampling at a continuous 120 Hz for predictable real-time tracking.
- Added independently adjustable spacing for the three circular macOS traffic-light controls.
- Added hidden traffic-light reveal modes for enlarging the full group or only the nearest control.
- Shrink and hide overlay controls before starting the native minimize animation.
- Prevented symbol drawing crashes when maximum-size controls animate from native button bounds.
- Removed application names, window titles, and settings-window geometry from diagnostic logs.

## 1.0.0 - 2026-07-14

- Adjustable 18-48 pt macOS traffic-light controls.
- Optional edge-aligned square controls.
- Live settings preview and one-click reset.
- Multi-display and full-screen handling.
- Accessibility permission onboarding.
- Native menu bar operation with no network access.
