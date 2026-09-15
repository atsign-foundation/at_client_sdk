# DRAFT from the 2026-09-02 feasibility sample, not a catalogue artefact.
# Translated by hand from docs/projects/pq/acceptance.md to test whether the
# catalogue's rows fit Gherkin; nothing executes these. The clause maps and the
# friction each row exposed are in ../analysis.md section 6.

  # acceptance.md section 15.3 UC-C1.3 — WITHDRAWN 2026-08-12 by decisions.md 95 ruling 1: there is no envelope axis.
  # It read: given a client at PqPosture.pqActive, when any signer wraps a payload with no per-signer
  # version assigned, then the envelope goes out in the JWS (v2) shape. Every clause is void:
  # envelopeVersion is not a posture axis and there is one envelope shape. What replaced it is UC-G1.x.
  @UC-C1.3 @withdrawn
  Scenario: WITHDRAWN — there is no envelope axis
