Feature: A connection budget that fires after the challenge is not an unreachable atServer

  AtClientImpl's one bounded connect and authenticate maps a TimeoutException
  to offline(unreachable). That is the right reading only while the atServer
  has said nothing: no challenge means nothing is known about reachability.
  A budget that fires after the atServer answered from: is a post-challenge
  outcome — the atServer was reached, and what the authentication then does
  (sign, wait for the pkam: reply) is the client's own work. So the attempt
  keeps waiting for the authentication's own outcome and reports that:
  online, refused, or a local fault thrown as itself, never offline because
  of the budget. Each attempt opens an AuthAttempt on RemoteSecondary, which
  knows which side of the challenge the budget fired on: the attempt is
  unanswered when it opens and answered as soon as an authenticator run that
  started while it was open gets a reply to its first command. The attempt
  ends when its authentication returns or throws, whatever the outcome.

  # Threats. Each answer names the scenario that holds it.
  #
  # Race: the budget and the challenge are two events on one authentication.
  #   An attempt is answered only by a run that started while it was open,
  #   and only by that run's own first reply, so a run left to finish on its
  #   own after its budget cannot answer for a later attempt: the later
  #   attempt still sees no challenge and reports offline on its own budget
  #   rather than re-awaiting an atServer it never heard from ("a late
  #   challenge from an earlier run does not answer a later attempt").
  #   The attempt hears every run that starts while it is open and keeps the
  #   first answer, so a verb or a retry that starts another run mid-attempt
  #   cannot erase it ("a verb that starts another run mid-attempt does not
  #   turn an answered challenge into offline"); a run that starts after the
  #   attempt has ended does not answer for it. The attempt is ended in a
  #   finally, so no attempt stays open after success, a local fault or the
  #   budget ("an attempt that ends leaves no open attempt").
  # Replay: no challenge or signature is reused; the attempt still runs one
  #   authenticator run per connection and reports what it found.
  # DoS: a dead atServer is still bounded by the budget, because a budget
  #   spent before the challenge stays offline at once; a reached atServer
  #   that is slow to finish is bounded by the authentication's own command
  #   timeouts, not by the attempt's budget ("a budget that ends after the
  #   challenge reports the authentication's own outcome, not offline"). The
  #   residual is a timeout the lookup raises from its own read: whatever the
  #   challenge it is reported offline, as it always was ("a budget that ends
  #   after the challenge still reports offline when the lookup itself times
  #   out").
  # Forgery: nothing here reads a peer's text as truth. an answered
  #   attempt says only that a reply arrived, and a reply that is not a challenge the
  #   client will sign is still reported as it was.
  # Impersonation: a local fault — an unreadable signing key, for instance —
  #   says nothing about the atServer, so a reached atServer never turns it
  #   into an offline state that would send the app to the network for it
  #   ("a budget that ends after the challenge does not hide a local fault as
  #   offline").

  Scenario: a budget that ends before the atServer's challenge arrives reports offline
    Given a client whose authentication's from: is never answered
    When the connection attempt's budget is spent
    Then the connection state is offline with cause unreachable

  Scenario: a budget that ends after the challenge reports the authentication's own outcome, not offline
    Given a client whose from: is answered at once with a valid challenge
    And whose pkam: reply lands after the attempt's budget and succeeds
    When the connection attempt's budget is spent
    Then the attempt waits for the authentication and the connection state is online

  Scenario: a budget that ends after the challenge does not hide a local fault as offline
    Given a client whose from: is answered at once with a valid challenge
    And whose authentication hits a local fault after the attempt's budget
    When the connection attempt's budget is spent
    Then the attempt throws that fault and records no offline state

  Scenario: a budget that ends after the challenge reports the atServer's refusal as itself, not offline
    Given a client whose from: is answered at once with a valid challenge
    And whose authentication is refused by the atServer after the attempt's budget
    When the connection attempt's budget is spent
    Then the connection state is not offline for being unreachable

  Scenario: a verb that starts another run mid-attempt does not turn an answered challenge into offline
    Given a client whose from: is answered at once and whose pkam: reply lands after the budget
    And a verb starts an authenticator run whose from: is not yet answered
    When the connection attempt's budget is spent
    Then the connection state is online

  Scenario: a run that starts after the attempt has ended does not answer for it
    Given an attempt that has ended
    When an authenticator run starts and its from: is answered
    Then the attempt is not answered

  Scenario: an attempt is unanswered until the atServer answers a run
    Given an open attempt and an authenticator run that has not been answered
    When the atServer answers its from: with a challenge
    Then the attempt is answered, having been unanswered

  Scenario: a late challenge from an earlier run does not answer a later attempt
    Given a first attempt whose from: is held until its budget is spent, reporting offline
    And a second attempt whose from: is held in its turn
    When the first attempt's from: is answered while the second attempt waits
    Then the second attempt is still unanswered
    And the second attempt reports offline with cause unreachable on its own budget

  Scenario: an attempt that ends leaves no open attempt
    Given a client whose attempt succeeds within its budget, one whose attempt fails with a local fault, and one whose budget is spent before any challenge
    When each attempt returns
    Then RemoteSecondary has no open attempt after each

  Scenario: a budget that ends after the challenge still reports offline when the lookup itself times out
    Given a client whose from: is answered at once with a valid challenge
    And whose pkam: leg times out on the lookup's own read, after the attempt's budget
    When the connection attempt's budget is spent
    Then the connection state is offline with cause unreachable
