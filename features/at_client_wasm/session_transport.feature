Feature: A browser session's transport carries the root its connections are built for

  `sessionTransport` turns transport options into the lookups, the address
  finder and the root that every connection of a `portalSession` client is
  built for. The default is direct: each Atsign's own atServer, found through
  the production atDirectory, `root.atsign.org:64`, over HTTPS. A proxy given
  by `proxyHost` and `proxyPort` becomes a `proxy:<proxyHost>` root at
  `proxyPort`, and at_lookup sends `from:<atSign>` first on every connection
  built for such a root, so the session does not send it itself.
  `portalSession` builds its preference from the transport's root, so the
  root is given once.

  Races: the transport is an immutable record whose root is fixed when it is
  built. `portalSession` reads it once per open, under the existing lock per
  Atsign and enrollment. at_lookup sends `from:<atSign>` in the `onConnect`
  slot, which no command on that connection overtakes.
  Replay: `from:<atSign>` carries no secret and proves nothing, so resending
  it gains nothing. The atServer's challenge and PKAM stay per connection.
  DoS: nothing new is allocated, looped or sized by input. A proxy connection
  sends one short command before its first, as before. Options with an empty
  proxy host or a port outside 1-65535 are refused before any connection.
  Forgery: the proxy carries the whole session and answers for every Atsign,
  so it already holds more than any check here could deny it, and nothing is
  built against it. The root comes from the app's own code, never from the
  network.
  Impersonation: the atServer behind the proxy proves the Atsign through its
  own `from:` challenge and PKAM, as before. The preamble names the Atsign
  the connection was built for, never one read from the network. A
  preference on another root is refused, so every connection of a session is
  built for one root.

  Scenario: Transport options with nothing set go direct through the production atDirectory
    Given transport options built with no arguments
    When the session transport is built from them
    Then its root is "root.atsign.org" at port 64
    And Atsigns are looked up at "root.atsign.org" port 64 over HTTPS

  Scenario: A root given to the transport options is where Atsigns are looked up
    Given transport options with root "root.example" at port 6464
    When the session transport is built from them
    Then its root is "root.example" at port 6464
    And Atsigns are looked up at "root.example" port 6464 over HTTPS

  Scenario: A proxy given to the transport options becomes a proxy: root
    Given transport options with proxyHost "proxy.example" and proxyPort 443
    When the session transport is built from them
    Then its root is "proxy:proxy.example" at port 443
    And "@bob" resolves to "proxy.example:443"

  Scenario: Transport options given a root and a proxy are refused
    Given root "root.example" at port 64, proxyHost "proxy.example" and proxyPort 443
    When transport options are built from them
    Then an ArgumentError naming "root" is thrown

  Scenario: A proxy: root given as the root selects that proxy
    Given transport options with root "proxy:proxy.example" at port 443
    When the session transport is built from them
    Then "@bob" resolves to "proxy.example:443"

  Scenario: A session opened without a preference takes its root from the transport
    Given a session transport whose root is "root.example" at port 6464
    When portalSession opens a client for "@alice" with no prefs
    Then the client's preference has rootDomain "root.example" and rootPort 6464
    And every connection the client builds is built for "root.example" at port 6464

  Scenario: A session opened with a preference on another root is refused before any connection
    Given a session transport whose root is "root.example" at port 6464
    And a preference whose root is "root.atsign.org" at port 64
    When portalSession opens a client for "@alice" with that preference
    Then an ArgumentError naming "prefs" is thrown
    And no connection is dialled

  Scenario: Each connection of a proxy session sends from:<atSign> once, before anything else
    Given a session transport built for proxyHost "proxy.example" and proxyPort 443
    When a connection for "@alice" is built from its lookups for its root and opened
    Then "from:@alice" is the only thing it sends before the caller's first command

  Scenario: A direct session's connections send nothing before the caller's first command
    Given a session transport built with no proxy
    When a connection for "@alice" is built from its lookups for its root
    Then it has no preamble

  Scenario Outline: A proxy named by a bracketed IPv6 literal is reached at that address
    Given a session transport built from <options> naming "[::1]" and the port of a proxy on ::1
    When a connection for "@alice" is built from its lookups for its root and opened
    Then it opens a WebSocket to "wss://[::1]" at that port, path "/ws"
    And "from:@alice" is the only thing it sends before the caller's first command

    Examples:
      | options                  |
      | proxyHost and proxyPort  |
      | a proxy: root            |

  Scenario: An atDirectory named by a bracketed IPv6 literal is asked at that address
    Given an HTTPS finder for "[::1]" at the port of an atDirectory on ::1
    When it looks up "@alice"
    Then the atDirectory receives one request, for "/@alice"
    And the finder returns the atDirectory's answer
