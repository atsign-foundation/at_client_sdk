Feature: A server error in reply to a PKAM is not a refusal

  An atServer refuses the credentials a pkam: carries with AT0401, AT0025,
  AT0026, AT0027, AT0028 or AT0029. Any other code it answers a pkam: with,
  such as AT0011 when it fails to process the request, says nothing about the
  credentials, and at_client reads it, in any form, as a failure that is not a
  refusal: the connection is not refused, a first open hands back its client,
  and the error reaches the caller as it is. A reply that carries no code is
  read as a refusal, as it is today. A cram: reply is read the same way, since
  at_auth raises both alike.

  Races: none arise; each reply is read on the connection it arrived on.
  Replay: none arises; an error code carries no secret and no freshness.
  DoS: a server error can now be retried where a refusal was not, by the
  app's own awaitOnline within its budget and by the verbs the client sends
  anyway; no retry is added.
  Forgery and impersonation: only the client's own atServer writes the code,
  over TLS, and it already decides whether the credentials stand. Reading a
  server error as not a refusal grants nothing: the connection is still not
  authenticated.

  Scenario Outline: A server error in reply to a connection's PKAM leaves it offline, not refused
    Given a client of an approved enrollment of @alice🛠
    When the atServer answers its connection's PKAM with AT0011, in the <form> form
    Then the connection state is offline, carrying that error

    Examples:
      | form  |
      | dash  |
      | colon |
      | JSON  |

  Scenario: A first open whose PKAM gets a server error hands back its client
    Given a device where @alice🛠's keys have never been online
    When the app opens @alice🛠 and the atServer answers the PKAM with AT0011
    Then open hands back a client whose connection state is offline, carrying that error

  Scenario: Checking which enrollment keys authenticate as throws a server error as it is
    Given keys for an enrollment of @alice🛠
    When the app calls authenticatesAs and the atServer answers the PKAM with AT0011
    Then that error propagates as it is, and no AtCredentialRefusedException is thrown

  Scenario: A verb whose PKAM gets a server error leaves the connection state as it was
    Given a client of @alice🛠 whose connection state is online
    When a verb's PKAM on a new connection is answered with AT0011
    Then the verb throws, and the connection state is still online

  Scenario Outline: A refusal code in reply to a PKAM still refuses
    When the atServer answers a connection's PKAM with <code>
    Then the connection state is refused, with cause <cause>

    Examples:
      | code    | cause                 |
      | AT0401  | unauthenticated       |
      | AT0025  | enrollmentDenied      |
      | AT0026  | enrollmentNotApproved |
      | AT0027  | revoked               |
      | AT0028  | invalidEnrollment     |
      | AT0029  | invalidEnrollment     |
      | no code | unauthenticated       |
