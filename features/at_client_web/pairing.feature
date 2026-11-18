Feature: An approving device enrolls another browser

  otp, pendingEnrollments, approve and deny need a session with the __manage
  access. The approving device approves a request exactly as filed.

  Scenario: each call rejects with unsupported without __manage
    Given an open session without the __manage access
    When otp, pendingEnrollments, approve or deny is called
    Then each rejects with code unsupported

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
