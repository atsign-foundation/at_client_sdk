Feature: create opens a session and close ends it

  create takes {atSign, namespace, keys, rootDomain?} and resolves a session. It
  needs a secure context. close stops the session: a later call that returns a
  promise rejects with code closed, and subscribe and onStatus return {code:
  closed} instead of a function.

  These scenarios describe the Dart bridge that @atsign/at_client_web wraps; the
  npm package turns {code, message} into AtError and the callbacks into async
  iterators, and specifies that in at_js.

  # Threats. Each answer names the scenario that holds it.
  #
  # Race: two concurrent close calls share one teardown so the second does not
  #   resolve before the client has stopped ("concurrent close awaits the first
  #   stop"), and portalSession serializes opens per (atSign, enrollment).
  # Replay: no session handle or challenge is persisted or reused across close;
  #   every post-close call rejects ("close stops the session and later calls
  #   reject with closed").
  # DoS: create rejects non-secure contexts, missing/invalid options, and
  #   credential-less keys before opening a connection ("create rejects with
  #   unsupported outside a secure context", "invalid or empty atSign rejects
  #   naming atSign", "invalid or empty namespace rejects naming namespace",
  #   "credential-less keys reject with bad_key").
  # Forgery: options are read only as own plain properties and keys are parsed
  #   into AtKeys rather than trusted as strings ("keys may be an object as
  #   well as the document text").
  # Impersonation: create validates the requested atSign and authenticates via
  #   PKAM in portalSession ("opens with the options and returns a session",
  #   "invalid or empty atSign rejects naming atSign").

  Scenario: opens with the options and returns a session
    Given create options with an atSign, a namespace and keys
    When create is called
    Then the session opens with exactly those options
    And the result has notify, subscribe, status, onStatus, collection and close

  Scenario: keys may be an object as well as the document text
    Given create options whose keys are the parsed .atKeys object instead of its JSON text
    When create is called
    Then the session opens with the same keys the JSON text gives

  Scenario: rootDomain host:port and host pass through
    Given create options with a rootDomain of host:port, of a bare host and of proxy:host:port
    When create is called with each
    Then each session opens with that host and port, the port being 64 when none is given
    And the proxy: prefix stays on the host

  Scenario: create rejects with unsupported outside a secure context
    Given a page that is not a secure context
    When create is called
    Then it rejects with code unsupported
    And no session is opened

  Scenario: close stops the session and later calls reject with closed
    Given an open session
    When close is called and then notify, collection, otp, pendingEnrollments, approve or deny is called
    Then the session is stopped
    And each rejects with code closed

  Scenario: concurrent close awaits the first stop
    Given an open session whose underlying client stop takes time to finish
    When close is called twice concurrently
    Then the client stops only once
    And the second close waits until the first stop completes

  Scenario: invalid or empty atSign rejects naming atSign
    Given create options with an empty or malformed atSign
    When create is called
    Then it rejects with code internal and a message naming atSign without its value
    And no session is opened

  Scenario: invalid or empty namespace rejects naming namespace
    Given create options with an empty or invalid namespace
    When create is called
    Then it rejects with code internal and a message naming namespace without its value
    And no session is opened

  Scenario: credential-less keys reject with bad_key
    Given create options whose .atKeys document holds no usable credential
    When create is called
    Then it rejects with code bad_key
