Feature: A notify can bound its final-status wait

  notify takes an optional finalStatusBudget. When it is given, the poll for
  the notification's final delivery status stops once that budget has run
  out, and the result is marked unconfirmed: still the queued status, with
  neither onSuccess nor onError called. Without a budget the poll runs as
  before, until the atServer reports a final status or the service stops.

  Races: the budget is checked between polls, so an answer that arrives
  while the budget runs out is still returned; a stop still ends the poll at
  once, and still throws.
  Replay: none arise; the notification is sent once, and the budget bounds
  only how long its status is asked for.
  DoS: an offline recipient cannot hold a notify's final-status wait open
  forever: a caller that gives a budget gets an answer within it.
  Forgery and impersonation: none arise; the status is the atServer's own
  reply about this client's notification id, as before.

  Scenario: A final-status poll stops at its budget and returns the queued status
    Given a notification whose status stays queued at the atServer
    When it is notified with a final-status budget
    Then the notify returns the queued status marked unconfirmed within the budget, calling neither onSuccess nor onError

  Scenario: A notify without a final-status budget polls as before
    Given a notification whose status is queued for a while and then delivered
    When it is notified with no final-status budget
    Then the notify waits through the queued answers and returns delivered, confirmed
