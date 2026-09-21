Feature: Layout persistence
  Layouts and their display assignments survive a relaunch.

  Scenario: A saved layout returns with its identity intact
    Given an empty layout store
    When I save a layout named "Work" with 3 zones
    And the store is reloaded from the same storage
    Then the layout named "Work" is present
    And it has the same identifier
    And it has 3 zones

  Scenario: A layout stays with its display across a disconnect
    Given an empty layout store
    When I save a layout named "Wide" with 2 zones
    And I assign it to a display identified by UUID
    And the store is reloaded from the same storage
    Then that display is still assigned the layout named "Wide"

  Scenario: Deleting a layout clears any assignment pointing at it
    Given an empty layout store
    When I save a layout named "Temp" with 2 zones
    And I assign it to a display identified by UUID
    And I delete the layout named "Temp"
    Then that display has no assigned layout

  Scenario: Corrupt stored layouts do not stop the app
    Given a layout store backed by corrupt storage
    Then the store has no layouts
    And the store did not crash

  Scenario: An archive from a newer version is left alone
    Given a layout store whose archive claims a future version
    Then the store has no layouts
    And the store is read only
    And the store did not crash

  Scenario: A newer archive is never overwritten by built-in layouts
    Given a layout store whose archive claims a future version
    When I install the built-in layouts
    Then the store has no layouts
    And the stored bytes are unchanged

  Scenario: Corrupt storage is replaceable, unlike a newer archive
    Given a layout store backed by corrupt storage
    When I install the built-in layouts
    Then the store has some layouts
    And the store is not read only

  Scenario: A UUID-less display keeps its assignment for the session only
    Given an empty layout store
    When I save a layout named "Fallback" with 2 zones
    And I assign it to a display identified only by geometry
    Then that display is assigned the layout named "Fallback"
    And the stored archive holds no assignments
    When the store is reloaded from the same storage
    Then that display has no assigned layout
