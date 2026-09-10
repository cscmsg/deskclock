# DeskClock

A tiny, self-contained native macOS app that floats a round analog clock face
above all your other windows. It has no Dock icon and no app menu — it runs as a
menu-bar accessory. The face is drawn with SwiftUI (`Canvas` + `TimelineView`);
window behavior (borderless, transparent, always-on-top, across Spaces and over
fullscreen apps) is handled with AppKit. It is dependency-free, targets macOS 14+,
and builds from the command line with Swift Package Manager — no Xcode project.

It asks for no permissions, collects nothing, and talks to no network.

## Install

Download the notarized build from [Releases](../../releases), move it to
`/Applications`, and open it.

Or build it yourself — see [Build](#build) below. macOS 14 (Sonoma) or later.

## It stops drawing when you can't see it

A `.periodic` `TimelineView` keeps firing while its view is off-screen — unlike
`.animation`, it does not pause on occlusion. For a borderless always-on-top
overlay that means redrawing the face up to ~30 fps behind the screen saver or a
sleeping display, forever.

DeskClock tracks the three ways the clock goes unseen — window occlusion, screens
asleep, screen saver up — and drops to a single static frame until it is visible
again. Worth knowing if you are the kind of person who checks what your menu-bar
apps cost you.

## Build

```sh
./build.sh
```

This builds a universal binary (Apple silicon and Intel) with `swift build`,
assembles `DeskClock.app`, and writes its `Info.plist`. It signs the bundle with
your Developer ID if you have exactly one, or with the one whose SHA-1 you put in
a `.signing-identity` file; otherwise it ad-hoc signs, which is fine for running
it on your own Mac. The app icon is `Assets/AppIcon.icns`, drawn by
`scripts/make_icon.swift`; delete the icns and `./build.sh` draws it again.

`./build.sh --notarize` also notarizes the app with Apple, staples the ticket,
checks that Gatekeeper accepts it, and writes `dist/DeskClock-<version>.zip`,
which is the file attached to each Release. It needs a Developer ID certificate
and a `notarytool` keychain profile; `./build.sh --help` has the details.

## Run

```sh
open DeskClock.app
```

A floating round clock appears (top-right of your main screen on first launch).

- **Move it:** drag anywhere on the face.
- **Configure:** click the clock icon in the menu bar to open the **Settings
  popover**. It stays open while you adjust things and dismisses when you click
  outside (or press Esc):
  - **Size** (Small / Medium / Large) and **Theme** (Classic / Monochrome / Ocean
    / Forest / Sunset / Berry) **preview live as you hover** and commit on click;
    a hovered-but-unclicked choice reverts when the popover closes.
  - **Opacity** slider (30–100%), and switches for **Sweeping Second Hand**,
    **Show Hour Numerals**, **Float Over Fullscreen Apps**, **Click-Through**, and
    **Launch at Login** — all apply immediately.
  - **Quit DeskClock** is at the bottom of the popover.

(Click-Through lets clicks pass through to whatever is underneath; it also
disables dragging, so use the popover to turn it back off.)

Every setting — plus the window position — is remembered across launches.

## Permissions

None. DeskClock only manages its own window — it uses no Accessibility,
screen-recording, or global window-pinning APIs, so macOS asks for nothing.

**Launch at Login** registers a standard login item via `SMAppService` (also
manageable under System Settings → General → Login Items). Because the bundle is
ad-hoc signed, re-running `./build.sh` changes its signature — if the setting was
on, toggle it off and back on after a rebuild so the login item points at the
fresh build.

## Project layout

| File | Role |
| --- | --- |
| `Sources/DeskClock/main.swift` | App bootstrap, `AppDelegate`, window-side settings + login item |
| `Sources/DeskClock/ClockSettings.swift` | Observable settings model (persistence) + color themes |
| `Sources/DeskClock/ClockWindow.swift` | Borderless transparent always-on-top `NSWindow`; size definitions |
| `Sources/DeskClock/ClockView.swift` | SwiftUI `Canvas` clock face (sweep, numerals, themes) |
| `Sources/DeskClock/SettingsPanel.swift` | SwiftUI settings popover (hover-preview size/theme, live toggles) |
| `Sources/DeskClock/StatusItem.swift` | Menu-bar `NSStatusItem` + settings popover host |
| `build.sh` | Build, bundle, sign |

The app's display name is the single `AppInfo.name` constant in `main.swift`; the
bundle/executable name and identifier are variables at the top of `build.sh`.

## License

MIT — see [LICENSE](LICENSE).
