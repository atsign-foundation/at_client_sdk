Feature: The SDK's activation dialogs keep a pending enrollment until the user abandons it

  A program that has submitted an enrollment request means to complete it:
  it waits for the request to be approved, denied or to expire, across
  restarts. ApkamActivationDialog stops its wait when the user leaves it and
  keeps the request, which the next onboarding resumes without asking for a
  passcode. Only Cancel, a button of its own beside the back arrow, abandons
  the request, after the user confirms it. PkamDialog, given a keychain entry
  that holds only an enrollment awaiting approval, resumes it in the same way,
  and offers the same Cancel.

  Races: leaving stops the wait before the dialog goes, so a dialog reopened
  at once waits alone; an approval that lands as the user leaves is not
  written, and the next resume completes it, while a client opened on an
  approval already written is stopped; a request another process on this
  device completes or abandons first is found as it then is; a wait whose
  request another wait cancels ends with its failure shown, since only the
  user's own confirmed Cancel ends a wait silently; and a dialog closes
  once, whichever of its wait's failure, a confirmed Cancel and the user's
  leaving comes first.
  Replay: none arises; leaving and Cancel send nothing.
  DoS: no poll runs once the user has left.
  Forgery and impersonation: the dialogs resume only what the store they are
  given holds for their atSign, and abandoning needs a confirmed Cancel; the
  dialog adopts only a request in the store it is given, which only programs
  on this device write; the names it shows are the ones the request was
  filed under, with their control characters escaped and each clipped at
  180 characters.

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
  Scenario: A confirmed Cancel after the approval was written lets the approval stand
    Given that confirmation, and the approval written to the store just before cancel runs
    When the user confirms
    Then the user is told the approval landed before the Cancel took effect, so it stands, and the dialog returns the client opened on the approved keys

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

  @race
  Scenario: A failure while Cancel is being confirmed closes the confirmation and shows the failure
    Given the Cancel confirmation showing
    When the wait fails
    Then the confirmation closes, the failure is shown and the dialog stays open

  @race
  Scenario: Leaving the enrollment dialog while its confirmed Cancel runs closes it once
    Given the dialog waiting for approval
    When the user confirms Cancel and leaves with the back arrow before the pending keys are removed
    Then the dialog closes with no client, and the screen it was opened from stays

  @race
  Scenario: The enrollment dialog says so when another wait has cancelled the request it waits on
    Given the enrollment dialog waiting on a request, and Cancel not chosen
    When its wait ends because another wait cancelled the request
    Then the failure is shown and the dialog stays open

  Scenario Outline: The enrollment dialog adopts the request its store holds under another app or device name
    Given a key store holding one pending enrollment <id> for @alice, filed by app "wavi-old" on device "phone"
    When ApkamActivationDialog opens @alice for app "<app>" on device "<device>"
    Then it shows "Resuming enrollment <id>, filed as wavi-old on phone.." and Cancel, without asking for a passcode
    And once the request is approved, the dialog returns the client

    Examples:
      | app      | device |
      | wavi     | phone  |
      | wavi-old | tablet |

  Scenario: The enrollment dialog waits on a request filed for other namespaces
    Given a key store holding one pending enrollment <id> for @alice, filed by app "todos" on device "phone" for namespaces {todos: rw}
    When ApkamActivationDialog opens @alice for app "todos2" on device "phone" with namespaces {todos2: rw}
    Then it shows "Resuming enrollment <id>, filed as todos on phone.." and Cancel, without asking for a passcode
    And once the request is approved, the dialog returns the client

  Scenario: The enrollment dialog shows a recorded app name with its control characters escaped
    Given a key store holding one pending enrollment <id> for @alice, filed by app "wa<ESC>vi" on device "phone"
    When ApkamActivationDialog opens @alice for app "wavi" on device "phone"
    Then it shows "Resuming enrollment <id>, filed as wa\u001bvi on phone.." and Cancel

  Scenario: The Cancel confirmation shows the enrollment id with its control characters escaped
    Given a dialog waiting on an enrollment whose id holds an ESC character
    When the user chooses Cancel
    Then the confirmation shows the id with the ESC escaped as \u001b

  Scenario: The abandoned message shows the enrollment id with its control characters escaped
    Given a dialog waiting on an enrollment whose id holds an ESC character
    When the user confirms Cancel and the pending keys are removed
    Then the message saying the request was abandoned shows the ESC escaped as \u001b

  Scenario: PkamDialog resumes a pending keychain entry
    Given a keychain entry for an atSign holding only an enrollment awaiting approval
    When the user logs in with it through PkamDialog
    Then it waits on that enrollment as ApkamActivationDialog does, without asking for a passcode, and returns the client opened on approval

  Scenario: PkamDialog's Cancel asks first
    Given PkamDialog waiting on the enrollment it resumed from a keychain entry
    When the user chooses Cancel
    Then a confirmation names the enrollment id and says this abandons the request, and that trying again needs a new OTP from another enrollment; nothing ends yet

  Scenario: A confirmed Cancel in PkamDialog abandons
    Given that confirmation
    When the user confirms
    Then cancel runs and the pending keys go, the user is told to ask the atSign's manager to deny that enrollment id, no failure is shown, and the dialog closes with no client

  @race
  Scenario: A confirmed Cancel in PkamDialog after the approval was written lets the approval stand
    Given that confirmation, and the approval written to the store just before cancel runs
    When the user confirms
    Then the user is told the approval landed before the Cancel took effect, so it stands, and the dialog returns the client opened on the approved keys

  Scenario: A declined Cancel in PkamDialog changes nothing
    Given that confirmation
    When the user declines
    Then the wait goes on

  Scenario: A confirmed Cancel in PkamDialog that cannot remove the keys says so, and the request is kept
    Given that confirmation, and a store that cannot be updated
    When the user confirms
    Then the dialog says the request could not be abandoned and the pending keys stay, its wait has ended, and it stays open offering Cancel again; choosing it again retries cancel

  @race
  Scenario: An approval landing while PkamDialog's Cancel is being confirmed closes the confirmation and returns the client
    Given the Cancel confirmation showing in PkamDialog
    When the approval arrives and the client opens
    Then the confirmation closes, nothing is cancelled, and the dialog returns the client

  @race
  Scenario: PkamDialog says so when another wait has cancelled the request it waits on
    Given PkamDialog waiting on a resumed enrollment, and Cancel not chosen
    When its wait ends because another wait cancelled the request
    Then the failure is shown and the dialog closes with no client

  @race
  Scenario: A failure while PkamDialog's Cancel is being confirmed closes the confirmation and the dialog
    Given PkamDialog's Cancel confirmation showing
    When the wait fails
    Then the confirmation closes, the failure is shown and the dialog closes with no client

  @race
  Scenario: A failure ending PkamDialog's wait as its confirmed Cancel runs closes the dialog once
    Given PkamDialog waiting on a resumed enrollment
    When the user confirms Cancel, and the wait then fails with a denial as the dialog closes
    Then the dialog closes with no client, and the screen it was opened from stays
