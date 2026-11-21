Feature: A client never runs below its floor

  A client runs at the higher of the posture it is configured with and its
  floor, which is set by what its enrollment holds: an active ML-DSA-65
  client data signing key sets pqActive, and any namespace-key private sets
  pqReady. A start configured below its floor logs a warning naming both
  postures and what was raised, and is raised on each setting the floor
  raises: the authentication key algorithm, the strongest data signing
  algorithm, configuring and writing post-quantum, and the pq key exchange.
  A raised client seeds no namespace keys and mints no signing root that its
  configured posture would not, and every other setting stays as configured.
  The floor is read from the keyfile at every start, so a start with no
  atServer applies it too.

  Races: the floor is read from the keyfile before the enrollment settles,
  and nothing is written for it.
  Replay: none arises; nothing is sent.
  DoS: none new; the floor reads only the keyfile, and a client it lifts
  re-enrolls itself once under the existing bounds.
  Forgery and impersonation: the floor only raises what a client does, never
  lowers it, and counts only key material in the client's own keyfile. A
  raised client never creates the atSign's signing root, so only a client
  configured for post-quantum does.

  Scenario: A client whose keyfile holds a namespace-key private runs at pqReady at least
    Given @kilo's keyfile holds the namespace-key private for k1.sensor
    When a client of that keyfile is configured PqPosture.legacy and starts
    Then it warns that it runs at pqReady, ensureReachable answers alreadyReachable with holdsPrivate true, and it opens what @sierra seals there

  Scenario: A client whose keyfile holds an ML-DSA-65 client data signing key runs at pqActive
    Given an enrollment whose keyfile holds an active ML-DSA-65 client data signing key
    When a client of it is configured PqPosture.pqReady and starts
    Then it warns that it is raised to its pqActive floor, writes post-quantum by default, and mints no RSA-2048 client data signing key

  Scenario: The floor holds at a start with no atServer
    Given a keyfile holding a namespace-key private
    When a client of it starts configured PqPosture.legacy with no atServer reachable
    Then it warns that it runs at pqReady, and runs at pqReady

  Scenario: A client configured at or above its floor runs as configured, without a warning
    Given a keyfile holding a namespace-key private
    When a client of it is configured PqPosture.pqReady, or PqPosture.pqActive, and starts
    Then it runs at the posture it was configured with, and logs no warning about the floor

  Scenario: A client with no floor runs as configured
    Given an enrollment holding neither a namespace-key private nor an ML-DSA-65 client data signing key
    When a client of it is configured PqPosture.legacy and starts
    Then it runs at legacy and logs no warning about the floor

  Scenario: A posture no named stage defines is raised only where it is below the floor
    Given a keyfile holding a namespace-key private
    When a client of it starts configured with PqPosture.legacy.copyWith(mintLegacyMaterial: false)
    Then it reads post-quantum data and authenticates with ML-DSA-65 as pqReady does, and keeps mintLegacyMaterial false

  Scenario: A floor does not turn seeding on
    Given a keyfile holding a namespace-key private
    When a client of it starts configured with a posture that seeds no namespace keys
    Then it runs at its pqReady floor and seeds none

  Scenario: A floor does not mint a signing root
    Given a fully privileged keyfile holding a namespace-key private, on an atSign that publishes no signing root
    When a client of it starts configured PqPosture.legacy
    Then it runs at its pqReady floor and publishes no signing root
