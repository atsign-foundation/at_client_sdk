Feature: CLIBase says why an atServer refused, apart from an outage

  A CLI program opens its client through CLIBase.fromCommandLineArgs. A refusal
  stands until someone acts (the keys were revoked, or the enrollment awaits
  approval), so CLIBase throws it at once with the reason; an atServer not
  reached within maxConnectAttempts is transient, and CLIBase throws a
  different exception, which is the one a retry loop catches. A keyfile still
  holding only its enrollment request is resumed: the program waits for that
  enrollment's approval, as at_activate does, then runs. An atSign the
  atDirectory has no atServer for is neither, and says so with an exception
  of its own.

  Races: CLIBase opens one client and stops it on any failure, as before; a
  resumed request is waited on, never submitted again.
  Replay: the resumed wait proves possession of the keypair the request was
  submitted with, as at_activate's does; nothing new is issued or accepted.
  DoS: a refusal or an unknown atSign no longer looks like an outage, so a
  retry loop stops repeating an open that cannot succeed; the wait for
  approval asks every 10 seconds and ends after at_activate's retries when
  the atServer is not reached.
  Forgery and impersonation: authentication is unchanged; a resume names no
  app or device and takes only the one request its own keyfile holds, and the
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

  Scenario: A keyfile still holding only its enrollment request is resumed
    Given a program built on CLIBase whose keyfile holds only an enrollment awaiting approval
    When it starts
    Then it says it is waiting for approval of that enrollment id, and waits as at_activate does; once approved it opens its client and runs, and the request is not submitted again

  Scenario: A denied or expired request ends the program with that reason, and its keys go
    Given a program built on CLIBase whose keyfile holds only an enrollment awaiting approval
    When the atServer answers that the request was denied, or has expired
    Then it ends with AtEnrollmentException, the pending keys are removed, and no client is left open

  Scenario: An atServer not reached for the retry budget ends the program, keeping the request
    Given a program built on CLIBase whose keyfile holds only an enrollment awaiting approval
    When its atServer cannot be reached for at_activate's retries
    Then it ends with that failure, the request stays in the keyfile, and no client is left open

  Scenario: Ctrl-C ends the wait, keeping the request
    Given a program built on CLIBase waiting for approval of the enrollment its keyfile holds the request for
    When the user presses Ctrl-C
    Then the program ends, and the request stays in the keyfile for the next run

  Scenario: An atSign the atDirectory has no atServer for is named as such
    Given an atSign the atDirectory has no atServer for
    When the program calls CLIBase.fromCommandLineArgs
    Then it throws SecondaryNotFoundException saying the atSign is not in the atDirectory, and no client is left open
