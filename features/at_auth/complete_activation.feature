Feature: Completing an activation publishes the encryption public key, then deletes the CRAM secret
  completeActivationOf finishes an activation started with its completion
  deferred, on a connection authenticated as the atSign's first enrollment.
  It publishes the encryption public key it is given as
  public:publickey@<atSign> with ttr -1, replacing any key already
  published, and then deletes the CRAM secret. Given no key, it publishes
  nothing and deletes the CRAM secret all the same. The update command
  carries the key as it is, so a key must be one line.

  Races: of two completions of one activation, the later publish replaces
  the earlier key, and a CRAM secret the first deleted counts as deleted for
  the second.
  Replay: nothing is issued or checked; the connection is already
  authenticated. Denial of service: at most two commands, on the caller's
  own connection. Forgery and impersonation: the connection is
  authenticated as the atSign's first enrollment, so only that enrollment's
  holder publishes the key or deletes the CRAM secret.

  Scenario: A completion publishes the encryption public key with ttr -1, then deletes the CRAM secret
    # packages/at_auth/test/complete_activation_test.dart
    Given a connection authenticated as @alice's first enrollment
    When the activation is completed with an encryption public key
    Then the key is published as public:publickey@alice with ttr -1
    And the CRAM secret is deleted after it

  Scenario: A completion with no encryption public key deletes only the CRAM secret
    # packages/at_auth/test/complete_activation_test.dart
    Given a connection authenticated as @alice's first enrollment
    When the activation is completed with no encryption public key
    Then nothing is published
    And the CRAM secret is deleted

  Scenario: A failed publish keeps the CRAM secret and propagates
    # packages/at_auth/test/complete_activation_test.dart
    Given the atServer refuses the publish of the encryption public key
    When the activation is completed with that key
    Then the publish's error propagates
    And no delete of the CRAM secret is sent

  Scenario: An encryption public key holding a line feed is refused before any command
    # packages/at_auth/test/complete_activation_test.dart
    Given an encryption public key holding a line feed
    When the activation is completed with that key
    Then it throws an ArgumentError
    And no command is sent

  Scenario: An encryption public key holding a carriage return is refused before any command
    # packages/at_auth/test/complete_activation_test.dart
    Given an encryption public key holding a carriage return
    When the activation is completed with that key
    Then it throws an ArgumentError
    And no command is sent

  Scenario: A CRAM secret the atServer reports as not found counts as deleted
    # packages/at_auth/test/complete_activation_test.dart
    Given the atServer answers the CRAM secret's delete with AT0015
    When the activation is completed
    Then it completes without an error

  Scenario: A CRAM secret delete refused for another reason propagates
    # packages/at_auth/test/complete_activation_test.dart
    Given the atServer answers the CRAM secret's delete with AT0003
    When the activation is completed
    Then that refusal propagates
