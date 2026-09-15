# DRAFT from the 2026-09-02 feasibility sample, not a catalogue artefact.
# Translated by hand from docs/projects/pq/acceptance.md to test whether the
# catalogue's rows fit Gherkin; nothing executes these. The clause maps and the
# friction each row exposed are in ../analysis.md section 6.

  # acceptance.md section 16.3 UC-G1.7
  @UC-G1.7 @in-process @live-owed @security @adversarial
  Scenario: A corrupted stronger signature is not rescued by a valid weaker one
    Given "alice1" advertises signing keys under both "rsa2048" and "mldsa65"
    And an envelope signed by "alice1" carries a valid "rsa2048" signature and a corrupted "mldsa65" signature
    When a verifier that implements "mldsa65" verifies the envelope
    Then verification is refused
    And the refusal names the "mldsa65" failure

  @UC-G1.7 @in-process @control
  Scenario: The control arm — both signatures valid — verifies
    Given "alice1" advertises signing keys under both "rsa2048" and "mldsa65"
    And an envelope signed by "alice1" carries valid "rsa2048" and "mldsa65" signatures
    When a verifier that implements "mldsa65" verifies the envelope
    Then verification succeeds

  # acceptance.md section 16.3 UC-G1.7 — from the ✅ paragraph, not from the clause
  @UC-G1.7 @in-process @security
  Scenario Outline: The verdict does not depend on the order the signatures are listed
    Given "alice1" advertises signing keys under both "rsa2048" and "mldsa65"
    And an envelope signed by "alice1" lists a corrupted "mldsa65" signature <position> the valid "rsa2048" one
    When a verifier that implements "mldsa65" verifies the envelope
    Then verification is refused
    Examples:
      | position |
      | before   |
      | after    |

  @UC-G1.7 @in-process @security @negative
  Scenario: An envelope whose signatures claim two different signers is refused at parse
    Given an envelope whose "rsa2048" and "mldsa65" signatures name different signers
    When any verifier reads the envelope
    Then it is refused before any signature is checked
