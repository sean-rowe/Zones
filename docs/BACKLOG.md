# Zones — v1 Backlog

Ten epics, 38 stories. Ordered so that each epic leaves the app demonstrably
better than the one before; E1–E4 together are the first thing worth showing
anyone. Acceptance criteria are Gherkin so they drop into `ZonesTests` as
feature files.

Rationale for the order: the core loop (E4) cannot be built without the model
(E2) or proven without fidelity (E7), so E7 is early, not a polish pass. It is
the epic most likely to change the product design.

---

## E1 — Foundation and permissions

Goal: an app that launches, sits in the menu bar, and holds Accessibility.

**Z-1 · SPM skeleton with ZonesCore/Zones split**
- Given a clean checkout, when I run `swift build`, then the `Zones` executable
  and `ZonesCore` library both build on macOS 13.
- And `swift test` runs and reports zero tests without failing.

**Z-2 · Menu bar status item**
- Given the app is running, then a status item appears in the menu bar.
- And the app shows no Dock icon and never takes focus on launch.

**Z-3 · Accessibility permission gate**
- Given permission has not been granted, when the app launches, then the
  permission window explains what Zones needs it for and links to the pane.
- Given permission is granted while the app runs, then the app begins working
  without a relaunch.

**Z-4 · Onboarding and Move to Applications**
- Given the app is launched from a mounted DMG, then it offers to move itself
  to /Applications and relaunch.

**Z-5 · Settings store**
- Given I change a setting, then it persists to UserDefaults as JSON and a
  `settingsDidChange` notification fires.
- Given the stored JSON is corrupt, when the app launches, then it falls back to
  defaults rather than crashing.

---

## E2 — Layout model and templates

Goal: layouts exist, generate, persist, and survive a resolution change.

**Z-6 · Normalized Zone and ZoneLayout**
- Given a zone at (0, 0, 0.5, 1), when resolved on a 3840-wide display, then it
  is 1920 wide; and on a 1440-wide display, 720 wide.

**Z-7 · Built-in templates**
- Given I pick Columns with 3, then a layout of 3 equal zones is generated.
- Given I pick Grid 2×2, then 4 equal zones are generated.
- Given I pick Priority Grid with 3, then a wide primary zone and two stacked
  secondaries are generated.

**Z-8 · Layout persistence**
- Given I save a layout and relaunch, then the layout is present with the same
  UUID, name, and zones.

**Z-9 · Per-display layout assignment keyed by display UUID**
- Given a layout assigned to my external display, when I disconnect and
  reconnect it, then the same layout is still assigned to it.
- Given a display that reports no UUID, then Zones falls back to
  resolution+origin and does not lose the assignment within one session.

**Z-10 · Resolution change keeps the layout**
- Given a layout on a display, when the display's resolution changes, then the
  zones re-resolve proportionally and no zone falls outside the visible frame.

---

## E3 — Layout editor

Goal: a user can build a layout they invented.

**Z-11 · Editor window with template picker**
**Z-12 · Adjust a template's zone count live**
**Z-13 · Drag splitters to resize zones**
- Given a 2-column layout, when I drag the splitter right, then the left zone
  grows and the right shrinks, and the two still tile the display exactly.

**Z-14 · Split and merge zones in a custom layout**
**Z-15 · Name, save, duplicate, and delete layouts**
**Z-16 · Editor previews at true proportions on the target display**
- Given I open the editor for my external display, then the preview matches
  that display's aspect ratio, not the editor window's.

---

## E4 — Drag to snap (the core loop)

Goal: the product.

**Z-17 · Detect a window drag via CGEventTap**
- Given I press and hold on a window's title bar and move, then Zones
  identifies the dragged window's AXUIElement.
- And every mouse event continues to reach the application underneath.

**Z-18 · Show the zone overlay while the modifier is held**
- Given I am dragging a window, when I press and hold Shift, then the zone
  overlay appears on every display.
- Given I release Shift mid-drag, then the overlay disappears and no snap occurs
  on drop.
- Given I begin the drag *before* pressing Shift, then pressing Shift during the
  drag still shows the overlay.

**Z-19 · Overlay never intercepts the drag**
- Given the overlay is visible, when I move the cursor across it, then the drag
  continues uninterrupted and the window keeps following the cursor.

**Z-20 · Highlight the hovered zone**
- Given the overlay is visible, when the cursor enters a zone, then that zone
  highlights and any previously highlighted zone clears.

**Z-21 · Snap on drop**
- Given a zone is highlighted, when I release the mouse, then the window is
  moved and resized to that zone's resolved rect, within quantisation slack.
- And the overlay disappears.

**Z-22 · Multi-zone span**
- Given the overlay is visible, when I hold the span modifier and hover two
  adjacent zones, then both highlight and the drop target is their bounding rect.
- Given I hover two non-adjacent zones, then the bounding rect covers the zones
  between them.

**Z-23 · Cancel a snap with Escape**
- Given a zone is highlighted, when I press Escape, then the overlay clears, no
  snap occurs, and the window returns to following the cursor.

---

## E5 — Keyboard snapping

**Z-24 · Move focused window to zone N**
- Given a layout with 4 zones, when I press ⌃⌥⌘2, then the focused window snaps
  to zone 2.

**Z-25 · Cycle to next / previous zone**
**Z-26 · Move to the same zone index on the next display**
- Given a window in zone 1 of display A, when I press the move-display
  shortcut, then it lands in zone 1 of display B's layout.
- Given display B's layout has fewer zones, then it lands in the last zone.

**Z-27 · Shortcut recorder in settings, with shadowing guard**
- Given I try to record ⌘1, then Zones warns that the chord is commonly owned by
  the frontmost app and requires confirmation.

---

## E6 — Multi-display correctness

**Z-28 · Zones resolve against visibleFrame**
- Given a display with the Dock on the left, then no zone overlaps the Dock or
  the menu bar.

**Z-29 · Correct snapping on a display above or left of the primary**
- Given a display positioned above the primary, when I snap a window into its
  top-left zone, then the window lands on that display, not off-screen.

**Z-30 · Correct snapping across displays of differing heights**
- Given a 1080p display beside a 4K display, when I snap into either, then the
  window's Y position is correct on both.

**Z-31 · Decline gracefully for full-screen Spaces**
- Given the dragged window is in a full-screen Space, then no overlay appears
  and no snap is attempted.

---

## E7 — Window fidelity and reconciliation

Goal: be honest about what windows actually do. Early, because it may change
the design.

**Z-32 · Accept a size within quantisation slack**
- Given Terminal is snapped to a 700×500 zone, when it takes 706×494, then the
  snap is recorded as successful.

**Z-33 · Report a refused axis rather than retrying**
- Given System Settings is snapped to a 400-wide zone, when it ignores the width,
  then Zones records the refusal and does not attempt the resize again.

**Z-34 · Respect a window's minimum size**
- Given Calendar will not go below 908 wide, when I snap it into a 600-wide
  zone, then it is positioned at the zone's origin at its minimum width, and no
  resize loop occurs.

**Z-35 · Never compare frames for equality**
- Given any snap, then success is determined by slack comparison; a test asserts
  no equality comparison exists on the snap path.

---

## E8 — Zone memory and restore

**Z-36 · Remember which zone a window occupies**
**Z-37 · Restore windows after a display is reattached**
- Given a window was in zone 2 of a now-disconnected display, when that display
  reconnects, then the window returns to zone 2.
- Given the display does not return, then the window is moved onto a connected
  display rather than left off-screen.

**Z-38 · Snap a newly launched window into its remembered zone**
- Given the setting is on and an app's window was last in zone 3, when that app
  launches, then its window snaps to zone 3.

---

## E9 — Licensing and trial

Ports of Tack's `LicenseStore` / `TrialManager` / `TrialReminder`. Not detailed
here — mirror Tack's scenarios against `zones.pinyridgelabs.com`.

**Decide the API host and appcast URL before the first public build.** They are
compiled into every shipped binary and an installed copy can never be told a new
address.

---

## E10 — Distribution

Ports of Tack's `scripts/` and `packaging/`. Sparkle appcast, DMG, notarize,
staple. Two rules carried over: never pipe a build step into `tail` (it hides
the exit status, and a notarization failure once looked like success), and the
website lives in its own repo which fetches artifacts from a GitHub Release and
refuses to publish an incomplete set.
