Feature: Every write of a server-held @keys document holds the enrollment's lock
  Every write of an enrollment's server-held @keys document runs under a
  server mutex: the short-ttl immutable self record that ServerMutex takes,
  one per enrollment. A writer that finds the lock held waits and tries
  again, from a fresh read of the document. A put needs at least half the
  lock's ttl left on its lease; with less, the writer takes the lock again
  and re-reads. A refused write (a candidate that drops stored material,
  or a read-back that differs) still stops the store: it accepts no further
  write.

  A writer whose own last lease is too short to reuse first waits until
  the atServer has let that lock go: what is left of the lease, under half
  the ttl, plus the time its take took to be answered. Its bound on
  waiting for the lock starts after that.

  Races: two clients of one enrollment (two tabs, or two devices on one
  synced passkey) each take the lock before reading, so the second builds
  on the first's write. A put sent late in a lease could land after the
  lock expired, so a put needs half the ttl left. That margin is the only
  guard that prevents a lost write: a put that takes longer than half the
  ttl to land can land after the lock expired, and then it and the put of
  the next writer to take the lock can each drop what the other added,
  whichever lands last. The refusal of a write that drops material does not
  catch this, since the overwriting writer's last read predates the put it
  overwrites, and the overwritten writer's read-back catches it only when
  the overwrite lands first; otherwise both writes report success. Replay: the
  lock record is not a credential and is created on the enrollment's own
  authenticated connection. Denial of service: a held lock is released by
  its ttl, so a writer that stopped holding it delays the enrollment's
  writes by at most that ttl, and a writer gives up after a bounded wait:
  for its own last lock, under half the ttl plus the time its take took,
  then its bound.
  Forgery and impersonation: only the Atsign's own authenticated
  connections create its self records, and the lock record and the document
  sit in the enrollment's own namespace, which an atServer lets only that
  enrollment change; an atServer that predates that rule lets another
  enrollment of the Atsign hold the lock to delay writes, but there it could
  already overwrite the document.

  @race
  Scenario: Two clients of one enrollment add key material at once, and both additions survive
    Given two passkey sessions of @alice🛠 as the same enrollment, each with its own client and connection
    When each adds a different key to its @keys at the same moment
    Then each write reports success
    And the @keys document holds both keys

  Scenario: A write that finds the lock held waits, re-reads and keeps the other writer's change
    Given another client of the same enrollment holds the @keys lock and is adding a key
    When this client adds a different key
    Then it writes only once it has taken the lock
    And it reads the document after taking the lock
    And the document it writes holds both keys

  Scenario: Every @keys write holds the enrollment's lock
    Given a passkey session's client of @alice🛠
    When the client writes its @keys document
    Then it held an unexpired lease on the enrollment's immutable lock record, with a ttl, when it put the document

  @race
  Scenario: A writer whose lock runs out before it puts takes the lock again and re-reads
    Given the client took the @keys lock and its lease ran out before it put the document
    When the write goes on
    Then the client puts nothing on that lease
    And it takes the lock again and re-reads the document before it puts

  @dos
  Scenario: A writer that cannot take the lock within its bound fails without writing
    Given the enrollment's @keys lock stays held past the writer's bound
    When the client adds a key to its @keys
    Then the write fails with an AtException that names the lock
    And nothing was put
    And the store accepts a later write

  @dos
  Scenario: A writer waits out its own last lease before its bound starts
    Given the client's last lease on the @keys lock has under half its ttl left
    And the client's bound is shorter than what is left of that lease
    And no other writer holds the lock
    When the client adds a key to its @keys
    Then it takes the lock again once that lease has run out
    And the key is written

  Scenario: A write whose read-back differs stops the store
    Given the @keys document read back after a write differs from the one written
    When the client writes its @keys again
    Then the write is refused before anything is read or put
