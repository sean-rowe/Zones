Feature: Notarized stapled DMG release
  One command produces the file that goes on the website: doctor gate,
  release build, signed disk image, notarization, stapled ticket — in
  that order, refusing early rather than dying mid-pipeline.

  Scenario: One command runs build, image, notarize and staple in order
    Given the release script
    Then it runs the doctor, the release build, the disk image and the notarization in order

  Scenario: The release refuses to start while the doctor finds gaps
    Given the release script
    Then a failing doctor stops the release before any build

  Scenario: The stapled image is validated before it is called done
    Given the notarize script
    Then it staples the ticket and validates the staple

  Scenario: A malformed version stops the release before anything runs
    Given the release script runs with version "banana"
    Then it refuses before the doctor or any build stage

  Scenario: Release scripts enforce pipefail and never pipe into tail
    Given the release scripts directory
    Then every script enforces pipefail
    And no script pipes build or notarization into tail
