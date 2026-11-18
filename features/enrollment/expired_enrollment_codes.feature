Feature: A client reads AT0028 and AT0029 alike as its own enrollment expired

  An atServer refuses a PKAM for an enrollment that has expired, or that it
  no longer holds, with AT0028 today, and with AT0029 once it knows the client
  reads it. The client takes either code, in any form, as expiry wherever it
  meets a PKAM refusal: at_auth's enrollment wait throws
  AtEnrollmentExpiredException, an AtEnrollmentException that at_client
  re-exports, PendingEnrollment removes the request's pending keys, and a
  running client reports its connection refused with cause invalidEnrollment.
  AT0028 in reply to any other verb is a throttle, or names another
  enrollment, and changes nothing about the connection.

  Races: the wait polls one PKAM at a time; an expiry racing a stop or a
  cancel resolves as pending_enrollment_cancel.feature says.
  Replay: none arises; an error code carries no secret or freshness.
  DoS: the wait now ends on the first AT0029, where it used to poll until
  its retry budget ran out, so it sends fewer requests, never more.
  Forgery and impersonation: only the client's own atServer can send the
  code, and it already decides whether the enrollment stands, so a forged
  expiry gains it nothing.

  Scenario Outline: The enrollment wait ends as expired on <code>
    Given an app waiting for its enrollment request to be approved
    When the atServer refuses the wait's PKAM with <code>, in the <form> form
    Then the wait throws AtEnrollmentExpiredException carrying the atServer's text, which an AtEnrollmentException catch also catches, and polls no more

    Examples:
      | code   | form  |
      | AT0028 | colon |
      | AT0029 | colon |
      | AT0029 | JSON  |

  Scenario Outline: A running client whose enrollment expired reports it as invalidEnrollment
    Given a client of an enrollment that has since expired
    When its connection's PKAM is refused with <code>
    Then the connection state is refused, with cause invalidEnrollment

    Examples:
      | code   |
      | AT0028 |
      | AT0029 |

  Scenario: An AT0028 reply to a verb leaves the connection online
    Given a client authenticated as an approved enrollment
    When the atServer answers one of its verbs with AT0028
    Then the connection state stays online
