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
  #   and re-classifies the current state when the browser's online/offline
  #   state changes, emitting only when the status differs; it retains the last
  #   state after close without replaying stale transitions ("status() reads the
  #   latest value", "an event that changes nothing reports nothing").
  # DoS: non-function callbacks are rejected synchronously without registering a
  #   listener ("onStatus with non-function callback returns {code: invalid_argument}
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

  Scenario: onStatus with non-function callback returns {code: invalid_argument} without throwing
    Given an open session
    When onStatus is called with a non-function callback
    Then it returns {code: invalid_argument} naming callback without throwing

  Scenario: onStatus listener error does not skip sibling listeners
    Given an open session with two status listeners where the first throws
    When the connection status changes
    Then the second listener still receives the new status

  Scenario: an event re-reads whether the browser is online and reports it
    Given a session whose connection is down, built with a browser-online check and a network-change stream
    When the browser goes offline and a network event arrives, then comes back online and another event arrives
    Then the session reclassifies each time and the listener saw waiting:network and then waiting:server

  Scenario: each online or offline event reaches the session
    Given the browser's network-change stream
    When online and offline events are dispatched, then the stream is cancelled and another event is dispatched
    Then each dispatched event before cancel arrives once and nothing arrives after cancel

  Scenario: an event that changes nothing reports nothing
    Given a session whose connection is down with a status listener
    When a network event arrives and the browser's online state is unchanged
    Then the status is the same and the listener was not called
