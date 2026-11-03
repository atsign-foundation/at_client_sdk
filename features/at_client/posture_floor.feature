Feature: A client never runs below its floor

  A client runs at the higher of the posture it is configured with and its
  floor. The floor is the higher of what its enrollment holds, where an
  active ML-DSA-65 client data signing key sets pqActive and any
  namespace-key private sets pqReady, and what its atSign advertises, where
  any namespace key the atSign publishes sets pqReady. A start configured
  below its floor logs a warning naming both postures, and runs at the
  floor. What the atSign advertises is read at each start that reaches the
  atServer and kept in the keyfile, so a start with no atServer keeps the
  floor, and the floor never comes down.

  Races: the floor is the higher of what the keyfile holds and what the
  atServer answers at that start; two processes that raise it in one
  keyfile each write the higher value, so neither lowers the other's.
  Replay: none arises; nothing new is sent, and the floor only rises.
  DoS: one scan of the atSign's namespace-key records at each start that
  reaches the atServer, none offline; a client the floor lifts re-enrolls
  itself once and asks for its keys under the existing bounds.
  Forgery and impersonation: the floor only raises what a client does,
  never lowers it; it counts only records the atSign's own atServer holds
  under the atSign's own name, which only the atSign's enrollments can
  publish, and never a cached copy of another atSign's.

  Scenario: A client whose keyfile holds a namespace-key private runs at pqReady at least
    Given @kilo's keyfile holds the namespace-key private for k1.sensor
    When a client of that keyfile is configured PqPosture.legacy and starts
    Then it warns that it runs at pqReady, ensureReachable answers alreadyReachable with holdsPrivate true, and it opens what @sierra seals there

  Scenario: A client whose keyfile holds an ML-DSA-65 client data signing key runs at pqActive
    Given an enrollment whose keyfile holds an active ML-DSA-65 client data signing key
    When a client of it is configured PqPosture.pqReady and starts
    Then it warns that it runs at pqActive, writes post-quantum by default, and mints no RSA-2048 client data signing key

  Scenario: A legacy client of an atSign that publishes a namespace key runs at pqReady
    Given @alice publishes a namespace key, and an enrollment of @alice at the legacy key exchange that holds no namespace key
    When a client of it is configured PqPosture.legacy and starts with its atServer reachable
    Then it warns that it runs at pqReady, re-enrolls itself with ML-DSA-65 authentication, and asks @alice's other enrollments for its namespace keys

  Scenario: A peer's namespace key does not raise the floor
    Given @alice publishes no namespace key, and @alice's atServer holds a cached copy of @bob's
    When a client of @alice configured PqPosture.legacy starts
    Then it runs at legacy and logs no warning about the floor

  Scenario: The floor an atSign set holds at a start with no atServer
    Given a client that found @alice publishing a namespace key at an earlier start
    When it restarts configured PqPosture.legacy with no atServer reachable
    Then it warns that it runs at pqReady, and runs at pqReady

  Scenario: The floor never comes down
    Given a keyfile whose floor is pqReady, kept from an earlier start
    When @alice publishes no namespace key any more, and a client of the keyfile starts configured PqPosture.legacy
    Then it runs at pqReady

  Scenario: A client configured at or above its floor runs as configured, without a warning
    Given a keyfile whose floor is pqReady
    When a client of it is configured PqPosture.pqReady, or PqPosture.pqActive, and starts
    Then it runs at the posture it was configured with, and logs no warning about the floor

  Scenario: A client with no floor runs as configured
    Given an atSign that publishes no namespace key, and an enrollment holding neither a namespace-key private nor an ML-DSA-65 client data signing key
    When a client of it is configured PqPosture.legacy and starts
    Then it runs at legacy and logs no warning about the floor

  Scenario: A posture no named stage defines is raised only where it is below the floor
    Given a keyfile whose floor is pqReady
    When a client of it starts configured with PqPosture.legacy.copyWith(mintLegacyMaterial: false)
    Then it reads post-quantum data and authenticates with ML-DSA-65 as pqReady does, and keeps mintLegacyMaterial false
