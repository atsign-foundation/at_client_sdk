Feature: The tabs of one origin share one monitor connection

  Every tab of an app that opens the same atSign under the same scope asks
  for one named lock. The tab granted it leads: it runs notifications on its
  own connection and relays every line, and whether that connection is up,
  on a channel of the same name. The other tabs follow: their monitor sees
  the relayed lines and state as if from a connection of their own, and
  never opens one. When the leader stops, the next tab in line is granted
  the lock and starts its connection from its own cursor. A leader the
  browser has frozen falls silent; a follower that misses three beacons and
  gets no answer to a hello takes the lock, and the thawed leader finds its
  grant lost, drops its connection and follows.

  Races: the lock serialises leadership; a follower promoted while the old
  leader's last lines are in flight still receives them, as its channel
  stays open until it leads. Two tabs that steal at once are serialised by
  the lock as well; only one is granted.
  Replay: a promoted tab resumes from its own cursor, which the relayed
  lines advanced; the atServer's inclusive filter re-sends the cursor's
  notification, which the service above de-duplicates.
  DoS: the channel is same-origin only; a message the codec does not know
  is dropped; a leader whose connection will not start retries on the capped
  backoff and never gives the lock up.
  Forgery and impersonation: the channel and the lock are reachable only
  from the origin's own pages; a tab of another origin can neither post nor
  take the lock. Relayed lines carry what the leader's authenticated
  connection received, nothing more.

  Scenario: Three tabs start one connection
    Given three tabs starting notifications on one name
    When their roles settle
    Then the first leads and starts its connection once
    And the two others follow and never start theirs

  Scenario: A line on the leader reaches every tab once
    Given a leader and two followers
    When the leader's connection delivers a line
    Then each tab's notifications carry that line once
    And each tab's connection state mirrors the leader's, once per change

  Scenario: A late joiner learns the state at once
    Given a leader whose connection is up
    When another tab starts and follows
    Then it hears the leader's state without waiting for a change

  Scenario: The leader stopping passes the lock
    Given a leader and two followers
    When the leader stops notifications
    Then the next tab leads and starts its connection from its own cursor
    And the remaining follower saw the connection go down and come up

  Scenario: A follower stopping leaves the leader alone
    Given a leader and a follower
    When the follower stops and starts notifications
    Then its lock request is withdrawn and made again
    And neither connection is touched

  Scenario: A frozen leader is replaced
    Given a leader whose page the browser has frozen
    When three beacons are missed and a hello goes unanswered for one more
    Then a follower takes the lock and starts its connection
    And the leader, once thawed, drops its connection and follows

  Scenario: With steal off a follower waits
    Given a follower started with steal off and a frozen leader
    When many beacon intervals pass
    Then the follower still follows and the lock is not taken

  Scenario: A stale leader reconnects when its page shows
    Given a leader whose connection has been silent longer than staleAfter
    When the page becomes visible
    Then the connection is dropped once, so that it reconnects
    And a fresh connection is left alone when the page shows again
    And coming back online drops the connection regardless

  Scenario: The browser's lock and channel behave as the ports expect
    Given two channels of one name and a third of another, in one page
    When one posts
    Then the other of its name hears it and neither the poster nor the third does
    And lock requests are granted in order, an aborted request never takes the
      lock, and a steal takes it from its holder, whose grant is lost
