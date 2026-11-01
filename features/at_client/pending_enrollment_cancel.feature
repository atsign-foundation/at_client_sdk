Feature: An app ends a pending enrollment's wait with cancel()

  PendingEnrollment.cancel() ends the wait awaitApproval or client() is in.
  The wait throws AtEnrollmentCancelledException, an AtEnrollmentException,
  and this enrollment's pending keys leave the store, as a denial's do.
  Nothing withdraws the request on the atServer: the atSign's manager can
  still approve it, and that approval names keys nobody holds.

  Races: a cancel and an approval resolve at the write to the store. A
  cancel that lands first leaves nothing written. An approval written first
  stands, and if cancel lands before client() returns, the client it opened
  is stopped. A cancel and a denial at once both remove the pending keys,
  once.
  Replay: none arises; cancel sends nothing.
  DoS: no poll runs after cancel, on any connection.
  Forgery and impersonation: cancel removes only this enrollment's pending
  keys, found by atSign and enrollment id.

  Scenario: Cancel ends a wait for approval
    Given a pending enrollment waiting in awaitApproval
    When the app calls cancel
    Then awaitApproval throws AtEnrollmentCancelledException, the enrollment's pending keys are gone from the store, and no further poll reaches the atServer

  Scenario: An approval that arrives after cancel writes nothing
    Given a pending enrollment whose wait was cancelled
    When the atSign's manager then approves the request
    Then the store holds nothing for the enrollment, and no client is opened

  Scenario: A cancel that lands between the atServer's approval and the write
    Given an approval the atServer has given, not yet written to the store
    When the app calls cancel
    Then nothing is written, the pending keys are gone, and the wait throws AtEnrollmentCancelledException

  Scenario: A cancel while client() opens the approved client
    Given an approval already written to the store, and client() opening a client on it
    When the app calls cancel
    Then the client is stopped, client() throws AtEnrollmentCancelledException, and the approved keys stay in the store

  Scenario: Cancel after approval does nothing
    Given a pending enrollment whose client() has returned an open client
    When the app calls cancel
    Then the client keeps running and the store keeps the approved keys

  Scenario: A repeat cancel does nothing
    Given a pending enrollment whose wait was cancelled
    When the app calls cancel again
    Then it completes without error and nothing more changes

  Scenario: A connection the app supplied is left open
    Given a pending enrollment built with a connection the app supplied, waiting in awaitApproval
    When the app calls cancel
    Then the wait throws AtEnrollmentCancelledException, no further poll runs on that connection, and the connection is neither stopped nor closed

  Scenario: Cancel before anyone waits
    Given a pending enrollment nobody is waiting on
    When the app calls cancel
    Then its pending keys are gone, and a later awaitApproval throws AtEnrollmentCancelledException

  Scenario: A stopped connection ends the wait at once
    Given at_auth waiting for approval on a connection
    When the connection is stopped
    Then the wait throws StoppedException at the next poll, without spending its retry budget
