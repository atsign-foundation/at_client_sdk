Feature: A notification connection the atServer does not let in is retried less often

  A client listening for notifications reconnects when its connection drops.
  When the atServer answers an attempt without letting the client in, the
  client tries less often: a refusal can clear (an enrollment can be
  unrevoked or approved), and so can an atServer that fails to process the
  request, is paused, or is at its connection limit. So the client never
  stops trying. It says the connection was refused, and why, only when the
  atServer refused the credentials; any other answer leaves the connection
  state as it was.

  Races: a stop or a restart landing while a failed attempt is handled ends
  that attempt as a stop does; a refusal heard on a verb and on the
  notification connection at once is one change of connection state; a
  refusal that arrives after the connection has recovered is not reported.
  Replay: no value crosses attempts; each attempt answers a new challenge.
  DoS: a device whose atServer keeps answering its notification connection
  without letting it in settles at one attempt every 5 minutes, not one every
  34 seconds for as long as it runs. An atServer that cannot be reached is
  retried every 34 seconds. Sync's own attempts are unchanged.
  Forgery: an answer comes from the atServer this client reached over TLS, or
  from this client's own authenticator when it has no credential to offer or
  will not sign the challenge it was sent; a party able to forge either holds
  the atServer or the device, more than this denies, and the answer only
  slows reconnecting, never ends it.
  Impersonation: the answer changes only this client's own attempts and lets
  no one act as the atSign.

  Scenario Outline: a notification reconnect the atServer refuses as <cause> is retried less often
    Given a client of @alice listening for notifications
    And the atServer answers each connection from that client with <code>
    When the notification connection drops
    Then the client keeps trying, waiting longer after each refusal, up to 5 minutes between attempts
    And the client's connection is refused, with cause <cause>

    Examples:
      | code   | cause                 |
      | AT0027 | revoked               |
      | AT0025 | enrollmentDenied      |
      | AT0029 | invalidEnrollment     |
      | AT0026 | enrollmentNotApproved |
      | AT0401 | unauthenticated       |

  Scenario Outline: a notification start the atServer refuses as <cause> is retried less often
    Given a client of @alice whose connections the atServer answers with <code>
    When the client starts listening for notifications
    Then the client keeps trying, waiting longer after each refusal, up to 5 minutes between attempts
    And the client's connection is refused, with cause <cause>

    Examples:
      | code   | cause                 |
      | AT0027 | revoked               |
      | AT0025 | enrollmentDenied      |
      | AT0029 | invalidEnrollment     |
      | AT0026 | enrollmentNotApproved |
      | AT0401 | unauthenticated       |

  Scenario Outline: a notification reconnect the atServer answers with <answer> is retried less often, leaving the connection state as it was
    Given a client of @alice listening for notifications
    And the atServer answers each connection from that client with <answer>
    When the notification connection drops
    Then the client keeps trying, waiting longer after each such answer, up to 5 minutes between attempts
    And the client's connection state is as it was before the drop

    Examples:
      | answer                                    |
      | AT0011                                    |
      | a code this build does not know           |
      | no challenge to sign                      |

  Scenario Outline: a notification start the atServer answers with <answer> is retried less often, leaving the connection state as it was
    Given a client of @alice whose connections the atServer answers with <answer>
    When the client starts listening for notifications
    Then the client keeps trying, waiting longer after each such answer, up to 5 minutes between attempts
    And the client's connection state is as it was before the start

    Examples:
      | answer                                    |
      | AT0011                                    |
      | a code this build does not know           |
      | no challenge to sign                      |

  Scenario: an app keeps its notifications through a refusal that clears
    Given an app subscribed to @alice's notifications
    And the atServer refuses the client's notification reconnect
    When the atServer accepts that client's connection again
    Then the app's existing subscription receives the next notification for @alice
    And the client's connection is online

  Scenario: a program reading notifications keeps receiving through a refusal
    Given a program reading @alice's notifications in an await for loop
    And the atServer refuses the notification reconnect
    When the atServer accepts that connection again
    Then the program's loop receives the next notification for @alice

  Scenario: a dropped notification connection to an unreachable atServer is retried as before
    Given a client of @alice listening for notifications
    When the notification connection drops and the atServer cannot be reached
    Then the client keeps trying, up to 34 seconds between attempts
    And once the atServer answers, the client listens again
