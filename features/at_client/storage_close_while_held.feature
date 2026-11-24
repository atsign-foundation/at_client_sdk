Feature: A storage a client still holds is not closed

  An AtClientStorage is held by one client at a time. Closing it while a
  client holds it would leave that client on a closed backend, so close()
  refuses until the client has stopped or detached, and closes nothing. A
  client's own stop() detaches and closes a storage it owns in one step when
  the storage is built on AtClientStorageBase, as every storage the SDK
  ships is, so that close is never refused.

  Races: a close() during an attach() still opening the backend is refused,
  and the attach completes with the backend open; a close() during a
  client's stop() is refused until the stop has released the storage.
  Replay: none; nothing is sent. DoS: none; close() decides from the
  storage's own state. Forgery and impersonation: only the app holding the
  storage object can close it, and it already holds the client.

  Scenario: Closing a storage a client holds is refused
    Given a client holds the storage
    When the app closes the storage
    Then it throws StateError saying to stop the client first, and the storage stays open and held

  Scenario: Closing a storage once its client has stopped closes it
    Given a client that held the storage has stopped
    When the app closes the storage
    Then the backend closes and the location is free for another storage

  @race
  Scenario: Closing a storage while a client is attaching is refused
    Given a client's attach is still opening the storage's backend
    When the app closes the storage
    Then it throws StateError, and the attach completes with the backend open

  Scenario: A client that owns its storage closes it on stop without error
    Given a client whose storage it closes on stop
    When the client stops
    Then the storage is closed and nothing throws
