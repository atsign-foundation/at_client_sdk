# DRAFT from the 2026-09-02 feasibility sample, not a catalogue artefact.
# Translated by hand from docs/projects/pq/acceptance.md to test whether the
# catalogue's rows fit Gherkin; nothing executes these. The clause maps and the
# friction each row exposed are in ../analysis.md section 6.

  # acceptance.md section 16.2 UC-G1.2
  @UC-G1.2 @in-process @live-owed @happy
  Scenario: A retrofit leaves exactly one active authentication key and touches nothing legacy
    Given "alice1" holds a legacy keyfile for "@alice"
    When "alice1" retrofits itself to a PQ authentication key
    Then the keyfile holds the new APKAM material as active under the new enrollment id
    And that is the only active authentication key in the keyfile
    And the legacy APKAM keypair is still in the keyfile's flat fields, byte-identical
    And the legacy APKAM keypair carries no status
    And the keyfile's resolver answers the new enrollment id
