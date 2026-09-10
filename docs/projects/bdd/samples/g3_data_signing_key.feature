# DRAFT from the 2026-09-02 feasibility sample, not a catalogue artefact.
# Translated by hand from docs/projects/pq/acceptance.md to test whether the
# catalogue's rows fit Gherkin; nothing executes these. The clause maps and the
# friction each row exposed are in ../analysis.md section 6.

  # acceptance.md section 18.4 UC-G3.10
  @UC-G3.10 @in-process @live-owed @negative @security
  Scenario: A client with no post-quantum providers refuses an approval it would have to mint for, before it reaches the atServer
    Given "alice1" runs at a posture that configures no post-quantum providers
    And "alice2" has a pending enrolment request carrying a key package and no wrapped symmetric key
    When "alice1" is asked to approve "alice2"
    Then the approval is refused
    And no approval reached the atServer
    And "alice2"'s request is still pending
    And another approver can still approve "alice2"

  @UC-G3.10 @in-process @negative
  Scenario: The same client refuses the unanchored-enrollment sweep
    Given "alice1" runs at a posture that configures no post-quantum providers
    When "alice1" is asked directly to sweep unanchored enrolments
    Then the sweep is refused, naming the missing providers

  # acceptance.md section 18.4 UC-G3.10, third clause — the controls, and the ⚠️ "keys on the missing wrapped key"
  @UC-G3.10 @in-process @control
  Scenario Outline: The refusal is about the posture and the missing wrapped key, not the fixture
    Given "alice1" runs at <posture>
    And "alice2" has a pending enrolment request <request>
    When "alice1" is asked to approve "alice2"
    Then the approval succeeds
    Examples:
      | posture                                             | request                                             |
      | a posture that configures no post-quantum providers | carrying its own wrapped symmetric key              |
      | a PQ-capable posture                                | carrying a key package and no wrapped symmetric key |
