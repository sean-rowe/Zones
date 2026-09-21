Feature: Layout model
  Zones are normalized, so a layout is independent of the display it
  was built on.

  Scenario: A normalized zone resolves proportionally on a wide display
    Given a zone covering the left half of the unit square
    When it is resolved on a display 3840 by 2160
    Then the resolved width is 1920
    And the resolved height is 2160

  Scenario: The same zone resolves proportionally on a narrow display
    Given a zone covering the left half of the unit square
    When it is resolved on a display 1440 by 900
    Then the resolved width is 720
    And the resolved height is 900

  Scenario: A zone is clamped into the unit square
    Given a zone whose rect escapes the unit square
    Then the zone rect lies inside the unit square

  Scenario: Zones resolve against the visible frame, not the full frame
    Given a display 1000 by 1000 with a visible frame inset by 50 at the top
    When a full-display zone is resolved
    Then the resolved rect does not overlap the menu bar area
