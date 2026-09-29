Feature: The documents Zones is used under
  Zones is bought, so what it is bought under has to be readable from inside
  it — not only from the website someone visited once. A menu bar app has no
  application menu, so the status menu carries the About card and the card
  carries every document.

  Scenario: The status menu offers About
    Given the status menu is rebuilt
    Then it offers an About Zones item

  Scenario: The About card offers every document
    Given the about card is shown
    Then it offers the license agreement, privacy policy, terms of purchase and acknowledgements

  Scenario: The About card says which copy this is
    Given a build reporting version 1.2.3 build 45
    And the about card is shown
    Then the card reads "Version 1.2.3 (45)"

  Scenario: The card keeps its buttons off the window edges
    Given the about card is shown
    Then no button sits closer than 20 points to the card's edge
    And every button is the same width

  Scenario: Choosing a document opens it on the canonical host
    Given the about card is shown
    When the license agreement is chosen
    Then https://zones.pinyridgelabs.com/eula/ is opened
