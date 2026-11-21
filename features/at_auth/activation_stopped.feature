Feature: An activation whose connection is stopped says it was stopped
  An activation may first wait for its atServer to answer, and then, once
  the atServer has accepted the CRAM secret, authenticates its new
  enrollment by PKAM. A caller that supplied the activation's connection
  and stops it while it authenticates, or while it waits once the
  atDirectory has answered, gets the StoppedException a stopped connection
  raises, as every other at_lookup call on it does, rather than an
  AtAuthenticationException that reads as a failed login, or an
  AtTimeoutException once the wait runs out. A stop while the atDirectory
  cannot be reached, or does not yet list the Atsign, is seen only at the
  deadline. A stop before the PKAM succeeds writes no keys: they are stored
  only after it. A stop once the PKAM has succeeded, while the activation
  publishes the encryption public key and deletes the CRAM secret, also
  throws StoppedException, but the keys are already written and the
  activation is not complete: the caller finishes it with
  completeActivationOf over a connection authenticated with the written
  keys, rather than activating again.

  Races: the stop and the atServer's PKAM reply race on one connection;
  at_lookup fails the call in flight once stop() has run, so the activation
  meets one or the other. A PKAM that has already succeeded is not undone.
  Replay: the stop sends nothing, and nothing the atServer sent is reused.
  Denial of service: once the atDirectory has answered, a stop ends the
  wait at once and nothing retries it; while the atDirectory cannot be
  reached or does not list the Atsign, the wait polls it until its deadline
  (5 minutes by default), as it does with no stop.
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

  Scenario: An activation whose connection is stopped while it completes throws StoppedException with its keys written
    # packages/at_auth/test/activation_stopped_test.dart
    #   test 'An activation whose connection is stopped while it completes throws StoppedException with its keys written'
    Given an activation of @alice whose PKAM the atServer has accepted
    When the caller stops the activation's connection while it publishes the encryption public key
    Then the activation throws StoppedException
    And the keys for @alice are written
    And the CRAM secret is not deleted

  Scenario: An activation whose connection is stopped while it waits for its atServer throws StoppedException
    # packages/at_auth/test/activation_stopped_test.dart
    #   test 'An activation whose connection is stopped while it waits for its atServer throws StoppedException'
    Given an activation of @alice that waits for its atServer to answer
    When the caller stops the activation's connection while it waits
    Then the activation throws StoppedException, without waiting out its deadline
    And no keys for @alice are written
