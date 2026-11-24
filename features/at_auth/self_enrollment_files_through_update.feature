Feature: A self-enrollment files its keys through update
  A self-enrollment reads the keyfile, asks the atServer for a new
  enrollment and then files that enrollment's keys. It files them through
  the store's update, on a fresh read of the keyfile, so whatever another
  writer added meanwhile is kept, and a keyfile removed meanwhile is not
  written again. The request to the atServer stays outside the update, since
  update may run its change more than once.

  Races: another writer's update can land between the self-enrollment's read
  and its filing; the filing runs on what the store holds then, so both
  writes are kept. A live enrollment filed meanwhile refuses this filing,
  and the self-enrollment revokes the enrollment it created. Two
  self-enrollments of one keyfile are serialised only where the process sets
  a retrofit serializer, as at_client_cli does in its auth command and in
  CliKeys.fileFor, and the keys are a keyfile. Elsewhere both may send a
  request, and the second to file is refused and revokes its enrollment.
  Replay: nothing the atServer sent is stored for reuse; the enrollment id
  comes from its answer to this request, and a re-run of the change files
  the same keys, minted once.
  Denial of service: a writer that removes the keyfile meanwhile makes the
  self-enrollment fail and revoke its enrollment; such a writer could
  remove the keyfile at any other time too. When the connection's
  enrollment lacks __manage, the revoke fails, and the error says the
  enrollment stays approved with no keyfile holding its private key, as it
  already does for a failed write.
  Forgery and impersonation: the connection authenticates as the keyfile's
  enrollment, and the filing checks that the keys still hold the
  authentication keypair read before the request: a keyfile replaced
  meanwhile by one holding another credential is refused, and the
  self-enrollment revokes the enrollment it created. One that already holds
  a live typed enrollment refuses the filing too.

  Scenario: A key another writer adds while a self-enrollment waits on the atServer is kept
    # packages/at_auth/test/at_self_enrollment_test.dart
    Given @alice's keyfile on disk, which a self-enrollment has read
    When another writer adds an active namespace key to the keyfile before the atServer answers the self-enrollment's request
    Then the self-enrollment succeeds
    And the keyfile holds the added key and the new enrollment's keys

  Scenario: A keyfile removed while a self-enrollment waits on the atServer is not written again
    # packages/at_auth/test/at_self_enrollment_test.dart
    Given @alice's keyfile on disk, which a self-enrollment has read
    When the keyfile is removed before the atServer answers the self-enrollment's request
    Then no keyfile exists afterwards
    And the enrollment the self-enrollment created is revoked
    And it throws AtEnrollmentException saying the keyfile could not be written and that the enrollment it created was revoked

  Scenario: A second live enrollment filed while a self-enrollment waits is refused and revoked
    # packages/at_auth/test/at_self_enrollment_test.dart
    Given @alice's keyfile on disk, holding no live typed enrollment, which a self-enrollment has read
    When another writer files a live enrollment into the keyfile before the atServer answers the self-enrollment's request
    Then the keyfile holds the other writer's enrollment and not the new enrollment's keys
    And the enrollment the self-enrollment created is revoked
    And it throws AtEnrollmentException saying the keyfile could not be written

  Scenario: A keyfile replaced by one holding a different credential while a self-enrollment waits on the atServer is not filed into
    # packages/at_auth/test/at_self_enrollment_test.dart
    Given @alice's keyfile on disk, which a self-enrollment has read
    When the keyfile is replaced by one holding a different credential before the atServer answers the self-enrollment's request
    Then the keyfile holds the replacement's credential and not the new enrollment's keys
    And the enrollment the self-enrollment created is revoked
    And it throws AtEnrollmentException saying the keyfile could not be written and that the enrollment it created was revoked

  Scenario: A key another writer adds to the keychain while a self-enrollment waits on the atServer is kept
    # packages/at_client_flutter/test/self_enrollment_files_through_update_test.dart
    Given @alice's keys in the keychain, which a self-enrollment has read
    When another writer adds an active namespace key to the keychain before the atServer answers the self-enrollment's request
    Then the self-enrollment succeeds
    And the keychain holds the added key and the new enrollment's keys
