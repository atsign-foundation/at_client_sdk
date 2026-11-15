Feature: Every failure is an AtError whose code the caller branches on

  A call rejects with an AtError. A {code, message} the bridge reports keeps
  its code when it is a known one; anything else is internal. An argument the
  bridge rejects names the parameter, never the value it received.

  Races: none arise; each rejection belongs to one call.
  Replay: none arise.
  DoS: none arise; a malformed argument is refused at once.
  Forgery: an unknown code from the bridge cannot be forged into a known one;
  it becomes internal.
  Impersonation: none arise. Argument errors never echo the received value,
  so a secret passed in the wrong place (a CRAM secret, an otp) is not copied
  into an error message or a log.

  Scenario: maps a {code, message} rejection to an AtError
    Given a bridge that rejects with { code: 'pkam_refused', message: 'refused' }
    When create is called
    Then it rejects with an AtError, an Error with that message and the code pkam_refused

  Scenario: maps an unknown code or a thrown Error to internal
    Given a bridge that rejects with an unknown code, or with a thrown Error
    When create is called
    Then it rejects with AtError code internal and the message given

  Scenario: a rejection is a plain object with only code and message
    Given a failure inside the Dart bridge
    When create is called
    Then the rejection is a plain object, not an Error
    And its only keys are code and message

  Scenario: onboard names cram and deviceName without their values
    Given a bridge argument that is neither a string nor absent
    When onboard is called with it as cram or as deviceName
    Then the error message names cram or deviceName
    And it does not contain the received value

  Scenario: session calls name the parameter without its value
    Given an open session
    When put, get, delete, keys, notify or approve is called with a malformed argument
    Then the error message names the parameter, with code bad_key for a key field
    And it does not contain the received value
