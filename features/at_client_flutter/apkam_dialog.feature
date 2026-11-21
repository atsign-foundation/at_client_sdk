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
  approval already written is stopped; a request another process on this
  device completes or abandons first is found as it then is.
  Replay: none arises; leaving and Cancel send nothing.
  DoS: no poll runs once the user has left.
  Forgery and impersonation: the dialogs resume only what the store they are
  given holds for their atSign, and abandoning needs a confirmed Cancel; the
  dialog adopts only a request in the store it is given, which only programs
  on this device write; the names it shows are the ones the request was
  filed under, with their control characters escaped and each clipped at
  180 characters, and its warning quotes them.

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

  Scenario Outline: The enrollment dialog adopts the request its store holds under another app or device name
    Given a key store holding one pending enrollment <id> for @alice, filed by app "wavi-old" on device "phone"
    When ApkamActivationDialog opens @alice for app "<app>" on device "<device>"
    Then it shows "Resuming enrollment <id>, filed as wavi-old on phone.." and Cancel, without asking for a passcode
    And it logs a warning naming wavi-old and <app>
    And once the request is approved, the dialog returns the client

    Examples:
      | app      | device |
      | wavi     | phone  |
      | wavi-old | tablet |

  Scenario: The enrollment dialog waits on its own request when its store holds several
    Given a key store holding two pending enrollments for @alice, one filed by this app under device name "phone" and one under "old-phone"
    When ApkamActivationDialog opens @alice with device name "phone"
    Then it shows "Resuming enrollment <the phone request's id>.." and Cancel, without asking for a passcode

  Scenario: The enrollment dialog resumes this app's request from another device before another app's
    Given a key store holding pending enrollments for @alice filed by app "wavi" on device "old-phone" and by app "buzz" on device "phone"
    When ApkamActivationDialog opens @alice for app "wavi" on device "new-phone"
    Then it shows "Resuming enrollment <id>, filed as wavi on old-phone.." and Cancel, without asking for a passcode

  Scenario: The enrollment dialog says it cannot go on when its store holds several requests, none its own
    Given a key store holding pending enrollments for @alice filed by app "wavi" on device "phone" and by app "wavi" on device "tablet"
    When ApkamActivationDialog opens @alice for app "wavi" on device "laptop"
    Then it says this device already has several requests waiting for approval, in place of the Activate button
    And a passcode entered is never sent, and no request is waited on

  Scenario: The enrollment dialog does not wait on a request filed for other namespaces
    Given a key store holding one pending enrollment <id> for @alice, filed by app "todos" for namespaces {todos: rw}
    When ApkamActivationDialog opens @alice for app "todos2" with namespaces {todos2: rw}
    Then it says the request waiting for approval was filed for other namespaces, in place of the Activate button, and logs a warning naming <id>
    And it never waits on that request, and a passcode entered is never sent

  Scenario: The enrollment dialog shows a recorded app name with its control characters escaped
    Given a key store holding one pending enrollment <id> for @alice, filed by app "wa<ESC>vi" on device "phone"
    When ApkamActivationDialog opens @alice for app "wavi" on device "phone"
    Then it shows "Resuming enrollment <id>, filed as wa\u001bvi on phone.." and Cancel

  Scenario: The enrollment dialog's adoption warning names the recorded app quoted and escaped
    Given a key store holding one pending enrollment <id> for @alice, filed by app "wa<ESC>vi" on device "phone"
    When ApkamActivationDialog opens @alice for app "wavi" on device "phone"
    Then the warning it logs names the filed app as "wa\u001bvi", in double quotes

  Scenario: The enrollment dialog's adoption warning escapes a double quote inside the recorded app name
    Given a key store holding one pending enrollment <id> for @alice, filed by app wa"vi on device "phone"
    When ApkamActivationDialog opens @alice for app "wavi" on device "phone"
    Then the warning it logs names the filed app as "wa\"vi"

  Scenario: PkamDialog resumes a pending keychain entry
    Given a keychain entry for an atSign holding only an enrollment awaiting approval
    When the user logs in with it through PkamDialog
    Then it waits on that enrollment as ApkamActivationDialog does, without asking for a passcode, and returns the client opened on approval
