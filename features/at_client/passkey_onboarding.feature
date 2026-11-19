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
  and saves the passkey hints the onboarding could not.
  Before it writes the @keys document, onboarding records that the
  activation's completion is due, in a record no other enrollment can read
  or write, `completion-due.<enrollmentId>.a.__e@<atSign>`; once its own
  delete of the CRAM secret answers, it records there that the CRAM secret
  is deleted, and the completion deletes the record as its last step,
  after the publish. A login on a device with no saved hints for the
  Atsign reads that record before it looks at the published key. When the
  record says the CRAM secret is deleted, the login takes the same three
  steps, publishing the document's key over any other key, then deletes
  the record. When it says only that the completion is due, the login
  takes the same three steps, revoking every other approved enrollment,
  only when no key or the document's key is published, and refuses another
  key before it sends any delete, revoke or publish. When the completion
  is not due, the login
  revokes nothing: it publishes the document's key when none is published,
  deletes the CRAM secret, which is already gone, and refuses a published
  key that is not the document's.
  A login that uses saved hints sends none of these, since a device saves
  them only once the completion is done. The device keeps nothing about an
  unfinished onboarding: IndexedDB holds only the passkey hints, written
  once the CRAM secret is deleted.

  The CRAM secret is deleted before the revoke, so nothing a CRAM holder
  enrolled before the delete survives it. A revoke that fails stops the
  completion before the publish and leaves the record, so the next login
  without saved hints tries the revoke again.
  A login publishes over another key only when its onboarding's own delete
  of the CRAM secret answered, so it finishes an onboarding over a key
  another activation tool published while the CRAM secret was live, and
  refuses a key another tool published after it activated with the same
  secret and deleted it. A login revokes only while the completion is due,
  so a key another enrollment published later is still refused. Each
  revoke is named in a warning.
  An onboarding whose own delete of the CRAM secret landed but whose
  answer was lost, or whose record of it could not be written, after
  another activation tool published a key while the secret was live,
  leaves the record saying only that the completion is due; a login then
  refuses that key, and the Atsign needs a new CRAM secret from its
  registrar.

  Races: tabs of one origin onboarding one Atsign wait on its setup lock.
  Two devices onboarding one Atsign with the same CRAM secret at once can
  revoke each other's enrollments, and in the worst order leave the Atsign
  activated with no usable enrollment until its registrar resets the CRAM
  secret; only the CRAM secret's holder can do that, and that holder can
  already create or end any enrollment, so nothing guards against it. Two
  logins with one passkey finishing one activation each delete the CRAM
  secret, revoke the same enrollments and publish the same key, so the
  second changes nothing. A login that finishes a completion while the
  onboarding's own last steps run sends the same delete, revoke and
  publish; it reads the record before the published key, so it never finds
  the completion not due while the key is still unpublished. Two devices
  holding the same synced passkey can leave a stale record: when a login
  on one finishes the completion and deletes the record while the
  onboarding on the other stalls before it records the CRAM secret's
  deletion, that write recreates the record, and if the onboarding then
  stops before its own delete, a later login without saved hints revokes
  every enrollment approved since and publishes the document's key over
  any other. Two logins
  with passkeys from two attempts, after a retry's revoke failed, can
  revoke each other's enrollment as two onboardings can; both passkeys
  came from the CRAM secret's holder. A
  failed onboarding releases the setup lock without waiting for the
  platform to take its report that the new passkey is unknown; the report
  names only that passkey, so the onboarding that takes the lock next is
  untouched by it.
  Replay: a retry sends a new enrollment request with a new key; nothing
  captured is resent. A login's delete, revoke and publish run on its own
  PKAM-authenticated connection, and sending any of them again changes
  nothing the first did not. Denial of service: each interrupted attempt
  leaves one approved enrollment until a retry or a login revokes it, and
  its completion-due record. A
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
  the enrollment its passkey's pointer names; it publishes only the key its
  @keys document holds, which
  only the passkey opens. A login revokes only while the onboarding's
  completion is due, so a published key that has gone does not make a
  later login revoke: the login publishes the document's key again. The
  atServer refuses every other enrollment a read, write or delete of the
  completion-due record from atServer p3.15.0, and a connection with the
  Atsign's legacy keys from p3.16.5. A CRAM-authenticated connection may read
  the record, and from atServer p3.19.0 is refused a write or delete of
  it; while the CRAM secret lives, its holder already holds more than any
  enrollment. A key
  replaced by another enrollment that
  holds `*:rw` and `__manage:rw` makes every login refuse it while the
  completion is not due, until such an enrollment publishes the document's
  key again.

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

  Scenario: Onboarding records its completion as due before it writes the @keys document, records the CRAM secret's deletion, and deletes that record last
    Given @alice🛠 is not yet activated and its CRAM secret is known
    When the app onboards @alice🛠 with a new passkey
    Then the atServer stored `completion-due.<enrollmentId>.a.__e@alice🛠` before the @keys document
    And the record said the CRAM secret was deleted after the CRAM secret's delete answered and before the revoke
    And it deleted that record after the encryption public key was published
    And while it was stored, another enrollment of @alice🛠 holding `*:rw` and `__manage:rw` was refused a read and a delete of it

  Scenario: An onboarding whose completion-due record cannot be written fails before it writes anything else
    Given the atServer refuses the write of @alice🛠's completion-due record
    When the app onboards @alice🛠 with a new passkey
    Then the onboarding throws that refusal
    And no @keys document or pointer is written and the CRAM secret is not deleted
    And the new credential is reported to the platform as unknown

  Scenario: An onboarding whose record of the CRAM secret's deletion cannot be written fails, and a login finishes it
    Given the atServer refuses, once, the write recording that @alice🛠's CRAM secret is deleted
    When the app onboards @alice🛠 with a new passkey
    Then the onboarding fails after the CRAM secret is deleted and before any revoke
    When the app then logs in to @alice🛠 with the passkey on a device with no saved hints
    Then the login finishes the completion and opens the onboarding's enrollment

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

  Scenario: A login that finds the completion due deletes the CRAM secret, then revokes the other enrollments, then publishes the key
    Given an onboarding of @alice🛠 was interrupted after its enrollment was approved
    And a second onboarding of @alice🛠 deleted the CRAM secret and then could not revoke the first one's enrollment
    When the app logs in to @alice🛠 with the second onboarding's passkey on a device with no saved hints
    Then the login deletes the CRAM secret, then revokes the first onboarding's enrollment, then publishes the @keys document's encryption public key, then deletes the completion-due record
    And it opens the second onboarding's enrollment

  Scenario: A login that finds the completion done and the document's key published deletes the CRAM secret and revokes nothing
    Given @alice🛠 was onboarded and its completion is done
    And another enrollment of @alice🛠 has since been approved
    When the app logs in to @alice🛠 with that passkey on a device with no saved hints
    Then the login deletes the CRAM secret, which is already gone
    And it sends no revoke and publishes nothing
    And the other enrollment is still approved

  Scenario: A login finishes an onboarding over a key another activation tool published while the CRAM secret was live
    Given another activation tool published an encryption public key for @alice🛠 while the CRAM secret was live, and stopped
    And an onboarding of @alice🛠 then deleted the CRAM secret, recorded that, and stopped before it published its own key
    When the app logs in to @alice🛠 with that onboarding's passkey on a device with no saved hints
    Then the login revokes the other tool's enrollment, publishes the @keys document's encryption public key over the other tool's key, then deletes the completion-due record
    And it opens the onboarding's enrollment

  Scenario: A login refuses a key another tool published after its onboarding stopped before deleting the CRAM secret
    Given an onboarding of @alice🛠 stopped after it wrote its pointer and before its delete of the CRAM secret answered
    And another activation tool then activated @alice🛠 with the same CRAM secret, published its encryption public key and deleted the CRAM secret
    When the app logs in to @alice🛠 with that onboarding's passkey on a device with no saved hints
    Then it throws a PublicKeyMismatchException
    And it sends no delete, revoke or publish
    And the other tool's enrollment is still approved

  Scenario: A login after an onboarding that stopped before deleting the CRAM secret, with no key published, finishes it
    Given an onboarding of @alice🛠 stopped after it wrote its pointer and before its delete of the CRAM secret answered
    And another enrollment of @alice🛠 is approved and no encryption public key is published
    When the app logs in to @alice🛠 with that passkey on a device with no saved hints
    Then the login deletes the CRAM secret, revokes the other enrollment, publishes the @keys document's encryption public key and deletes the completion-due record

  Scenario: A login that finds no key published and the completion done publishes the document's key and revokes nothing
    Given @alice🛠 was onboarded and its completion is done
    And another enrollment of @alice🛠 has since been approved
    And the atServer no longer answers a lookup of `publickey@alice🛠`
    When the app logs in to @alice🛠 with that passkey on a device with no saved hints
    Then the login publishes the @keys document's encryption public key and deletes the CRAM secret, which is already gone
    And it sends no revoke, and the other enrollment is still approved

  Scenario: A login that finds another key published and the completion done refuses it
    Given @alice🛠 was onboarded and its completion is done
    And another enrollment of @alice🛠 holding `*:rw` and `__manage:rw` published a different encryption public key
    When the app logs in to @alice🛠 with that passkey on a device with no saved hints
    Then it throws a PublicKeyMismatchException
    And it sends no delete, revoke or publish

  Scenario: A completion whose record delete fails saves no passkey hints, and the next login finishes it
    Given the atServer refuses the delete of @alice🛠's completion-due record once
    When the app onboards @alice🛠 with a new passkey
    Then the onboarding throws that refusal, after the encryption public key is published
    And this device saves no passkey hints for @alice🛠
    When the app then logs in to @alice🛠 with the passkey on a device with no saved hints
    Then the login finishes the completion and deletes the completion-due record
    And it opens the onboarding's enrollment

  Scenario: A completion-due record the atServer reports as not found counts as deleted
    Given the atServer answers the delete of @alice🛠's completion-due record with AT0015
    When the app onboards @alice🛠 with a new passkey
    Then it gets a passkey session whose client is online as the new enrollment

  Scenario: A login whose read of the completion-due record fails throws and sends nothing
    Given an onboarding of @alice🛠 deleted the CRAM secret and stopped before it published its key
    And the atServer fails the read of @alice🛠's completion-due record with an error other than not found
    When the app logs in to @alice🛠 with that passkey on a device with no saved hints
    Then the login throws that failure
    And it sends no delete, revoke or publish

  @race
  Scenario: A login reads the completion-due record before it looks at the published key
    Given an onboarding of @alice🛠 deleted the CRAM secret and stopped before it published its key
    When the app logs in to @alice🛠 with that passkey on a device with no saved hints
    Then the login reads the completion-due record before it looks up `publickey@alice🛠`

  Scenario: A login refuses a @keys document whose APKAM public key is not the passkey's, even while the completion is due
    Given an onboarding of @alice🛠 deleted the CRAM secret and stopped before it published its key
    And the @keys document holds an APKAM public key that is not the passkey's
    When the app logs in to @alice🛠 with that passkey on a device with no saved hints
    Then it throws a PublicKeyMismatchException
    And it sends no delete, revoke or publish

  Scenario: A login whose revoke keeps failing throws the revoke's failure, and the next login tries again
    Given an onboarding of @alice🛠 deleted the CRAM secret and then could not revoke the other approved enrollments
    And the atServer still lists another approved enrollment after every revoke
    When the app logs in to @alice🛠 with that passkey on a device with no saved hints
    Then the login throws the revoke's AtEnrollmentException, not a PasskeyLostException
    And it publishes no encryption public key and saves no passkey hints
    And the next login sends the revoke again

  Scenario: A login that revokes names each enrollment it revokes in a warning
    Given an onboarding of @alice🛠 deleted the CRAM secret and then could not revoke another approved enrollment
    When the app logs in to @alice🛠 with that passkey on a device with no saved hints
    Then a warning names @alice🛠 and the id of the enrollment the login revoked

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
