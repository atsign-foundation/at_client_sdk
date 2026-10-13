Feature: Server mutex on AtClient
  A client takes a short-lived lock by creating an immutable self record with
  a ttl on its own atServer. The atServer refuses a second create of the same
  record until the ttl runs out, so exactly one client wins. The create goes
  straight to the atServer with :nc, so the record never enters the local
  store or the commit log, and its ttl is the only thing that releases it.

  Races: the atServer serialises creates of one record and accepts exactly
  one. Replay: the record is not a credential, and the create travels on the
  client's own authenticated connection. Denial of service: the ttl is capped
  at 15 minutes, and a lock leaves no commit entry, so locks taken for other
  atSigns' requests no longer grow the commit log. Forgery and impersonation:
  only the atSign's own authenticated connections can create its self
  records, and a key owned by another atSign, shared with one, or public is
  refused.

  Scenario: The first client to ask takes the lock
    Given no record exists for "s1.session_mutexes.sshnp@alice"
    When a client of @alice asks for that lock with a ttl of 30 seconds
    Then it gets a lease expiring no later than 30 seconds after it asked
    And the atServer holds the record as immutable with a ttl of 30000 ms
    And the record's value is the client's enrollment id

  Scenario: A client is refused while another holds the lock
    Given another client of @alice holds "s1.session_mutexes.sshnp@alice"
    When a client of @alice asks for that lock
    Then it gets no lease

  @race
  Scenario: Exactly one of two racing clients takes the lock
    Given two clients of @alice, each under its own enrollment
    When both ask for the same lock at the same moment
    Then exactly one gets a lease

  @race
  Scenario: A lock taken without the extension still excludes the extension
    Given a client created the lock record with an immutable put and no :nc
    When a client asks for the same lock through the extension
    Then it gets no lease

  Scenario: The lock frees itself when its ttl runs out
    Given a client took a lock with a ttl of 2 seconds
    When another client asks for the same lock 3 seconds later
    Then it gets a lease

  Scenario: Taking a lock writes no commit entry
    When a client takes a lock
    Then the command it sends carries immutable, the ttl and :nc
    And another client of @alice that syncs afterwards does not receive it

  Scenario: Taking a lock writes nothing to the local store
    When a client takes a lock
    Then its local store holds no record for the lock key

  @dos
  Scenario: A ttl over 15 minutes is refused
    When a client asks for a lock with a ttl of 15 minutes and 1 millisecond
    Then it throws an ArgumentError naming the ttl
    And nothing is sent to the atServer

  Scenario: A ttl of exactly 15 minutes is accepted
    When a client asks for a lock with a ttl of 15 minutes
    Then the create is sent with a ttl of 900000 ms

  @dos
  Scenario: A ttl of zero or less is refused
    When a client asks for a lock with a ttl of 0
    Then it throws an ArgumentError naming the ttl
    And nothing is sent to the atServer

  @impersonation
  Scenario: A key owned by another atSign is refused
    When a client of @alice asks for "s1.session_mutexes.sshnp@bob"
    Then it throws an ArgumentError naming the key
    And nothing is sent to the atServer

  @impersonation
  Scenario: A key shared with another atSign is refused
    When a client of @alice asks for "@bob:s1.session_mutexes.sshnp@alice"
    Then it throws an ArgumentError naming the key
    And nothing is sent to the atServer

  @impersonation
  Scenario: A public key is refused
    When a client of @alice asks for "public:s1.session_mutexes.sshnp@alice"
    Then it throws an ArgumentError naming the key
    And nothing is sent to the atServer

  Scenario: Any other failure is thrown to the caller
    Given the atServer answers the create with an error other than the
      refusal of a second create
    When a client asks for a lock
    Then that error is thrown, so the caller decides whether to go ahead

  Scenario: A client recognises a lock its own enrollment holds
    Given a client took a lock under its enrollment
    When a client under the same enrollment asks whether it holds that lock
    Then the answer is yes

  Scenario: A lock held by another enrollment is not the client's own
    Given a client under another enrollment holds the lock
    When a client asks whether it holds that lock
    Then the answer is no

  Scenario: A lock that no longer exists is not held
    Given no record exists for the lock key
    When a client asks whether it holds that lock
    Then the answer is no
