Feature: A weaker posture keeps a stronger client data signing key

  An enrollment's client data signing keys follow the in-use set,
  AtClientPreference.dataSigningKeyAlgorithms, which a posture sets: a start
  mints a key for each algorithm the set names that the enrollment lacks,
  and retires each one it holds that the set no longer names. A held key
  stronger than every algorithm the set names stays active, and while the
  enrollment holds one nothing is minted, so a start at a weaker posture
  changes neither the keyfile nor the published _apsk, and logs that it
  kept the key.

  Races: none new; a start that keeps the key writes nothing, and one that
  mints or retires does so inside the one _apsk write section as before.
  Replay: none arise; nothing new is sent.
  DoS: a start at a weaker posture writes nothing, so the keyfile and _apsk
  do not grow however often the posture alternates.
  Forgery and impersonation: an enrollment holding an ML-DSA-65 client data
  signing key is given no RSA-2048 one by a weaker posture, so the keys its
  _apsk advertises change only when a stronger set asks.

  Scenario: A weaker posture does not downgrade the client data signing key
    Given an enrollment whose keyfile holds an active ML-DSA-65 client data signing key
    When a client opens it at PqPosture.pqReady
    Then the ML-DSA-65 key stays active, no RSA-2048 client data signing key is minted, and neither the keyfile nor the published _apsk changes

  Scenario: Alternating postures does not grow the keyfile
    Given an enrollment opened at pqActive
    When it is opened alternately at pqReady and pqActive five times
    Then its keyfile holds one client data signing key and its _apsk lists one
