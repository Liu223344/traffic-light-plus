# Changelog

## Unreleased

## 1.4.1 - 2026-07-22

- Added a persistent option to hide the Traffic Lights+ menu bar icon while keeping Settings recoverable by reopening the app.
- Added multi-selection when choosing applications for the quit-on-close list.
- Fixed enlarged zoom-button clicks in Safari Web Apps after opening the native zoom and tiling menu.
- Left all minimized-window restoration to the Dock so every application keeps the native macOS transition without an Accessibility-driven flash.

## 1.4.0 - 2026-07-20

- Added an independent quit-on-close switch that works with native window controls when enlarged traffic lights are disabled.
- Prevented Stage Manager desktop clicks from being blocked by Dock observation and repeated hidden-panel updates.
- Fixed Stage Manager Dock clicks failing to restore minimized windows or immediately minimizing them again.
- Prevented Stage Manager desktop and window-group clicks from entering the synchronous Dock event interception path.
- Fixed repeated Dock clicks being ignored when an application temporarily omits its focused or main Accessibility window.
- Recovered safely from non-finite button size or spacing values in damaged preferences.
- Added Sparkle 2.9.2 with automatic update checks and background downloads enabled by default.
- Added bilingual software-update settings and a menu-bar command for immediate update checks.
- Added architecture-specific HTTPS appcasts with EdDSA-signed ZIP updates for arm64 and x86_64.
- Added strict Sparkle framework embedding, rpath, architecture, entitlement, and code-signing validation.
- Added a stable-release workflow that validates release assets before atomically deploying appcasts through GitHub Pages.

## 1.3.0 - 2026-07-18

- Added an in-app Simplified Chinese and English language selector with immediate interface updates.
- Added an option to minimize the active window when its already-frontmost application's Dock icon is clicked again.
- Decoupled Dock click handling from the enlarged traffic-light switch and added independent settings and menu-bar toggles.
- Prevented independent Dock minimization from reusing stale overlay controls after enlarged traffic lights are disabled.
- Left minimized-window restoration to macOS while Stage Manager is enabled, preserving its window-group restore behavior.
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
