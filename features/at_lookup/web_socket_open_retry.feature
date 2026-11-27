Feature: A browser WebSocket open retries a transient failure on a fresh socket

  WebSocketTransportFactory.connect opens a `wss://` socket to the atServer.
  A socket that errors, closes or does not open within five seconds is
  retried on a fresh socket, after a one-second pause and then a two-second
  one: three attempts in all. A caller's timeout caps the whole ladder, and
  closing the lookup it opens for ends it at once, without another socket.

  # Threats. Each answer names the scenario that holds it.
  #
  # Race: closing the lookup while the ladder waits between attempts ends it
  #   with no further socket opened, and closing it while a socket is still
  #   connecting is not retried ("an open abandoned during a backoff opens no
  #   further socket", "an open abandoned while connecting is not retried").
  # Replay: an open carries no atSign, challenge or command, so a fresh socket
  #   re-sends nothing a peer could replay; authentication happens after it on
  #   the socket that opened, as features/at_lookup/transports.feature's "A
  #   lookup authenticates only with its authenticator" holds.
  # DoS: a caller timeout caps attempts and pauses together, each attempt is
  #   bounded by five seconds, and there are never more than three sockets ("a
  #   caller timeout caps the whole retry ladder").
  # Forgery: the retry decision is taken from the socket's own open, error and
  #   close events, never from message text, and a failure names only the host,
  #   port and last cause ("an open gives up after three failed attempts with
  #   the last cause").
  # Impersonation: opening a socket decides no identity; it carries no atSign
  #   and the socket is only the atServer its URL names ("an open whose socket
  #   constructor throws is not retried").

  Scenario: an open retries a socket that closed before open, on a fresh socket each time
    Given a browser transport factory
    When its first two sockets close before they open and the third opens
    Then the connect succeeds on the third socket
    And each of the first two sockets was closed by the attempt that gave it up

  Scenario: an open waits one then two seconds between attempts
    Given a browser transport factory whose sockets never open
    When its connect runs to three failed attempts
    Then the second attempt starts one second after the first fails
    And the third starts two seconds after the second fails

  Scenario: an open gives up after three failed attempts with the last cause
    Given a browser transport factory whose sockets never open
    When its connect runs to three failed attempts
    Then it fails with SecondaryConnectException naming the last cause after 3 attempts
    And all three sockets were closed

  @race
  Scenario: an open abandoned during a backoff opens no further socket
    Given a browser transport factory whose first socket does not open
    And the lookup it opens for is closed while the ladder waits between attempts
    When its connect runs
    Then it fails at once as abandoned
    And no further socket is opened

  Scenario: an open abandoned while connecting is not retried
    Given a browser transport factory whose first socket does not open
    And the lookup it opens for is closed while that socket connects
    When its connect runs
    Then it fails at once as abandoned
    And no second socket is opened

  @dos
  Scenario: a caller timeout caps the whole retry ladder
    Given a browser transport factory whose sockets never open
    And a caller timeout shorter than two attempts and their pause
    When its connect runs
    Then it fails within the caller timeout
    And no more than two sockets were opened

  Scenario: an open whose socket constructor throws is not retried
    Given a browser transport factory whose socket constructor refuses the URL
    When its connect runs
    Then it fails at once with SecondaryConnectException
    And no second socket is constructed

  Scenario: an open retries an attempt that errored before open
    Given a browser transport factory whose first socket errors before it opens
    When its second socket opens
    Then the connect succeeds on the second socket

  Scenario: flush on a closed transport throws even with an empty buffer
    Given a WebSocket transport that has been destroyed
    And nothing is buffered on it
    When it is flushed
    Then it throws AtIOException
