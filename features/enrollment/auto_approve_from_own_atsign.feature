Feature: at_activate auto_approve acts only on requests announced by its own atSign

  at_activate auto_approve acts on a notification keyed
  <id>.new.enrollments.__manage only when its sender is the atSign it runs
  for. The two are compared in canonical form, toAtsign() on both sides.
  Any other notification whose key matches is passed over, and a warning on
  stderr names its sender and its key. A request from its own atSign is
  approved, or passed over, as before.

  The atServer announces a new request as a self notification, sent by the
  atSign to itself. From atServer 3.19.0 it refuses a notification from
  another atSign that uses __manage, or any other reserved namespace, so
  this check is defence in depth.

  Races: none arise; each notification is checked on its own, against the
  atSign auto_approve runs for, which does not change during the run.
  Replay: none new; the check reads only the sender, so a request the atSign
  announced to itself is handled as before.
  DoS: none new; a notification passed over costs one stderr line and no
  read of the atServer.
  Forgery and impersonation: the sender is the one the atSign's own atServer
  reports over auto_approve's authenticated connection. A matching
  notification from any other atSign is never approved, and never counts
  toward the limit.

  @forgery @impersonation
  Scenario: at_activate auto_approve acts only on requests announced by its own atSign
    Given at_activate auto_approve running for @alice
    When a notification whose key matches .new.enrollments.__manage arrives from @bob
    Then auto_approve does not act on it
    And a warning is logged naming the sender and the key
