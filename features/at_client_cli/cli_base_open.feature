Feature: CLIBase says why an atServer refused, apart from an outage

  A CLI program opens its client through CLIBase.fromCommandLineArgs. A refusal
  stands until someone acts (the keys were revoked, or the enrollment awaits
  approval), so CLIBase throws it at once with the reason; an atServer not
  reached within maxConnectAttempts is transient, and CLIBase throws a
  different exception, which is the one a retry loop catches. A keyfile still
  holding only its enrollment request, and an atSign the atDirectory has no
  atServer for, are neither, and each says so with an exception of its own.

  Races: none arise; CLIBase opens one client and stops it on any failure, as
  before.
  Replay: none arise; the keys authenticate as before, and nothing is issued
  or accepted.
  DoS: a refusal, a pending keyfile or an unknown atSign no longer looks like
  an outage, so a retry loop stops repeating an open that cannot succeed.
  Forgery and impersonation: none arise; authentication is unchanged, and the
  exception names only the atSign and the cause.

  Scenario: A refused open throws, naming the cause
    Given keys the atServer refuses, on a device that has never held the atSign online
    When the program calls CLIBase.fromCommandLineArgs
    Then it throws AtCredentialRefusedException naming the atSign and the cause, and no client is left open

  Scenario: A refusal throws the same way after the atSign has been online on the device
    Given an atSign this device has held online, whose keys the atServer now refuses
    When the program calls CLIBase.fromCommandLineArgs
    Then it throws AtCredentialRefusedException naming the cause, and the client it opened is stopped

  Scenario: An enrollment awaiting approval says so
    Given keys whose enrollment the atServer reports as still awaiting approval
    When the program calls CLIBase.fromCommandLineArgs
    Then it throws AtCredentialRefusedException saying the enrollment awaits approval

  Scenario: An atServer not reached is an outage, not a refusal
    Given an atServer that does not answer within maxConnectAttempts tries
    When the program calls CLIBase.fromCommandLineArgs
    Then it throws SecondaryServerConnectivityException, and no client is left open

  Scenario: A keyfile still holding only its enrollment request says so
    Given a keyfile that holds only an enrollment request awaiting approval
    When the program calls CLIBase.fromCommandLineArgs
    Then it throws AtEnrollmentPendingException naming the pending enrollment, and no client is opened

  Scenario: An atSign the atDirectory has no atServer for is named as such
    Given an atSign the atDirectory has no atServer for
    When the program calls CLIBase.fromCommandLineArgs
    Then it throws SecondaryNotFoundException saying the atSign is not in the atDirectory, and no client is left open
