Feature: An approving device enrolls another browser

  otp, pendingEnrollments, approve and deny need a session with the __manage
  access. A browser enrolls with the code otp issued; the approving device
  approves the request exactly as filed.

  Races: approve and deny read the pending list first, so an id that is no
  longer pending is refused before any verb is sent.
  Replay: an enrollment id that is not pending cannot be approved or denied
  again.
  DoS: none arise; each call is one request, and a refused enrollment ends.
  Forgery: approve sends the id alone, so the approver cannot widen the
  namespaces the new browser asked for.
  Impersonation: a session without __manage cannot issue codes or decide
  requests; it rejects unsupported.

  Scenario: otp, pendingEnrollments, approve and deny reach the bridge
    Given an open client whose session holds __manage
    When otp, pendingEnrollments, approve and deny are called
    Then each reaches the bridge, with the ids passed on
    And pendingEnrollments returns the requests as { id, appName, deviceName, namespaces }

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

  Scenario: a denied enrollment throws and maps to enrollment_denied
    Given a browser enrolling with a one-time code
    When the approving device denies the request
    Then enroll rejects with code enrollment_denied
    And no login was made and no record was stored
