Feature: The connection status is readable and observable

  status returns the latest state and onStatus reports each change until the
  caller calls the function it returned. The states are connecting, connected,
  waiting:network, waiting:server and waiting:auth. There is no retry call; the
  client reconnects by itself.

  These scenarios describe the Dart bridge that @atsign/at_client_web wraps; the
  npm package turns {code, message} into AtError and the callbacks into async
  iterators, and specifies that in at_js.

  Scenario: onStatus delivers changes and returns an off function
    Given an open client with a listener
    When the state changes twice and the listener is switched off
    Then the listener saw both states in order
    And the bridge listener was removed once

  Scenario: status() reads the latest value
    Given an open session
    When the state changes
    Then status returns the new state

  Scenario: onStatus after close answers {code: closed}
    Given a closed session
    When onStatus is called
    Then it returns {code: closed} instead of the off function
