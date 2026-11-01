Feature: A client that holds its namespace key writes after an offline restart

  A client verifies its own namespace key advertisement against the signing
  key of the enrollment that published it, read from the atServer. Once it
  has verified it, it keeps a local record of the bytes it verified, signed by
  its client data signing key (its client authentication signing key until it
  holds one, as for every envelope it signs) and naming the namespace keys it
  held then.
  When a restart finds no atServer, it accepts the advertisement in local
  storage only if that record vouches for exactly those bytes and the
  namespace keys it holds now. Online, and when the atServer refuses, nothing
  changes.

  Races: the record is written after the verification it describes, for the
  bytes verified; a change pulled later no longer matches it and is verified
  online.
  Replay: a restored older copy of local storage is refused once the client
  holds a namespace key it did not hold then. Left over: a copy from before a
  rotation whose key never reached this client is accepted until sync next
  pulls the current advertisement. An online client already accepts such a
  copy until that pull, since it reads its own advertisement local-first.
  DoS: one record per namespace the client writes in, rewritten only when the
  verified bytes change; an offline start checks one signature per namespace,
  locally.
  Forgery and impersonation: only this client's data signing key can produce
  a record; a local _apsk is never read; own writes seal only to namespace
  keys this client holds, so no advertisement can make it seal to a key it
  lacks.

  Scenario: A client restarted with no atServer writes in a namespace it verified and holds the key for
    Given a pqActive client that verified its own advertisement for N online and holds N's namespace key
    When it restarts with no atServer reachable and writes a self key in N
    Then the write succeeds locally and is queued for sync

  Scenario: The same holds when another enrollment of the atSign published the namespace key
    Given a pqActive client holding N's namespace key, whose advertisement another enrollment signed, verified online
    When it restarts with no atServer reachable and writes a self key in N
    Then the write succeeds locally and is queued for sync

  Scenario: An advertisement altered in local storage is not accepted offline
    Given a client that verified N's advertisement online, whose local copy of it was then altered
    When it restarts with no atServer reachable and writes in N
    Then the write fails, naming N's namespace key and the unreachable atServer, and nothing is written

  Scenario: A local record not signed with this client's data signing key is not accepted
    Given a client whose local record for N's advertisement was altered or written without its client data signing key
    When it restarts with no atServer reachable and writes in N
    Then the write fails, naming N's namespace key and the unreachable atServer, and nothing is written

  Scenario: A restored older copy of local storage is not accepted once a newer namespace key is held
    Given a client that has been conveyed a newer namespace key for N since local storage was copied
    When the older copy is restored and the client restarts with no atServer reachable and writes in N
    Then the write fails, naming N's namespace key and the unreachable atServer

  Scenario: Online, a restart verifies the advertisement against the atServer as before
    Given a client that holds a local record for N's advertisement
    When it restarts with the atServer reachable and writes in N
    Then it verifies the advertisement against the publishing enrollment's _apsk from the atServer, and refreshes the record

  Scenario: A refusal from the atServer is not overridden by the local record
    Given a client that holds a local record for N's advertisement
    When it restarts, and the atServer answers that the publishing enrollment's signing key is withdrawn
    Then the write fails with that refusal

  Scenario: An offline write before the client holds a namespace key names that key
    Given a pqActive client that has never verified an advertisement for N
    When it writes in N with no atServer reachable
    Then the write fails with the same exception type as today, and its message names N's namespace key and the unreachable atServer
