# DRAFT from the 2026-09-02 feasibility sample, not a catalogue artefact.
# Translated by hand from docs/projects/pq/acceptance.md to test whether the
# catalogue's rows fit Gherkin; nothing executes these. The clause maps and the
# friction each row exposed are in ../analysis.md section 6.

Feature: A5 · Rotation & revocation (new world)
  Two distinct levers, never conflated: rotating the content key is the cheap
  forward-secrecy lever; rotating the namespace keypair is the expensive
  revocation and post-compromise lever.

  Rule: Rotating the content key is the forward-secrecy lever

    # acceptance.md section 6.1 UC-A5.1 Then (a)
    @UC-A5.1 @UC-A5.1a @live @security
    Scenario: Deleting the superseded content key's conveyance makes its era unreadable
      Given "@alice" has a namespace key for "app_1.my_apps"
      And "alice1" wrote "early" into "app_1.my_apps" and can read it back
      When "alice1" rotates the content key for "app_1.my_apps" and deletes the superseded conveyance
      And "alice1" writes "later" into "app_1.my_apps"
      Then "alice1" can no longer read "early"
      And "alice1" still holds the namespace key private for "app_1.my_apps"
      And "alice1" can read "later"

    # acceptance.md section 6.1 UC-A5.1 Then (a) — "Retaining the old conveyance instead = history access"
    @UC-A5.1 @UC-A5.1a @live @control
    Scenario: Rotating without the delete keeps the era readable — the default
      Given "@alice" has a namespace key for "app_1.my_apps"
      And "alice1" wrote "retained" into "app_1.my_apps"
      When "alice1" rotates the content key for "app_1.my_apps"
      Then new writes into "app_1.my_apps" use a different content key
      And "alice1" can still read "retained"

  Rule: Rotating the namespace keypair is the revocation and post-compromise lever

    # acceptance.md section 6.1 UC-A5.1 Then (b)
    @UC-A5.1 @UC-A5.1b @live @security
    Scenario: A namespace-key rotation excludes a revoked enrollment from the new generation
      Given "@alice" has a namespace key for "app_1.my_apps"
      And "alice1", "alice2" and "alice3" are enrollments of "@alice" holding it
      And "alice1" wrote "before" into "app_1.my_apps"
      When "alice1" rotates the namespace key for "app_1.my_apps" excluding "alice3"
      And "alice1" writes "after" into "app_1.my_apps"
      Then "@alice"'s published namespace key for "app_1.my_apps" names the new generation
      And "alice2" holds the new generation's private
      And "alice3" does not hold the new generation's private
      And "alice1" and "alice2" still hold the superseded generation's private
      And "alice2" can still read "before"
      And the content key for "before" was sealed to the superseded generation
      And the content key for "after" is sealed to the new generation

    # acceptance.md section 6.1 UC-A5.1 Then (b) — "Without that re-fetch the revocation does not hold"
    @UC-A5.1 @UC-A5.1b @in-process @live-owed @security
    Scenario: A peer notices the rotation at its next check and seals to the successor
      Given "@bob" has conveyed a content key to "@alice"'s "app_1.my_apps" under the current generation
      When "@alice" rotates the namespace key for "app_1.my_apps"
      And "@bob" next checks "@alice"'s published namespace key
      Then "@bob" cuts a fresh content key sealed to the new generation
      And "@bob" stops sealing to the superseded generation

    # acceptance.md section 6.1 UC-A5.1 Then (b), late joiner
    @UC-A5.1 @UC-A5.1b @in-process @live-owed
    Scenario: A late joiner is pushed every generation its approver holds
      Given "@alice"'s namespace key for "app_1.my_apps" has two generations and "alice1" holds both
      When "alice4" is approved by "alice1" for an enrollment scoped to "app_1.my_apps"
      Then "alice4" holds both generations for "app_1.my_apps" without asking any holder
      And "alice4" holds nothing for a namespace it was not approved for

    @UC-A5.1 @UC-A5.1b @in-process @live-owed
    Scenario: A joiner the push missed pulls the generation it meets and does not hold
      Given "alice4" holds only the current generation for "app_1.my_apps"
      When "alice4" meets a retained record sealed under a generation it does not hold
      Then "alice4" pulls that generation from a holder and opens the record
