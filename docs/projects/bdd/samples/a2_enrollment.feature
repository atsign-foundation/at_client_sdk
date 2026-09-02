# DRAFT from the 2026-09-02 feasibility sample, not a catalogue artefact.
# Translated by hand from docs/projects/pq/acceptance.md to test whether the
# catalogue's rows fit Gherkin; nothing executes these. The clause maps and the
# friction each row exposed are in ../analysis.md section 6.

Feature: A2 · Enrollments (a new enrollment joins)
  Start state: "@alice" is PQ-native, its signing root is published, and
  "alice1" (E1) is online and fully privileged.   # acceptance.md:477

  Background:
    Given "@alice" is PQ-native with its signing root published
    And "alice1" is a fully privileged enrollment of "@alice" and is online

  # acceptance.md section 3.1 UC-A2.1
  @UC-A2.1 @live @happy @security
  Scenario: A scoped enrollment is approved with nothing RSA-wrapped and receives only what it is granted
    Given "@alice" has namespace keys for "app_1.my_apps" and "app_2.my_apps"
    When "alice2" is approved by "alice1" for an enrollment scoped to "app_1.my_apps"
    Then nothing conveyed to "alice2" during enrollment is RSA-wrapped
    And "alice2" authenticates with a PQ APKAM key
    And "alice2" holds the namespace key for "app_1.my_apps"
    And "alice2" does not hold the namespace key for "app_2.my_apps"
    And "alice2"'s key package is registered on its enrollment record
    And "alice2" does not hold "@alice"'s signing root private
    And "alice2"'s advertised signing key chains to "@alice"'s signing root
    And the chain link does not change what "alice2" advertises as its signing key
    And "alice2" reads "@alice"'s own data in "app_1.my_apps"
    And "alice2" is refused the key channel of "app_2.my_apps"
    And revoking "alice2" does not affect "alice1"

  # acceptance.md section 3.1 UC-A2.1, second clause — the differential the live test runs
  @UC-A2.1 @live @security @control
  Scenario Outline: The signing root private reaches only fully privileged enrollments
    When "alice3" is approved by "alice1" for an enrollment with <grants>
    Then "alice3" <holds> "@alice"'s signing root private
    Examples:
      | grants                        | holds         |
      | rw on * and rw on __manage    | holds         |
      | rw on app_1.my_apps only      | does not hold |
