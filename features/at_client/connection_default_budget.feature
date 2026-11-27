Feature: A connection attempt keeps its five second default budget

  AtConnection.defaultBudget bounds each attempt() and awaitOnline() call that
  names no budget of its own. A session open is not one of them: it passes the
  network default as the budget of its first connect, so the retry ladder and
  the authentication it waits for fit. The default itself stays five seconds
  for every other caller.

  # Threats. Each answer names the scenario that holds it.
  #
  # Race: none arise; the budget is a constant read at each call, and nothing
  #   here shares state between callers.
  # Replay: none arise; a budget is a duration, not a message, so nothing is
  #   sent or reused.
  # DoS: an attempt that names no budget is still bounded by the five second
  #   default, so a dead atServer cannot hold a caller past it ("the default
  #   connection budget stays five seconds").
  # Forgery: none arise; nothing here reads or trusts a peer's text.
  # Impersonation: none arise; a budget carries no identity.

  Scenario: the default connection budget stays five seconds
    Given AtConnection's default budget
    When it is read
    Then it is five seconds
    And a session open passes the network default as its own budget
