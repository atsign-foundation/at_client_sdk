Feature: A session checks manage access from its own enrollment record

  Before otp, pendingEnrollments, approve or deny, a session reads its own
  enrollment record with one enroll:fetch for its enrollment id and allows
  the call only when that record is approved and grants __manage read-write.
  The primary enrollment, whose *:rw limits nothing, is allowed with no
  server call. A missing record or an atServer refusal means the session lacks
  manage access; any other failure reaches the caller unchanged.

  Races: none arise beyond the one decision per enrollment id that pairing.feature
  states; the check reads once and changes nothing.
  Replay: none arise; nothing sent or accepted changes.
  DoS: none arise; one record read, named by the session's own enrollment id.
  Forgery and impersonation: none arise; the check selects the record by the
  session's own enrollment id and the atServer stays the authority on every
  operation.

  Scenario: A session whose approved enrollment holds __manage read-write is allowed
    Given a session whose own enrollment is approved and granted {wavi: rw, __manage: rw, *: r}
    When it checks manage access
    Then the call is allowed
    And one enroll:fetch is sent for the session's own enrollment id

  Scenario: The primary enrollment is allowed with no server call
    Given a session with no enrollment id, or the primary one
    When it checks manage access
    Then the call is allowed
    And no enroll:fetch and no enroll:list is sent

  Scenario: An enrollment the atServer does not list is refused with ManageAccessRequiredException
    Given a session whose enrollment id the atServer holds no record for
    When it checks manage access
    Then it throws ManageAccessRequiredException

  Scenario: Only an approved enrollment is allowed, whatever it grants
    Given a session whose own enrollment holds __manage rw in each status: pending, approved, denied, revoked and expired
    When it checks manage access
    Then only the approved one is allowed
    And every other status throws ManageAccessRequiredException

  Scenario: A refusal reading the record is refused as lacking manage access
    Given a session whose enroll:fetch is refused by the atServer
    When it checks manage access
    Then it throws ManageAccessRequiredException, not the refusal

  Scenario: A transport failure reading the record reaches the caller unchanged
    Given a session whose enroll:fetch fails with an error that is not a missing record
    When it checks manage access
    Then that error is thrown, not ManageAccessRequiredException
