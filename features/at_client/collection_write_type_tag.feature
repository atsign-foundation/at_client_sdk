Feature: A collection stamps new items with its writeTypeTag

  collection and subCollection take an optional writeTypeTag. When no factory
  is registered for the item's type, the item is stamped with that tag instead
  of n/a; a registered factory's tag wins. The tag is not inherited by a
  sub-collection. A blank tag, or one that differs from typeTag, is refused at
  construction.

  An AtClient remembers the tag each namespace was first opened with, by
  collection or by subCollection, and refuses another one with
  CollectionTypeTagMismatchException. This holds on that client only; another
  client, session or device of the atSign does not see it.

  Races: the tag is resolved synchronously at write time. The reopen check
  reads and updates the client's tag map with no await in between, so two
  opens on one client cannot interleave.
  Replay: none new; no wire message or nonce is added, and the tag is part of
  the existing item format.
  DoS: one optional string per collection, validated non-blank at
  construction.
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

  # ---------------------------------------------------------------------------
  # Reopening a collection
  #
  # The tag an open asks for is writeTypeTag, or typeTag when writeTypeTag is
  # not given. AtClient.collection remembers the first tag asked for each
  # namespace, for every event source. An open asking another tag throws; an
  # open asking none adopts it. A first writeTypeTag is also stamped by the
  # untagged instances already handed out for the namespace.

  Scenario: Given a collection opened with writeTypeTag Todo, when the same client opens it again with writeTypeTag Note, then CollectionTypeTagMismatchException is thrown and the first keeps Todo
    Given AtClient.collection opened the namespace with writeTypeTag Todo
    When the same client opens it again with writeTypeTag Note
    Then CollectionTypeTagMismatchException is thrown naming Todo and Note, and the first instance still stamps Todo

  Scenario: Given a collection opened with factory typeTag Todo, when the same client opens it again with typeTag Note, then CollectionTypeTagMismatchException is thrown
    Given the namespace was opened with fromJson and typeTag Todo
    When it is opened again with fromJson and typeTag Note
    Then CollectionTypeTagMismatchException is thrown

  Scenario: Given a collection opened with factory typeTag Todo, when the same client opens it again with writeTypeTag Note, then CollectionTypeTagMismatchException is thrown
    Given the namespace was opened with fromJson and typeTag Todo
    When it is opened again with writeTypeTag Note
    Then CollectionTypeTagMismatchException is thrown

  Scenario: Given a collection opened with writeTypeTag Todo, when it is opened from another event source with writeTypeTag Note, then CollectionTypeTagMismatchException is thrown
    Given the namespace was opened for data events with writeTypeTag Todo
    When it is opened for notifications with writeTypeTag Note
    Then CollectionTypeTagMismatchException is thrown

  Scenario: Given a collection opened with writeTypeTag Todo, when it is opened again with Todo, then it gets the open collection
    Given the namespace was opened with writeTypeTag Todo
    When it is opened again with writeTypeTag Todo
    Then the same instance is handed out

  Scenario: Given a collection opened with factory typeTag Todo, when it is opened again with typeTag Todo, then it gets the open collection
    Given the namespace was opened with fromJson and typeTag Todo
    When it is opened again with fromJson and typeTag Todo
    Then the same instance is handed out

  Scenario: Given a collection opened with writeTypeTag Todo, when it is opened again with no tag, then it gets the open collection
    Given the namespace was opened with writeTypeTag Todo
    When it is opened again with no tag
    Then the same instance is handed out, stamping Todo

  Scenario: Given a collection opened with factory typeTag Todo, when it is opened from another event source with no tag, then the new instance stamps Todo
    Given the namespace was opened for data events with fromJson and typeTag Todo
    When it is opened for notifications with no tag
    Then the new instance stamps new items Todo

  Scenario: Given an untagged open collection, when it is opened with writeTypeTag Todo, then the open instance adopts Todo
    Given the namespace was opened for data events with no tag
    When it is opened for notifications with writeTypeTag Todo
    Then the instance opened first stamps new items Todo

  Scenario: Given a collection opened with writeTypeTag Todo, when it is opened again with a blank writeTypeTag, then ArgumentError is thrown
    Given the namespace was opened with writeTypeTag Todo
    When it is opened again with writeTypeTag " "
    Then ArgumentError is thrown, not CollectionTypeTagMismatchException

  Scenario: Given a collection opened with writeTypeTag Todo, when another namespace is opened with Note, then it opens with Note
    Given the namespace things.wavi was opened with writeTypeTag Todo
    When others.wavi is opened with writeTypeTag Note
    Then it opens and stamps new items Note

  # ---------------------------------------------------------------------------
  # Reopening a sub-collection
  #
  # An AtClient remembers the tag each sub-collection's
  # composed namespace (<subName>.<parent.id>.<namespace>) was first opened
  # with, across every instance of the parent collection, so a reopen on that
  # client asking another tag throws, and a reopen asking none adopts it. It
  # remembers 4096 namespaces and forgets the one tagged longest ago: a parent
  # id can come from another atSign, so the map is bounded. Another client,
  # session or device of the atSign does not see it.

  Scenario: Given a sub-collection opened with writeTypeTag Comment, when it is opened again with writeTypeTag Note, then CollectionTypeTagMismatchException is thrown
    Given the sub-collection comments of post p1 is open with writeTypeTag Comment
    When it is opened again with writeTypeTag Note
    Then CollectionTypeTagMismatchException is thrown naming comments.p1.<namespace>, Comment and Note

  Scenario: Given a sub-collection opened with writeTypeTag Comment, when it is opened again with factory typeTag Note, then CollectionTypeTagMismatchException is thrown
    Given the sub-collection is open with writeTypeTag Comment
    When it is opened again with fromJson and typeTag Note
    Then CollectionTypeTagMismatchException is thrown

  Scenario: Given a sub-collection opened with factory typeTag Comment, when it is opened again with writeTypeTag Note, then CollectionTypeTagMismatchException is thrown
    Given the sub-collection is open with fromJson and typeTag Comment
    When it is opened again with writeTypeTag Note
    Then CollectionTypeTagMismatchException is thrown

  Scenario: Given a sub-collection opened with writeTypeTag Comment, when it is opened again from another instance of the parent collection with Note, then CollectionTypeTagMismatchException is thrown
    Given the sub-collection is open with writeTypeTag Comment
    When another instance of the parent collection on the same client opens it with Note
    Then CollectionTypeTagMismatchException is thrown

  Scenario: Given a sub-collection opened with writeTypeTag Comment, when it is opened again with a blank writeTypeTag, then ArgumentError is thrown
    Given the sub-collection is open with writeTypeTag Comment
    When it is opened again with writeTypeTag "  "
    Then ArgumentError is thrown, not CollectionTypeTagMismatchException

  Scenario: Given a sub-collection opened with writeTypeTag Comment, when it is opened again with no tag, then the new instance stamps Comment
    Given the sub-collection is open with writeTypeTag Comment
    When it is opened again with no tag
    Then the new instance stamps new items Comment

  Scenario: Given a sub-collection opened with writeTypeTag Comment, when it is opened again with Comment, then it opens
    Given the sub-collection is open with writeTypeTag Comment
    When it is opened again with writeTypeTag Comment
    Then it opens and stamps new items Comment

  Scenario: Given a sub-collection opened with writeTypeTag Comment, when the same subName is opened under another parent item with Note, then it opens with Note
    Given the sub-collection comments of post p1 is open with writeTypeTag Comment
    When the sub-collection comments of post p2 is opened with writeTypeTag Note
    Then it opens and stamps new items Note

  Scenario: Given 4097 tagged sub-collections on one client, when the first and the last are opened again with another tag, then the first opens and the last throws
    Given 4097 sub-collections opened with writeTypeTag Comment, one after another
    When the first and the last are opened again with writeTypeTag Note
    Then the first opens with Note and the last throws CollectionTypeTagMismatchException

  Scenario: Given a sub-collection opened with writeTypeTag Comment on one client, when another client opens it with Note, then it opens with Note
    Given the sub-collection is open with writeTypeTag Comment on one AtClient
    When another AtClient opens it with writeTypeTag Note
    Then it opens and stamps new items Note
