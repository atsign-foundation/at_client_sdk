Feature: Logging out of the todos example stops its client

  Races: logout awaits stop() before it clears the current client, so a
  sign-in after logout never meets the old client still live.
  Replay, DoS: none arise.
  Forgery and impersonation: after logout nothing goes on syncing or
  listening for the old atSign.

  Scenario: Logging out stops the client, so the same atSign can sign in again
    Given the todos app signed in as an atSign
    When the user logs out
    Then that client is stopped, no client is current, and opening the same atSign again succeeds

  Scenario: Logging out clears the client even when stopping it fails
    Given the todos app signed in, with a client whose stop throws
    When the user logs out
    Then logout throws that failure, and no client is current
