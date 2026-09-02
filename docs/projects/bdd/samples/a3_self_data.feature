# DRAFT from the 2026-09-02 feasibility sample, not a catalogue artefact.
# Translated by hand from docs/projects/pq/acceptance.md to test whether the
# catalogue's rows fit Gherkin; nothing executes these. The clause maps and the
# friction each row exposed are in ../analysis.md section 6.

  # acceptance.md section 4.3 UC-A3.3 — the headline Then (not a parser clause today)
  @UC-A3.3 @live @negative
  Scenario: A self write into a namespace with no namespace key is refused by name
    Given "@alice" has no namespace key for "cold.my_apps"
    And "alice1" has not opted in to the legacy fallback
    When "alice1" writes self data into "cold.my_apps"
    Then the write is refused
    And the refusal names the namespace "cold.my_apps"
    And the refusal is not a generic encryption error
    And "alice1" can ask beforehand whether "cold.my_apps" is ready, and the answer is no

  # acceptance.md section 4.3 UC-A3.3, first sub-bullet
  @UC-A3.3 @live @happy @control
  Scenario: With the legacy fallback opted in, the write goes legacy until the key exists, and then only new writes move
    Given "@alice" has no namespace key for "cold.my_apps"
    And "alice1" has opted in to the legacy fallback
    When "alice1" writes "first" into "cold.my_apps"
    Then "first" is stored legacy
    When "@alice" gains a namespace key for "cold.my_apps"
    And "alice1" writes "second" into "cold.my_apps"
    Then "second" is stored on the PQ data path
    And "first" is still stored legacy and still readable

  # acceptance.md section 4.3 UC-A3.3, second sub-bullet — why the cold start is rare
  @UC-A3.3 @in-process @live-exempt @assumption
  Scenario: A client seeds a namespace key for every namespace its enrollment grants, at start
    Given "alice1" is an enrollment of "@alice" granted "app_1.my_apps"
    When "alice1" starts
    Then "@alice" has a namespace key for "app_1.my_apps" before "alice1"'s first write
