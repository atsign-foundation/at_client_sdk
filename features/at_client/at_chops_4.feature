Feature: at_client and at_auth 4.0.0 expose no AtChops

  at_chops 3.7.0 deprecates the AtChops facade for the algorithm classes. at_client
  and at_auth 4.0.0 stop exposing it and stop using it, and stay on at_chops
  3.7.1's algorithm classes, so no record, signature or keyfile format changes.

  Races: none arise; nothing here adds state.
  Replay: none arise; nothing here changes what an atServer issues or
  accepts.
  DoS: none arise; the same work is done on the same inputs.
  Forgery and impersonation: none arise; signing and verification run the
  same at_chops algorithms on the same keys, and a client holding a keyfile
  signs from that keyfile alone, so every check refuses what it refused.

  Scenario: The public API names no AtChops
    Given at_client 4.0.0 and at_auth 4.0.0
    When their barrels are read
    Then no exported member takes, returns or exposes an AtChops

  Scenario: at_auth and at_client use no AtChops
    Given at_auth 4.0.0 and at_client 4.0.0
    When their libraries are read
    Then none of them constructs, holds or calls an AtChops, AtChopsImpl or AtChopsKeys
