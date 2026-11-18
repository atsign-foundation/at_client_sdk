Feature: Passkey PRF outputs are checked, and a recorded miss can be cleared
  Registering a passkey creates it, then asserts it to read its PRF output.
  An output that is missing or all zeroes is refused before any key is
  derived, and a passkey that was created but yields no usable output is
  reported to the platform as unknown, so the platform can drop it. In a
  browser that cannot say whether it supports PRF, a recorded miss refuses
  onboarding for 30 days unless the app clears it. Every platform names a
  passkey by one display-name rule, kept in core.

  Forgery and impersonation: an all-zero PRF output carries no secret, so it
  is refused. Races: none; each ceremony is the user's own, one at a time.
  Replay: the PRF input is fixed per passkey, and nothing here is sent.
  Denial of service: a miss is cleared by the app, and each failed
  registration's passkey is reported as unknown rather than left in the
  platform's list.

  @forgery
  Scenario: A PRF output of all zeroes is refused before any key is derived
    Given the authenticator returns a PRF output of 32 zero bytes
    When the app onboards @alice🛠
    Then it throws a PrfUnavailableException
    And no key was derived and no activation was attempted

  @forgery
  Scenario: A wiped PRF secret cannot be derived from
    Given a PRF secret that was wiped
    When a deriver is asked to derive from it
    Then it throws a StateError before deriving anything

  Scenario Outline: A passkey created without a usable PRF output is reported as unknown
    Given the authenticator creates a passkey and the assertion that follows <outcome>
    When the app onboards @alice🛠
    Then the new credential is reported to the platform as unknown
    And the onboarding fails before any activation

    Examples:
      | outcome                        |
      | fails because the user cancels |
      | returns no PRF output          |
      | returns 32 zero bytes          |

  Scenario: An app clears a recorded PRF miss, and onboarding tries the passkey again
    Given a browser that cannot report PRF support recorded a PRF miss today
    When the app clears the PRF miss and onboards @alice🛠
    Then the passkey create ceremony runs

  Scenario: Every platform names a passkey by the same rule
    Given an enrollment at 2026-11-06T14:05:59Z from the device "Alice Mac"
    When a passkey is created for it on any platform
    Then its display name is "2026-11-06 14:05Z · Alice Mac"
    And a device name too long for 64 UTF-8 bytes is cut between code points
