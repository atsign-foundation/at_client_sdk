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

  Scenario: A third code accepted with a follow-up gets the CRAM key
    Given a registrar that refuses two codes and accepts the third with a follow-up
    When at_register is given three codes
    Then it sends the third code again as a confirmation
    And it gets the CRAM key

  Scenario: A registrar asking twice to confirm a code ends the registration
    Given a registrar that answers every code with a follow-up
    When at_register is given a code
    Then it sends two validate-person requests, no more
    And it exits 4

  Scenario: Three refused verification codes exit 5
    Given a registrar that refuses every verification code
    When at_register is given three codes
    Then it says the maximum number of verification attempts was reached
    And it asks for no fourth code
    And it exits 5
