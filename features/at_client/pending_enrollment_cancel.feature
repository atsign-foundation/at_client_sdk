Feature: An app ends a pending enrollment's wait with stop() or cancel()

  PendingEnrollment.stop() ends the wait awaitApproval or client() is in,
  which throws StoppedException, and keeps the request: its pending keys stay
  in the store, so Atsign.resumeEnrollment picks it up again, with no names
  when the store holds that one pending enrollment. stop() closes the
  handshake connection it built, leaves one the app supplied open, sends
  nothing, and does nothing once the wait has ended.

  PendingEnrollment.cancel() ends the wait awaitApproval or client() is in.
  The wait throws AtEnrollmentCancelledException, an AtEnrollmentException,
  once this enrollment's pending keys have left the store, as a denial's do.
  A cancel that cannot remove them throws, and a later cancel tries again.
  Nothing withdraws the request on the atServer: the atSign's manager can
  still approve it, and that approval names keys nobody holds.

  An expired request, which the atServer answers with AT0028, has its pending
  keys removed as a denial does.

  Races: a stop or a cancel and an approval resolve at the write to the
  store. One that lands first leaves nothing written. stop then cancel
  removes the keys; cancel then stop changes nothing. An approval written first
  stands, and if a stop or a cancel lands before client() returns, the
  client it opened is stopped before the stop or cancel returns. A cancel and
  a denial at once both remove the pending keys, once.
  Replay: none arises; stop and cancel send nothing, and a resume polls the
  same enrollment as before.
  DoS: no poll runs after stop or cancel, on any connection; expiry ends a
  wait that every restart would otherwise resume into the same answer.
  Forgery and impersonation: cancel and expiry remove only this enrollment's
  pending keys, found by atSign and enrollment id. A resume with no names
  trusts the store it is given, as open does: a pending entry planted there
  still needs the manager's approval, and a passcode from an enrolled app to
  have been submitted at all.

  Scenario: Cancel ends a wait for approval
    Given a pending enrollment waiting in awaitApproval
    When the app calls cancel
    Then awaitApproval throws AtEnrollmentCancelledException, the enrollment's pending keys are gone from the store, and no further poll reaches the atServer

  Scenario: The cancelled wait throws only after the pending keys are gone
    Given a pending enrollment waiting in client(), in a program that exits as soon as client() throws
    When the program calls cancel() without awaiting it
    Then when client() throws AtEnrollmentCancelledException the keyfile holds none of the enrollment's pending keys
    And an approval of the request afterwards leaves nothing for resumeEnrollment or CLIBase to open

  Scenario: Cancel leaves no copy of the pending keys beside a keyfile
    Given a pending enrollment filed in a keyfile
    When the app calls cancel
    Then neither the keyfile nor the copy the file store keeps beside it holds the enrollment's pending keys

  Scenario: An approval that arrives after cancel writes nothing
    Given a pending enrollment whose wait was cancelled
    When the atSign's manager then approves the request
    Then the store holds nothing for the enrollment, and no client is opened

  Scenario: A cancel that lands between the atServer's approval and the write
    Given an approval the atServer has given, not yet written to the store
    When the app calls cancel
    Then nothing is written, the pending keys are gone, and the wait throws AtEnrollmentCancelledException

  @race
  Scenario: A cancel while client() opens the approved client
    Given an approval already written to the store, and client() opening a client on it
    When the app calls cancel
    Then cancel returns once that client has stopped, so the atSign opens again on the approved keys at once; client() throws AtEnrollmentCancelledException saying the approval was written, approved is true, and the approved keys stay in the store

  Scenario: Cancel after approval does nothing
    Given a pending enrollment whose client() has returned an open client
    When the app calls cancel
    Then the client keeps running and the store keeps the approved keys

  Scenario: A repeat cancel does nothing
    Given a pending enrollment whose wait was cancelled
    When the app calls cancel again
    Then it completes without error and nothing more changes

  Scenario: A cancel that cannot remove the pending keys throws
    Given a pending enrollment waiting in awaitApproval, in a store that cannot be updated
    When the app calls cancel
    Then the wait throws AtEnrollmentCancelledException, and cancel throws the store's failure

  Scenario: A cancel after one that failed removes the pending keys
    Given a pending enrollment whose cancel threw because the store could not be updated
    When the app calls cancel again once the store can be updated
    Then the enrollment's pending keys are gone from the store

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

  Scenario: A cancel signal that fails ends the wait
    Given at_auth waiting for approval with a cancel signal
    When the signal completes with an error
    Then the wait throws StoppedException at once, and no error escapes it

  Scenario: Stop ends a wait and keeps the request
    Given a pending enrollment waiting in awaitApproval, on a connection it built
    When the app calls stop
    Then awaitApproval throws StoppedException, no further poll reaches the atServer, the connection is closed, and the pending keys stay in the store

  Scenario: A stopped request resumes
    Given a pending enrollment whose wait was stopped
    When the app calls Atsign.resumeEnrollment for its app and device
    Then it waits again on the same enrollment id, with no new request

  Scenario: Stop leaves a connection the app supplied open
    Given a pending enrollment waiting on a connection the app supplied
    When the app calls stop
    Then the wait throws StoppedException, and the connection is neither stopped nor closed

  Scenario: A repeat stop does nothing
    Given a pending enrollment whose wait was stopped
    When the app calls stop again
    Then it completes without error, and nothing more changes

  Scenario: Stop before anyone waits
    Given a pending enrollment nobody is waiting on
    When the app calls stop
    Then a later awaitApproval throws StoppedException, and the pending keys stay

  Scenario: Cancel after stop abandons
    Given a pending enrollment whose wait was stopped
    When the app calls cancel
    Then the pending keys are gone

  Scenario: An approval landing as stop does is not written, and the next resume completes it
    Given an approval the atServer has given, not yet written to the store
    When the app calls stop
    Then nothing is written, the pending keys stay, and the wait throws StoppedException; a later resume finds the request approved and completes the keys

  @race
  Scenario: Stop while client() opens the approved client
    Given an approval already written, and client() opening a client on it
    When the app calls stop
    Then stop returns once that client has stopped, so the atSign opens again on the approved keys at once; client() throws StoppedException saying the approval was written, approved is true, and the approved keys stay

  @race
  Scenario: A second stop or cancel while the first waits for client()
    Given a stop or cancel waiting for client() to stop the client it opened
    When the app calls stop or cancel again
    Then that call also returns once the client has stopped

  @race
  Scenario: A stop or cancel awaited inside client()'s own work
    Given client() awaiting a key store or connection that awaits stop or cancel
    When that call runs
    Then it returns without waiting for client(), which then ends leaving no client live

  Scenario: An expired request's keys go, as a denial's do
    Given a pending enrollment whose request the atServer reports as expired (AT0028)
    When the wait polls
    Then awaitApproval throws AtEnrollmentException naming the expiry, and the enrollment's pending keys are gone from the store

  Scenario: The one pending enrollment resumes with no names
    Given a store holding one pending enrollment
    When the app calls resumeEnrollment with no app or device
    Then it gets that enrollment

  Scenario: Resuming by one name refuses a store holding several requests it names
    Given a store holding two pending requests for one app, from two devices
    When the app calls resumeEnrollment with only the app
    Then it throws AtEnrollmentPendingException naming both and saying to name the app and device, and naming a device as well resumes that one
