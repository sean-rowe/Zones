# Zones — Architecture

FancyZones for macOS. Define zone layouts per display, drag a window with the
activation modifier held, zones light up, drop to snap.

Zones is the second macOS window app from this shop. **Tack**
(`../Tack`) already shipped against the same platform and paid for most of the
hard lessons; this document says what Zones inherits, what it must build new,
and where the new parts are dangerous. Read `../Tack/CLAUDE.md` alongside it.

---

## Stack

Inherited from Tack wholesale — no reason to diverge:

- Swift Package Manager, `swift-tools-version: 5.9`, `platforms: [.macOS(.v13)]`
- System frameworks only (AppKit, ApplicationServices, CoreGraphics) plus
  **Sparkle** for updates. One dependency, as in Tack.
- `ZonesCore` library target holds all logic; `Zones` executable is a thin
  `main.swift`. Tests import the library — that split is the only reason Tack is
  testable at all.
- Gherkin BDD tests (`ZonesTests`) + integration tests (`ZonesE2ETests`).
- `scripts/release.sh` → build → DMG → notarize → staple → appcast.

**Not sandboxable.** Zones requires Accessibility permission and (see below) may
use private window-server calls on its own overlays. Mac App Store is therefore
a separate, reduced edition at best — treat it as out of scope for v1, as Tack
does.

**Screen Recording is not required.** Tack needs it for live tab-hover
thumbnails. Zones has no equivalent surface, so it can ship asking for exactly
one permission. Do not add a feature that spends that budget without deciding
it is worth a second permission prompt.

---

## Targets

```
Sources/Zones/main.swift            — entry point, nothing else
Sources/ZonesCore/
  Layout/                           — the zone model (new; Tack has no analogue)
  Geometry/                         — normalized zone → screen rect
  Drag/                             — drag detection and the live snap loop
  Overlay/                          — the zone overlay windows
  Snapping/                         — applying a rect to a foreign window
  Memory/                           — window↔zone assignments, restore
  Editor/                           — the layout editor UI
  HotKey/                           — keyboard snapping
  Accessibility/                    — ported near-verbatim from Tack
  WindowDiscovery/                  — ported near-verbatim from Tack
  Settings/                         — AppSettings + UserDefaults JSON
  Utilities/                        — CoordinateConverter, logging
Tests/ZonesTests/                   — BDD
Tests/ZonesE2ETests/                — integration
```

---

## Layers

### 1. Layout model — `Layout/`

The part Tack has nothing to lend.

- **`Zone`** — a rect in **normalized** coordinates (`0...1` on both axes) plus
  an index. Normalized, not absolute, so one layout survives a resolution
  change, a scaling change, and being applied to a different display.
- **`ZoneLayout`** — an ordered `[Zone]`, a name, a stable `UUID`, and the
  template it came from. Zones may overlap (FancyZones allows it); nothing in
  the model forbids it, and hit-testing resolves ties by z-order then index.
- **`LayoutTemplate`** — generators: `columns(n)`, `rows(n)`, `grid(rows:cols:)`,
  `priorityGrid(n)`, `focus(n)`, and `custom`. A generated layout is just a
  `ZoneLayout`; the template is provenance, not a live link, so editing a
  generated layout does not fight its generator.
- **`LayoutStore`** — persistence and per-display assignment.

**Display identity is the trap here.** `CGDirectDisplayID` is recycled across
reconnects and reboots; key a layout to it and a user's second monitor comes
back wearing the laptop's layout. Key on
`CGDisplayCreateUUIDFromDisplayID` instead, and keep the display's
resolution+origin only as a tiebreaker for the case where the UUID is
unavailable (some virtual displays and a few KVMs return nothing). This risk is
new — Tack never persists anything per-display — so it gets its own scenarios.

### 2. Geometry — `Geometry/`

- **`ZoneResolver`** — `(Zone, NSScreen, ZoneSpacing) -> CGRect`. Resolves
  against the screen's **`visibleFrame`**, not `frame`, so zones never sit under
  the menu bar or Dock. Applies outer padding and inter-zone gap from settings.
- **`CoordinateConverter`** — **copy Tack's file verbatim**, including its
  doc comment. macOS has two coordinate systems (CoreGraphics top-left/Y-down,
  AppKit bottom-left/Y-up) and both are anchored to the *primary* display.
  Tack's comment records that `NSScreen.main` is the screen with the key window,
  **not** the primary; three drag paths used it and windows jumped by the height
  difference whenever focus crossed to a shorter display. Zones is a
  multi-display product by definition, so this bug is not hypothetical here.

### 3. Drag detection — `Drag/`

Adapted from Tack's `DragToGroupManager`.

- A global **`CGEventTap`** on `mouseDown`/`mouseDragged`/`mouseUp` and
  `flagsChanged`. Not an `NSEvent` global monitor — Tack's `HotKeyManager`
  documents why the tap is the one that works.
- On mouse-down, identify the window under the cursor: enumerate with
  `CGWindowListCopyWindowInfo`, then bridge the `CGWindowID` to an `AXUIElement`
  via the private `_AXUIElementGetWindow` (Tack's `WindowMatcher` does exactly
  this — port it).
- **Activation policy** is a setting, defaulting to *hold the modifier*
  (Shift, matching FancyZones). Alternative: always-on while dragging. The
  modifier may be pressed *after* the drag begins — watch `flagsChanged`
  throughout the drag, not only at mouse-down. Getting this wrong makes the
  product feel broken in the exact moment the user reaches for it.
- **Whose pixels are these.** Tack's CLAUDE.md: *"Before consuming any event by
  geometry, ask whose pixels those are."* Tack lost right-clicks by claiming the
  title-bar band, because Chromium draws its tab strip there. Zones must pass
  every event through — it observes drags, it never consumes them.

### 4. Overlay — `Overlay/`

- **`ZoneOverlayWindow`** — one non-activating borderless `NSPanel` per display,
  at a level above normal windows, `ignoresMouseEvents = true`. That flag is
  load-bearing: an overlay that takes the mouse eats the very drag it exists to
  assist.
- **`ZoneOverlayView`** — draws zone rects, hover highlight, and the
  multi-zone selection. Honours light/dark and the user's accent colour.
- These are **Zones' own windows**, which is the one place private
  SkyLight/CGS calls are legitimate. Tack's rule: those calls work on your own
  windows and **silently no-op on other applications'** — `SLSSetWindowAlpha`
  and `SLSMoveWindow` return success and change nothing, `SLSOrderWindow`
  returns 1000. Tack built a whole approach on `SLSSetWindowAlpha` before anyone
  measured that it did nothing. Use `SLSTransaction*` to show/hide overlays on
  multiple displays without flicker; never point any of it at a user's window.

### 5. Hit testing — `Geometry/ZoneHitTester`

Cursor point → zone. Two behaviours:

- Single zone: the topmost zone containing the point.
- **Multi-zone span**: with the span modifier held, accumulate zones and snap to
  their bounding rect. This is a headline FancyZones feature; design it in from
  the start rather than retrofitting, because it changes the highlight model
  from "one zone" to "a set".

### 6. Snapping — `Snapping/`

Where Tack's most expensive lesson lands squarely on Zones' core loop.

- **`WindowSnapper`** applies the resolved rect to the window's `AXUIElement`
  using the **size → position → size** dance (Tack's
  `AccessibilityElement.setFrame`). All foreign-window movement goes through
  Accessibility. Never SkyLight — see above.
- **`SnapReconciler`** then re-reads what the window *actually took*, because:

  > **Windows do not take the size they are given.** Terminal sizes itself in
  > whole character cells — asked for 700×500 it wears 706×494. Calendar will
  > not go below 908 wide. System Settings ignores width entirely. macOS also
  > clamps position writes to keep ~40pt of a window on screen.

  Tack encodes a **quantisation slack** (16pt) so a window counts as having
  taken a size if it lands within a character cell of it. Zones needs the same
  constant and must **never compare frames for equality**. Concretely: a snap
  that lands within slack is a success and the zone highlight confirms; a window
  that refuses an axis outright is reported, not fought. A retry loop against
  System Settings' width is an infinite loop.

### 7. Zone memory — `Memory/`

- **`ZoneAssignmentStore`** — which window is in which zone of which layout.
  Keyed by a durable window identity, which macOS does not really provide;
  compose one from bundle identifier + window title + AX index and accept that
  it is heuristic. Persisted to UserDefaults as JSON.
- Drives: restore zones after a display is disconnected and reattached, re-snap
  on app relaunch, and "move window to next display, same zone index".
- Borrow the shape of Tack's `CrashRecovery`, which persists group state and
  restores off-screen windows on launch. Windows stranded off-screen by a
  display change are the same failure.

### 8. Keyboard snapping — `HotKey/`

Port Tack's `HotKeyManager` (a `CGEventTap`, per above).

- Move focused window to zone *N* — default ⌃⌥⌘1–9, following Tack's choice of
  ⌃⌥⌘ as the safe modifier set.
- Move to next / previous zone; move to the same zone on the next display.
- **Tack's shortcut lesson:** it ships ⌃Tab and ⌘1–9 force-disabled
  (`retireShadowingShortcuts`) because they shadow the frontmost app's own keys.
  Zones must not claim a chord any editor or browser already owns. ⌘1–9 is
  tempting and is exactly the mistake Tack already backed out of.

### 9. Layout editor — `Editor/`

A real, activating app window (unlike every other surface here).

- Pick a template, set zone count, drag splitters to adjust, name and save.
- Edits a live preview overlaid on the target display at true proportions.
- Assign a layout to the current display; optionally per Space.

### 10. Settings — `Settings/`

Tack's pattern exactly: an `AppSettings` struct, a `Settings.shared` singleton,
persisted to UserDefaults as JSON, changes broadcast via
`Notification.Name.settingsDidChange`.

Surface: activation modifier, span modifier, zone gap and outer padding, overlay
colour/opacity, flash-zones-on-layout-switch, snap-on-app-launch,
restore-on-display-change, launch at login.

### 11. Permissions and onboarding

Port Tack's `AccessibilityPermission`, `PermissionWindowController`,
`OnboardingWindowController`, and `MoveToApplications`. Zones is useless without
Accessibility, so the onboarding must be as good as Tack's — and Zones has the
easier job of asking for one permission instead of two.

### 12. Distribution

Port Tack's `scripts/` and `packaging/` nearly unchanged: `release.sh`,
`release-doctor.sh`, `build-app.sh`, `make-dmg.sh`, `notarize.sh`,
`make-appcast.sh`. Sparkle ships in the bundle and its licence must be
reproduced wherever the app is distributed.

Two traps Tack records, both of which have cost a release:

1. Piping a build step into `tail` hides its exit status — a notarization
   failure once looked like success.
2. Firebase Hosting replaces the whole site with the local folder, so a file
   missing locally is deleted from production.

Tack solved (2) by splitting the site into its own repo (`tack-web`) which
fetches artifacts from a GitHub Release and refuses to deploy an incomplete set.
**Zones should be born with that split**, not grow into it.

Licensing and trial (`LicenseStore`, `TrialManager`, `TrialReminder`) port from
Tack against a `zones.pinyridgelabs.com` equivalent. Note Tack's warning: the
API host and appcast URL are compiled into every shipped binary, and an
installed copy can never be told a new address. Decide those URLs once, before
the first public build.

---

## Risk register

Ordered by how much they can cost.

| Risk | Why it bites | Mitigation |
|---|---|---|
| Windows refuse the size they are given | The core loop is "window fills zone". It often won't, exactly. | Quantisation slack, never compare frames for equality, report refusals rather than retry |
| Display identity across reconnect | Layouts land on the wrong monitor; users lose configuration | Key on display UUID, not `CGDirectDisplayID` |
| Coordinate conversion on mixed-height displays | Windows jump by the height difference | Copy Tack's `CoordinateConverter` verbatim; never `NSScreen.main` |
| Overlay swallows the drag | Product appears completely broken | `ignoresMouseEvents = true`; never consume tap events |
| Private API assumed to work | An entire approach built on a silent no-op | Accessibility for foreign windows; measure effect, never trust a return code |
| Shortcut shadowing | Breaks the user's other apps, gets uninstalled | Avoid ⌘1–9; default to ⌃⌥⌘ |
| Spaces and full-screen | Snapping into a full-screen Space is undefined | Explicitly out of scope for v1; detect and decline |

## Out of scope for v1

Mac App Store edition, window thumbnails, Spaces-aware layouts, per-app layout
rules, and layout sync across machines. Each is a reasonable v2; none should be
allowed to complicate the v1 model.
