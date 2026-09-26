Feature: Layout editing
  Splitters, splits and merges keep a layout a valid exact tiling.

  Scenario: A two-column layout has one vertical splitter
    Given the columns template with 2
    Then there is 1 splitter
    And splitter 0 is vertical
    And splitter 0 is at 0.5

  Scenario: A two-by-two grid has one splitter on each axis
    Given the grid template with 2 rows and 2 columns
    Then there are 2 splitters
    And there is a vertical splitter at 0.5
    And there is a horizontal splitter at 0.5

  Scenario: Dragging a splitter resizes both neighbours and preserves the tiling
    Given the columns template with 2
    When I drag the vertical splitter to 0.7
    Then zone 0 is 0.7 wide
    And zone 1 is 0.3 wide
    And the zones tile the unit square exactly

  Scenario: A splitter cannot be dragged past the minimum zone size
    Given the columns template with 2
    When I drag the vertical splitter to 0.001
    Then zone 0 is at least the minimum width
    And the zones tile the unit square exactly

  Scenario: A splitter cannot be dragged past the minimum in the other direction
    Given the columns template with 2
    When I drag the vertical splitter to 0.999
    Then zone 1 is at least the minimum width
    And the zones tile the unit square exactly

  Scenario: A grid splitter moves every zone that shares it
    Given the grid template with 2 rows and 2 columns
    When I drag the vertical splitter to 0.25
    Then all zones on the left of the splitter are 0.25 wide
    And the zones tile the unit square exactly

  Scenario: Splitting a zone vertically produces two halves of it
    Given the columns template with 1
    When I split zone 0 vertically
    Then the layout has 2 zones
    And the zones tile the unit square exactly

  Scenario: Splitting a zone horizontally produces two halves of it
    Given the columns template with 1
    When I split zone 0 horizontally
    Then the layout has 2 zones
    And the zones tile the unit square exactly

  Scenario: Two adjacent zones merge into their bounding rect
    Given the columns template with 3
    When I merge zones 0 and 1
    Then the layout has 2 zones
    And the zones tile the unit square exactly

  Scenario: An L-shaped selection is refused
    Given an L-shaped layout of three zones
    When I try to merge the two zones that do not form a rectangle
    Then the merge is refused
    And the layout still has 3 zones

  Scenario: A single zone cannot be merged
    Given the columns template with 2
    When I try to merge only zone 0
    Then the merge is refused

  Scenario: Editing marks the layout as custom rather than generated
    Given the columns template with 2
    When I drag the vertical splitter to 0.6
    Then the layout origin is custom

  Scenario: Two dividers at the same position but disjoint spans stay separate
    Given a layout of two column pairs separated by a full-width band
    Then there are 4 splitters
    And there are 2 vertical splitters at 0.5

  Scenario: Dragging one of two same-position dividers leaves the other alone
    Given a layout of two column pairs separated by a full-width band
    When I drag the upper vertical splitter to 0.8
    Then the upper pair splits at 0.8
    And the lower pair still splits at 0.5
    And the zones tile the unit square exactly

  Scenario: Zones stacked against one divider form a single grab area
    Given the grid template with 2 rows and 2 columns
    Then there is a vertical splitter at 0.5
    And that vertical splitter spans the whole height
