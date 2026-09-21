Feature: Move to Applications
  Zones offers to relocate itself when it is running from a place it
  should not stay.

  Scenario: Running from a mounted disk image offers the move
    Given the bundle is at "/Volumes/Zones 0.1.0/Zones.app"
    Then Zones offers to move itself
    And the location is reported as a mounted disk image

  Scenario: A translocated bundle offers the move
    Given the bundle is at "/private/var/folders/x1/abc/T/AppTranslocation/9F2/d/Zones.app"
    Then Zones offers to move itself
    And the location is reported as translocated

  Scenario: Already in Applications does not offer the move
    Given the bundle is at "/Applications/Zones.app"
    Then Zones does not offer to move itself
    And the location is reported as already in Applications

  Scenario: A development build elsewhere does not offer the move
    Given the bundle is at "/Users/someone/Projects/Zones/.build/debug/Zones.app"
    Then Zones does not offer to move itself
    And the location is reported as elsewhere
