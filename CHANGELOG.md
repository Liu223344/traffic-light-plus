# Changelog

## Unreleased

- Reworked tracking to cover all visible application windows instead of only the frontmost window.
- Added WindowServer window-ID matching and high-frequency position synchronization during drags.
- Kept native button centers stable while a window is moving to avoid stale accessibility coordinates.
- Matched native activation behavior: the active window stays colored, while background windows use AppKit's inactive control color and regain color on hover.
- Rechecked window occlusion on every position sample so background overlays cannot remain above a quickly moved foreground window.
- Reconciled hover state against the live pointer position so a dragged panel cannot remain colored after moving away from the pointer.

## 1.0.0 - 2026-07-14

- Adjustable 18-48 pt macOS traffic-light controls.
- Optional edge-aligned square controls.
- Live settings preview and one-click reset.
- Multi-display and full-screen handling.
- Accessibility permission onboarding.
- Native menu bar operation with no network access.
