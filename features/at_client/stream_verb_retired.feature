Feature: The client SDK no longer uses the stream verb

  From atServer 3.12.0 the stream: command at_client sent is refused as an
  unknown verb. at_client 4.0.0 has no AtClient.stream or
  AtClient.sendStreamAck.

  Races: nothing is sent, read or stored, so there is nothing to race.
  Replay: no stream command or acknowledgement is sent, so none can be
  captured and resent.
  DoS: no stream connection is opened; the path that opened its own socket to
  the atServer is gone.
  Forgery and impersonation: the client no longer decrypts bytes a stream
  notification's fields point it at, and at_lookup no longer takes a stream:
  line as an atServer's reply.

  Scenario: at_lookup takes a response starting stream: as unexpected
    Given a connection to an atServer
    When the atServer answers a command with a line starting stream:
    Then the client refuses it as an unexpected response (AT0014), as it does any line that is not data:, error: or the handshake's @<atSign>@
