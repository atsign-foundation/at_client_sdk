Feature: Enrollments.requests reports only new-enrollment notifications from the client's own atSign

  client.enrollments.requests reports a notification keyed
  <id>.new.enrollments.__manage only when its sender is the client's own
  atSign. The two are compared in canonical form, toAtsign() on both sides,
  so @Alice and @alice match. Any other notification whose key matches is
  dropped, and a warning names its sender and its key; so is one whose
  sender is not an atSign at all.

  The atServer announces a new request as a self notification, sent by the
  atSign to itself. From atServer 3.19.0 it refuses a notification from
  another atSign that uses __manage, or any other reserved namespace, so
  this check is defence in depth.

  Races: none arise; each notification is checked on its own, against the
  client's atSign, which does not change while the client runs.
  Replay: none new; the check reads only the sender, so a request the atSign
  announced to itself is reported as before, however often it is delivered.
  DoS: none new; a dropped notification costs one warning line and is never
  parsed as a request.
  Forgery and impersonation: the sender is the one the client's own atServer
  reports over the client's authenticated connection. A matching
  notification from any other atSign is never reported as a request to this
  atSign's approvers.

  Scenario: a request announced by the client's own atSign is reported
    Given an AtClient for @alice listening on Enrollments.requests
    When a <id>.new.enrollments.__manage notification arrives from @alice
    Then it is reported as a new enrollment request

  @forgery @impersonation
  Scenario: a matching notification from another atSign is dropped, and the drop is logged
    Given an AtClient for @alice listening on Enrollments.requests
    When a notification whose key matches .new.enrollments.__manage arrives from @bob
    Then nothing is reported on requests
    And a warning is logged naming the sender and the key
