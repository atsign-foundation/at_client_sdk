Feature: Onboarding writes the @keys before it deletes the CRAM secret
  Onboarding activates the Atsign with the CRAM secret's deletion deferred,
  writes the sealed @keys document and the passkey's pointer as the new
  enrollment, then completes the activation in three steps: it deletes the
  CRAM secret, then revokes every other approved enrollment of the Atsign,
  then publishes the encryption public key, sending the CRAM secret's
  delete once more with it. Only then does it remember the passkey on the
  device and open the client, which, under a posture that creates a signing
  root, mints the Atsign's signing root, filing the root's private key in
  the @keys document before publishing the root. Until the CRAM secret is
  deleted, an onboarding that was interrupted is run again with the same
  CRAM secret, and that retry revokes every other approved enrollment of the
  Atsign, including those earlier attempts left; once it is deleted the
  Atsign is onboarded, and logging in with the passkey opens its enrollment
  and saves the passkey hints the onboarding could not. A login on a device
  with no saved hints for the Atsign finishes an activation that an
  onboarding left half done. When no encryption public key is published it
  takes the same three steps: it deletes the CRAM secret, then revokes every
  other approved enrollment, then publishes the @keys document's encryption
  public key. When the document's key is already published it only deletes
  the CRAM secret, which is already gone. A login that uses saved hints
  sends none of these, since a device saves them only once the activation is
  finished. Every login refuses a different published key. The device keeps
  nothing about an unfinished onboarding: IndexedDB holds only the passkey
  hints, written once the CRAM secret is deleted.

  The CRAM secret is deleted before the revoke so that a published key
  means the revoke ran once no new `cram:` login could succeed: nothing a
  CRAM holder enrolled before the delete survives it. A login therefore
  revokes only when no key is published. A revoke that fails stops the
  completion before the publish, so the key stays unpublished and the next
  login without saved hints tries the revoke again.

  Races: tabs of one origin onboarding one Atsign wait on its setup lock.
  Two devices onboarding one Atsign with the same CRAM secret at once can
  revoke each other's enrollments, and in the worst order leave the Atsign
  activated with no usable enrollment until its registrar resets the CRAM
  secret; only the CRAM secret's holder can do that, and that holder can
  already create or end any enrollment, so nothing guards against it. Two
  logins with one passkey finishing one activation each delete the CRAM
  secret, revoke the same enrollments and publish the same key, so the
  second changes nothing. Two logins with passkeys from two attempts,
  after a retry's revoke failed, can revoke each other's enrollment as two
  onboardings can; both passkeys came from the CRAM secret's holder. A
  failed onboarding releases the setup lock without waiting for the
  platform to take its report that the new passkey is unknown; the report
  names only that passkey, so the onboarding that takes the lock next is
  untouched by it.
  Replay: a retry sends a new enrollment request with a new key; nothing
  captured is resent. A login's delete, revoke and publish run on its own
  PKAM-authenticated connection, and sending any of them again changes
  nothing the first did not. Denial of service: each interrupted attempt
  leaves one approved enrollment until a retry or a login revokes it. A
  revoke that keeps failing fails every login without saved hints; only an
  enrollment that holds `__manage`, which can approve or reinstate
  enrollments as fast as they are revoked, or the atServer can keep it
  failing, and either already holds more than the login. A platform that
  never finishes taking a report that a passkey is unknown holds up
  neither the failed onboarding nor the setup lock. Forgery and
  impersonation: only a CRAM secret's holder activates or retries, and that
  holder already holds more than any enrollment; the retry revokes only
  enrollments of this Atsign, after the CRAM secret is deleted and before
  its key is published. A login revokes and publishes only after PKAM as
  the enrollment its passkey's pointer names, and only when no key is
  published; it publishes only the key its @keys document holds, which
  only the passkey opens. The atServer refuses a delete of `publickey`, so
  a published key cannot be made absent to make a later login revoke, only
  replaced, which makes every login refuse it.

  Scenario: Onboarding writes the @keys document and pointer before it deletes the CRAM secret
    Given @alice🛠 is not yet activated and its CRAM secret is known
    When the app onboards @alice🛠 with a new passkey
    Then the atServer stored the @keys document and the pointer before the CRAM secret was deleted
    And the @keys document reads back and opens with the passkey
    And a `cram:` login with that secret is then refused

  Scenario: Onboarding deletes the CRAM secret, then revokes the other enrollments, then publishes its encryption public key
    Given @alice🛠 is not yet activated and its CRAM secret is known
    When the app onboards @alice🛠 with a new passkey
    Then it deletes the CRAM secret, then asks the atServer to revoke every other approved enrollment, then publishes its encryption public key
    And it sends the CRAM secret's delete once more after the publish, and the atServer accepts it

  Scenario: A signing root is published only after the CRAM secret is deleted
    Given @alice🛠 is not yet activated and its CRAM secret is known
    And the app's passkey client uses a posture that creates a signing root
    When the app onboards @alice🛠 with a new passkey
    Then `public:pq_signing_root@alice🛠` was first published after the CRAM secret was deleted
    And the @keys document held the root's private key before the root was published

  @race
  Scenario Outline: An onboarding interrupted before the CRAM secret is deleted can be run again with the same secret
    Given an onboarding of @alice🛠 was interrupted <when>
    When the app onboards @alice🛠 again with the same CRAM secret and a new passkey
    Then it gets a passkey session whose client is online

    Examples:
      | when                                       |
      | after its enrollment was approved          |
      | after its @keys document was written       |
      | after its pointer was written              |

  Scenario: The retry revokes the enrollments interrupted attempts left approved
    Given an onboarding of @alice🛠 was interrupted after its enrollment was approved
    When the app onboards @alice🛠 again with the same CRAM secret
    Then the earlier enrollment was revoked after the CRAM secret was deleted and before the new encryption public key was published
    And the new enrollment is the only approved enrollment of @alice🛠

  Scenario: The retry publishes its own encryption public key over an interrupted attempt's
    Given an interrupted activation of @alice🛠 by another tool published an encryption public key before the CRAM secret was deleted
    When the app onboards @alice🛠 with the same CRAM secret
    Then `publickey@alice🛠` is the new enrollment's encryption public key

  Scenario: A passkey left by an interrupted onboarding is refused as lost
    Given an onboarding of @alice🛠 was interrupted and then run again with a new passkey
    When the app logs in to @alice🛠 with the first passkey
    Then it throws a PasskeyLostException

  Scenario: A login after an onboarding interrupted once the CRAM secret is deleted opens its enrollment
    Given an onboarding of @alice🛠 was interrupted after the CRAM secret was deleted and before its client opened
    When the app logs in to @alice🛠 with that passkey
    Then it gets a passkey session whose client is online as the onboarding's enrollment

  Scenario: A login after an onboarding that stopped before deleting the CRAM secret deletes it
    Given an Atsign whose passkey onboarding wrote its @keys document and pointer, but did not delete the CRAM secret
    When the app logs in with that passkey
    Then the login deletes the CRAM secret

  Scenario: A login after an onboarding that stopped before publishing its encryption public key publishes it and deletes the CRAM secret
    Given an Atsign whose passkey onboarding wrote its @keys document and pointer, but published no encryption public key and did not delete the CRAM secret
    When the app logs in with that passkey
    Then the login publishes the document's encryption public key
    And it deletes the CRAM secret

  Scenario: A login that finds no encryption public key published deletes the CRAM secret, then revokes the other enrollments, then publishes the key
    Given an onboarding of @alice🛠 was interrupted after its enrollment was approved
    And a second onboarding of @alice🛠 deleted the CRAM secret and then could not revoke the first one's enrollment
    When the app logs in to @alice🛠 with the second onboarding's passkey on a device with no saved hints
    Then the login deletes the CRAM secret, then revokes the first onboarding's enrollment, then publishes the @keys document's encryption public key
    And it opens the second onboarding's enrollment

  Scenario: A login that finds the document's encryption public key published deletes the CRAM secret and revokes nothing
    Given an onboarding of @alice🛠 was interrupted after it published its encryption public key
    And another enrollment of @alice🛠 has since been approved
    When the app logs in to @alice🛠 with that passkey on a device with no saved hints
    Then the login deletes the CRAM secret, which is already gone
    And it sends no revoke and publishes nothing
    And the other enrollment is still approved

  Scenario: A login whose revoke keeps failing throws the revoke's failure, and the next login tries again
    Given an onboarding of @alice🛠 deleted the CRAM secret and then could not revoke the other approved enrollments
    And the atServer still lists another approved enrollment after every revoke
    When the app logs in to @alice🛠 with that passkey on a device with no saved hints
    Then the login throws the revoke's AtEnrollmentException, not a PasskeyLostException
    And it publishes no encryption public key and saves no passkey hints
    And the next login sends the revoke again

  Scenario: A login with saved hints sends no activation completion
    Given @alice🛠 was onboarded on this device, which saved its passkey hints
    When the app logs in to @alice🛠 with that passkey
    Then the login publishes no encryption public key and sends no CRAM secret delete

  Scenario: The device keeps nothing about an onboarding that did not complete
    Given an onboarding of @alice🛠 in this browser was interrupted after its enrollment was approved
    Then this origin's IndexedDB holds nothing for @alice🛠

  Scenario: A passkey whose onboarding fails before it completes the activation is reported as unknown
    Given the app onboards @alice🛠 with a new passkey
    When the onboarding fails before it starts completing the activation
    Then the new credential is reported to the platform as unknown

  @dos
  Scenario: A failed activation is thrown without waiting for the platform to take the unknown passkey report
    Given the app onboards @alice🛠 with a new passkey
    And the platform never finishes taking a report that a passkey is unknown
    When the activation fails
    Then the onboarding throws the activation's failure without waiting for the report
    And the new credential was reported to the platform as unknown once
    And @alice🛠's setup lock is released while that report is still pending

  Scenario: A passkey whose onboarding fails while completing the activation is not reported
    Given the app onboards @alice🛠 with a new passkey
    When completing the activation fails
    Then nothing is reported to the platform about the new credential
