Feature: The onboarding dialogs say what failed

  PkamDialog, CramDialog, ApkamDialog and RegistrarCramDialog show a message
  chosen by what failed: a keys problem its own message, an atServer refusal
  its cause in plain words, a network failure the advice to check the
  connection, and anything else that something went wrong with the
  exception's message. No dialog shows a stack trace. PkamDialog's contract
  is unchanged: only a refusal on a device that has never held the atSign
  online is a failure.

  Races: none arise; each dialog shows one outcome of one attempt.
  Replay: none arise; nothing new is sent.
  DoS: none arise.
  Forgery: none arise; a message names only the atSign, the keys source and
  the cause.
  Impersonation: none arise; authentication is unchanged.

  Scenario: A dialog with no keys shows the keys message
    Given no keys for @alice in this device's keychain
    When PkamDialog opens @alice
    Then it shows "No keys for @alice in this device's keychain, so this device cannot authenticate as @alice. Activate @alice, enroll this device, or use the keyfile it already has." and returns no client

  Scenario Outline: An atServer refusal shows its cause in plain words
    Given keys for @alice the atServer refuses with cause <cause>, on a device that has never held @alice online
    When PkamDialog opens @alice
    Then it shows "<message>" and returns no client
    Examples:
      | cause                 | message                                                   |
      | revoked               | This device's access to @alice has been revoked.          |
      | enrollmentNotApproved | This device's enrollment for @alice has not been approved yet. |
      | enrollmentDenied      | This device's enrollment for @alice was denied.           |
      | noAtServer            | @alice is not in the atDirectory.                         |

  Scenario: A network failure still says to check the connection
    Given readable keys for @alice and an atServer that cannot be reached within the dialog's wait
    When PkamDialog opens @alice
    Then it shows "Authentication timed out — the atServer could not be reached. Please check your connection and try again."

  Scenario: Activation with a keychain it cannot read says so
    Given this device's keychain cannot be read
    When CramDialog activates @alice with its CRAM secret
    Then it shows the activation's refusal naming this device's keychain, not "Please check your connection"

  Scenario Outline: Anything else shows the exception's message and no stack trace
    Given <dialog> whose operation fails with an exception of no type above, message "boom"
    When the dialog runs for @alice
    Then it shows "Something went wrong with @alice: boom", with no type prefix and no stack trace
    Examples:
      | dialog              |
      | PkamDialog          |
      | CramDialog          |
      | ApkamDialog         |
      | RegistrarCramDialog |
