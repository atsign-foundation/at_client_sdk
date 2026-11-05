Feature: A program derives a posture from another with copyWith

  PqPosture.copyWith returns a posture with each axis given replaced and
  every other axis copied, and refuses a combination the PqPosture
  constructor refuses. It is how a program builds a posture none of the
  named stages defines in one line: one that writes post-quantum by default
  and still allows legacy encryption is
  PqPosture.pqActive.copyWith(disallowLegacyEncryption: false).

  Races, replay and DoS: none arise. A posture is an immutable value built
  inside the program, and copying one sends nothing.
  Forgery and impersonation: a posture decides only what this client writes
  and refuses, and every refusal the constructor makes applies to a copy.

  Scenario: Every axis is copied
    Given each named stage
    When the program copies it with no axis given
    Then the copy has every axis of the stage

  Scenario: An overridden axis changes, and every other axis is kept
    Given a posture
    When the program copies it with one axis given
    Then the copy has that axis's new value and every other axis of the original, for each axis in turn

  Scenario: A combination the constructor refuses is refused
    When the program copies pqReady with disallowLegacyEncryption true
    Then it throws ArgumentError saying the posture refuses its own writes

  Scenario: pqActive allowing legacy encryption writes post-quantum by default
    When the program copies pqActive with disallowLegacyEncryption false
    Then the copy writes post-quantum by default and does not disallow legacy encryption, and pqActive itself is unchanged
