Feature: Window fidelity and reconciliation
  Zones must accept terminal character-cell quantisation within slack,
  record axis refusals without fighting or looping, and position windows
  exceeding zone boundaries due to minimum size constraints at the zone origin.

  Scenario: Terminal character-cell quantisation counts as a successful snap
    Given Terminal is snapped to a 700x500 zone
    When it takes 706x494
    Then the snap is recorded as successful
    And the zone is not re-applied

  Scenario: A window that ignores width is recorded, not fought
    Given System Settings is snapped to a 400-wide zone
    When it ignores the width
    Then Zones records the refusal
    And does not attempt the resize again

  Scenario: A window below its minimum is positioned at the zone origin
    Given Calendar will not go below 908 wide
    When I snap it into a 600-wide zone
    Then it is positioned at the zone's origin at its minimum width
    And no resize loop occurs

  Scenario: Snap success is determined by slack comparison, never equality
    Given any snap
    Then success is determined by a slack comparison
    And a test asserts no frame equality comparison exists on the snap path
