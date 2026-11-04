Feature: A logged command leaves out its one-time code

  A lookup logs each command it sends, at finer. The passcode an otp:put sets
  and the otp an enroll: command carries are logged as ***, and every other
  command is logged as it is sent.

  Races: none arise; logging reads the command the lookup already holds.
  Replay: none arise; what is sent does not change.
  DoS: none arise; each command writes one log line, as before.
  Forgery and impersonation: none arise; no command or answer changes.

  Scenario: An otp:put command is logged without its passcode
    Given logging at its finest
    When a lookup sends otp:put with a passcode and a ttl
    Then the command is logged with *** for the passcode and its ttl intact
    And no log line holds the passcode

  Scenario: An enroll command is logged without its one-time code
    Given logging at its finest
    When a lookup sends enroll:request carrying an otp
    Then the command is logged with *** for the otp and the rest intact
    And no log line holds the otp

  Scenario: An enroll command an authenticator sends is logged without its one-time code
    Given logging at its finest
    When a lookup's authenticator sends enroll:request carrying an otp
    Then no log line holds the otp

  Scenario: Any other command is logged as it is sent
    Given logging at its finest
    When a lookup sends lookup:phone@bob
    Then the command is logged as it was sent
