# DRAFT from the 2026-09-02 feasibility sample, not a catalogue artefact.
# Translated by hand from docs/projects/pq/acceptance.md to test whether the
# catalogue's rows fit Gherkin; nothing executes these. The clause maps and the
# friction each row exposed are in ../analysis.md section 6.

  # acceptance.md section 17.9 UC-G2.9 — first clause: what the verifier does today
  @UC-G2.9 @in-process @live-exempt @security @limitation
  Scenario: A verifier cannot decline an algorithm it implements
    Given "alice1" signs envelopes under both "mldsa65" and "rsa2048"
    And a verifier holds an advertisement of "alice1" that names only "rsa2048"
    When the verifier verifies an envelope carrying both signatures
    Then verification succeeds under "rsa2048"

  # acceptance.md section 17.9 UC-G2.9 — second clause
  @UC-G2.9 @in-process @live-exempt @negative
  Scenario: A verifier sharing no algorithm with the envelope is refused, not rescued
    Given "alice1" advertises only an "rsa2048" signing key
    And an envelope signed by "alice1" carries only an "mldsa65" signature
    When a verifier verifies the envelope against that advertisement
    Then verification is refused
    And the refusal names the algorithms the envelope carries
    And the refusal names the algorithms the advertisement offers
    And no key derived any other way is tried

  # acceptance.md section 17.9 UC-G2.9 — third clause. Unprovable as written (manifest.dart unprovableClauses):
  # building the lever falsifies it; pinning the absence counts a hole as proven. Guarded by
  # architecture_guard_test.dart 'the verifier has no accept lever for signatures' — a tripwire, not proof.
  @UC-G2.9 @unprovable @limitation
  Scenario: Closing the gap needs a lever that does not exist
    Given a verifier that wishes to accept signatures only under algorithms it chooses
    Then it has no way to say so
