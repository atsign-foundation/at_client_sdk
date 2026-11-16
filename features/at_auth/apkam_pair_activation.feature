Feature: An activation can use an APKAM keypair the caller supplies
  Activating an enrolled atSign takes an optional apkamKeyPair, the two halves
  of the APKAM authentication keypair the activation is to enrol and keep, in
  place of letting at_auth mint one. The pair is checked before the atServer
  is contacted: it must match the requested signing algorithm and its halves
  must belong together. A pair that fails is refused, and neither the CRAM
  login nor an enrol command is sent. Atsign.activate in at_client passes the
  pair straight through to at_auth.

  If the activation fails after the enrollment is accepted (the PKAM login or
  the keyfile write), retrying with the same pair is refused by the atServer
  while that enrollment's record exists. The caller retries with a different
  pair, or with none so one is minted; the CRAM secret stays valid until an
  activation completes.

  Races: a retry of the same pair after a failure past the enrol step is
  refused by the atServer while that record exists, as above.
  Replay: nothing is issued or checked beyond what an activation already does.
  Denial of service: one signature and one verification per supplied pair,
  done before the atServer is contacted. Forgery and impersonation: whoever
  supplies the pair decides the first enrollment's client authentication
  signing key, so the pair must come from the activating device.
  Key material: a refused pair's error names no key text.

  Scenario: The supplied ML-DSA-65 pair is the one filed under the enrollment id
    # packages/at_auth/test/pq_native_onboard_test.dart
    #   group 'an activation with a caller-supplied APKAM keypair'
    #   test 'The supplied ML-DSA-65 pair is the one filed under the enrollment id'
    Given an activation carrying a matching mldsa65 apkamKeyPair
    When it is run
    Then the supplied pair is filed under the assigned enrollment id

  Scenario: The supplied RSA pair is the one in the flat fields
    # packages/at_auth/test/pq_native_onboard_test.dart
    #   group 'an activation with a caller-supplied APKAM keypair'
    #   test 'The supplied RSA pair is the one in the flat fields'
    Given an activation carrying a matching rsa2048 apkamKeyPair
    When it is run
    Then the keyfile's flat fields hold the supplied pair

  Scenario: The public key sent equals the supplied one
    # packages/at_auth/test/pq_native_onboard_test.dart
    #   group 'an activation with a caller-supplied APKAM keypair'
    #   test 'The public key sent equals the supplied one'
    Given an activation carrying a matching apkamKeyPair
    When it is run
    Then the apkamPublicKey in the enrol command equals the supplied public key

  Scenario: A pair whose halves do not match is refused and nothing is sent
    # packages/at_auth/test/pq_native_onboard_test.dart
    #   group 'an activation with a caller-supplied APKAM keypair'
    #   test 'A pair whose halves do not match is refused and nothing is sent'
    Given an activation carrying the public half of one keypair and the
      private half of another
    When it is run
    Then it is refused
    And the atServer is not contacted: no CRAM login, no command, no enrol

  Scenario: A pair of the wrong algorithm is refused and nothing is sent
    # packages/at_auth/test/pq_native_onboard_test.dart
    #   group 'an activation with a caller-supplied APKAM keypair'
    #   test 'A pair of the wrong algorithm is refused and nothing is sent'
    Given an activation for one signing algorithm carrying a pair of another
    When it is run
    Then it is refused
    And the atServer is not contacted: no CRAM login, no command, no enrol

  Scenario: Omitting the pair mints a fresh one under the requested algorithm
    # packages/at_auth/test/pq_native_onboard_test.dart
    #   group 'an activation with a caller-supplied APKAM keypair'
    #   test 'Omitting the pair mints a fresh one under the requested algorithm'
    Given an activation carrying no apkamKeyPair
    When it is run
    Then a fresh keypair is minted under the requested signing algorithm

  Scenario: Atsign.activate passes the pair through and keeps it
    # packages/at_client/test/lifecycle/activate_test.dart
    #   group 'a supplied APKAM keypair'
    #   test 'Atsign.activate passes the pair through and keeps it'
    Given Atsign.activate is given a matching apkamKeyPair
    When it runs
    Then the enrol command carries the supplied public key
    And the pair that is kept is the supplied one

  Scenario: Atsign.activate refuses a mismatched pair before enrolling
    # packages/at_client/test/lifecycle/activate_test.dart
    #   group 'a supplied APKAM keypair'
    #   test 'Atsign.activate refuses a mismatched pair before enrolling'
    Given Atsign.activate is given a pair whose halves do not match
    When it runs
    Then it is refused
    And no enrol command is sent

  Scenario: Atsign.activate with no pair mints a fresh one
    # packages/at_client/test/lifecycle/activate_test.dart
    #   group 'a supplied APKAM keypair'
    #   test 'Atsign.activate with no pair mints a fresh one'
    Given Atsign.activate is given no apkamKeyPair
    When it runs
    Then a fresh pair is minted

  Scenario: Atsign.activate passes a supplied ML-DSA-65 pair through and keeps it
    # packages/at_client/test/lifecycle/activate_test.dart
    #   group 'a supplied APKAM keypair'
    #   test 'Atsign.activate passes a supplied ML-DSA-65 pair through and keeps it'
    Given Atsign.activate is given a matching mldsa65 apkamKeyPair
    When it runs
    Then the enrol command carries the supplied public key
    And the keyfile files the supplied pair under the assigned enrollment id

  Scenario: The real enrollment sends and files the supplied ML-DSA-65 pair
    # packages/at_auth/test/pq_native_onboard_test.dart
    #   group 'an activation with a caller-supplied APKAM keypair'
    #   test 'The real enrollment sends and files the supplied ML-DSA-65 pair'
    Given an activation carrying a matching mldsa65 apkamKeyPair
    When it is run through the real AtEnrollmentImpl
    Then the enrol command carries the supplied public key
    And the keyfile files the supplied pair under the assigned enrollment id
