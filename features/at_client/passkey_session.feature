Feature: A passkey session owns its client and its passkey vault
  The passkey entry points return a passkey session: the client running as
  the enrollment, and the passkey vault its @keys are sealed with. The vault
  closes once the client has stopped, whether the app stopped the session
  or the client itself; closing zeroes the auth seed and closes the sealer.
  The session learns that its client stopped from the client's connection
  reporting `stopped`, its last change. `AtClient.stop()` is as it was
  before the passkey work: it closes no key store, and the `AtKeysIo` type
  hierarchy is unchanged.

  Races: once the client has stopped, the session waits, up to a bound, for
  every @keys write queued on the store before it closes the store and then
  the vault: a write already queued when the client stops, one queued while
  the client is stopping, and one queued while the session waits for an
  earlier write. A write that a startup step begins after the session has
  finished waiting fails, and the step's next start makes it. Replay:
  nothing here is sent. Denial of service: the wait is bounded. Forgery and
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

  @race
  Scenario: A @keys write queued while the client stops ends before the store closes
    Given a passkey session's client of @alice🛠 is writing its @keys document
    When the app stops the session
    And the client queues a second @keys write while it is stopping
    Then the second write is made before the store and the vault close

  @race
  Scenario: A @keys write queued while the session waits for an earlier write ends before the store closes
    Given a passkey session's client of @alice🛠 is writing its @keys document
    And the app has stopped the session, which is waiting for that write
    When a second @keys write is queued before the first one ends
    Then the store and the vault stay open, and the stop does not finish, until the second write has ended
    And the second write is made

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
