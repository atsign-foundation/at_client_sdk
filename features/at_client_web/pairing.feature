Feature: An approving device enrolls another browser

  otp, pendingEnrollments, approve and deny need a session with the __manage
  access. The approving device approves a request exactly as filed.

  These scenarios describe the Dart bridge that @atsign/at_client_web wraps; the
  npm package turns {code, message} into AtError and the callbacks into async
  iterators, and specifies that in at_js.

  # Threats. Each answer names the scenario that holds it.
  #
  # Race: concurrent approve or deny calls for the same enrollment id are
  #   serialized by an in-flight guard so only one decision goes to the
  #   atServer ("concurrent approve or deny on the same id rejects without
  #   sending a second approval").
  # Replay: approving or denying a non-pending id is refused before sending
  #   enroll:approve or enroll:deny ("approve of an id that is not pending is
  #   enrollment_denied", "deny denies a pending request and rejects unknown id
  #   with enrollment_denied").
  # DoS: in-flight duplicate decisions are refused immediately without queuing
  #   redundant enroll:list / enroll:approve traffic ("concurrent approve or deny
  #   on the same id rejects without sending a second approval").
  # Forgery: approve refuses to widen namespaces beyond what was filed and
  #   reports key-package verification failures distinctly ("approves the request
  #   as filed, with no namespaces of its own", "key conveyance failure rejects
  #   with enrollment_conveyance_failed").
  # Impersonation: every pairing call requires the __manage rw grant ("each call
  #   rejects with unsupported without __manage").

  Scenario: each call rejects with unsupported without __manage
    Given an open session without the __manage access
    When otp, pendingEnrollments, approve or deny is called
    Then each rejects with code unsupported

  Scenario: a decision reads the session's own grants once
    Given an open session with __manage rw access
    When approve is called for a pending id
    Then the session's own enrollment record is read from the atServer once for that decision

  Scenario: the primary enrollment is authorised without listing enrollments
    Given an open session whose enrollment is the primary one, named primary or none
    When otp is called
    Then the call is authorised and the passcode is returned
    And no enroll:list is sent
    And no enroll:fetch is sent

  Scenario: otp requests and returns a passcode
    Given an open session with __manage rw access
    When otp is called
    Then one otp:get is sent and the passcode is returned

  Scenario: pendingEnrollments lists pending requests and empty when none
    Given an open session with __manage rw access
    When pendingEnrollments is called with pending requests and with none
    Then it returns each pending request as filed and an empty list when none are pending

  Scenario: a peer-chosen app or device name is bounded in pending enrollments
    Given a pending enrollment whose app and device names are very long and carry control characters
    When pendingEnrollments is called
    Then both names come back on one line, at most the rejection bound long
    And its id and namespaces are returned unchanged

  Scenario: approves the request as filed, with no namespaces of its own
    Given a pending enrollment e1
    When approve is called with e1
    Then one enroll:approve is sent naming enrollmentId e1
    And it carries no namespace

  Scenario: approve of an id that is not pending is enrollment_denied
    Given no pending enrollment has the id gone
    When approve is called with gone
    Then it rejects with code enrollment_denied
    And no enroll:approve is sent

  Scenario: deny denies a pending request and rejects unknown id with enrollment_denied
    Given an open session with __manage rw access and pending enrollment e1
    When deny is called with e1 and then with gone
    Then e1 sends one enroll:deny and gone rejects with enrollment_denied without sending

  @race
  Scenario: concurrent approve or deny on the same id rejects without sending a second approval
    Given a pending enrollment e1 whose approval is still in flight
    When another approve or deny for e1 is called concurrently
    Then the second call rejects with code enrollment_in_flight
    And only one enroll:approve or enroll:deny is sent
    And the second call sends no enroll:list

  Scenario: key conveyance failure rejects with enrollment_conveyance_failed
    Given a pending enrollment e1 whose key conveyance fails after server approval
    When approve is called with e1
    Then it rejects with code enrollment_conveyance_failed rather than enrollment_denied

  Scenario: the in-flight rejection names no atSign and no enrollment id
    Given a pending enrollment e1 whose approval is still in flight
    When another approve for e1 is called concurrently
    Then the rejection's message is fixed text that says a decision is already in flight
    And neither the message nor the Dart exception's text holds the session's atSign or e1

  @replay
  Scenario: a decision repeated after the first settled is enrollment_denied, not enrollment_in_flight
    Given an approve of e1 that has completed, so e1 is no longer pending
    When approve or deny is called with e1 again
    Then it rejects with code enrollment_denied
    And no enroll:approve or enroll:deny is sent

  @race
  Scenario: a decision in flight on one id does not hold up another id
    Given pending enrollments e1 and e2 and an approve of e1 still in flight
    When approve is called with e2
    Then e2 is approved without waiting for e1

  @race
  Scenario: a failed decision releases the id for another attempt
    Given an approve of e1 that failed while e1 stayed pending
    When approve is called with e1 again
    Then one more enroll:approve is sent and it is not rejected with enrollment_in_flight

  Scenario: the in-flight failure is still an enrollment failure to a Dart caller
    Given a session whose approve of e1 is still in flight
    When a Dart caller awaits a second approve of e1 and catches AtEnrollmentException
    Then the failure is caught
    And the bridge maps it to enrollment_in_flight ahead of enrollment_denied
