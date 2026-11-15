Feature: The Dart bundle loads once and a failed load can be retried

  The first call that needs the bridge injects dist/dart/at_client.js as a
  script and resolves with the global it installs. Every later call and every
  concurrent caller shares that one load.

  Races: concurrent callers share one load, and an earlier load that fails
  late does not discard a loader installed since.
  Replay: none arise; a failed load is not cached, so a retry injects a fresh
  script.
  DoS: one script is injected per load; a failed one is removed from the page.
  Forgery: the script URL is resolved from the module's own URL, never from
  caller input.
  Impersonation: none arise.

  Scenario: loads once however many calls and callers
    Given an installed loader
    When loadBridge is called twice at once and then once more
    Then the loader ran once
    And all three calls resolved with the same bridge

  Scenario: rejects with an internal AtError when the script fails to load
    Given the bundle script is injected and fails to load
    When the load fails
    Then loadBridge rejects with AtError code internal
    And the failed script is removed from the page

  Scenario: injects a fresh script on the retry after a failed load
    Given a failed load
    When loadBridge is called again
    Then a second script is injected
    And it resolves with the bridge the script installs, leaving the script in place

  Scenario: keeps a loader installed while an earlier load was failing
    Given a load in progress on one loader
    When a replacement loader is installed and the earlier load then fails
    Then the replacement is used and is kept for later calls
