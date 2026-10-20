Feature: The client SDK no longer uses the stream verb

  From atServer 3.12.0 the stream: command at_client sent is refused as an
  unknown verb. at_client keeps AtClient.stream and AtClient.sendStreamAck,
  deprecated, until v4, but they no longer contact an atServer.

  Races: nothing is sent, read or stored, so there is nothing to race.
  Replay: no stream command or acknowledgement is sent, so none can be
  captured and resent.
  DoS: no stream connection is opened; the path that opened its own socket to
  the atServer is gone.
  Forgery and impersonation: the client no longer decrypts bytes a stream
  notification's fields point it at, and at_lookup no longer takes a stream:
  line as an atServer's reply.

  Scenario: AtClient.stream fails at once, sending nothing
    Given an AtClient
    When an app calls the deprecated AtClient.stream
    Then it throws an UnsupportedError saying atServers no longer support the stream verb
    And nothing is sent to the atServer

  Scenario: AtClient.sendStreamAck fails at once, connecting to nothing
    Given an AtClient
    When an app calls the deprecated AtClient.sendStreamAck
    Then it throws an UnsupportedError saying atServers no longer support the stream verb
    And no connection is opened

  Scenario: at_lookup takes a response starting stream: as unexpected
    Given a connection to an atServer
    When the atServer answers a command with a line starting stream:
    Then the client refuses it as an unexpected response (AT0014), as it does any line that is not data:, error: or the handshake's @<atSign>@
