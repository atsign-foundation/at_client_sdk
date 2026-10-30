Feature: at_register's exit code says how registration ended

  at_register registers a free atSign to an email address and then activates
  it. A script reads its exit code to learn which way it ended.

  Races: none arise; the code is set after the flow has ended.
  Replay: none arise; no request or answer changes.
  DoS: none arise; no request is added, and one prompt goes.
  Forgery and impersonation: none arise; nothing sent or accepted changes.

  Scenario: An activation that fails after registration exits non-zero
    Given a registrar that registers an atSign and hands over its CRAM secret
    And a keyfile for that atSign already exists
    When at_register runs
    Then it exits 1, as at_activate does for the same failure

  Scenario: Three refused verification codes exit 5
    Given a registrar that refuses every verification code
    When at_register is given three codes
    Then it says the maximum number of verification attempts was reached
    And it asks for no fourth code
    And it exits 5
