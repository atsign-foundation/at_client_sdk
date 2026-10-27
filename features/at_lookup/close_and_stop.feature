Feature: AtLookUp.close() closes the connection, and stop() ends the lookup

  close() means what it meant in at_lookup 3.6: it closes the connection,
  and the next call opens a new one. stop() ends the lookup for good, which
  is what a stopped client needs.

  Races: a request in flight when close() runs fails at once and the next
  call reconnects; calls made after close() share one new connection; stop()
  wins over a reconnect in flight; close() after stop() changes nothing.
  Replay: each reconnect authenticates afresh on its own connection, against
  a new challenge from the atServer, so nothing from the old connection is
  reused.
  DoS: nothing reconnects by itself after close(), and nothing ever after
  stop().
  Forgery and impersonation: a reconnect authenticates as the lookup's own
  atSign with the authenticator it was built with; a stopped client's lookup,
  and a superseded enrollment's after a retrofit, cannot reconnect.

  Scenario: A call after close() reconnects
    Given a lookup that has authenticated and run a command
    When the caller closes it and then runs another command
    Then the lookup opens a new connection, authenticates as the same atSign with the same credentials, and runs the command

  Scenario: close() fails a request in flight at once
    Given a lookup with a request waiting on its connection
    When the caller closes it
    Then the request fails with ConnectionInvalidException without waiting for its timeout
    And the next command opens a new connection

  Scenario: Nothing reconnects by itself after close()
    Given a lookup with notifications on
    When the caller closes it
    Then notifications stop
    And no connection is opened until the caller runs a command

  Scenario: stop() ends the lookup
    Given a lookup with a request in flight and notifications on
    When the caller stops it
    Then the request fails with StoppedException, notifications stop and its socket closes
    And every later call fails with StoppedException without opening a connection

  Scenario: stop() wins over a reconnect in flight
    Given a closed lookup that is opening a new connection for a command
    When the caller stops it before the connection is up
    Then the command fails with StoppedException and the new connection is closed

  Scenario: close() after stop() changes nothing
    Given a stopped lookup
    When the caller closes it
    Then every later call still fails with StoppedException

  Scenario: A stopped client opens no connection
    Given an AtClient that has stopped
    When anything calls its remote secondary
    Then the call fails with StoppedException and no connection is opened

  Scenario: A superseded enrollment's lookup cannot reconnect after a retrofit
    Given a client that rederived its connection after a self-retrofit
    When anything uses the previous lookup
    Then it fails with StoppedException

  Scenario: A stopped monitor ends its lookup at once
    Given a monitor whose notification start is in flight
    When the notification service stops
    Then the start fails with StoppedException without waiting for it to finish
