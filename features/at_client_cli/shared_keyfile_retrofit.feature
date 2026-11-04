Feature: Instances of a program that share a keyfile retrofit it one at a time

  A keyfile whose credential is an RSA key is retrofitted at the first start
  of a client whose posture asks for ML-DSA. A program that opens its keyfile
  through CliKeys.fileFor, as CLIBase does, takes a lock beside the keyfile for
  the retrofit, so instances of it that share the keyfile take turns.

  Races: the lock spans the read of the keyfile, the request and the write, so
  the second instance reads what the first wrote and sends no request.
  Replay: none arises; each request is sent once, over an authenticated
  connection.
  DoS: a lock whose holder died is stale after two minutes, and a waiter waits
  for it at most thirty seconds.
  Forgery and impersonation: no instance leaves an approved enrollment whose
  private key nobody holds.

  Scenario: Instances of a program sharing a keyfile retrofit it one at a time
    Given an atSign's keyfile whose credential is an RSA key, opened through CliKeys.fileFor by two instances of a program
    When both start at PqPosture.pqActive at once
    Then one sends the self-enrollment request, and the other waits for it and authenticates as the enrollment it wrote
