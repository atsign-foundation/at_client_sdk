Feature: An activation whose connection is stopped says it was stopped
  An activation authenticates its new enrollment by PKAM once the atServer
  has accepted the CRAM secret. A caller that supplied the activation's
  connection and stops it meanwhile gets the StoppedException a stopped
  connection raises, as every other at_lookup call on it does, rather than
  an AtAuthenticationException that reads as a failed login. No keys are
  written, as for any activation that does not finish.

  Races: the stop and the atServer's PKAM reply race on one connection;
  at_lookup fails the call in flight once stop() has run, so the activation
  meets one or the other. A PKAM that has already succeeded is not undone.
  Replay: the stop sends nothing, and nothing the atServer sent is reused.
  Denial of service: a stop ends work; nothing waits on it or retries.
  Forgery and impersonation: only the caller holding the connection, in its
  own process, can stop it. The atServer's replies are unchanged, and a
  refusal is still an AtAuthenticationException.

  Scenario: An activation whose connection is stopped while it authenticates by PKAM throws StoppedException
    # packages/at_auth/test/activation_stopped_test.dart
    #   test 'An activation whose connection is stopped while it authenticates by PKAM throws StoppedException'
    Given an activation of @alice whose CRAM secret the atServer has accepted
    When the caller stops the activation's connection while it authenticates by PKAM
    Then the activation throws StoppedException, not AtAuthenticationException
    And no keys for @alice are written

  Scenario: An activation whose PKAM the atServer refuses still throws AtAuthenticationException
    # packages/at_auth/test/activation_stopped_test.dart
    #   test 'An activation whose PKAM the atServer refuses still throws AtAuthenticationException'
    Given an activation of @alice whose CRAM secret the atServer has accepted
    When the atServer refuses its PKAM
    Then the activation throws AtAuthenticationException
    And no keys for @alice are written
