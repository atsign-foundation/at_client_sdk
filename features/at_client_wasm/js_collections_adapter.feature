Feature: The JS collections adapter translates onto AtCollection

  at_client_wasm carries an unexported Dart-side adapter that the JS facade
  will call. It turns plain values (strings, numbers, maps, lists, callbacks)
  into AtCollection calls and turns results, events and failures back into
  plain values. It adds no behaviour of its own: no namespace qualification,
  no defaults, no sorting, no caching, no type filter. Items are addressed by
  id and owner. A failure rejects with a collection error code (js-api.md §6).

  # Threats. Each answer names the scenario that holds it.
  #
  # Race: another device may write a recipient copy while this adapter updates
  #   or shares an item. Each write re-reads the item right before writing and
  #   never removes a recipient it did not read: "An update keeps a recipient
  #   copy another device writes during the update" and "A share keeps a
  #   recipient copy another device writes during the share". Two creates with
  #   one id at the same moment are not serialised by the adapter; that check
  #   belongs to AtCollection.create.
  # Replay: a replayed notification only makes the collection re-read the stored,
  #   signed record. It creates no item and changes no item's type or owner:
  #   "Each upstream event is delivered once and cancel stops delivery".
  # DoS: AtCollection refuses a new item id longer than 64 characters ("A
  #   create with an id of 65 characters rejects with
  #   COLLECTION_INVALID_ARGUMENT"), and an unreadable record is reported
  #   beside the readable items instead of failing the listing ("A list
  #   returns readable items and reports unreadable ones").
  # Forgery: an item's owner is the sharedBy of its key and never a field of its
  #   data or envelope: "An item's owner comes from the key's sharedBy, never from its data".
  # Impersonation: a write to an item another atSign owns is refused before any
  #   key is written: "An update, share or remove of another owner's item rejects
  #   with COLLECTION_ITEM_NOT_OWNER".

  Scenario: An open passes namespace, expiration, type and eventSource through unchanged
    Given a client
    When the adapter opens "todos.demo" with type "Todo", 5 hours and each eventSource
    Then AtClient.collection is called with "todos.demo", 5 hours, writeTypeTag "Todo" and the matching EventSource
    And an open with no eventSource leaves the upstream default

  Scenario: An unknown eventSource rejects with COLLECTION_INVALID_ARGUMENT
    When the adapter opens a collection with eventSource "bogus"
    Then the open rejects with COLLECTION_INVALID_ARGUMENT

  Scenario: An empty type rejects with COLLECTION_INVALID_ARGUMENT
    When the adapter opens a collection with type ""
    Then the open rejects with COLLECTION_INVALID_ARGUMENT

  Scenario: A non-positive expirationMs rejects with COLLECTION_INVALID_ARGUMENT
    When the adapter opens a collection with expirationMs 0 or -1
    Then the open rejects with COLLECTION_INVALID_ARGUMENT
    And AtClient.collection is never called

  Scenario: A failed open rejects with COLLECTION_FAILED naming the error kind
    Given AtClient.collection fails with a StateError
    When the adapter opens a collection
    Then the open rejects with COLLECTION_FAILED and kind "StateError"

  Scenario: JsCollectionsError is an AtException and keeps its fields
    Given an adapter error built with a code, message, id, owner, kind and failures
    When a Dart caller catches AtException
    Then the adapter error is caught
    And its code, message, id, owner, kind and failures are kept

  Scenario: The error codes are the COLLECTION_ and COLLECTION_ITEM_ names
    Given the adapter's error codes
    Then item-level codes start with COLLECTION_ITEM_ and the rest with COLLECTION_

  Scenario: A record written through the adapter carries its declared type tag on the wire
    When the adapter creates an item in a collection opened with type "Todo"
    Then the stored envelope's type is "Todo"

  Scenario: A create returns the item with id, owner, type, data and sharedWith
    When the adapter creates an item shared with "bob"
    Then the item has its id, owner "@alice", type "Todo", data and sharedWith ["@bob"]

  Scenario: A create with an existing id rejects with COLLECTION_ITEM_ALREADY_EXISTS
    Given an item "i1"
    When the adapter creates another item "i1"
    Then the create rejects with COLLECTION_ITEM_ALREADY_EXISTS

  Scenario: A get addresses an item by id and owner
    Given @alice and @bob each own an item "a1" that @alice can read
    When the adapter gets "a1" owned by @bob and "a1" owned by @alice
    Then each get returns that owner's item
    And a get of an id nobody owns resolves to null

  Scenario: A get of an unreadable item rejects with COLLECTION_ITEM_UNREADABLE naming id and owner
    Given @bob shares "b1" with @alice and @alice cannot read it
    When the adapter gets "b1" owned by @bob
    Then the get rejects with COLLECTION_ITEM_UNREADABLE, id "b1", owner "@bob" and no cause text

  Scenario: An item's owner comes from the key's sharedBy, never from its data
    Given @bob shares "f1" with @alice and its stored envelope and data name @carol as owner
    When the adapter gets and lists "f1"
    Then the owner is "@bob" in both
    And a get of "f1" owned by @alice is null and an update of "f1" owned by @carol rejects with COLLECTION_ITEM_NOT_OWNER

  Scenario: A list returns readable items and reports unreadable ones
    Given a readable item and an unreadable shared item "b1" owned by @bob
    When the adapter lists the collection
    Then the list resolves with the readable item in items
    And unreadable holds one entry with id "b1", owner "@bob" and code COLLECTION_ITEM_UNREADABLE

  Scenario: A list keeps the upstream order of items and recipients
    Given items created in an unsorted order with recipients in an unsorted order
    When the adapter lists the collection
    Then items and recipients come back in the order AtCollection returns them

  Scenario: Items of every type tag are listed with their type
    Given items tagged "Todo", "Other" and untagged
    When the adapter lists the collection
    Then all three are returned, each with its own type

  Scenario: An update replaces the data and keeps sharedWith, expiresAt and availableAt
    Given an item shared with @bob with an expiresAt and availableAt in the past
    When the adapter updates its data
    Then the stored item has the new data and the same sharedWith, expiresAt and availableAt

  Scenario: An update of another type's item rejects with COLLECTION_ITEM_WRONG_TYPE
    Given an item whose type tag is "Other"
    When a "Todo" adapter updates it
    Then the update rejects with COLLECTION_ITEM_WRONG_TYPE and the stored item is unchanged
    And share and remove of an item of any type are still allowed

  Scenario: An update adopts an untagged item and returns its stored createdAt
    Given an item with no type tag
    When the adapter updates its data
    Then the item's type is "Todo" and the returned createdAt is the stored one

  Scenario: An update of a missing item rejects with COLLECTION_ITEM_NOT_FOUND
    When the adapter updates an id that does not exist
    Then the update rejects with COLLECTION_ITEM_NOT_FOUND

  Scenario: An update, share or remove of another owner's item rejects with COLLECTION_ITEM_NOT_OWNER
    Given @bob shares "b1" with @alice and @alice owns no "b1"
    When @alice's adapter updates, shares or removes "b1" owned by @bob
    Then each rejects with COLLECTION_ITEM_NOT_OWNER and no item "b1" owned by @alice exists

  Scenario: An update addresses the owner's own item when an unreadable peer item shares the id
    Given @bob shares an unreadable "a1" with @alice and @alice owns "a1"
    When the adapter updates "a1" owned by @alice
    Then @alice's "a1" has the new data

  Scenario: An update keeps a recipient copy another device writes during the update
    Given an item shared with @bob
    And another device writes a recipient copy for @carol while the update is writing
    When the adapter updates the item's data
    Then @carol's recipient copy still exists

  Scenario: A share adds recipients and keeps existing ones
    Given an item shared with @carol
    When the adapter shares it with "bob"
    Then sharedWith is @carol and @bob, and both recipient copies exist

  Scenario: A share keeps a recipient copy another device writes during the share
    Given an item shared with @bob
    And another device writes a recipient copy for @carol while the share is writing
    When the adapter shares the item with @dave
    Then @carol's recipient copy still exists

  Scenario: A share of a missing item rejects with COLLECTION_ITEM_NOT_FOUND
    When the adapter shares an id that does not exist
    Then the share rejects with COLLECTION_ITEM_NOT_FOUND

  Scenario: A share with an invalid atSign rejects with COLLECTION_INVALID_ARGUMENT
    Given an item
    When the adapter shares it with "@a@b"
    Then the share rejects with COLLECTION_INVALID_ARGUMENT and sharedWith is unchanged

  Scenario: A partial write failure rejects with COLLECTION_PARTIAL_FAILURE naming the recipient
    Given writes of @bob's recipient copy fail
    When the adapter creates an item shared with @bob
    Then the create rejects with COLLECTION_PARTIAL_FAILURE listing a put for @bob

  Scenario: A partial failure on a create without an id rejects with the written id and owner
    Given writes of @bob's recipient copy fail
    When the adapter creates an item shared with @bob and no id
    Then the create rejects with COLLECTION_PARTIAL_FAILURE carrying the id and owner of the item that was written
    And a get of that id returns the item

  Scenario: An error kind is a name the adapter knows or "Unknown"
    Given an error of a type the adapter does not name, for an open and for a key-level write
    When the adapter rejects
    Then kind and each failure's kind are "Unknown"
    And the adapter source never reads a runtime type name

  Scenario: A remove deletes the item and a missing item rejects with COLLECTION_ITEM_NOT_FOUND
    Given an item "i1"
    When the adapter removes "i1" twice
    Then the item is gone and the second remove rejects with COLLECTION_ITEM_NOT_FOUND

  Scenario: A remove of an item with sub-items rejects with COLLECTION_ITEM_HAS_SUB_ITEMS unless cascade
    Given an item with a sub-item
    When the adapter removes it without cascade, then with cascade
    Then the first rejects with COLLECTION_ITEM_HAS_SUB_ITEMS and the second removes both

  Scenario: Each where operator maps onto wherePath over nested and missing paths
    Given items with flat, nested, null and missing values
    When the adapter queries each operator
    Then each returns the items wherePath selects

  Scenario: Chained where clauses combine with AND
    When the adapter queries two clauses
    Then only items matching both are returned

  Scenario: An ordering where over mixed types rejects with COLLECTION_TYPE_MISMATCH
    Given items whose value at a path is a number, a string and a boolean
    When the adapter queries that path with "<"
    Then the query rejects with COLLECTION_TYPE_MISMATCH

  Scenario: An unknown or reserved operator or a bad path or value rejects with COLLECTION_INVALID_ARGUMENT
    When the adapter queries with "like", "~", "=<" with a map value, an empty path segment or a map value for "<"
    Then each rejects with COLLECTION_INVALID_ARGUMENT naming the problem

  Scenario: A query returns matching readable items and reports unreadable ones
    Given a readable item and an unreadable shared item "b1" owned by @bob
    When the adapter queries the collection
    Then the query resolves with the matching readable item in items
    And unreadable holds one entry with id "b1", owner "@bob" and code COLLECTION_ITEM_UNREADABLE

  Scenario: A query with where clauses over a set with an unreadable record keeps upstream order
    Given items matching and not matching a where clause and an unreadable shared item
    When the adapter queries with the where clause
    Then items holds the matching readable items in the order AtCollection returns them
    And unreadable holds the unreadable record

  Scenario: An item id AtCollection refuses rejects with COLLECTION_INVALID_ARGUMENT
    When the adapter creates, gets, updates, shares or removes with the id "a:b", "a@b", "", "a.b" or "a b"
    Then each rejects with COLLECTION_INVALID_ARGUMENT
    And nothing is written

  Scenario: A create with an id starting with "_" rejects with COLLECTION_INVALID_ARGUMENT
    When the adapter creates an item with the id "_a"
    Then it rejects with COLLECTION_INVALID_ARGUMENT
    And nothing is written

  Scenario: A create with an id of 65 characters rejects with COLLECTION_INVALID_ARGUMENT
    When the adapter creates an item with an id of 65 "a" characters
    Then it rejects with COLLECTION_INVALID_ARGUMENT
    And nothing is written

  Scenario: A create with the id "A1" returns the item with the id "a1"
    When the adapter creates an item with the id "A1"
    Then the returned item's id is "a1"

  Scenario: A create with the id "A1" when "a1" exists rejects with COLLECTION_ITEM_ALREADY_EXISTS and the id "a1"
    Given an item created through the adapter with the id "a1"
    When the adapter creates an item with the id "A1"
    Then it rejects with COLLECTION_ITEM_ALREADY_EXISTS and the id "a1"

  Scenario: An update, share or remove of the missing id "B1" rejects with COLLECTION_ITEM_NOT_FOUND and the id "b1"
    Given no item with the id "b1"
    When the adapter updates, shares or removes the id "B1" owned by @alice
    Then it rejects with COLLECTION_ITEM_NOT_FOUND and the id "b1"

  Scenario: An update of the id "B1" owned by @bob rejects with COLLECTION_ITEM_NOT_OWNER and the id "b1"
    When the adapter updates the id "B1" owned by @bob
    Then it rejects with COLLECTION_ITEM_NOT_OWNER and the id "b1"

  Scenario: A get with the id "A1" returns the item created as "a1"
    Given an item created through the adapter with the id "a1"
    When the adapter gets the id "A1" owned by @alice
    Then it returns the item whose id is "a1"

  Scenario: A get addresses an item already stored under a 65-character id
    Given an item of @alice stored under an id of 65 "a" characters
    When the adapter gets that id owned by @alice
    Then it returns the item

  Scenario: An item id of 64 allowed characters round-trips
    When the adapter creates an item with a 64-character id of lowercase letters, digits, "_" and "-"
    Then a get of that id returns the item

  Scenario: Each upstream event is delivered once and cancel stops delivery
    Given a watch on the collection
    When an item is updated and deleted, then the watch is cancelled and the item updated again
    Then "updated" and "deleted" arrive once each with id and owner, and nothing after cancel

  Scenario: An event for an unreadable item is delivered with its id and owner
    Given @bob shares an unreadable "b1" with @alice
    When an update of "b1" arrives
    Then an "updated" event for "b1" owned by "@bob" is delivered and onError is not called
    And a get of it rejects with COLLECTION_ITEM_UNREADABLE

  Scenario: Events for other type tags and missing items are delivered
    Given an item tagged "Other"
    When it is updated, deleted on expiry, and an update for a missing id arrives
    Then all three events arrive, the delete with wasExpired true

  Scenario: Every CEvent subtype maps to its JS event and an unknown one to unknown
    Given a watch on a collection whose events are controlled by the test
    When each CEvent subtype and an unknown subtype are emitted
    Then each arrives as its JS type with its fields and the unknown one as "unknown"

  Scenario: A stream error reaches onError as a collection error and later events still arrive
    Given a watch on a collection whose events are controlled by the test
    When the event stream emits a CItemReadException and then an event
    Then onError receives COLLECTION_ITEM_UNREADABLE and the event still arrives

  Scenario: The adapter is not exported and reaches no web-only API
    Given the libraries directly under lib/
    Then none reaches the adapter through exports or parts, directly or through lib/src
    And the adapter's package-local imports reach no dart:js_interop or package:web
