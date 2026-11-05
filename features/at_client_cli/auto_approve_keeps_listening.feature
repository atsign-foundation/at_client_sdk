Feature: at_activate auto_approve keeps listening past what it cannot act on

  auto_approve approves each new enrollment request whose app and device
  names match its filters, until it reaches its limit. A notification that
  is not an enrollment request naming an appName and a deviceName, and a
  request whose approval fails, are each reported on stderr, and it goes on
  listening.

  Races: requests that arrive together are each handled, and reaching the
  limit ends the run once.
  Replay: none arise; each approval goes through the client as before.
  DoS: none arise; a notification it cannot act on costs one stderr line.
  Forgery and impersonation: none arise; what is approved, and by whom, is
  unchanged.

  Scenario: A notification that is not an enrollment request is passed over
    Given auto_approve is listening with a limit of one
    When a notification arrives whose value is not an enrollment request
    And then a matching request arrives
    Then the matching request is approved and the run ends
    And the notification is reported

  Scenario: A request whose approval fails is passed over
    Given auto_approve is listening with a limit of one
    When a matching request that is no longer awaiting approval arrives
    And then another matching request arrives
    Then the second request is approved and the run ends
    And the failed approval is reported
