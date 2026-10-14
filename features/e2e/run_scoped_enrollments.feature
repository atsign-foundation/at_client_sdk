Feature: The e2e pack's enrollments on the long-lived @ce2e atSigns belong to the run that made them
  end2end_test_14 enrolls one app per atSign on @ce2e1..@ce2e4, which every
  at_client_sdk workflow run shares and none recycles. No run denies or
  revokes an enrollment: each one is retired by its own expiry on the
  atServer.

  @race: overlapping runs; the first two scenarios.
  @replay: nothing reads another run's record.
  @dos: nothing lists or acts on the enrollment roster.
  @forgery: an appName labels an enrollment and never authorises anything.
  @impersonation: every verb runs as the atSign's own key, on that atSign's
    own connection.

  @race
  Scenario: Another run finishing does not revoke this run's approved enrollment
    Given run A's enrollment_setup.dart has approved enrollment E_A on @ce2e1
    And run A's suite is still running as E_A
    When run B's end2end_test_14 finishes
    Then enroll:fetch of E_A on @ce2e1 answers status "approved"
    And run A's next authentication as E_A succeeds

  @race
  Scenario: Another run finishing does not deny this run's pending enrollment
    Given run A has submitted enrollment E_A on @ce2e1 and not yet approved it
    When run B's end2end_test_14 finishes
    Then run A's approval of E_A succeeds

  Scenario: Every enrollment the setup approves is one the atServer retires by itself
    Given enrollment_setup.dart has approved enrollment E on an atSign
    When it fetches E with enroll:fetch
    Then E's expiresAt is set and no later than 3 hours after the approval
    And otherwise the setup step fails naming the atSign and E

  Scenario: An enrollment names the run that created it
    Given GITHUB_RUN_ID is 38415451898 and GITHUB_RUN_ATTEMPT is 2
    When enrollment_setup.dart submits an enrollment on @ce2e1
    Then the enrollment's appName begins "wavi-38415451898-2-"

  Scenario: A setup that leaves an atSign without an enrollment fails its step
    Given enrollment_setup.dart did not complete the enrollment on @ce2e2
    When its tearDownAll ends the process
    Then the process exits 1 naming @ce2e2

  Scenario: The job leaves its enrollments to expire
    Given run A's enrollment_setup.dart approved enrollment E_A on @ce2e1
    When run A's end2end_test_14 job ends
    Then no step in the job denies or revokes any enrollment

  Scenario: A client that never opened leaves notify_with_isolate's tearDown silent
    Given notify_with_isolate_test.dart failed before @ce2e4's client created test/hive/@ce2e4
    When its tearDown runs
    Then it raises no PathNotFoundException
    And the test reports only the failure that stopped it
