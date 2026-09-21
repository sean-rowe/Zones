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
    Then the settings equal the defaults
    And the store did not crash

  Scenario: Setting a value it already holds does not broadcast
    Given a settings store backed by empty storage
    When I change the zone gap to the value it already has
    Then no settingsDidChange notification was posted
