# DRAFT from the 2026-09-02 feasibility sample, not a catalogue artefact.
# Translated by hand from docs/projects/pq/acceptance.md to test whether the
# catalogue's rows fit Gherkin; nothing executes these. The clause maps and the
# friction each row exposed are in ../analysis.md section 6.

  # acceptance.md section 12.6 UC-B5.6 — the interlock IS the atServer refusing a second create of an immutable
  # record; a mocked executeVerb accepts the second take, so only a live run can find it.
  @UC-B5.6 @live @negative @security
  Scenario: A rotation inside the cooldown is refused, and the same call succeeds after it
    Given the mint lock ttl is "5 seconds"
    And "alice1" minted "@alice"'s namespace key for "cool.my_apps" a moment ago
    When "alice1" asks to rotate "cool.my_apps"
    Then the rotation is refused
    And the refusal says the mint lock is held
    And the refusal says to retry once the ttl elapses
    When the mint lock ttl has elapsed
    And "alice1" asks to rotate "cool.my_apps" again
    Then the rotation succeeds

  # acceptance.md section 12.6 UC-B5.6, the ⚠️ half — what revokeEnrollmentAndRotate does around a refused rotate
  @UC-B5.6 @in-process @live-exempt @negative
  Scenario: Revoke-and-rotate revokes first, and one namespace refusing to rotate does not abandon the rest
    Given "alice3" is an enrollment of "@alice" holding namespace keys for "a.my_apps" and "b.my_apps"
    And "b.my_apps" is inside its mint-lock cooldown
    When "alice1" revokes "alice3" and rotates every namespace it held
    Then "alice3" is revoked before any rotation is attempted
    And "a.my_apps" is rotated
    And the failure to rotate "b.my_apps" is logged at severe, naming "b.my_apps"
    And the call does not wait for the cooldown
