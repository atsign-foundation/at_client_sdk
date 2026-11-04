Feature: A registrar request is logged without its body

  at_activate's --debug logs each request it makes to the registrar. It logs
  the request's address and the response's status, and never a request or
  response body, which carry the one-time code and the CRAM secret.

  Races: none arise; logging reads what the request already holds.
  Replay: none arise; nothing sent or accepted changes.
  DoS: none arise; each request writes the same two log lines as before.
  Forgery and impersonation: none arise; no request or answer changes.

  Scenario: A registrar request is logged without its body
    Given a registrar that answers a CRAM request
    When at_activate fetches the CRAM secret with logging at its finest
    Then a log line names the response's status
    And no log line holds the one-time code or the CRAM secret
