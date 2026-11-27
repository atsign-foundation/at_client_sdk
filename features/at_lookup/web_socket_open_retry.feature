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

  # The pre-flight seam. A caller may give the ladder a prepare function to
  # run once, before its first socket: the ladder waits for it for at most
  # the pre-flight wait (never more than half of what a caller timeout still
  # leaves), or until it answers, or until the work is abandoned. The
  # pre-flight is never cancelled, its later failure is swallowed, and it is
  # not awaited again before the second and third attempts.

  Scenario: a connect prepares once, before its first socket
    Given a browser transport factory with a pre-flight that answers at once
    When its connect runs to three failed attempts
    Then the pre-flight ran once
    And it ran before the first socket was opened

  Scenario: a prepare that fails does not stop the open
    Given a browser transport factory whose pre-flight throws when called
    When its first socket opens
    Then the connect succeeds on that socket

  Scenario: a prepare that rejects does not stop the open
    Given a browser transport factory whose pre-flight returns a rejected future
    When its first socket opens
    Then the connect succeeds on that socket

  Scenario: a prepare that never answers is waited on for at most the pre-flight wait
    Given a browser transport factory whose pre-flight never answers
    And a pre-flight wait of 150 ms
    When its connect runs
    Then the first socket is opened no sooner than 150 ms
    And it is opened well within a second
    And the pre-flight was left pending, not cancelled

  Scenario: a prepare that fails after the ladder stopped waiting raises no uncaught error
    Given a browser transport factory whose pre-flight rejects after 300 ms
    And a pre-flight wait of 100 ms
    When its first socket opens before that rejection
    Then no uncaught zone error is raised
    And the connect succeeds as it would with no pre-flight

  Scenario: a prepare that settles during the backoff is not awaited again
    Given a browser transport factory whose pre-flight settles inside the pause between attempts
    When its first socket errors before it opens
    Then the second socket is opened when the pause ends, not later
    And the pre-flight ran exactly once

  @race
  Scenario: an abandonment during prepare opens no socket
    Given a browser transport factory whose pre-flight never answers
    And the lookup it opens for is closed while the pre-flight waits
    When its connect runs
    Then it fails at once as abandoned
    And no socket is opened

  @dos
  Scenario: prepare time counts against the ladder budget
    Given a browser transport factory whose pre-flight never answers
    And a caller timeout of 400 ms with a pre-flight wait of 10 s
    When its connect runs
    Then the first socket is opened at about half the caller timeout
    And at least one socket was opened
    And the pre-flight was left pending

  @dos
  Scenario: a budget too small to wait on the pre-flight opens without waiting
    Given a browser transport factory whose pre-flight never answers
    And a caller timeout of 4 ms with a pre-flight wait of 10 s
    When its connect runs
    Then it fails within a second, naming no answer within
    And the pre-flight ran exactly once
    And the pre-flight was left pending

  Scenario: a wss URL pre-flights the https origin
    Given a URL of scheme wss, host h and port 1
    When its pre-flight URI is taken
    Then it is https://h:1/

  Scenario: a ws URL has no pre-flight
    Given a URL of scheme ws, host h and port 1
    When its pre-flight URI is taken
    Then it is null

  Scenario: a wss connect composes its pre-flight from the origin and one fetch
    Given a URL of scheme wss, host h and port 1
    When its pre-flight step is built and run
    Then exactly one fetch of https://h:1/ is made, and none before the step runs

  Scenario: a ws connect has no pre-flight step
    Given a URL of scheme ws, host h and port 1
    When its pre-flight step is built
    Then it is null

  Scenario: an IPv6 literal host is bracketed
    Given a URL of scheme wss, host ::1 and port 443
    When its pre-flight URI is taken
    Then it is https://[::1]:443/

  Scenario: flush on a closed transport throws even with an empty buffer
    Given a WebSocket transport that has been destroyed
    And nothing is buffered on it
    When it is flushed
    Then it throws AtIOException
