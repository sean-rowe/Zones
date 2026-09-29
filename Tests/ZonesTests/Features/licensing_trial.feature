Feature: Licensing and trial
  Zones starts a fourteen-day trial on fresh installs, reminds users as expiry nears,
  gracefully gates snapping when expired, activates license keys securely across relaunches,
  and compiles in final agreed hostnames.

  Scenario: A fresh install starts a trial and reminds as it expires
    Given a fresh install
    Then a trial period begins
    And I am reminded as it nears expiry
    And an expired trial degrades predictably rather than crashing

  Scenario: A licence key activates and survives relaunch
    Given a valid licence key
    When I activate it
    Then the app is licensed
    And it is still licensed after relaunch

  Scenario: An invalid key reports refusal reason
    Given an invalid key
    When I activate it
    Then I am told why it was refused

  Scenario: The shipped binary points at final agreed hostnames
    Given a release build
    Then its licence API host is the final agreed hostname
    And its appcast URL is the final agreed hostname
    And neither is a placeholder
