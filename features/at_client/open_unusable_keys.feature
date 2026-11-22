Feature: Atsign.open refuses keys it cannot use before connecting, and says why

  An app opens an atSign with Atsign.open. Keys that are absent, cannot be
  read, hold no authentication keypair this device can use, or name another
  atSign are refused before any connection, on every device, with
  AtKeysUnusableException and a cause the app can switch on. The
  released AtNoCredentialException and AtEnrollmentPendingException are
  AtKeysUnusableExceptions too, so one catch covers every keys problem and a
  catch written for either still works. The connection state describes only
  the network and the atServer.

  Races: open reads the keys once before connecting; a keyfile that changes
  between that read and the connection's own read is handled as before.
  Replay: none arise; nothing new is sent.
  DoS: a refused open makes no connection.
  Forgery: none arise; no message carries the keys' contents.
  Impersonation: keys that name another atSign sign nothing for this one;
  keys that name no atSign (older keyfiles) are used as before.

  Scenario: An absent keyfile is refused before connecting
    Given no atKeys at the keys source for @alice
    When an app calls Atsign.open for @alice
    Then it throws AtKeysUnusableException with cause absent, source <path> and the message "No keys for @alice in the AtKeys store (<path>), so this device cannot authenticate as @alice. Activate @alice, enroll this device, or use the keyfile it already has.", and opens no connection

  Scenario: A keyfile path that cannot be resolved is refused before connecting
    Given an app whose keyfile path cannot be resolved, as the default path on a platform with no home directory
    When it opens @alice
    Then it throws AtKeysUnusableException with cause unreadable before connecting to the atServer

  Scenario: An unreadable keyfile is refused before connecting, even on a device that has held the atSign online
    Given a device that has held @alice online, and an atKeys file for @alice that cannot be read
    When an app calls Atsign.open for @alice
    Then it throws AtKeysUnusableException with cause unreadable and the message "The keys for @alice in the AtKeys store (<path>) could not be read: <reason>.", holding none of the file's contents, and opens no connection
    # cases: permission denied; not a JSON object; wrong passphrase; no passphrase; a field of the wrong type; a keyId that appears twice; an envelope version this build has no code for; an envelope that carries no salt; an envelope that carries no key derivation parameters; a role that appears twice for one keyId; an enrollment holding two active keys of one role and algorithm; an atKeys version this build has no code for; a namespace that names no string; a key derivation memory below one; a key derivation iterations below one; a key derivation parallelism below one; a key derivation memory and parallelism of zero; a key derivation memory below eight times its parallelism; a key derivation this device cannot run; a hashing algorithm this build has no code for

  Scenario: Keys that hold no authentication keypair this device can use are refused before connecting, even on a device that has held the atSign online
    Given a device that has held @alice online, and an atKeys file for @alice that can be read but holds no authentication keypair this device can use
    When an app calls Atsign.open for @alice
    Then it throws AtKeysUnusableException with cause noAuthenticationKeypair and the message "The keys for @alice in the AtKeys store (<path>) cannot be used to authenticate: <reason>.", holding no key material, and opens no connection
    # cases: no authentication keypair; an algorithm this build cannot sign with; several enrollments qualifying

  Scenario: A keyfile naming another atSign is refused before connecting
    Given an atKeys file whose atsign is @bob
    When an app calls Atsign.open for @alice
    Then it throws AtKeysUnusableException with cause anotherAtsign and the message "The keys in the AtKeys store (<path>) are for @bob, not @alice.", and opens no connection

  Scenario: A keyfile that names no atSign is used as before
    Given an atKeys file for @alice that records no atsign
    When an app calls Atsign.open for @alice
    Then the keys are used for @alice, as before

  Scenario: Keys with no credential, or only a pending enrollment, are AtKeysUnusableExceptions
    Given keys for @alice that hold no credential, and keys for @alice that hold only a pending enrollment
    When an app calls Atsign.open with each
    Then it throws AtNoCredentialException with cause noCredential, and AtEnrollmentPendingException with cause pendingEnrollment, each with a message naming the AtKeys store, and each caught by a catch for its own type

  Scenario: An atServer refusal still says the atServer refused it
    Given keys the atServer refuses, on a device that has never held @alice online
    When an app calls Atsign.open for @alice
    Then it throws AtOpenRefusedException naming the atServer's cause

  Scenario: A readable keyfile with the atServer unreachable still opens offline
    Given a readable keyfile for @alice and an unreachable atServer
    When an app calls Atsign.open for @alice
    Then it returns a client whose connection is offline (unreachable), as before

  Scenario: Enrolling into a store that holds live keys says to give the enrollment a store of its own
    Given an AtKeys store holding live keys for @alice
    When an app calls Atsign.enroll for @alice with that store
    Then it throws AtEnrollmentException starting "Give a new enrollment an AtKeys store of its own", then saying @alice already holds live keys in the AtKeys store, and its message does not suggest removing the keys

  Scenario: An activation failure's message holds no stack trace
    Given an activation of @alice whose PKAM step fails
    When the app activates @alice with its CRAM secret
    Then the exception's message holds no stack trace, and the trace is logged at fine
