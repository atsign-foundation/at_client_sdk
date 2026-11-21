Feature: IndexedDB failures reach the app as AtExceptions
  Every failure of the browser's IndexedDB that reaches a passkey entry
  point is an IndexedDbException, which extends AtException and is exported
  by package:at_client_web, so an app can catch it by type. Three never
  reach the app, since the passkey hints are a convenience: a failed write
  of the hints, after which the entry point returns its session; a failed
  read of the remembered credential id; and a remembered enrollment id
  that cannot be read, whether IndexedDB fails the read or its stored
  bytes are not UTF-8. Each read failure counts as no hints.

  Races, replay, forgery and impersonation: only this origin's own pages
  and browser can make IndexedDB fail, and they already hold more than the
  exception could deny them. Denial of service: the same; a database that
  will not open fails the call, and nothing retries it, and a database that
  fails the hints makes each login one without hints.

  Scenario: An IndexedDB database that will not open reaches the app as an IndexedDbException
    Given this origin's IndexedDB refuses to open the passkey database
    When the app logs in to @alice🛠 with a passkey
    Then it throws an IndexedDbException
    And that exception is an AtException exported by package:at_client_web

  Scenario: A passkey database a newer build upgraded opens as it is
    Given this origin's passkey database is at a version higher than this build creates
    When the app logs in to @alice🛠 with a passkey
    Then the device's passkey hints are read from that database
    And no version error is thrown

  Scenario: A failed IndexedDB write of the passkey hints during onboarding returns the session, and a login then saves the hints
    Given this origin's IndexedDB refuses the write of the passkey hints
    When the app onboards @alice🛠 with a new passkey
    Then it gets a passkey session as the new enrollment, and no IndexedDbException
    And this browser holds no passkey hints for @alice🛠
    When the app then logs in to @alice🛠 with the passkey
    Then it is logged in as the onboarded enrollment
    And the passkey hints are saved

  Scenario: A remembered enrollment id whose stored bytes are not UTF-8 counts as no hints
    Given this origin's IndexedDB holds a passkey hint for @alice🛠 whose enrollment id bytes are not UTF-8
    When the app logs in to @alice🛠 with the passkey
    Then the login asserts any passkey and reads the passkey's pointer
    And it is logged in as the pointed enrollment, with no IndexedDbException and no FormatException
    And the passkey hints are replaced

  Scenario: A failed IndexedDB read of the remembered enrollment id counts as no hints
    Given this origin's IndexedDB holds passkey hints for @alice🛠
    And IndexedDB fails the read of the remembered enrollment id after the credential id is read
    When the app logs in to @alice🛠 with the passkey
    Then the login asserts any passkey and reads the passkey's pointer
    And it is logged in as the pointed enrollment, with no IndexedDbException

  Scenario: A failed IndexedDB read of the remembered credential id counts as no hints
    Given this origin's IndexedDB holds passkey hints for @alice🛠
    And IndexedDB fails the read of the remembered credential id
    When the app logs in to @alice🛠 with the passkey
    Then the login asserts any passkey and reads the passkey's pointer
    And it is logged in as the pointed enrollment, with no IndexedDbException
