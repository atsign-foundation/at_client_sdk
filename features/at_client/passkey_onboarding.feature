Feature: Onboarding writes the @keys before it deletes the CRAM secret
  Onboarding activates the Atsign with the CRAM secret's deletion deferred,
  writes the sealed @keys document and the passkey's pointer as the new
  enrollment, then completes the activation: it publishes the encryption
  public key and deletes the CRAM secret. Only then does it remember the
  passkey on the device and open the client, which, under a posture that
  creates a signing root, mints the Atsign's signing root, filing the root's
  private key in the @keys document before publishing the root. Until the
  CRAM secret is deleted, an onboarding that was interrupted is run again
  with the same CRAM secret, and that retry revokes every other approved
  enrollment of the Atsign, including those earlier attempts left; once it
  is deleted, logging in with the passkey finishes the onboarding. A login
  on a device with no saved hints for the Atsign also finishes an
  activation that an onboarding left half done: it publishes the @keys
  document's encryption public key when none is published, and deletes the
  CRAM secret. A login that uses saved hints sends neither, since a device
  saves them only once the activation is finished. Every login refuses a
  different published key. The device keeps nothing about an unfinished
  onboarding: IndexedDB holds only the passkey hints, written once the CRAM
  secret is deleted.

  Races: tabs of one origin onboarding one Atsign wait on its setup lock.
  Two devices onboarding one Atsign with the same CRAM secret at once can
  revoke each other's enrollments, and in the worst order leave the Atsign
  activated with no usable enrollment until its registrar resets the CRAM
  secret; only the CRAM secret's holder can do that, and that holder can
  already create or end any enrollment, so nothing guards against it. Two
  logins finishing one activation each publish the same key and delete the
  CRAM secret, so the second changes nothing.
  Replay: a retry sends a new enrollment request with a new key; nothing
  captured is resent. Denial of service: each interrupted attempt leaves
  one approved enrollment until a retry revokes it. Forgery and
  impersonation: only a CRAM secret's holder activates or retries, and that
  holder already holds more than any enrollment; the retry revokes only
  enrollments of this Atsign, before its activation completes. A login
  publishes only the key its @keys document holds, which only the passkey
  opens, and only when none is published.

  Scenario: Onboarding writes the @keys document and pointer before it deletes the CRAM secret
    Given @alice🛠 is not yet activated and its CRAM secret is known
    When the app onboards @alice🛠 with a new passkey
    Then the atServer stored the @keys document and the pointer before the CRAM secret was deleted
    And the @keys document reads back and opens with the passkey
    And a `cram:` login with that secret is then refused

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
      | after its encryption public key was published |

  Scenario: The retry revokes the enrollments interrupted attempts left approved
    Given an onboarding of @alice🛠 was interrupted after its enrollment was approved
    When the app onboards @alice🛠 again with the same CRAM secret
    Then the earlier enrollment was revoked before the CRAM secret was deleted
    And the new enrollment is the only approved enrollment of @alice🛠

  Scenario: The retry publishes its own encryption public key over an interrupted attempt's
    Given an interrupted onboarding of @alice🛠 published its encryption public key before the CRAM secret was deleted
    When the app onboards @alice🛠 again with the same CRAM secret
    Then `publickey@alice🛠` is the new enrollment's encryption public key

  Scenario: A passkey left by an interrupted onboarding is refused as lost
    Given an onboarding of @alice🛠 was interrupted and then run again with a new passkey
    When the app logs in to @alice🛠 with the first passkey
    Then it throws a PasskeyLostException

  Scenario: An onboarding interrupted after the CRAM secret is deleted is finished by logging in
    Given an onboarding of @alice🛠 was interrupted after the CRAM secret was deleted and before its client opened
    When the app logs in to @alice🛠 with that passkey
    Then it gets a passkey session whose client is online as the onboarding's enrollment

  Scenario: A login after an onboarding that stopped before deleting the CRAM secret deletes it
    Given an Atsign whose passkey onboarding wrote its @keys document and pointer and published its encryption public key, but did not delete the CRAM secret
    When the app logs in with that passkey
    Then the login deletes the CRAM secret

  Scenario: A login after an onboarding that stopped before publishing its encryption public key publishes it and deletes the CRAM secret
    Given an Atsign whose passkey onboarding wrote its @keys document and pointer, but published no encryption public key and did not delete the CRAM secret
    When the app logs in with that passkey
    Then the login publishes the document's encryption public key
    And it deletes the CRAM secret

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

  Scenario: A passkey whose onboarding fails while completing the activation is not reported
    Given the app onboards @alice🛠 with a new passkey
    When completing the activation fails
    Then nothing is reported to the platform about the new credential
