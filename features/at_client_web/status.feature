Feature: The connection status is readable and observable

  status returns the latest state and onStatus reports each change until the
  caller calls the function it returned. The states are connecting, connected,
  waiting:network, waiting:server and waiting:auth. There is no retry call; the
  client reconnects by itself.

  These scenarios describe the Dart bridge that @atsign/at_client_web wraps; the
  npm package turns {code, message} into AtError and the callbacks into async
  iterators, and specifies that in at_js.

  # Threats. Each answer names the scenario that holds it.
  #
  # Race: closing the session stops status delivery, and listeners removed or
  #   throwing mid-dispatch do not disrupt sibling listeners ("onStatus after
  #   close answers {code: closed}", "onStatus listener error does not skip
  #   sibling listeners").
  # Replay: status reports live connection state transitions from AtConnection
  #   and retains the last state after close without replaying stale transitions
  #   ("status() reads the latest value").
  # DoS: non-function callbacks are rejected synchronously without registering a
  #   listener ("onStatus with non-function callback returns {code: internal}
  #   without throwing").
  # Forgery: status values come from a fixed enum mapping of AtConnectionState
  #   in the session, never from network payload text.
  # Impersonation: status only reflects the single authenticated session's own
  #   connection; no peer identity is involved.

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

  Scenario: onStatus with non-function callback returns {code: internal} without throwing
    Given an open session
    When onStatus is called with a non-function callback
    Then it returns {code: internal} naming callback without throwing

  Scenario: onStatus listener error does not skip sibling listeners
    Given an open session with two status listeners where the first throws
    When the connection status changes
    Then the second listener still receives the new status
