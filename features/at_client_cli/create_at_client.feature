Feature: createAtClient opens a command's client from its keyfile

  A command-line program that reads or administers an atSign, as
  at_activate's otp, list and approve do, opens its client with
  createAtClient: from the keyfile, syncing nothing, on a store of its own,
  and made the manager's current client. Its parameters are
  at_onboarding_cli 2.0.0-rc8's, so a program written against that release
  compiles unchanged.

  Races: each call opens its own client on a store of its own; the manager's
  current client is the one opened last, as before.
  Replay: none arise; the client authenticates with the keyfile's keys, as
  before.
  DoS: a client still offline after maxConnectAttempts tries, three seconds
  apart, is stopped, so a command does not wait without end.
  Forgery and impersonation: none arise; authentication is unchanged.

  Scenario: A program written against at_onboarding_cli 2.0.0-rc8 compiles unchanged
    Given a call that names each parameter rc8's createAtClient takes
    When the program is compiled against at_client_cli
    Then it compiles, and the call is at_client_cli's createAtClient

  Scenario: A client still offline after its connect attempts is stopped
    Given a keyfile for an atSign whose atDirectory refuses every connection
    When the program calls createAtClient with maxConnectAttempts 1
    Then it throws UnAuthenticatedException naming the attempts, and no client is left open
