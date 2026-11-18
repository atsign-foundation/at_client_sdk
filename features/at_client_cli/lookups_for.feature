Feature: lookUpsFor is deprecated; secureSocketLookUps() makes the connections CLIBase makes

  A CLI program that calls at_client's verbs itself passes them lookUps:.
  secureSocketLookUps() is the one CLIBase and at_activate use, whatever the
  root domain: for a root of the form proxy:<host>, at_lookup itself sends
  from:<atSign> before anything else on each connection, so the proxy can
  route it to the atServer; otherwise each connection is TLS on TCP straight
  to the atServer. lookUpsFor(rootDomain) is deprecated and returns
  secureSocketLookUps() for every root.

  Races: none arise; the root domain is read once, when the lookup is built.
  Replay: none arise; what a connection sends is what CLIBase sent before.
  DoS: none arise; building a factory opens no connection.
  Forgery and impersonation: none arise; the atSign a proxy routes by is the
  one the client was opened for, and authentication is unchanged.

  Scenario: Through a proxy, each connection names its atSign first
    Given a root domain that names a proxy
    When a lookup that secureSocketLookUps() builds connects and runs a command
    Then the first line it sends is from:<atSign>

  Scenario: Straight to an atServer, the command goes first
    Given a root domain that names an atDirectory
    When a lookup that secureSocketLookUps() builds connects and runs a command
    Then the first line it sends is the command
