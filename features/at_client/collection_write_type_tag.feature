Feature: A collection stamps new items with its writeTypeTag

  collection and subCollection take an optional writeTypeTag. When no factory
  is registered for the item's type, the item is stamped with that tag instead
  of n/a; a registered factory's tag wins. The tag is not inherited by a
  sub-collection. A blank tag, or one that differs from typeTag, is refused at
  construction.

  Races: none new; the tag is resolved synchronously at write time from
  constructor state, and no shared mutable state is added.
  Replay: none new; no wire message or nonce is added, and the tag is part of
  the existing record format.
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
  # The collection record
  #
  # AtClient.collection keeps one record per collection, the self key
  # __collection.<namespace>@<self>: owned by this atSign, shared with nobody,
  # encrypted like the items, written to the local store and synced to the
  # atServer, with no ttl. Its value is JSON: {"v": 1, "writeTypeTag": "Todo"}.
  # A reader needs v to be an integer of at least 1 and writeTypeTag to be a
  # non-blank string, and ignores every other field, so a later version can add
  # one (a JSON Schema document under "schema" is next) without breaking it.
  # A record that is not that shape, or is over 1 MiB, is refused with a
  # FormatException rather than read as no record.
  #
  # The tag an open asks for is writeTypeTag, or typeTag when writeTypeTag is
  # not given. An open that asks for no tag matches any record and adopts its
  # tag. Only an open with writeTypeTag writes the record, so an existing
  # collection with no record still opens as before, and its first open with
  # writeTypeTag claims it. Every instance this client holds for the namespace
  # follows the record. The id __collection is reserved: no item can take it,
  # and no key with it is read as an item.
  #
  # The record only counts when it is this atSign's own: a shared-in or cached
  # copy from another atSign never sets this atSign's tag. AtCollection's own
  # constructor and subCollection keep no record.
  #
  # Races: opens on one client run one at a time, so two opens asking for
  # different tags at once give one the collection and the other a mismatch.
  # Two clients of one atSign that both claim before either has synced each
  # keep their own tag until sync settles the record, and the next open of the
  # loser throws. A client that finds no record locally asks the atServer
  # before claiming, so a fresh install does not claim over a synced record.
  # Replay: a replayed record write sets the same tag again.
  # DoS: one record per collection; its value is refused over 1 MiB before it
  # is decoded.
  # Forgery and impersonation: the record is read from this atSign's own self
  # key, which only this atSign's clients can write.

  Scenario: Given no collection record and writeTypeTag Todo, when the collection is opened, then a version 1 record with tag Todo is written
    Given no collection record
    When the collection is opened with writeTypeTag Todo
    Then the record __collection.<namespace>@<self> holds {"v":1,"writeTypeTag":"Todo"}

  Scenario: Given a record with tag Todo, when the collection is opened with writeTypeTag Note, then CollectionTypeTagMismatchException is thrown
    Given a collection record with tag Todo
    When the collection is opened with writeTypeTag Note
    Then CollectionTypeTagMismatchException names Todo and Note

  Scenario: Given a record with tag Todo, when the collection is opened with writeTypeTag Todo, then it opens and no record is written
    Given a collection record with tag Todo
    When the collection is opened with writeTypeTag Todo
    Then the collection's writeTypeTag is Todo and nothing is written

  Scenario: Given a record with tag Todo, when the collection is opened with no tag, then it adopts Todo
    Given a collection record with tag Todo
    When the collection is opened with no writeTypeTag and no typeTag
    Then the collection's writeTypeTag is Todo and new items are typed Todo

  Scenario: Given a record with tag Todo, when the collection is opened with typeTag Note and no writeTypeTag, then CollectionTypeTagMismatchException is thrown
    Given a collection record with tag Todo
    When the collection is opened with fromJson and typeTag Note
    Then CollectionTypeTagMismatchException is thrown

  Scenario: Given no collection record, when the collection is opened with no writeTypeTag, then no record is written
    Given no collection record
    When the collection is opened with no writeTypeTag
    Then nothing is written and the collection's writeTypeTag is null

  Scenario: Given no collection record, when the collection is opened with typeTag Todo and no writeTypeTag, then no record is written
    Given no collection record
    When the collection is opened with fromJson and typeTag Todo and no writeTypeTag
    Then nothing is written: only writeTypeTag claims the record

  Scenario: Given an open collection, when it is opened again with a blank writeTypeTag, then ArgumentError is thrown and nothing is written
    Given the collection is open with no writeTypeTag
    When it is opened again with writeTypeTag "  "
    Then ArgumentError is thrown before the record is read, and nothing is written

  Scenario: Given no local record and a client stopped during the atServer read, when the collection is opened with Todo, then StoppedException is thrown and nothing is written
    Given no local collection record and the atServer read throws StoppedException
    When the collection is opened with writeTypeTag Todo
    Then StoppedException is thrown and nothing is written

  Scenario: Given an open collection with writeTypeTag Todo, when it is opened again with Note, then CollectionTypeTagMismatchException is thrown and the instance keeps Todo
    Given the collection is open with writeTypeTag Todo
    When it is opened again with writeTypeTag Note
    Then CollectionTypeTagMismatchException is thrown and the open instance keeps Todo

  Scenario: Given an untagged open collection with no record, when it is opened with writeTypeTag Todo, then the open instance adopts Todo
    Given the collection is open with no writeTypeTag and has no record
    When it is opened with writeTypeTag Todo
    Then the instance opened first stamps new items Todo

  Scenario: Given two opens with Todo and Note at once, when both run, then one gets the collection and the other a mismatch
    Given no collection record
    When the collection is opened with Todo and with Note concurrently
    Then exactly one open succeeds and the other throws CollectionTypeTagMismatchException

  Scenario: Given no local record and a record with Todo on the atServer, when the collection is opened with Note, then CollectionTypeTagMismatchException is thrown and nothing is written
    Given no local collection record and a record with tag Todo on the atServer
    When the collection is opened with writeTypeTag Note
    Then CollectionTypeTagMismatchException is thrown and nothing is written

  Scenario: Given no local record and an atServer that cannot be reached, when the collection is opened with Todo, then the record is claimed locally
    Given no local collection record and the atServer read fails
    When the collection is opened with writeTypeTag Todo
    Then the record is written locally with tag Todo

  Scenario: Given a version 2 record with tag Todo and a schema field, when the collection is opened with Todo, then it opens
    Given a collection record {"v":2,"writeTypeTag":"Todo","schema":{"type":"object"}}
    When the collection is opened with writeTypeTag Todo
    Then it opens with writeTypeTag Todo

  Scenario Outline: Given a malformed collection record, when the collection is opened, then FormatException is thrown
    Given a collection record <value>
    When the collection is opened with writeTypeTag Todo
    Then FormatException is thrown and nothing is written

    Examples:
      | value                              |
      | not json                           |
      | ["Todo"]                           |
      | {"writeTypeTag":"Todo"}            |
      | {"v":0,"writeTypeTag":"Todo"}      |
      | {"v":"1","writeTypeTag":"Todo"}    |
      | {"v":1}                            |
      | {"v":1,"writeTypeTag":"  "}        |
      | a value over 1 MiB                 |

  Scenario: Given the record cannot be read for another reason, when the collection is opened, then that error is thrown
    Given the local read of the record fails with an error other than not found
    When the collection is opened
    Then that error is thrown and nothing is written

  Scenario: Given a shared-in record from another atSign with tag Note, when the collection is opened with Todo, then the record is claimed as Todo
    Given only a key @self:__collection.<namespace>@<other> with tag Note
    When the collection is opened with writeTypeTag Todo
    Then the record read is this atSign's own self key and Todo is written

  Scenario: Given the reserved id __collection, when an item is drafted with it, then ArgumentError is thrown
    Given the id __collection
    When an item is drafted with it
    Then ArgumentError is thrown

  Scenario: Given a collection record in the local store, when the items are read or a data event for it arrives, then it is not an item
    Given the key __collection.<namespace>@<self> and a received copy cached:@self:__collection.<namespace>@<other>
    When the items are listed or a data event for the key arrives
    Then neither is read as an item
