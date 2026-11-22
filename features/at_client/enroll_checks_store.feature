Feature: Atsign.enroll checks the AtKeys store before it sends the request

  Atsign.enroll reads the AtKeys store as Atsign.open and
  Atsign.resumeEnrollment read it, before it sends anything: keys it cannot
  read, and keys recorded for another Atsign, are refused with
  AtKeysUnusableException and a cause the app can switch on. A store that
  holds nothing yet is asked whether it can be written, as onboarding asks,
  before the request goes out, since the request spends the passcode. A
  request that has gone out and then cannot be filed throws
  AtEnrollmentException naming the enrollment it sent, for the Atsign's
  manager to deny, and why it could not be filed.

  Races: the read before sending is a snapshot. The request is filed in the
  store's one update, which checks again, as now; a store another process
  changes in between, or makes unwritable, is reported naming the sent
  enrollment.
  Replay: none arises; a refused store sends nothing, and nothing new is
  sent.
  DoS: every check reads or probes the local store before anything is sent.
  The writability probe creates the keyfile's directory, as filing would,
  and a file it removes.
  Forgery and impersonation: only whoever already holds the store can put
  another Atsign's keys in it. The refusal keeps this Atsign's request out of
  them, and names the Atsign they record.

  Scenario: An enroll refuses keys it cannot read, before anything is sent
    Given an AtKeys store for @alice that cannot be read
    When an app asks to enroll @alice into that store
    Then enroll throws AtKeysUnusableException with cause unreadable and the message "The keys for @alice in the AtKeys store (<path>) could not be read: <reason>.", holding none of the store's contents, and nothing is sent to the atServer
    # cases: not JSON; a field of the wrong type

  Scenario Outline: An enroll refuses keys recorded for another Atsign, before anything is sent
    Given an AtKeys store whose atsign is @bob, holding <held>
    When an app asks to enroll @alice into that store
    Then enroll throws AtKeysUnusableException with cause anotherAtsign and the message "The keys in the AtKeys store (<path>) are for @bob, not @alice.", the store is unchanged, and nothing is sent to the atServer
    Examples:
      | held                      |
      | @bob's live keys          |
      | @bob's pending enrollment |
      | nothing                   |

  Scenario: An enroll refuses an AtKeys store it cannot write, before anything is sent
    Given no keys for @alice yet, in a keyfile whose directory cannot be written
    When an app asks to enroll @alice into that store
    Then enroll throws the store's refusal, naming the keyfile's path, and nothing is sent to the atServer

  Scenario Outline: A request that was sent and cannot be filed names the enrollment it sent
    Given <store>
    When an app enrolls @alice into that store, and the atServer accepts the request as e-1
    Then enroll throws AtEnrollmentException with the message "the atSign's manager can deny enrollment "e-1" of @alice, which is not filed: filing it in the AtKeys store (<path>) failed: <the failure's first line>", escaped and clipped, and the store is unchanged
    Examples:
      | store                                                                                |
      | a keyfile for @alice that a denial left empty, in a directory that cannot be written |
      | an AtKeys store for @alice whose write fails                                         |
