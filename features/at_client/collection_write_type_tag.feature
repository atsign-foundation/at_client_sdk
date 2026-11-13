Feature: A collection stamps new items with its writeTypeTag

  collection and subCollection take an optional writeTypeTag. When no factory
  is registered for the item's type, the item is stamped with that tag instead
  of n/a; a registered factory's tag wins. The tag is not inherited by a
  sub-collection. A blank tag, or one that differs from typeTag, is refused at
  construction. A client remembers the first effective tag (writeTypeTag, else
  typeTag) of each namespace, whatever the eventSource; reopening it with a
  different effective tag, including none versus a tag, is refused with
  CollectionTypeTagMismatchException, on that client only. subCollection checks
  the same way, remembering the last 4096 sub-collection namespaces per client
  (their names embed parent item ids that other atSigns control), so a
  mismatched reopen of a forgotten one is not caught. Equal tags pass; the same
  namespace and eventSource returns the cached instance.

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

  Scenario: Given a collection open with x, when it is reopened with y, then CollectionTypeTagMismatchException names the namespace and both tags
    Given a collection open with x
    When it is reopened with y
    Then CollectionTypeTagMismatchException names the namespace and both tags

  Scenario: Given a collection open with x, when another eventSource of the namespace is opened with y, then CollectionTypeTagMismatchException is thrown
    Given a collection open with x
    When another eventSource of the namespace is opened with y
    Then CollectionTypeTagMismatchException is thrown

  Scenario: Given a collection open with x, when it is reopened with none, then CollectionTypeTagMismatchException is thrown
    Given a collection open with x
    When it is reopened with none
    Then CollectionTypeTagMismatchException is thrown

  Scenario: Given a collection open with no tag, when it is reopened with x, then CollectionTypeTagMismatchException is thrown
    Given a collection open with no tag
    When it is reopened with x
    Then CollectionTypeTagMismatchException is thrown

  Scenario: Given a collection open with typeTag x, when it is reopened with writeTypeTag x, then a usable collection is returned
    Given a collection open with typeTag x
    When it is reopened with writeTypeTag x
    Then a usable collection is returned

  Scenario: Given a collection open with x, when it is reopened with x, then the same instance is returned
    Given a collection open with x
    When it is reopened with x
    Then the same instance is returned

  Scenario: Given a collection open with x, when it is reopened with a blank or conflicting tag, then ArgumentError is thrown, not a mismatch
    Given a collection open with x
    When it is reopened with a blank or conflicting tag
    Then ArgumentError is thrown, not a mismatch

  Scenario: Given a sub-collection open with x, when its namespace is reopened with y, then CollectionTypeTagMismatchException is thrown
    Given a sub-collection open with x
    When its namespace is reopened with y
    Then CollectionTypeTagMismatchException is thrown

  Scenario: Given a sub-collection open with x, when its namespace is reopened with none, or one open with none with x, then CollectionTypeTagMismatchException is thrown
    Given a sub-collection open with x
    When its namespace is reopened with none, or one open with none with x
    Then CollectionTypeTagMismatchException is thrown

  Scenario: Given a sub-collection open with typeTag x, when its namespace is reopened with writeTypeTag x, then a usable collection is returned
    Given a sub-collection open with typeTag x
    When its namespace is reopened with writeTypeTag x
    Then a usable collection is returned

  Scenario: Given a sub-collection namespace evicted past the cap, when it is reopened with another tag, then no exception is thrown
    Given a sub-collection namespace evicted past the cap
    When it is reopened with another tag
    Then no exception is thrown
