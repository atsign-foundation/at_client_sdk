Feature: The connection status is readable and observable

  status returns the latest state and onStatus reports each change until the
  caller calls the function it returned. The states are connecting, connected,
  waiting:network, waiting:server and waiting:auth. There is no retry call;
  the client reconnects by itself.

  Scenario: onStatus delivers changes and returns an off function
    Given an open client with a listener
    When the state changes twice and the listener is switched off
    Then the listener saw both states in order
    And the bridge listener was removed once
