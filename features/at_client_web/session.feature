Feature: create opens a session and close ends it

  create takes {atSign, namespace, keys, rootDomain?} and resolves a session. It
  needs a secure context. close stops the session: a later call that returns a
  promise rejects with code closed, and subscribe and onStatus return {code:
  closed} instead of a function.

  These scenarios describe the Dart bridge that @atsign/at_client_web wraps; the
  npm package turns {code, message} into AtError and the callbacks into async
  iterators, and specifies that in at_js.

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
