Feature: Sparkle updater integration
  Auto-update is the one external dependency Zones carries. Sparkle rides
  inside the bundle, signed like everything else, and the bundle declares
  where the feed lives and which key signs it.

  Scenario: The app links Sparkle and starts its updater
    Given the package manifest and the updater service
    Then ZonesCore depends on Sparkle and owns an updater service

  Scenario: The bundle carries the Sparkle framework signed for the hardened runtime
    Given the app build script
    Then it places Sparkle in the bundle's Frameworks and signs it before the app

  Scenario: The bundle declares the feed and the public signing key
    Given the packaged Info.plist
    Then it declares the appcast feed URL and a non-empty EdDSA public key

  Scenario: The status menu offers Check for Updates
    Given the status menu is rebuilt
    Then it offers Check for Updates

  Scenario: Constructing the controller does not start the updater prematurely
    Given a controller that has not run setup
    Then no Sparkle updater has been started
