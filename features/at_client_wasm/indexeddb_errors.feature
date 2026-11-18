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

  Scenario: A failed IndexedDB request reaches the app as an IndexedDbException
    Given IndexedDB fails the request that writes the device's passkey hints
    When the app onboards @alice🛠
    Then it throws an IndexedDbException naming the browser's error

  Scenario: A passkey database a newer build upgraded opens as it is
    Given this origin's passkey database is at a version higher than this build creates
    When the app logs in to @alice🛠 with a passkey
    Then the device's passkey hints are read from that database
    And no version error is thrown
