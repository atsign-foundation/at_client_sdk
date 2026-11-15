Feature: A notification connection the atServer refuses is retried less often

  A client listening for notifications reconnects when its connection drops.
  A refusal can clear: an enrollment can be unrevoked or approved, and an
  atServer can refuse once and then accept. So the client never stops trying;
  after a refusal it tries less often, and says the connection was refused
  and why.

  Races: a stop or a restart landing while a refused attempt is handled ends
  that attempt as a stop does today; a refusal heard on a verb and on the
  notification connection at once is one change of connection state.
  Replay: no value crosses attempts; each attempt is a new connection
  answering a new challenge.
  DoS: today a refused device authenticates every 34 seconds for as long as it
  runs; after the change it settles at one attempt every 5 minutes.
  Forgery: only the atServer this client authenticated to over TLS can give
  the refusal; a party able to forge it there holds more than this denies,
  and a refusal now only slows reconnecting, never ends it.
  Impersonation: the refusal changes only this client's own attempts and lets
  no one act as the atSign.

  Scenario Outline: a notification reconnect the atServer refuses as <cause> is retried less often
    Given a client of @alice listening for notifications
    And the atServer answers each connection from that client with <code>
    When the notification connection drops
    Then the client keeps trying, waiting longer after each refusal, up to 5 minutes between attempts
    And the client's connection is refused, with cause <cause>

    Examples:
      | code                                                           | cause                 |
      | AT0027                                                         | revoked               |
      | AT0025                                                         | enrollmentDenied      |
      | AT0029                                                         | invalidEnrollment     |
      | AT0026                                                         | enrollmentNotApproved |
      | AT0401                                                         | unauthenticated       |
      | an authentication refusal with a code this build does not know | unauthenticated       |

  Scenario Outline: a notification start the atServer refuses as <cause> is retried less often
    Given a client of @alice whose connections the atServer answers with <code>
    When the client starts listening for notifications
    Then the client keeps trying, waiting longer after each refusal, up to 5 minutes between attempts
    And the client's connection is refused, with cause <cause>

    Examples:
      | code                                                           | cause                 |
      | AT0027                                                         | revoked               |
      | AT0025                                                         | enrollmentDenied      |
      | AT0029                                                         | invalidEnrollment     |
      | AT0026                                                         | enrollmentNotApproved |
      | AT0401                                                         | unauthenticated       |
      | an authentication refusal with a code this build does not know | unauthenticated       |

  Scenario: an app keeps its notifications through a refusal that clears
    Given an app subscribed to @alice's notifications
    And the atServer refuses the client's notification reconnect
    When the atServer accepts that client's connection again
    Then the app's existing subscription receives the next notification for @alice
    And the client's connection is online

  Scenario: a dropped notification connection to an unreachable atServer is retried as before
    Given a client of @alice listening for notifications
    When the notification connection drops and the atServer cannot be reached
    Then the client keeps trying, up to 34 seconds between attempts
    And once the atServer answers, the client listens again
