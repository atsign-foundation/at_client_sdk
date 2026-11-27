Feature: create opens a session and close ends it

  create takes {atSign, namespace, keys, appName?, appVersion?, rootDomain?}
  for a keys-file session, or {atSign, namespace, passkey: true, rpId, rpName,
  appName?, appVersion?, rootDomain?} and no keys for a passkey session, and
  resolves a session. It needs a secure context.
  close stops the session: a later call that returns a promise rejects with
  code closed, and subscribe and onStatus return {code: closed} instead of a
  function.

  These scenarios describe the Dart bridge that @atsign/at_client_web wraps; the
  npm package turns {code, message} into AtError and the callbacks into async
  iterators, and specifies that in at_js.

  # Threats. Each answer names the scenario that holds it.
  #
  # Race: two concurrent close calls share one teardown so the second does not
  #   resolve before the client has stopped ("concurrent close awaits the first
  #   stop"); portalSession serializes opens per (atSign, enrollment), and a
  #   session's teardown runs inside that same queue, so a create after an
  #   unawaited close waits for the client to leave it ("create waits for an
  #   unawaited close of the same atSign", "close then create is queued for the
  #   keys and the passkey session forms", "a bridge session queues its close
  #   behind the open lock"), and a second create while a session is live
  #   rejects before opening ("a second create while a session is live rejects
  #   invalid_argument naming atSign").
  # Replay: no session handle or challenge is persisted or reused across close;
  #   every post-close call rejects ("close stops the session and later calls
  #   reject with closed").
  # DoS: create rejects non-secure contexts, missing/invalid options, and
  #   credential-less keys before opening a connection ("create rejects with
  #   unsupported outside a secure context", "invalid or empty atSign rejects
  #   naming atSign", "invalid or empty namespace rejects naming namespace",
  #   "credential-less keys reject with bad_key"), options are read with
  #   `Object.prototype.hasOwnProperty`, so an engine without `Object.hasOwn`
  #   still rejects a bad option as invalid_argument instead of reporting the
  #   open as internal ("options are read without Object.hasOwn"); appName and
  #   appVersion are
  #   carried as strings, trimmed and blank-cleared, and at_auth cuts each to
  #   64 UTF-16 units ("a non-string appName or appVersion rejects
  #   invalid_argument naming the option"). An open's connect and
  #   authentication are bounded by the network default, so a dead atServer
  #   ends the open in thirty seconds at most and never at the shorter
  #   connection budget, while one that answers late still succeeds ("an open
  #   that cannot finish within thirty seconds rejects offline", "an open
  #   passes the network default as its budget on both session forms", "an
  #   open whose authentication finishes after five seconds succeeds"); a
  #   refused first connection is retried on a fresh socket instead of failing
  #   the open ("create() tolerates one refused connection").
  # Forgery: options are read only as own plain properties and keys are parsed
  #   into AtKeys rather than trusted as strings ("keys may be an object as
  #   well as the document text").
  # Impersonation: create validates the requested atSign and authenticates via
  #   PKAM in portalSession ("opens with the options and returns a session",
  #   "invalid or empty atSign rejects naming atSign"). An app name is a label,
  #   not an identity: the atSign still comes from the keys and a session
  #   without one names no app ("an open with appName and appVersion names the
  #   app on the client preference", "an open without appName leaves the
  #   particulars unset"). The atSign a session reports is canonical, lower
  #   case in `@name` form with its dots stripped whatever spelling create was
  #   given, so JS composes keys for one spelling and not a look-alike ("a
  #   session atSign is canonical whatever spelling create was given", "atSign
  #   returns the canonical session atSign").

  Scenario: opens with the options and returns a session
    Given create options with an atSign, a namespace and keys
    When create is called
    Then the session opens with exactly those options
    And the result has notify, subscribe, status, onStatus, collection and close

  Scenario: a session atSign is canonical whatever spelling create was given
    Given create options whose atSign is given with capitals, without the @ or with dots
    When the options are built
    Then the atSign is lower case, in @ form and without dots
    And the keys form and the passkey form agree

  Scenario: atSign returns the canonical session atSign
    Given an open session
    When atSign is called
    Then it returns the session's atSign in @ form without dots
    And it still returns it after close

  Scenario: create resolves only once the session is open
    Given a bridge whose session opener has not yet returned
    When create is called
    Then create's promise is still pending
    When the opener then returns a session
    Then create resolves with that session

  Scenario: keys may be an object as well as the document text
    Given create options whose keys are the parsed .atKeys object instead of its JSON text
    When create is called
    Then the session opens with the same keys the JSON text gives

  Scenario: rootDomain host:port and host pass through
    Given create options with a rootDomain of host:port, of a bare host and of proxy:host:port
    When create is called with each
    Then each session opens with that host and port, the port being 64 when none is given
    And the proxy: prefix stays on the host

  Scenario: a keys session with no caller transport dials the options' root
    Given a keys session whose options name a rootDomain and no caller supplies a transport
    When the session is opened
    Then the transport dials the options' root host and port
    And Atsigns are looked up there over HTTPS

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

  @race
  Scenario: create waits for an unawaited close of the same atSign
    Given a session for one atSign and enrollment whose stop is held
    When close is called without awaiting it and create opens the same pair
    Then create stays pending until that stop completes
    And create then resolves with a fresh session

  @race
  Scenario: a second create while a session is live rejects invalid_argument naming atSign
    Given a live session for one atSign and enrollment
    When create is called again for the same pair
    Then it rejects with code invalid_argument and the message 'a session for this atSign is already open'
    And no second client is opened

  @race
  Scenario: close then create is queued for the keys and the passkey session forms
    Given a keys session and a passkey session, each built with the lock its open queued on, whose stops are held
    When each is closed without awaiting it and create opens the same pair
    Then each create stays pending until its session's stop completes
    And each create then resolves

  Scenario: a bridge session queues its close behind the open lock
    Given a bridge session opened with the lock its open used
    When close is called without awaiting it and an open is queued on that lock
    Then the queued open starts only after the session's stop completes

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

  Scenario: create with the passkey options opens a passkey session
    Given create options with passkey: true, an atSign, a namespace, rpId and rpName and no keys
    When create is called
    Then a session opens through the passkey login and its close awaits that session's stop

  Scenario: create with the passkey options opens through the browser's passkey login
    Given passkey options and no injected login
    When the session is opened
    Then the browser's passkey login is the opener, opening its hint store once
    And that store is closed when the login throws

  Scenario: create with missing or mistyped options rejects with invalid_argument naming the option
    Given options that are null, a string, an array, a function or a class instance, and options whose atSign, namespace or keys is absent, whose atSign, namespace or rootDomain is not a string, or whose keys is a number or JSON text of something other than an object, and passkey options with passkey: true and no keys whose passkey, rpId or rpName is absent or mistyped
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

  Scenario: appName and appVersion are optional on both session forms and blank means unset
    Given keys options and passkey options with and without appName and appVersion
    When each form is built
    Then both forms carry them trimmed
    And absent or blank appName and appVersion are unset

  Scenario: an open with appName and appVersion names the app on the client preference
    Given a session opened with appName and appVersion
    When the client is online
    Then its preference's atClientParticulars carry that appName and appVersion

  Scenario: an open without appName leaves the particulars unset
    Given a session opened without appName and appVersion
    When the client is online
    Then its preference's atClientParticulars name no app

  Scenario: an open whose authentication finishes after five seconds succeeds
    Given a session whose PKAM answers after five seconds
    When the session is opened
    Then the open waits for that answer and the session comes online
    And it does not fail at the five second connection budget

  Scenario: an open passes the network default as its budget on both session forms
    Given the network default timeout is set to seven seconds
    And a session whose PKAM never answers
    When the keys form is opened and the passkey form is opened
    Then each rejects offline after more than five seconds
    And each rejects within the seven second network default

  Scenario: an open that cannot finish within thirty seconds rejects offline
    Given the network default timeout is set below thirty seconds
    And a session whose PKAM never answers
    When the session is opened
    Then it rejects offline once the network default is spent
    And it did not reject at the five second connection budget

  Scenario: create() tolerates one refused connection
    Given a proxy that closes the first WebSocket upgrade before answering
    When create is called
    Then the first attempt is retried on a fresh socket
    And the session opens

  Scenario: appName with explicit prefs is refused naming appName
    Given an open with an explicit preference and an appName
    When the open is attempted
    Then it throws an ArgumentError naming appName
    And no connection is attempted

  Scenario: a portal session passes appName and appVersion to the client
    Given a portal session given appName and appVersion
    When it opens
    Then the client it returns names that app on its preference

  Scenario: a passkey open names the app on the client it opens
    Given a passkey open given appName and appVersion
    When the session is opened
    Then the client it returns names that app on its preference

  Scenario: create passes appName and appVersion to the keys and passkey options
    Given create options with appName and appVersion in both forms
    When create is called with each
    Then each session opens with exactly that appName and appVersion

  Scenario: a non-string appName or appVersion rejects invalid_argument naming the option
    Given create options whose appName or appVersion is not a string
    When create is called with each
    Then each rejects with code invalid_argument and a message naming that option
    And no session is opened

  Scenario: the passkey wiring forwards appName and appVersion to the client opener
    Given a passkey server side built with appName and appVersion
    When its gateway opens a client
    Then the client it opens names that app on its preference

  @dos
  Scenario: options are read without Object.hasOwn
    Given create options with an invalid option and an engine whose Object has no hasOwn
    When create is called
    Then it rejects with invalid_argument naming that option, not internal
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

  Scenario: the session close awaits the opener stop
    Given a session whose opener supplied its own stop
    When close is called
    Then close resolves only after that stop has completed

  Scenario: a session that fails to build after opening is stopped
    Given create options that open a client but whose session cannot be built
    When create is called
    Then the error is rethrown after the opened client or passkey session is stopped

  Scenario: close removes the network listeners even when a stop step fails
    Given a session listening for the browser going online and offline, whose status subscription fails to cancel
    When close is called
    Then the online and offline listeners are still removed and the failure is logged

  Scenario: a close whose stop failed returns the same failure when called again
    Given a session whose stop fails on the first close
    When close is called, rejects, and is called twice more
    Then each later close returns that same failed future and stop ran once in all

  Scenario: the entry installs one global whose only member is create
    Given the bridge entry module
    When its main is called
    Then the global __atsignAtClientWeb is created with only create
