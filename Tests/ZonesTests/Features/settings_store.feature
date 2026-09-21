Feature: Settings store
  Settings persist as JSON, broadcast on change, and survive corruption.

  Scenario: A changed setting persists and broadcasts
    Given a settings store backed by empty storage
    When I change the zone gap to 24
    Then the stored settings JSON contains a zone gap of 24
    And a settingsDidChange notification was posted

  Scenario: Corrupt stored settings fall back to defaults
    Given a settings store backed by corrupt storage
    Then the settings equal the defaults
    And the store did not crash

  Scenario: Unknown keys from a future version are ignored
    Given a settings store whose stored JSON has an unknown key
    Then the zone gap is 21
    And the other settings equal the defaults
    And the store did not crash

  Scenario: Setting a value it already holds does not broadcast
    Given a settings store backed by empty storage
    When I change the zone gap to the value it already has
    Then no settingsDidChange notification was posted

  Scenario: An out-of-range value set at runtime is clamped before it persists
    Given a settings store backed by empty storage
    When I set the zone gap to -50
    Then the zone gap is 0
    And the stored settings JSON contains a zone gap of 0

  Scenario: Overlay opacity above one is clamped at runtime
    Given a settings store backed by empty storage
    When I set the overlay opacity to 4
    Then the overlay opacity is 1

  Scenario: An out-of-range value that clamps to the current one does not broadcast
    Given a settings store backed by empty storage
    When I set the overlay padding to -1
    And I set the overlay padding to -2
    Then exactly 1 settingsDidChange notification was posted
