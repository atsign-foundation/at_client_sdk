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

  Scenario: otp requests and returns a passcode
    Given an open session with __manage rw access
    When otp is called
    Then one otp:get is sent and the passcode is returned

  Scenario: pendingEnrollments lists pending requests and empty when none
    Given an open session with __manage rw access
    When pendingEnrollments is called with pending requests and with none
    Then it returns each pending request as filed and an empty list when none are pending

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

  Scenario: concurrent approve or deny on the same id rejects without sending a second approval
    Given a pending enrollment e1 whose approval is still in flight
    When another approve or deny for e1 is called concurrently
    Then the second call rejects with enrollment_denied
    And only one enroll:approve or enroll:deny is sent

  Scenario: key conveyance failure rejects with enrollment_conveyance_failed
    Given a pending enrollment e1 whose key conveyance fails after server approval
    When approve is called with e1
    Then it rejects with code enrollment_conveyance_failed rather than enrollment_denied
