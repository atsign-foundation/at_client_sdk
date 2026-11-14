Feature: A notification is delivered once across a change of leading tab

  Two tabs of one app share a monitor connection. The leading tab's
  connection receives a notification and relays it; both tabs' subscribers
  are given it. When the leading tab closes, the other takes the connection
  and resumes from its own cursor, the time of the last notification it was
  given. The atServer's inclusive filter sends that notification again; the
  subscriber does not see it twice, and what follows it is delivered.

  Races: the old leader's close and the new leader's start are ordered by
  the lock; a notification relayed before the close has advanced the new
  leader's cursor before it starts.
  Replay: the re-sent notification is de-duplicated by id; a later one with
  the same timestamp is not dropped.
  DoS: the de-duplication set is bounded.
  Forgery and impersonation: unchanged; the new leader authenticates its own
  connection as any tab would.

  Scenario: The notification before the handoff and the ones after it
    Given two tabs of one atSign, the first leading
    When the atServer sends a notification to the first tab's connection
    Then both tabs' subscribers are given it, on one connection
    When the first tab closes its notification service
    Then the second leads and starts its connection from that notification's time
    When the atServer sends that notification again and then a later one
    Then the second tab's subscriber is given the later one, and the first only once
