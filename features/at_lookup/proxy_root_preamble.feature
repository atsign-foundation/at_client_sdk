Feature: A lookup through a proxy root opens each connection with from:<atSign>

  A root domain of the form `proxy:<host>` (with the root port as the proxy's
  port) already tells at_lookup that every atSign is served by that one
  address, a proxy fronting many atServers. Such a proxy has to be told which
  atServer a connection is for, so at_lookup sends `from:<atSign>` itself as
  the first thing on every connection it opens to a proxy root, ahead of any
  `onConnect` the caller passed, where each caller used to send it from its
  own `onConnect`. A lookup built with any other root domain is unchanged.

  Races: the preamble runs in `onConnect`'s slot, under the lock that already
  keeps every command off a connection until it has finished, so no command
  overtakes it; the atSign and the root are fixed when the lookup is built.
  Replay: it is sent once per connection, and a replacement connection sends
  it again, as its own; nothing is cached or reused across connections.
  DoS: one short command per connection, no loop. A preamble that fails
  because the connection drops before its reply closes the connection, as any
  failing `onConnect` does, and the next command opens another and sends it
  again. An `error:` reply, a proxy that cannot route the atSign, fails the
  preamble the same way: the connection is closed and the command fails with
  the error the proxy sent, rather than going out on a connection the proxy
  did not route.
  Forgery and impersonation: `from:<atSign>` is a claim about which atServer
  the proxy should route to, not a proof. at_lookup proves nothing; the
  atServer behind the proxy proves the atSign, through its own `from:`
  challenge and the PKAM or enrollment authentication that follows it, and a
  connection is authenticated only when that succeeds. The atSign sent is the
  one the lookup was built for, never read from the network, and a write that
  holds a line feed before its end is refused, so an atSign cannot smuggle a
  second command into the preamble.

  Scenario: A proxy root sends from:<atSign> first on each connection
    Given a lookup built with a root domain of "proxy:proxy.example.com" for "@alice"
    When it opens a connection and a command is run
    Then "from:@alice" is the first thing written on the connection
    And the command is written only after the preamble has its reply

  Scenario: A replacement connection through a proxy root opens with from:<atSign> again
    Given a lookup built with a proxy root whose connection has been closed by the atServer
    When the next command is run
    Then a new connection is opened and "from:@alice" is written on it before the command

  Scenario: A proxy root's preamble runs before the caller's onConnect
    Given a lookup built with a proxy root and an onConnect of its own
    When it opens a connection
    Then "from:@alice" is written first and the caller's onConnect runs after it, on the same connection

  Scenario: A root domain that is not a proxy sends no from:<atSign>
    Given a lookup built with root domain "root.atsign.org" and an onConnect of its own
    When it opens a connection and a command is run
    Then the first thing written is what the caller's onConnect writes
    And nothing at_lookup wrote precedes it

  Scenario: A proxy root whose connection drops before the preamble's reply is retried on a new one
    Given a lookup built with a proxy root whose connection the proxy closes before answering from:<atSign>
    When a command is run
    Then it fails and the command is not written
    And the next command opens a new connection and writes "from:@alice" on it first

  Scenario: A proxy root's preamble that gets an error: reply fails the connection
    Given a lookup built with a proxy root whose proxy answers from:<atSign> with an error
    When a command is run
    Then it fails with the proxy's error code and the command is not written
    And the connection is closed
