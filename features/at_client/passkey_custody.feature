Feature: Passkey custody onboards, logs in and recovers an atSign without losing its keys

  PasskeyCustody onboards an atSign with a passkey, logs it in again from the
  same passkey, and keeps the @keys document on the atServer sealed under the
  passkey's own key. The stored document never holds the APKAM private key;
  the client's key store derives it again on each login. A pending record
  journals the minted keys before the CRAM secret is spent, so an onboarding
  that stopped part way is finished by the next onboard or open rather than
  started again.

  Races: onboard, open and discard of one atSign run under that atSign's
  setup lock; another tab's setup waits and then uses what it wrote. Writes
  from one client's key store run one at a time, each re-reading the stored
  document first, and a write queued after the store closed is refused before
  any I/O.
  Replay: a sealed record is bound to its atSign and its type, so one
  replayed under another atSign or type does not open. The unfinished
  activation hands its keys over once.
  DoS: a failed put or read is retried a fixed number of times; a refusal is
  never retried. A server error or throttling is never read as a refusal, so
  it cannot be used to make the client drop its record.
  Forgery: a stored document that is not these keys, or whose public keys do
  not match the published ones, is refused before use and never overwritten.
  Impersonation: a pointer naming another enrollment is refused by PKAM
  before any document is read; an atSign not in canonical form is refused
  before any work.

  Scenario: Onboard writes the document, then the pointer, and opens the client
    Given a device with no hints and a CRAM secret for @alice
    When PasskeyCustody onboards @alice
    Then the sealed document is written before the pointer
    And the client opens on the keys without the APKAM private key
    And the credential and enrollment id are remembered
    # Test: packages/at_client/test/passkey/passkey_custody_test.dart :: onboard writes writes the document, then the pointer
    # Test: packages/at_client/test/passkey/passkey_custody_test.dart :: onboard writes opens the client with the @keys, without the APKAM private key
    # Test: packages/at_client/test/passkey/passkey_custody_test.dart :: onboard writes remembers the credential and enrollment id and asks for persistence

  Scenario: Login with saved hints asks nothing of the atServer's pointer
    Given an onboarded @alice and a device that remembers its credential and enrollment
    When PasskeyCustody opens @alice
    Then the pointer is not read
    And the passkey assertion is narrowed to the remembered credential
    # Test: packages/at_client/test/passkey/passkey_custody_test.dart :: open returns without reading the pointer when the device remembers
    # Test: packages/at_client/test/passkey/passkey_custody_test.dart :: open narrows the assertion to the remembered credential

  Scenario: Login with stale hints finds the enrollment again through the pointer, once
    Given hints that name a deleted passkey or a replaced enrollment
    When PasskeyCustody opens @alice
    Then any discoverable passkey is tried and the pointer names the enrollment
    And a second failure is a lost passkey rather than another retry
    # Test: packages/at_client/test/passkey/passkey_custody_test.dart :: open stale hints a deleted passkey is replaced by any discoverable one
    # Test: packages/at_client/test/passkey/passkey_custody_test.dart :: open stale hints a replaced enrollment is found again through the pointer
    # Test: packages/at_client/test/passkey/passkey_custody_test.dart :: open stale hints the retry happens once, then the passkey is lost
    # Test: packages/at_client/test/passkey/passkey_custody_test.dart :: open stale hints a refused PKAM is retried once, then it is lost

  Scenario: An onboarding that stopped after the activation is resumed by the next onboard
    Given a pending record for @alice and no CRAM secret left to spend
    When PasskeyCustody onboards @alice again
    Then it resumes without a new passkey and without the CRAM secret
    And it files the keys the record held
    # Test: packages/at_client/test/passkey/pending_onboarding_test.dart :: onboard with a record resumes without registering and without the CRAM
    # Test: packages/at_client/test/passkey/pending_onboarding_test.dart :: onboard with a record files the keys the record held
    # Test: packages/at_client/test/passkey/pending_onboarding_test.dart :: T5 a failed open keeps the record onboard: the retry resumes it with no new passkey and no CRAM

  Scenario: An onboarding that stopped after the activation is resumed by open
    Given a pending record for @alice
    When PasskeyCustody opens @alice
    Then the record is resumed under the setup lock
    # Test: packages/at_client/test/passkey/pending_onboarding_test.dart :: open with a record resumes it under the setup lock
    # Test: packages/at_client/test/passkey/pending_onboarding_test.dart :: T5 a failed open keeps the record open: the retry resumes it with no new passkey and no CRAM

  Scenario: A failed open keeps the pending record
    Given a pending record for @alice and a client that fails to open
    When the resume fails
    Then the record stays for the next try
    # Test: packages/at_client/test/passkey/pending_onboarding_test.dart :: T5 a failed open keeps the record a resumed record whose open fails stays for the next try
    # Test: packages/at_client/test/passkey/pending_onboarding_test.dart :: T5 a failed open keeps the record a login whose open fails keeps the record it proved obsolete

  Scenario: An explicit refusal of the enrollment drops the pending record
    Given a pending record whose enrollment the atServer refuses PKAM for
    When PasskeyCustody onboards or opens @alice
    Then the record is dropped and the new CRAM or the login carries on
    But a refused enrollment that is not the record's leaves the record
    # Test: packages/at_client/test/passkey/pending_onboarding_test.dart :: a pending record whose enrollment the atServer refuses PKAM onboard drops it and carries on with the new CRAM
    # Test: packages/at_client/test/passkey/pending_onboarding_test.dart :: a pending record whose enrollment the atServer refuses PKAM open drops it under the lock and continues the login
    # Test: packages/at_client/test/passkey/pending_onboarding_test.dart :: a pending record whose enrollment the atServer refuses PKAM open keeps a record whose refused enrollment is not the record's

  Scenario Outline: A server error or throttling during PKAM keeps the record and the hints
    Given a pending record for @alice
    When the atServer answers PKAM with "<reply>"
    Then the record is kept on a resumed onboard and on a resumed open
    And a login with hints keeps them and does not retry
    And the failure is not a lost passkey
    # Test: packages/at_client/test/passkey/pending_onboarding_test.dart :: T-ticket1 a server error or throttle during PKAM is no refusal "$reply" keeps the record on a resumed onboard
    # Test: packages/at_client/test/passkey/pending_onboarding_test.dart :: T-ticket1 a server error or throttle during PKAM is no refusal "$reply" keeps the record on a resumed open
    # Test: packages/at_client/test/passkey/pending_onboarding_test.dart :: T-ticket1 a server error or throttle during PKAM is no refusal "$reply" on a login with hints keeps them and is not retried
    # Test: packages/at_client/test/passkey/pending_onboarding_test.dart :: T-ticket1 a server error or throttle during PKAM is no refusal "$reply" on a login through the pointer is not a lost passkey
    Examples:
      | reply                   |
      | error:AT0028:throttled  |

  Scenario: A failing pending-record delete is logged at severe and does not fail the open
    Given a pending store whose delete fails
    When an open deletes or drops an obsolete record
    Then the failure is logged at severe with the enrollment id and error type only
    # Test: packages/at_client/test/passkey/pending_onboarding_test.dart :: an obsolete pending record a failing store is logged with the enrollment id and type only

  Scenario: Discarding with no pending record changes nothing
    Given no pending record for @alice
    When @alice's pending onboarding is discarded, once or twice
    Then nothing is removed, and the hints stay
    # Test: packages/at_client/test/passkey/pending_onboarding_test.dart :: discardPendingOnboarding does nothing when there is no record, or the second time
    # Test: packages/at_client_wasm/test/web/passkey_custody_browser_test.dart :: discarding with no pending record keeps the atSign's hints

  Scenario: Discarding clears hints only when they name the discarded enrollment
    Given a pending record and hints for @alice, and hints for @other
    When @alice's pending onboarding is discarded
    Then the record is deleted without a ceremony or a server call
    And @alice's hints are cleared when they name the record's enrollment
    But hints that name another enrollment, and @other's hints, stay
    # Test: packages/at_client/test/passkey/pending_onboarding_test.dart :: discardPendingOnboarding removes the record without a ceremony or a server call
    # Test: packages/at_client_wasm/test/web/passkey_custody_browser_test.dart :: discarding deletes the record and the hints that name its enrollment, and no other atSign's hints
    # Test: packages/at_client_wasm/test/web/passkey_custody_browser_test.dart :: discarding deletes the record and keeps hints that name another enrollment

  Scenario: The unfinished activation hands its keys over once
    Given an onboarding whose activation did not finish
    When the keys are taken from OnboardingIncompleteException and taken again
    Then the second take throws StateError
    # Test: packages/at_client/test/passkey/pending_onboarding_test.dart :: T7 the unfinished activation hands its keys over once after onboard takes them the exception no longer holds them
    # Test: packages/at_client/test/passkey/enrollment_gateway_test.dart :: T7 the exception hands its keys over once and forgets them

  Scenario: Closing the key store zeroes the pair, and a read after close throws
    Given a key store the client closes when it stops
    When the key store is closed
    Then a read throws StateError and the pair is zeroed
    And the vault it was given is closed
    # Test: packages/at_client/test/passkey/at_server_at_keys_io_test.dart :: close zeroes the private key, so a read after close throws
    # Test: packages/at_client/test/passkey/passkey_open_test.dart :: C1 and C5 reads a read after close throws StateError and the pair is gone

  Scenario: A store that is lent zeroes its pair and leaves the lender's vault open
    Given a key store built without closedByClient
    When the key store is closed
    Then a read throws StateError and a write is refused
    And the vault it was lent still opens
    # Test: packages/at_client/test/passkey/at_server_at_keys_io_test.dart :: close a store that is lent zeroes its key and refuses writes, and leaves the vault it was given open

  Scenario: A write queued after the key store closed is refused with no I/O
    Given an update running on a key store and a second queued behind it
    When the key store is closed
    Then the running update finishes whole and the queued one is refused
    And nothing is sent to the atServer after the close
    # Test: packages/at_client/test/passkey/at_server_at_keys_io_test.dart :: close an update in flight finishes whole before the vault closes; one queued behind it is refused with no I/O
    # Test: packages/at_client/test/passkey/at_server_at_keys_io_test.dart :: close closes the vault, after which a flush or update throws

  Scenario: Writes from one client are serialised
    Given two overlapping updates on one key store
    When both run
    Then both land, one after the other, and a failing one does not stop the next
    # Test: packages/at_client/test/passkey/at_server_at_keys_io_test.dart :: two overlapping updates on one instance both land
    # Test: packages/at_client/test/passkey/at_server_at_keys_io_test.dart :: a queued update still runs when the one before it throws
    # Test: packages/at_client/test/passkey/at_server_at_keys_io_test.dart :: two stores on one record: a change made while the other held a stale read is refused, typed, and the first change stays

  Scenario: The stored document never holds APKAM private material
    Given keys that carry the derived APKAM private key
    When the key store writes, flushes or updates them
    Then the sealed document holds no APKAM private key
    # Test: packages/at_client/test/passkey/passkey_open_test.dart :: T3 the stored document never holds APKAM private material write, flush and update strip the overlay
    # Test: packages/at_client/test/passkey/passkey_open_test.dart :: T3 the stored document never holds APKAM private material a first write of keys carrying the flat key strips it
    # Test: packages/at_client/test/passkey/passkey_custody_test.dart :: onboard writes seals the document without the APKAM private key

  Scenario Outline: A foreign private authentication key is refused in any status
    Given keys that hold a <status> private authentication key that is not the store's own pair
    When the key store flushes them
    Then the flush is refused, the document is unchanged and no further write is accepted
    # Test: packages/at_client/test/passkey/at_server_at_keys_io_test.dart :: a flush carrying a <status> foreign private auth key is refused
    # Test: packages/at_client/test/passkey/passkey_open_test.dart :: T8 foreign private authentication material a flush carrying another private auth key is refused
    # Test: packages/at_client/test/passkey/passkey_open_test.dart :: T8 foreign private authentication material a flat private key that is not the pair is refused
    Examples:
      | status  |
      | active  |
      | pending |
      | retired |

  Scenario: A sealed record does not open for another atSign
    Given a record sealed for @alice
    When it is opened with @bob's sealer
    Then it fails authentication
    # Test: packages/at_auth/test/passkey/passkey_record_test.dart :: another atSign's sealer cannot open the record
    # Test: packages/at_client/test/passkey/passkey_custody_test.dart :: second passkey X-K18: a second passkey derives different keys, so it cannot open

  Scenario Outline: An atSign not in canonical form is refused before any work
    Given the atSign "<atSign>"
    When PasskeyCustody onboards, opens or discards it
    Then InvalidAtSignException is thrown and no ceremony or setup lock is used
    # Test: packages/at_client/test/passkey/passkey_custody_test.dart :: an atSign not in canonical form "<atSign>" is refused by onboard, open and discard before any work
    # Test: packages/at_client_wasm/test/web/passkey_custody_browser_test.dart :: a discard of an atSign not in canonical form is refused
    Examples:
      | atSign      |
      | alice       |
      | left@right  |
      | @left@right |
      | @@alice     |

  Scenario Outline: A line break in a stored value is refused before any command
    Given a document or pointer record containing <break>
    When it is put to the atServer
    Then ArgumentError is thrown and no command is sent
    # Test: packages/at_client/test/passkey/enrollment_document_store_test.dart :: put rejects a document with a newline
    # Test: packages/at_client/test/passkey/enrollment_document_store_test.dart :: put rejects a document with a carriage return
    # Test: packages/at_client/test/passkey/enrollment_pointer_store_test.dart :: RemoteEnrollmentPointerStore put rejects a record with a newline
    # Test: packages/at_client/test/passkey/enrollment_pointer_store_test.dart :: RemoteEnrollmentPointerStore put rejects a record with a carriage return
    Examples:
      | break           |
      | a line feed     |
      | a carriage return |

  Scenario: A swapped pointer is refused by PKAM before any document is read
    Given a pointer that names an enrollment the passkey did not make
    When PasskeyCustody opens @alice
    Then PKAM refuses it before any document read
    # Test: packages/at_client/test/passkey/passkey_custody_test.dart :: open a swapped pointer is refused by PKAM before any document read
