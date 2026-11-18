Feature: create opens a session and close ends it

  create takes the options and returns a session. It needs a secure context.
  close stops the session; every later call rejects with closed.

  Scenario: opens with the options and returns a session
    Given create options with an atSign, a namespace and keys
    When create is called
    Then the session opens with exactly those options
    And the result has notify, subscribe, status, onStatus, collection and close

  Scenario: keys may be an object as well as the document text
    Given create options whose keys are an object
    When create is called
    Then the session opens with the same keys as the document text would give

  Scenario: rootDomain host:port and host pass through
    Given create options with a rootDomain of host:port, of a bare host and of a proxy form
    When create is called with each
    Then each session opens with that root domain and its port, 64 when none is given

  Scenario: create rejects with unsupported outside a secure context
    Given a page that is not a secure context
    When create is called
    Then it rejects with code unsupported
    And no session is opened

  Scenario: close stops the session and later calls reject with closed
    Given an open session
    When close is called and then notify is called
    Then the session is stopped
    And notify rejects with code closed
