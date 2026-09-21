Feature: Layout templates
  Every generator tiles the unit square exactly.

  Scenario: Columns generates equal full-height zones
    Given the columns template with 3
    Then the layout has 3 zones
    And every zone is 1 high
    And the zones tile the unit square exactly

  Scenario: Rows generates equal full-width zones
    Given the rows template with 4
    Then the layout has 4 zones
    And every zone is 1 wide
    And the zones tile the unit square exactly

  Scenario: Grid generates rows times columns zones
    Given the grid template with 2 rows and 3 columns
    Then the layout has 6 zones
    And the zones tile the unit square exactly

  Scenario: Priority grid generates a wide primary and stacked secondaries
    Given the priority grid template with 3
    Then the layout has 3 zones
    And zone 0 is wider than zone 1
    And the zones tile the unit square exactly

  Scenario: Focus generates a centre zone flanked by sides
    Given the focus template with 3
    Then the layout has 3 zones
    And zone 0 is wider than zone 1
    And the zones tile the unit square exactly

  Scenario: A single column is still a valid tiling
    Given the columns template with 1
    Then the layout has 1 zones
    And the zones tile the unit square exactly

  Scenario: A zero count is corrected rather than producing an empty layout
    Given the columns template with 0
    Then the layout has 1 zones
    And the zones tile the unit square exactly
