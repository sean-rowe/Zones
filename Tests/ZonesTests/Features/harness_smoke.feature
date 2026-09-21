Feature: BDD harness
  The harness itself works before anything relies on it.

  Scenario: Steps run in order and carry captured arguments
    Given a counter starting at 3
    When I add 4
    Then the counter is 7

  Scenario: And continues the preceding keyword
    Given a counter starting at 0
    And I add 2
    When I add 5
    And I add 1
    Then the counter is 8
