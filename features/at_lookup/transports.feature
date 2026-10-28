Feature: at_lookup 4.0.0 runs over a transport the caller chooses, and builds for the web

  A lookup speaks the Atsign Protocol over an AtTransport: TLS sockets from
  at_lookup_io.dart, or WebSockets from at_lookup_web.dart. at_lookup.dart
  and at_lookup_web.dart reach no dart:io. close() and stop() mean what
  close_and_stop.feature says, over every transport.

  Races: close() and stop() keep the behaviour close_and_stop.feature
  agrees, on the WebSocket transport as on TLS; a close() abandons a
  WebSocket connect or atDirectory request in flight, as it does a TLS one.
  Replay: each connection authenticates against its own challenge from the
  atServer, whatever the transport, so nothing from one connection is
  accepted on another.
  DoS: a WebSocket connect and an atDirectory request each give up after a
  bounded time; an atDirectory answer and the bytes a WebSocket holds unread
  are bounded in size, and going over closes the connection with a warning.
  Forgery and impersonation: a lookup authenticates only with the
  authenticator it holds, never from credentials set on it field by field;
  a browser lookup asks the atDirectory for the atSign in canonical form,
  over HTTPS, and connects over wss.

  Scenario: The default barrels reach no platform library
    Given at_lookup 4.0.0
    When wasm_shakedown walks at_lookup.dart and at_lookup_web.dart
    Then neither reaches dart:io, directly or through another package
    And each compiles with dart2wasm

  Scenario: A lookup runs the same over either transport
    Given an atServer reachable over TLS and over a WebSocket
    When one lookup connects over the TLS transport and another over the WebSocket transport
    Then each authenticates as the same atSign and gets the same answer to the same command

  Scenario: A browser lookup finds its atServer through the atDirectory's HTTPS face
    Given an atDirectory that answers an HTTPS request for the atSign with its atServer's host and port
    When a browser lookup runs its first command
    Then it connects to wss://host:port/ws and runs the command there

  Scenario: A browser lookup asks for the atSign in canonical form
    Given a lookup for an atSign written with capitals
    When it asks the atDirectory where the atSign's atServer is
    Then the request names the atSign folded to lower case

  Scenario: A lookup authenticates only with its authenticator
    Given a lookup with no authenticator
    When a command that needs authentication runs
    Then it fails with UnAuthenticatedException and the command is never sent

  Scenario: A WebSocket connect that never opens gives up
    Given an atServer address whose WebSocket never opens
    When a browser lookup runs a command
    Then the command fails with SecondaryConnectException once the connect timeout passes

  Scenario: An oversized atDirectory answer is refused
    Given an atDirectory that answers with more than the bound
    When a browser lookup asks it where the atSign's atServer is
    Then the lookup fails without reading the rest, and the error does not echo the answer

  Scenario: A WebSocket holding too much unread closes
    Given a browser lookup whose caller is not reading notifications
    When the atServer sends more than the bound
    Then the connection closes, a warning names the bound, and the next command reconnects
