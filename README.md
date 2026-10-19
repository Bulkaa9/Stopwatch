# Stopwatch

A tiny always-on-top stopwatch for macOS. Lives as a small pill in the top-left corner, above every app and every desktop (including full-screen), and gets out of your way when the menu bar needs the space.

## Features

- Floats above everything — all apps, all Spaces, full-screen included.
- Click to start / pause, double-click to reset.
- Click-through by default so it never steals focus from what you're working on. Hover to fade it out; hold ⌘ while hovering to make it solid and clickable.
- ⌥⌘-drag to move it anywhere on screen.
- Auto-hides when a menu drops down over it, or when the menu bar slides down in full-screen.
- Blinks the colon past one hour so you can tell it's still running when only `H:MM` is shown.
- Menu-bar icon with Start/Pause, Reset, Hide, Reset Position, Open at Login, and Quit.
- Pauses while the Mac is asleep (uses system uptime, not wall clock).

## Build

Apple Silicon, macOS 13+.

```
./build.sh
open build/Stopwatch.app
```

## Icon

To regenerate the app icon:

```
swiftc tools/make-icon.swift -o /tmp/make-icon
/tmp/make-icon Resources/AppIcon.icns
```

---

Created by [Bulkaa9](https://github.com/Bulkaa9), helped by Claude.
