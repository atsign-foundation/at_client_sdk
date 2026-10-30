Feature: Opening a client on a connection lost during authentication

  A connection lost while the client authenticates says nothing about its
  credentials. Opening authenticates on a fresh connection, and when that is
  lost too the client comes back offline, never refused.

  Races: the atServer closes the connection while the client reads its keys,
  the window between the connect and the first command.
  Replay: each connection answers its own challenge, and nothing sent for a
  lost connection goes on another.
  DoS: an open spends one fresh connection on the loss before coming back
  offline.
  Forgery and impersonation: a device does not count a lost connection as
  having been online, and a lost connection never reads as revoked or refused
  credentials.

  Scenario: An open whose connection is lost during authentication comes back online
    Given an atServer that closes the connection while the client reads its keys
    When the client opens
    Then it authenticates on a fresh connection and comes back online

  Scenario: An open whose atServer closes every connection during authentication comes back offline, not refused
    Given an atServer that closes every connection while the client reads its keys
    When the client opens
    Then it comes back offline and unreachable, carrying ConnectionInvalidException, and the device does not count it as having been online

  Scenario: A connection lost during authentication classifies as one lost during a read
    Given an atServer that closes each connection during authentication, and one that closes the connection instead of answering a command
    When a command fails on each, through executeVerb and through executeCommand
    Then every failure, through either route, classifies offline and unreachable, and none as a refusal
