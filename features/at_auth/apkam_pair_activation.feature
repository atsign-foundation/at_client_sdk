Feature: An activation can use an APKAM keypair the caller supplies
  Activating an enrolled atSign takes an optional apkamKeyPair, the two halves
  of the APKAM authentication keypair the activation is to enrol and keep, in
  place of letting at_auth mint one. The pair is checked before anything is
  sent: it must match the requested signing algorithm and its halves must
  belong together. A pair that fails is refused and no enrol command is sent.
  Atsign.activate in at_client passes the pair straight through to at_auth.

  Scenario: The supplied ML-DSA-65 pair is the one filed under the enrollment id
    # packages/at_auth/test/pq_native_onboard_test.dart
    #   group 'an activation with a caller-supplied APKAM keypair'
    #   test 'the supplied ML-DSA-65 pair is the one filed under the enrollment id'
    Given an activation carrying a matching mldsa65 apkamKeyPair
    When it is run
    Then the supplied pair is filed under the assigned enrollment id

  Scenario: The supplied RSA pair is the one in the flat fields
    # packages/at_auth/test/pq_native_onboard_test.dart
    #   group 'an activation with a caller-supplied APKAM keypair'
    #   test 'the supplied RSA pair is the one in the flat fields'
    Given an activation carrying a matching rsa2048 apkamKeyPair
    When it is run
    Then the keyfile's flat fields hold the supplied pair

  Scenario: The public key sent equals the supplied one
    # packages/at_auth/test/pq_native_onboard_test.dart
    #   group 'an activation with a caller-supplied APKAM keypair'
    #   test 'the public key sent equals the supplied one'
    Given an activation carrying a matching apkamKeyPair
    When it is run
    Then the apkamPublicKey in the enrol command equals the supplied public key

  Scenario: A pair whose halves do not match is refused and nothing is sent
    # packages/at_auth/test/pq_native_onboard_test.dart
    #   group 'an activation with a caller-supplied APKAM keypair'
    #   test 'a pair whose halves do not match is refused and nothing is sent'
    Given an activation carrying the public half of one keypair and the
      private half of another
    When it is run
    Then it is refused
    And nothing is sent to the atServer

  Scenario: A pair of the wrong algorithm is refused and nothing is sent
    # packages/at_auth/test/pq_native_onboard_test.dart
    #   group 'an activation with a caller-supplied APKAM keypair'
    #   test 'a pair of the wrong algorithm is refused and nothing is sent'
    Given an activation for one signing algorithm carrying a pair of another
    When it is run
    Then it is refused
    And nothing is sent to the atServer

  Scenario: Omitting the pair mints a fresh one under the requested algorithm
    # packages/at_auth/test/pq_native_onboard_test.dart
    #   group 'an activation with a caller-supplied APKAM keypair'
    #   test 'omitting it mints a fresh pair under the requested algorithm'
    Given an activation carrying no apkamKeyPair
    When it is run
    Then a fresh keypair is minted under the requested signing algorithm

  Scenario: Atsign.activate passes the pair through and keeps it
    # packages/at_client/test/lifecycle/activate_test.dart
    #   group 'a supplied APKAM keypair'
    #   test 'is the one enrolled and the one kept'
    Given Atsign.activate is given a matching apkamKeyPair
    When it runs
    Then the enrol command carries the supplied public key
    And the pair that is kept is the supplied one

  Scenario: Atsign.activate refuses a mismatched pair before enrolling
    # packages/at_client/test/lifecycle/activate_test.dart
    #   group 'a supplied APKAM keypair'
    #   test 'that does not match is refused before anything is enrolled'
    Given Atsign.activate is given a pair whose halves do not match
    When it runs
    Then it is refused
    And no enrol command is sent

  Scenario: Atsign.activate with no pair mints a fresh one
    # packages/at_client/test/lifecycle/activate_test.dart
    #   group 'a supplied APKAM keypair'
    #   test 'omitted, a fresh pair is minted'
    Given Atsign.activate is given no apkamKeyPair
    When it runs
    Then a fresh pair is minted

  Scenario: A malformed mldsa65 pair is refused with fixed text that echoes no key
    # packages/at_auth/test/enrollment_test.dart
    #   test 'when an mldsa65 pair is base64 of the wrong length, then the error
    #   is fixed text holding none of the keys'
    Given an enrollment request carrying an mldsa65 pair that is base64 of the
      wrong length
    When it is submitted
    Then it fails with AtSigningException saying the supplied mldsa65 APKAM
      key pair is malformed
    And the error holds none of the supplied key material
    And no enroll:request is sent
