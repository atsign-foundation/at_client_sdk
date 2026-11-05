Feature: A lookup over TLS reads the atDirectory's answer whole, as host:port

  Over TLS, a lookup asks the atDirectory where an atSign's atServer is by
  writing the atSign as one line after the atDirectory's prompt. It reads the
  answer up to its line end, however many chunks it arrives in, and takes it
  only as host:port, or as null for an atSign with no entry. An answer of any
  other shape, or longer than the bound a browser lookup's answer has, is
  refused.

  Races: none arise; one question is answered on one connection.
  Replay: none arise; what is asked, and how the atServer is then reached,
  do not change.
  DoS: the answer is bounded in size.
  Forgery and impersonation: the atServer a lookup connects to is the one the
  atDirectory named; TLS to it and authentication are unchanged.

  Scenario: An answer split across chunks is read whole
    Given an atDirectory whose host:port answer arrives in two chunks, split inside the port
    When a lookup asks it where the atSign's atServer is
    Then the address carries the whole port

  Scenario: An answer that is not host:port is refused
    Given an atDirectory that answers with a host name holding a space
    When a lookup asks it where the atSign's atServer is
    Then the lookup fails and nothing is cached

  Scenario: An atSign holding a line feed is not sent
    Given an atSign holding a line feed
    When a lookup asks the atDirectory where its atServer is
    Then the request fails before any connection is made
