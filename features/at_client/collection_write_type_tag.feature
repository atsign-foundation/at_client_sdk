Feature: A collection stamps new items with its writeTypeTag

  collection and subCollection take an optional writeTypeTag. When no factory
  is registered for the item's type, the item is stamped with that tag instead
  of n/a; a registered factory's tag wins. The tag is not inherited by a
  sub-collection. A blank tag, or one that differs from typeTag, is refused at
  construction. AtClient.collection hands back the collection it already built
  for the same namespace, folded to lower case, and eventSource. While any
  collection of the namespace is open on that client, an open that would stamp
  a new T with another tag is refused with ArgumentError and caches nothing.
  An open stamps its typeTag, else the factory tag registered for T, else its
  writeTypeTag, else n/a; a byte collection always stamps binary. The check
  holds on that client only. Sub-collections are not cached, so reopening one
  with another tag is not refused.

  Races: none new; the tag is resolved synchronously at write time from
  constructor state, and the tag check runs synchronously with the cache
  lookup, so two callers cannot both win a slot with different tags.
  Replay: none new; no wire message or nonce is added, and the tag is part of
  the existing record format.
  DoS: one optional string per collection, validated non-blank at
  construction; a refused reopen allocates nothing and runs no orphan sweep.
  Forgery and impersonation: the type tag only labels the payload; signatures
  and ownership checks are unchanged, and a peer can already write any tag on
  its own items.

  Scenario: Given a collection with writeTypeTag Todo and no registered factory, when an item is created, then its type is Todo
    Given a collection with writeTypeTag Todo and no registered factory
    When an item is created
    Then its type is Todo

  Scenario: Given a collection with no writeTypeTag and no registered factory, when an item is created, then its type is n/a
    Given a collection with no writeTypeTag and no registered factory
    When an item is created
    Then its type is n/a

  Scenario: Given an empty writeTypeTag, when a collection is built, then ArgumentError is thrown
    Given an empty writeTypeTag
    When a collection is built
    Then ArgumentError is thrown

  Scenario: Given a whitespace-only writeTypeTag, when a collection is built, then ArgumentError is thrown
    Given a whitespace-only writeTypeTag
    When a collection is built
    Then ArgumentError is thrown

  Scenario: Given a writeTypeTag that differs from typeTag, when a collection is built, then ArgumentError is thrown
    Given a writeTypeTag that differs from typeTag
    When a collection is built
    Then ArgumentError is thrown

  Scenario: Given a writeTypeTag equal to typeTag, when an item is created, then its type is that tag
    Given a writeTypeTag equal to typeTag
    When an item is created
    Then its type is that tag

  Scenario: Given a registered factory tag and a different writeTypeTag, when an item is drafted, then its type is the factory tag
    Given a registered factory tag and a different writeTypeTag
    When an item is drafted
    Then its type is the factory tag

  Scenario: Given a sub-collection with writeTypeTag Comment, when an item is drafted, then its type is Comment
    Given a sub-collection with writeTypeTag Comment
    When an item is drafted
    Then its type is Comment

  Scenario: Given a sub-collection opened through subCollection with writeTypeTag Comment, when an item is drafted, then its type is Comment
    Given a sub-collection opened through subCollection with writeTypeTag Comment
    When an item is drafted
    Then its type is Comment

  Scenario: Given a parent with writeTypeTag Post and a sub-collection with none, when a sub-collection item is drafted, then its type is n/a
    Given a parent with writeTypeTag Post and a sub-collection with none
    When a sub-collection item is drafted
    Then its type is n/a

  Scenario: Given a sub-collection with typeTag and no fromJson, when it is built, then ArgumentError is thrown
    Given a sub-collection with typeTag and no fromJson
    When it is built
    Then ArgumentError is thrown

  Scenario: Given a sub-collection with fromJson and no typeTag, when it is built, then ArgumentError is thrown
    Given a sub-collection with fromJson and no typeTag
    When it is built
    Then ArgumentError is thrown

  Scenario: Given a sub-collection writeTypeTag that differs from typeTag, when it is built, then ArgumentError is thrown
    Given a sub-collection writeTypeTag that differs from typeTag
    When it is built
    Then ArgumentError is thrown

  Scenario: Given an empty sub-collection writeTypeTag, when it is built, then ArgumentError is thrown
    Given an empty sub-collection writeTypeTag
    When it is built
    Then ArgumentError is thrown

  Scenario: Given a whitespace-only sub-collection writeTypeTag, when it is built, then ArgumentError is thrown
    Given a whitespace-only sub-collection writeTypeTag
    When it is built
    Then ArgumentError is thrown

  Scenario: Given a collection open with x, when it is reopened with y, then ArgumentError names the namespace and both tags
    Given a collection open with x
    When it is reopened with y
    Then ArgumentError names the namespace and both tags

  Scenario: Given a collection open with x, when another eventSource of the namespace is opened with y, then ArgumentError is thrown
    Given a collection open with x
    When another eventSource of the namespace is opened with y
    Then ArgumentError is thrown

  Scenario: Given a collection open with x, when it is reopened with y and an orphan sweep, then ArgumentError is thrown
    Given a collection open with x
    When it is reopened with y and an orphan sweep
    Then ArgumentError is thrown

  Scenario: Given a collection open with x, when it is reopened with none, then ArgumentError is thrown
    Given a collection open with x
    When it is reopened with none
    Then ArgumentError is thrown

  Scenario: Given a collection open with no tag, when it is reopened with x, then ArgumentError is thrown
    Given a collection open with no tag
    When it is reopened with x
    Then ArgumentError is thrown

  Scenario: Given a collection open with x, when it is reopened with typeTag todo, then ArgumentError is thrown
    Given a collection open with x
    When it is reopened with typeTag todo
    Then ArgumentError is thrown

  Scenario: Given a collection open with typeTag todo, when it is reopened with writeTypeTag todo, then a collection stamping todo is returned
    Given a collection open with typeTag todo
    When it is reopened with writeTypeTag todo
    Then a collection stamping todo is returned

  Scenario: Given a collection open with writeTypeTag todo, when it is reopened with typeTag todo, then a collection stamping todo is returned
    Given a collection open with writeTypeTag todo
    When it is reopened with typeTag todo
    Then a collection stamping todo is returned

  Scenario: Given a collection open with typeTag todo, when it is reopened with no tag arguments, then the same instance is returned
    Given a collection open with typeTag todo
    When it is reopened with no tag arguments
    Then the same instance is returned

  Scenario: Given a collection open with typeTag todo, when it is reopened with writeTypeTag x, then the same instance is returned
    Given a collection open with typeTag todo
    When it is reopened with writeTypeTag x
    Then the same instance is returned

  Scenario: Given a collection open with x, when it is reopened with x, then the same instance is returned
    Given a collection open with x
    When it is reopened with x
    Then the same instance is returned

  Scenario: Given a collection open with x, when another eventSource of the namespace is opened with x, then a separate instance is returned
    Given a collection open with x
    When another eventSource of the namespace is opened with x
    Then a separate instance is returned

  Scenario: Given a collection open with x, when it is reopened with a blank or conflicting tag, then ArgumentError is thrown, not a refusal
    Given a collection open with x
    When it is reopened with a blank or conflicting tag
    Then ArgumentError is thrown, not a refusal

  Scenario: Given a collection open with x, when it is reopened in mixed case with x, then the same instance is returned
    Given a collection open with x
    When it is reopened in mixed case with x
    Then the same instance is returned

  Scenario: Given a collection open with x, when it is reopened in mixed case with y, then ArgumentError is thrown
    Given a collection open with x
    When it is reopened in mixed case with y
    Then ArgumentError is thrown

  Scenario: Given a namespace opened in mixed case, when the collection is handed out, then its namespace is lower-cased
    Given a namespace opened in mixed case
    When the collection is handed out
    Then its namespace is lower-cased

  Scenario: Given an open that failed to register its factory, when the namespace is opened again without tags, then a collection is handed out
    Given an open that failed to register its factory
    When the namespace is opened again without tags
    Then a collection is handed out

  Scenario: Given a byte collection open with writeTypeTag x, when it is reopened with none, then the same instance is returned
    Given a byte collection open with writeTypeTag x
    When it is reopened with none
    Then the same instance is returned
