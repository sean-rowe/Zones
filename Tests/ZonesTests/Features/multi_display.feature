Feature: Multi-display correctness
  Zones must resolve against visibleFrame, correctly calculate coordinates
  on displays above or left of primary and of differing heights, and decline
  full-screen Spaces.

  Scenario: Zones resolve against visibleFrame excluding Dock and Menu Bar
    Given a display with the Dock on the left
    When zones are resolved
    Then no zone overlaps the Dock
    And no zone overlaps the menu bar

  Scenario: Moving the Dock re-resolves the zones
    Given zones resolved with the Dock at the bottom
    When I move the Dock to the left
    Then the zones re-resolve to the new visible frame

  Scenario: Snapping onto a display above the primary
    Given a display positioned above the primary
    When I snap a window into its top-left zone
    Then the window lands on that display
    And not off-screen

  Scenario: Snapping onto a display left of the primary
    Given a display positioned left of the primary
    When I snap a window into any zone
    Then the window lands within that display's bounds

  Scenario: Correct snapping across displays of differing heights
    Given a 1080p display beside a 4K display
    When I snap a window into a zone on either
    Then the window's Y position is correct on both
    And the window does not jump when focus moves between them

  Scenario: Decline gracefully for full-screen Spaces
    Given the dragged window is in a full-screen Space
    When I hold the activation modifier
    Then no overlay appears
    And no snap is attempted
