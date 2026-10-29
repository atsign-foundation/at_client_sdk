Feature: An authentication whose connection is lost starts again on a fresh one

  An authentication's commands all go on the connection it began on. When
  that connection is lost before the authentication finishes, the lookup opens
  a fresh connection and runs the authenticator again from its first command,
  once. A second loss fails as a lost connection, never as a refusal of the
  credentials.

  Races: an authentication waiting behind one whose connection is lost finds
  the fresh connection already authenticated, and a close() by the caller
  opens no fresh connection.
  Replay: the fresh run answers a new challenge on its own connection, and
  nothing sent for the lost connection goes on another.
  DoS: one fresh connection per authentication, and a refused authentication
  is not run again.
  Forgery and impersonation: the fresh run is the lookup's own authenticator
  for its own atSign, and only the connection it ran on is recorded as
  authenticated.

  Scenario: A connection lost before the authenticator's first command is replaced
    Given a lookup whose atServer closes the connection before the authenticator sends anything
    When the lookup authenticates
    Then the authenticator runs again on a fresh connection, nothing is written to the closed one, and the lookup authenticates

  Scenario: A connection lost between the challenge and its answer is replaced
    Given a lookup whose atServer closes the connection after answering from:
    When the authenticator sends its answer
    Then the answer goes on no connection, the authenticator runs again from from: on a fresh connection, and only that connection is recorded as authenticated

  Scenario: A second lost connection fails as a lost connection, not a refusal
    Given a lookup whose atServer closes every connection before the authenticator sends anything
    When the lookup authenticates, alone or for a verb
    Then after one fresh connection it fails with ConnectionInvalidException, or for a verb with an AtLookUpException whose code is not AT0401

  Scenario: A refused authentication is not run again
    Given a lookup whose atServer refuses the answer
    When the lookup authenticates
    Then it fails with UnAuthenticatedException and the authenticator ran once

  Scenario: A command waiting behind a lost authentication runs on the fresh connection
    Given a command waiting to authenticate while an authentication loses its connection
    When that authentication succeeds on a fresh connection
    Then the command runs on that connection without the authenticator running again
