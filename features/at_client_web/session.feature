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
    Then it rejects with code invalid_argument and a message naming atSign without its value
    And no session is opened

  Scenario: invalid or empty namespace rejects naming namespace
    Given create options with an empty or invalid namespace
    When create is called
    Then it rejects with code invalid_argument and a message naming namespace without its value
    And no session is opened

  Scenario: credential-less keys reject with bad_key
    Given create options whose .atKeys document holds no usable credential
    When create is called
    Then it rejects with code bad_key

  Scenario: create with missing or mistyped options rejects with invalid_argument naming the option
    Given options that are null, a string, an array, a function or a class instance, and options whose atSign, namespace or keys is absent, whose atSign, namespace or rootDomain is not a string, or whose keys is a number or JSON text of something other than an object
    When create is called with each
    Then each rejects with code invalid_argument and a message naming opts or that option
    And no session is opened

  Scenario: an unusable rootDomain rejects with invalid_argument naming rootDomain
    Given create options whose rootDomain is empty, has a port outside 1-65535 or is not host or host:port
    When create is called
    Then it rejects with code invalid_argument and a message naming rootDomain without its value
    And no session is opened

  Scenario: create with several bad inputs reports the type checks and key decoding before the options
    Given create options with an atSign that is not an atSign and keys that are not JSON, or a rootDomain of a:b:c and keys that are not JSON, or a mistyped namespace and keys that are not JSON
    When create is called with each
    Then the first two reject with code bad_key, naming no value
    And the third rejects with code invalid_argument naming namespace
    And no session is opened

  @dos
  Scenario: a caller mistake at create opens no connection
    Given create options with one invalid option and otherwise valid keys
    When create is called
    Then it rejects with code invalid_argument before the opener is called
    And no connection to the atDirectory or an atServer is attempted

  Scenario: a closed session refuses each call with SessionClosedException
    Given a session that has been closed
    When notify, subscribe, onStatus, collection, otp, pendingEnrollments, approve or deny is called on the session, or any operation on a collection it opened
    Then each throws SessionClosedException, an AtException; at_client's StoppedException never reaches the caller

  Scenario: a router sends each kind to its opener
    Given create options of the keys kind and of the passkey kind
    When the router opens each
    Then the keys options go to the keys opener and the passkey options go to the passkey opener
    And an opener given options of another kind rejects naming options

  Scenario: a wrap that fails stops the opened session and rethrows its error
    Given an opener that opens a session and a wrap step that throws
    When the session is opened through the wrap
    Then the opened session is stopped once and the wrap error is thrown unchanged

  Scenario: a stop that fails during that cleanup leaves the wrap error
    Given an opener whose session stop throws and a wrap step that throws
    When the session is opened through the wrap
    Then the wrap error, not the stop error, is thrown

  Scenario: the session close awaits the opener stop
    Given a session whose opener supplied its own stop
    When close is called
    Then close resolves only after that stop has completed

  Scenario: close removes the network listeners even when a stop step fails
    Given a session listening for the browser going online and offline, whose status subscription fails to cancel
    When close is called
    Then the online and offline listeners are still removed and the failure is logged

  Scenario: a close whose stop failed can be tried again
    Given a session whose stop fails on the first close
    When close is called, rejects, and is called again twice
    Then the second close stops the client, the third is a no-op, and stop ran twice in all
