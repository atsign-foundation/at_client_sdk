Feature: Every failure is an AtError whose code the caller branches on

  A call rejects with an AtError. A {code, message} the bridge reports keeps
  its code when it is a known one; anything else is internal. An argument the
  bridge rejects names the parameter, never the value it received.

  Scenario: an unmapped exception rejects internal with a fixed message
    Given a failure inside the Dart bridge that no code maps
    When create is called
    Then it rejects with code internal and the message 'internal error'
    And nothing the exception printed is in the message

  Scenario: a mapped exception keeps its message
    Given a failure inside the Dart bridge that maps to bad_key
    When a session call is made
    Then it rejects with code bad_key and the exception's message

  Scenario: a rejection is a plain object with only code and message
    Given a failure inside the Dart bridge
    When create is called
    Then the rejection is a plain object, not an Error
    And its only keys are code and message

  Scenario: session calls name the parameter without its value
    Given an open session
    When notify or approve is called with a malformed argument
    Then the error message names the parameter, with code bad_key for a key field
    And it does not contain the received value
