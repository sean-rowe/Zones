Feature: Accessibility permission
  Zones is inert without Accessibility, and must notice a grant arriving
  while it is already running.

  Scenario: Granting permission while running is noticed without a relaunch
    Given the process is not trusted
    When accessibility is granted
    And the permission check runs
    Then a trust change notification was posted
    And the permission reports that it is trusted

  Scenario: Revoking permission while running is noticed
    Given the process is trusted
    When accessibility is revoked
    And the permission check runs
    Then a trust change notification was posted
    And the permission reports that it is not trusted

  Scenario: An unchanged trust state does not post repeatedly
    Given the process is trusted
    When the permission check runs
    And the permission check runs
    Then no trust change notification was posted
