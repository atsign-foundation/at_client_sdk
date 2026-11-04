Feature: Notifications start once however many callers ask

  startNotifications connects, authenticates if required and sends monitor:.
  A call made while another is still starting joins that start and sends
  nothing of its own; a call made after stopNotifications has ended that
  start begins a new one.

  Races: two starts at once send one monitor:, and a start a stop has ended
  is never joined.
  Replay: none arise; monitor: is sent on a connection this lookup logged in.
  DoS: one monitor: per start, however many callers ask.
  Forgery and impersonation: none arise; no command or login changes.

  Scenario: Two starts at once send one monitor:
    Given a start waiting on the caller's watermark
    When a second start is made before the first sends monitor:
    Then one monitor: is sent, and both starts complete

  Scenario: A start after a stop sends its own monitor:
    Given a start waiting on the caller's watermark
    When the caller stops notifications and starts them again
    Then the second start sends monitor:
