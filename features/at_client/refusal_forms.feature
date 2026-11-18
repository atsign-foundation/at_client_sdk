Feature: A refusal reads the same whichever form the atServer writes it in

  An atServer writes a refusal's code as error:<code>-<text>,
  error:<code>:<text> or JSON, depending on the path that refused and on
  whether the connection's from: named a version. at_client acts on the code
  the same way in every form: in the enrollment wait, the expired-request
  cleanup and the connection state it reports.

  Races: none arise; each refusal is read on the connection it arrived on.
  Replay: none arise; a refusal carries no secret and no freshness.
  DoS: none arise; no retry or work is added, and a refusal that names no
  code is handled as one that names an unknown code.
  Forgery and impersonation: the refusal comes from the client's own atServer
  over TLS; reading its code the same way in every form grants nothing.

  Scenario: A refusal reads the same in either error form
    Given an atServer that answers an at_client connection's from: with version
    When it refuses on that connection with error:{"errorCode":...}
    Then the client handles the refusal as it does error:<code>-<text>

  Scenario: A verb refused because the enrollment was revoked reports the connection refused
    Given an at_client connection whose enrollment the atServer has since revoked
    When the client sends a verb and the atServer answers error:AT0027:<text>
    Then the client's connection state is refused, with cause revoked
