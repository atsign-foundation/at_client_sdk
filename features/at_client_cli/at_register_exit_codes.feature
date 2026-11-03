Feature: at_register's exit code says how registration ended

  at_register registers a free atSign to an email address and then activates
  it. A script reads its exit code to learn which way it ended.

  When the registrar accepts a code with a follow-up, at_register confirms it at
  once by sending that code again, and a refused confirmation sends the next
  code typed as a fresh code, not as a confirmation.

  Races: none arise; the code is set after the flow has ended.
  Replay: bounded; a confirmation re-sends only the code the registrar has just
  accepted, so nothing the registrar did not already take is replayed.
  DoS: bounded; each code costs at most two validate-person requests, one code
  and one confirmation, and at most three codes are asked for, so a registrar
  that keeps asking for confirmation gets at most six requests.
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

  Scenario: A code typed after a refused confirmation is confirmed in its turn
    Given a registrar that accepts a code with a follow-up
    And it refuses that code's confirmation as expired
    And it accepts the next code typed with a follow-up
    When at_register is given two codes
    Then it sends the second code as a fresh code, not as a confirmation
    And it sends the second code again as a confirmation
    And it gets the CRAM key

  Scenario: Three refused verification codes exit 5
    Given a registrar that refuses every verification code
    When at_register is given three codes
    Then it says the maximum number of verification attempts was reached
    And it asks for no fourth code
    And it exits 5
