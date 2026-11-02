Feature: The SDK's activation dialogs keep a pending enrollment until the user abandons it

  A program that has submitted an enrollment request means to complete it:
  it waits for the request to be approved, denied or to expire, across
  restarts. ApkamActivationDialog stops its wait when the user leaves it and
  keeps the request, which the next onboarding resumes without asking for a
  passcode. Only Cancel, a button of its own beside the back arrow, abandons
  the request, after the user confirms it. PkamDialog, given a keychain entry
  that holds only an enrollment awaiting approval, resumes it in the same way.

  Races: leaving stops the wait before the dialog goes, so a dialog reopened
  at once waits alone; an approval that lands as the user leaves is not
  written, and the next resume completes it, while a client opened on an
  approval already written is stopped.
  Replay: none arises; leaving and Cancel send nothing.
  DoS: no poll runs once the user has left.
  Forgery and impersonation: the dialogs resume only what the store they are
  given holds for their atSign, and abandoning needs a confirmed Cancel.

  Scenario: Leaving the waiting screen keeps the request
    Given the dialog waiting for approval
    When the user leaves it without choosing Cancel
    Then its wait is stopped, not cancelled, the pending keys stay, and no client is returned

  Scenario: Leaving while the request is still being sent
    Given the dialog sending its request
    When the user leaves it
    Then the wait is stopped once the request is in, and its keys stay

  Scenario: Cancel asks first
    Given the dialog waiting for approval
    When the user chooses Cancel
    Then a confirmation names the enrollment id and says this abandons the request, and that trying again needs a new OTP from another enrollment; nothing ends yet

  Scenario: A confirmed Cancel abandons
    Given that confirmation
    When the user confirms
    Then cancel runs and the pending keys go, the user is told to ask the atSign's manager to deny that enrollment id, and the dialog closes with no client

  @race
  Scenario: A confirmed Cancel after the approval was written says to revoke it
    Given that confirmation, and the approval written to the store just before cancel runs
    When the user confirms
    Then the user is told the enrollment was approved before it could be abandoned, that its keys stay in the key store, and to ask the atSign's manager to revoke it, and the dialog closes with no client

  Scenario: A declined Cancel changes nothing
    Given that confirmation
    When the user declines
    Then the wait goes on

  Scenario: A confirmed Cancel that cannot remove the keys says so, and the request is kept
    Given that confirmation, and a store that cannot be updated
    When the user confirms
    Then the dialog says the request could not be abandoned and the pending keys stay, its wait has ended, and it stays open offering Cancel again; choosing it again retries cancel; leaving keeps the request, and the next open resumes it

  @race
  Scenario: An approval landing while Cancel is being confirmed closes the confirmation and returns the client
    Given the Cancel confirmation showing
    When the approval arrives and the client opens
    Then the confirmation closes, nothing is cancelled, and the dialog returns the client

  Scenario: PkamDialog resumes a pending keychain entry
    Given a keychain entry for an atSign holding only an enrollment awaiting approval
    When the user logs in with it through PkamDialog
    Then it waits on that enrollment as ApkamActivationDialog does, without asking for a passcode, and returns the client opened on approval
