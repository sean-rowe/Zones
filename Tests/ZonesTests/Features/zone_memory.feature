Feature: Zone memory and restore
  Windows remember which zone they occupy across app and system relaunches,
  return to zones when disconnected displays reconnect, get rescued when
  stranded off-screen, and optionally snap on app launch.

  Scenario: A snapped window's zone is recorded and survives relaunch
    Given I snap a window into zone 2
    Then the assignment is recorded
    And it is still recorded after Zones relaunches

  Scenario: A window moved out of its zone by hand drops the assignment
    Given a window assigned to zone 2
    When I drag it well outside that zone without snapping
    Then the assignment is dropped rather than silently wrong

  Scenario: A window returns to its zone when its display reconnects
    Given a window was in zone 2 of a now-disconnected display
    When that display reconnects
    Then the window returns to zone 2

  Scenario: A window whose display never returns is rescued onto a connected display
    Given a window was on a display that does not return
    When Zones notices it is off-screen
    Then the window is moved onto a connected display
    And not left off-screen

  Scenario: Snap a newly launched window into its remembered zone
    Given the snap-on-launch setting is on
    And an app's window was last in zone 3
    When that app launches
    Then its window snaps to zone 3

  Scenario: The setting off means a launching window is left alone
    Given the snap-on-launch setting is off
    When an app launches
    Then Zones does not move its window
