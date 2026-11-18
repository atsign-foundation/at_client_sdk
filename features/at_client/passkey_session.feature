Feature: A passkey session owns its client and its passkey vault
  The passkey entry points return a passkey session: the client running as
  the enrollment, and the passkey vault its @keys are sealed with. The vault
  closes once the client has stopped, whether the app stopped the session
  or the client itself; closing zeroes the auth seed and closes the sealer.
  The session learns that its client stopped from the client's connection
  reporting `stopped`, its last change. `AtClient.stop()` is as it was
  before the passkey work: it closes no key store, and the `AtKeysIo` type
  hierarchy is unchanged.

  Races: a @keys write already queued when the client stops is waited for,
  up to a bound, before the vault closes; a write a startup step begins
  after that fails, and the step's next start makes it. Replay: nothing
  here is sent. Denial of service: the wait is bounded. Forgery and
  impersonation: a session adds no credential and no path to one; it only
  ends what the entry point built.

  Scenario: Stopping a passkey session stops its client and then closes its vault
    Given a passkey session of @alice🛠 is open
    When the app stops the session
    Then the client is stopped
    And then the vault refuses to seal or open a record

  Scenario: Stopping the session's client directly closes the vault too
    Given a passkey session of @alice🛠 is open
    When the app stops the session's client
    Then the vault refuses to seal or open a record once the client has stopped

  @race
  Scenario: A @keys write queued when the client stops ends before the vault closes
    Given a passkey session's client of @alice🛠 is writing its @keys document
    When the app stops the session
    Then the vault closes only after that write has ended
    And the session stops within its bound even when the write never ends

  Scenario: Stopping the session closes the vault even when stopping the client fails
    Given a passkey session whose client's stop throws an Error
    When the app stops the session
    Then the vault is closed
    And the client's Error propagates

  Scenario: Stopping a session a second time does nothing
    Given a passkey session of @alice🛠 was stopped
    When the app stops it again
    Then nothing is stopped or closed a second time and nothing is thrown

  Scenario: Stopping a client closes no key store
    Given a client opened on a key store it was handed
    When the client stops
    Then the key store was not closed

  Scenario: A switch over AtKeysIo's subtypes needs only WrittenAtKeysIo and GeneratedAtKeysIo
    Given a switch over an AtKeysIo with one case for WrittenAtKeysIo and one for GeneratedAtKeysIo
    Then it compiles as exhaustive
