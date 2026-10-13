Feature: AtRpc request mutex
  A responder with enableRequestMutex takes a server mutex on each request's
  id before handling it, so when several responders share an atSign, exactly
  one handles each request. The lock lasts 30 seconds. It needs an atServer
  from p3.13.0; on an older one every lock is refused, so a responder with the
  mutex on handles no requests.

  Races: the atServer serialises the creates, so two responders can't both
  take one request's lock. Replay: the lock dedupes a request only within its
  30 seconds, as before; this adds no replay surface. DoS: each request costs
  one lock record for 30 seconds, and from c3.16.3/p3.16.5 no commit entry.
  Forgery and impersonation: unchanged; only allow-listed requesters are
  handled, and the lock is a self record on the responder's own atServer.

  @race
  Scenario: Exactly one of two responders handles a request
    Given two responders for @alice with the request mutex on, each its own client
    When @bob sends one request to @alice
    Then exactly one responder handles it

  Scenario: A request's lock records no commit
    Given a responder for @alice with the request mutex on
    When it takes the lock for a request from @bob
    Then the atServer's latest commit id does not move
