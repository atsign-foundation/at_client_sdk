Feature: The onboarding dialogs say what failed

  PkamDialog, CramDialog, ApkamDialog and RegistrarCramDialog show a message
  chosen by what failed: a keys problem its own message, keys holding no
  credential or an enrollment PkamDialog cannot wait on what to do next in
  plain words, an atServer refusal its cause in plain words, a network
  failure the advice to check the connection, and anything else that
  something went wrong with the exception's message. No dialog shows a stack
  trace. PkamDialog's contract is unchanged: only a refusal on a device that
  has never held the atSign online is a failure.

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

  Scenario Outline: Keys with no credential, or an enrollment PkamDialog cannot wait on, say what to do in plain words
    Given keys for @alice that <hold>
    When PkamDialog opens @alice
    Then it shows "<message>" and returns no client
    Examples:
      | hold                                            | message                                                                                                                                             |
      | hold no credential                              | This device's enrollment for @alice was denied, cancelled or expired, or never completed. Enroll this device again to use @alice here.              |
      | hold only one enrollment awaiting approval      | This device's enrollment for @alice is still waiting for approval and cannot be completed here. Enroll this device again from this app to carry on. |

  Scenario: Several pending enrollments that match say to name the app and the device
    Given keys for @alice that hold only several pending enrollments that match, e-1 and e-2
    When PkamDialog opens @alice
    Then it shows "@alice holds several pending enrollments that match: e-1, e-2. To resume one, name both the app and the device" and returns no client
    And it does not say to enroll again, which would only add another pending enrollment

  Scenario Outline: An atServer refusal shows its cause in plain words
    Given keys for @alice the atServer refuses with cause <cause>, on a device that has never held @alice online
    When PkamDialog opens @alice
    Then it shows "<message>" and returns no client
    Examples:
      | cause                 | message                                                        |
      | revoked               | This device's access to @alice has been revoked.               |
      | enrollmentNotApproved | This device's enrollment for @alice has not been approved yet. |
      | enrollmentDenied      | This device's enrollment for @alice was denied.                |
      | invalidEnrollment     | This device's enrollment for @alice has expired.               |
      | unauthenticated       | The atServer for @alice did not accept this device's keys.     |
      | otherRefusal          | The atServer for @alice refused this device.                   |
      | noAtServer            | @alice is not in the atDirectory.                              |

  Scenario Outline: A raw atServer refusal, as at_lookup throws it, shows the same words
    Given an operation on @alice that fails with <raw refusal>
    When a dialog shows its failure
    Then it shows "<message>" and no error code or exception type
    Examples:
      | raw refusal                                        | message                                                    |
      | UnAuthenticatedException "AT0401 CRAM authentication failed" | The atServer for @alice did not accept this device's keys. |
      | AtLookUpException AT0027 "enrollment revoked"      | This device's access to @alice has been revoked.           |
      | AtLookUpException AT0025 "enrollment denied"       | This device's enrollment for @alice was denied.            |

  Scenario: A network failure still says to check the connection
    Given an activation whose atServer cannot be reached
    When CramDialog or ApkamActivationDialog runs
    Then it shows "… could not be reached. Please check your connection and try again."

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
