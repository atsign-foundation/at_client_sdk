Feature: A sync asked for while a round runs gets a round of its own

  A round of sync answers every sync request queued when it reads the
  atServer. A request made after that read, by the app, by a local write or
  by a stats notification, is not answered by that round: once it ends, one
  more round runs for every request made during it, reading the atServer
  afresh when any of them is the app's.

  Races: a request is answered only by a round that read the atServer after
  it was made, so a write made during a round is pushed by the next round
  rather than waiting for the periodic sync.
  Replay: none arises; requests are local calls, and nothing on the wire
  changes.
  DoS: the requests made during one round share one more round, so a burst
  costs at most one extra round, and the queue keeps its bound.
  Forgery and impersonation: none arise; a stats notification counts only
  when it is the atServer's own for this client's atSign, as before.

  @race
  Scenario: A sync an app asks for while a round runs gets a round of its own
    Given a round waiting on its read of the atServer
    When the app asks for a sync
    Then another round runs after it, reading the atServer afresh
