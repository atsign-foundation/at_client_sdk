Feature: IndexedDB failures reach the app as AtExceptions
  Every failure of the browser's IndexedDB that reaches a passkey entry
  point is an IndexedDbException, which extends AtException and is exported
  by package:at_client_wasm, so an app can catch it by type.

  Races, replay, forgery and impersonation: only this origin's own pages
  and browser can make IndexedDB fail, and they already hold more than the
  exception could deny them. Denial of service: the same; a failing
  database fails the call, and nothing retries it.

  Scenario: An IndexedDB database that will not open reaches the app as an IndexedDbException
    Given this origin's IndexedDB refuses to open the passkey database
    When the app logs in to @alice🛠 with a passkey
    Then it throws an IndexedDbException
    And that exception is an AtException exported by package:at_client_wasm

  Scenario: A passkey database a newer build upgraded opens as it is
    Given this origin's passkey database is at a version higher than this build creates
    When the app logs in to @alice🛠 with a passkey
    Then the device's passkey hints are read from that database
    And no version error is thrown

  Scenario: A failed IndexedDB write of the passkey hints during onboarding reaches the app as an IndexedDbException, and a login then logs in
    Given the onboarding of @alice🛠 has deleted its CRAM secret
    And this origin's IndexedDB refuses the write of the passkey hints
    When the onboarding writes the passkey hints
    Then it throws an IndexedDbException that names the browser's error
    And this browser holds no passkey hints for @alice🛠
    When the app then logs in to @alice🛠 with the passkey
    Then it is logged in as the onboarded enrollment
    And the passkey hints are saved
