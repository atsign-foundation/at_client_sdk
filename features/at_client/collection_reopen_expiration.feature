Feature: A collection is not reopened with another default expiration

  AtClient.collection hands back the collection it already built for the
  same namespace, folded to lower case, and eventSource. That collection's
  defaultExpiration is the lifetime new items get, and it is final at
  construction: every write through the cached collection stamps expiresAt
  from it. A reopen of the same namespace and eventSource that names another
  default expiration is therefore refused with ArgumentError naming
  `defaultExpiration` and caches nothing, because handing the cached
  collection out would leave the caller writing items that live for a time
  it did not ask for. A reopen naming the expiration the collection already
  holds returns that same cached instance, and so does an open of another
  eventSource, which is a separate collection with its own expiration. The
  check holds on that client only.

  Threats: none new.
  Race: the expiration check runs synchronously with the cache lookup, so
    two callers cannot both win the slot with different expirations; the
    first caller's expiration is the one that holds.
  Replay: no wire message or nonce is added; the expiration only feeds the
    expiresAt of the items this client writes, as it did before.
  DoS: one Duration comparison per open; a refused open allocates nothing,
    registers no factory and runs no orphan sweep.
  Forgery and impersonation: the expiration only sets the expiresAt of the
    caller's own writes. Signatures and ownership checks are unchanged, and
    a peer cannot change an item's stored expiresAt through this argument.

  Scenario: reopening a collection with another expiration is refused
    Given a collection open on this client with a one day default expiration
    When the same namespace and eventSource are reopened with a two day default expiration
    Then ArgumentError names defaultExpiration
    And the first collection stays cached with its one day expiration

  Scenario: reopening a collection with its own expiration returns the cached collection
    Given a collection open on this client with a one day default expiration
    When it is reopened with a one day default expiration
    Then the same cached instance is returned

  Scenario: opening another eventSource of the namespace with another expiration is allowed
    Given a collection open on this client with a one day default expiration
    When another eventSource of the namespace is opened with a two day default expiration
    Then a separate instance with the two day expiration is returned
