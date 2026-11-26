Feature: Every failure carries a code the caller branches on

  A call rejects with a plain {code, message} object, which the npm package
  wraps in an AtError. A {code, message} the bridge reports keeps its code when
  it is a known one; anything else is internal. An argument the bridge rejects
  names the parameter, never the value it received.

  These scenarios describe the Dart bridge that @atsign/at_client_web wraps; the
  npm package turns {code, message} into AtError and the callbacks into async
  iterators, and specifies that in at_js.

  # An UnsupportedError maps to unsupported by its type alone; its text is never
  # read or shown (the setup lock's UnsupportedError takes this path).

  # Threats. Each answer names the scenario that holds it.
  #
  # Race: error mapping is pure and stateless per thrown object; concurrent
  #   failures never interfere with one another.
  # Replay: rejections carry no tokens or credentials, so replaying an error
  #   message reveals no reusable material.
  # DoS: error messages omit raw values and truncate untrusted tokens ("an
  #   unmapped exception rejects internal with a fixed message", "session calls
  #   name the parameter without its value").
  # Forgery: rejections are constructed as plain objects carrying only fixed
  #   codes and parameter-only or sanitized messages ("a rejection is a plain
  #   object with only code and message").
  # Impersonation: errors carry no unverified peer-supplied identity claims ("a
  #   mapped exception keeps its message").

  Scenario: an unmapped exception rejects internal with a fixed message
    Given a failure inside the Dart bridge that no code maps
    When create is called
    Then it rejects with code internal and the message 'internal error'
    And nothing the exception printed is in the message

  Scenario: a mapped exception keeps its message
    Given a failure inside the Dart bridge that maps to bad_key
    When a session call is made
    Then it rejects with code bad_key and the message the bridge words for that exception

  Scenario: a rejection is a plain object with only code and message
    Given a failure inside the Dart bridge
    When create is called
    Then the rejection is a plain object, not an Error
    And its only keys are code and message

  Scenario: session calls name the parameter without its value
    Given an open session
    When notify is called with a non-string key or a non-string value, approve or deny with a non-string id, or collection with a non-string name, non-object opts or a fractional expiration
    Then the error message names the parameter, with code bad_key for the key and invalid_argument for every other parameter
    And it does not contain the received value

  @dos
  Scenario: an invalid_argument message is bounded and never echoes the value
    Given an argument of the wrong type whose text is one megabyte long and holds line breaks and bidirectional controls
    When any bridge call is made with it
    Then the rejection is a plain object whose only keys are code and message, plus id for the bad address owner rejection that keeps it
    And the message is at most 128 characters, is one line and holds no part of the argument

  @dos @forgery
  Scenario: a peer-chosen id and owner are bounded in a rejection
    Given a collection failure carrying a very long id and an owner holding a newline and a direction character
    When the failure reaches JS
    Then the rejection's id and owner are each at most 128 characters and one line

  @dos @forgery
  Scenario: a peer-chosen failure recipient is bounded in a rejection
    Given a collection failure whose failure recipient holds a newline, a direction character and 600 characters
    When the failure reaches JS
    Then the recipient is at most 128 characters and one line
    And the failure's op and kind are unchanged

  @forgery
  Scenario: an ArgumentError from inside at_client rejects internal with the fixed message
    Given an open session whose client throws an ArgumentError, or at_commons' IllegalArgumentException, with a message that names a parameter
    When create, notify, otp, approve or close reaches that failure
    Then it rejects with code internal and the message 'internal error'
    And nothing the error printed is in the message

  @forgery
  Scenario: exception text never chooses the code
    Given failures no code maps whose text contains invalid_argument, closed, a COLLECTION_ code or a JSON {code, message} object
    When a session call reaches each
    Then each rejects with code internal and the message 'internal error'

  Scenario: an unsupported operation is worded by the bridge, not by its error
    Given an UnsupportedError, whose text is long, multi-line or looks like a bridge message
    When it is mapped
    Then it rejects with code unsupported and the message 'the operation is not supported here'

  Scenario: an unsupported operation raised here keeps its text, from its enum
    Given an UnsupportedOperationException for the secure context
    When it is mapped
    Then it rejects with code unsupported and the message 'a secure context (HTTPS) is required'

  Scenario: a browser without navigator.locks gets UnsupportedError from the setup lock
    Given a browser with no navigator.locks
    When a passkey setup runs under the setup lock
    Then it throws UnsupportedError, as on trunk

  Scenario: the shared log text sanitizer escapes, bounds and flattens untrusted text
    Given untrusted text holding control characters, bidirectional formatting characters, a surrogate pair at the cut, and more than the bound
    When it goes through sanitizeLogText, singleLine and truncateText
    Then sanitizeLogText returns one JSON string literal with those characters as \u escapes, bounded with an ellipsis
    And singleLine replaces each of them with a space
    And truncateText never splits a surrogate pair

  Scenario: every closed rejection carries the same fixed message
    Given a closed session, and an open session whose client fails a call with at_client's StoppedException
    When a call is made on each
    Then both reject with code closed and the message 'the session is closed'
    And the message names no Dart class

  Scenario: every code the bridge can reject with is produced by one mapping
    Given the bridge's list of error codes
    Then it holds invalid_argument, enrollment_in_flight, pkam_refused, offline, timeout, refused, onboarding_incomplete, enrollment_conveyance_failed, enrollment_denied, closed, unsupported, bad_key, notify_failed, internal and the eleven COLLECTION_ codes, and no other
    And each code is produced by at least one exception the mapping test names
