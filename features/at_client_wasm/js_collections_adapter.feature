Feature: The JS collections adapter translates onto AtCollection

  at_client_wasm carries an unexported Dart-side adapter that the JS facade
  will call. It turns plain values (strings, numbers, maps, lists, callbacks)
  into AtCollection calls and turns results, events and failures back into
  plain values. It adds no behaviour of its own: no namespace qualification,
  no defaults, no sorting, no caching, no type filter. Items are addressed by
  id and owner. A failure rejects with a W8 code (js-api.md §6).

  Races: a write re-reads the item right before writing and writes recipient
  copies with unshareWithOthers false, so a recipient another device added
  since the last read is never removed. A share passes the union of the
  re-read recipients and the new ones to updateSharedWith. Two devices
  writing the item's data at once still end last-writer-wins, as upstream.
  Replay: none arise; the adapter issues the same AtCollection calls an app
  would and nothing it accepts is signed or checked for freshness here.
  DoS: none new; every call is one AtCollection call plus at most one
  re-read, and a watch holds one subscription that cancel releases.
  Forgery and impersonation: every item carries the owner AtCollection read
  from the key, and a write to an item owned by another atSign is refused
  before it reaches AtCollection, so a peer's id can never turn into a write
  of the caller's own item. Atsigns are normalised and validated by
  toAtsign, not by the adapter.

  Scenario: An open passes namespace, expiration, type and eventSource through unchanged
    Given a client
    When the adapter opens "todos.demo" with type "Todo", 5 hours and each eventSource
    Then AtClient.collection is called with "todos.demo", 5 hours, writeTypeTag "Todo" and the matching EventSource
    And an open with no eventSource leaves the upstream default

  Scenario: An unknown eventSource rejects with W8_INVALID_ARGUMENT
    When the adapter opens a collection with eventSource "bogus"
    Then the open rejects with W8_INVALID_ARGUMENT

  Scenario: An empty type rejects with W8_INVALID_ARGUMENT
    When the adapter opens a collection with type ""
    Then the open rejects with W8_INVALID_ARGUMENT

  Scenario: A failed open rejects with W8_FAILED naming the error kind
    Given AtClient.collection fails with a StateError
    When the adapter opens a collection
    Then the open rejects with W8_FAILED and kind "StateError"

  Scenario: A record written through the adapter carries its declared type tag on the wire
    When the adapter creates an item in a collection opened with type "Todo"
    Then the stored envelope's type is "Todo"

  Scenario: A create returns the item with id, owner, type, data and sharedWith
    When the adapter creates an item shared with "bob"
    Then the item has its id, owner "@alice", type "Todo", data and sharedWith ["@bob"]

  Scenario: A create with an existing id rejects with W8_ALREADY_EXISTS
    Given an item "i1"
    When the adapter creates another item "i1"
    Then the create rejects with W8_ALREADY_EXISTS

  Scenario: A get addresses an item by id and owner
    Given @alice and @bob each own an item "a1" that @alice can read
    When the adapter gets "a1" owned by @bob and "a1" owned by @alice
    Then each get returns that owner's item
    And a get of an id nobody owns resolves to null

  Scenario: A get of an unreadable item rejects with W8_UNREADABLE naming id and owner
    Given @bob shares "b1" with @alice and @alice cannot read it
    When the adapter gets "b1" owned by @bob
    Then the get rejects with W8_UNREADABLE, id "b1", owner "@bob" and no cause text

  Scenario: A list rejects with W8_UNREADABLE when one record is unreadable
    Given a readable item and an unreadable shared item
    When the adapter lists the collection
    Then the list rejects with W8_UNREADABLE instead of skipping the record

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

  Scenario: An update of a missing item rejects with W8_NOT_FOUND
    When the adapter updates an id that does not exist
    Then the update rejects with W8_NOT_FOUND

  Scenario: An update, share or remove of another owner's item rejects with W8_NOT_OWNER
    Given @bob shares "b1" with @alice and @alice owns no "b1"
    When @alice's adapter updates, shares or removes "b1" owned by @bob
    Then each rejects with W8_NOT_OWNER and no item "b1" owned by @alice exists

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

  Scenario: A share of a missing item rejects with W8_NOT_FOUND
    When the adapter shares an id that does not exist
    Then the share rejects with W8_NOT_FOUND

  Scenario: A share with an invalid atSign rejects with W8_INVALID_ARGUMENT
    Given an item
    When the adapter shares it with "@a@b"
    Then the share rejects with W8_INVALID_ARGUMENT and sharedWith is unchanged

  Scenario: A partial write failure rejects with W8_PARTIAL_FAILURE naming the recipient
    Given writes of @bob's recipient copy fail
    When the adapter creates an item shared with @bob
    Then the create rejects with W8_PARTIAL_FAILURE listing a put for @bob

  Scenario: A remove deletes the item and a missing item rejects with W8_NOT_FOUND
    Given an item "i1"
    When the adapter removes "i1" twice
    Then the item is gone and the second remove rejects with W8_NOT_FOUND

  Scenario: A remove of an item with sub-items rejects with W8_HAS_SUB_ITEMS unless cascade
    Given an item with a sub-item
    When the adapter removes it without cascade, then with cascade
    Then the first rejects with W8_HAS_SUB_ITEMS and the second removes both

  Scenario: Each where operator maps onto wherePath over nested and missing paths
    Given items with flat, nested, null and missing values
    When the adapter queries each operator
    Then each returns the items wherePath selects

  Scenario: Chained where clauses combine with AND
    When the adapter queries two clauses
    Then only items matching both are returned

  Scenario: An ordering where over mixed types rejects with W8_TYPE_MISMATCH
    Given items whose value at a path is a number, a string and a boolean
    When the adapter queries that path with "<"
    Then the query rejects with W8_TYPE_MISMATCH

  Scenario: An unknown or reserved operator or a bad path or value rejects with W8_INVALID_ARGUMENT
    When the adapter queries with "like", "~", "=<" with a map value, an empty path segment or a map value for "<"
    Then each rejects with W8_INVALID_ARGUMENT naming the problem

  Scenario: A query rejects with W8_UNREADABLE when one record is unreadable
    Given a readable item and an unreadable shared item
    When the adapter queries the collection
    Then the query rejects with W8_UNREADABLE

  Scenario: Each upstream event is delivered once and cancel stops delivery
    Given a watch on the collection
    When an item is updated and deleted, then the watch is cancelled and the item updated again
    Then "updated" and "deleted" arrive once each with id and owner, and nothing after cancel

  Scenario: An event for an unreadable item is delivered with its id and owner
    Given @bob shares an unreadable "b1" with @alice
    When an update of "b1" arrives
    Then an "updated" event for "b1" owned by "@bob" is delivered and onError is not called
    And a get of it rejects with W8_UNREADABLE

  Scenario: Events for other type tags and missing items are delivered
    Given an item tagged "Other"
    When it is updated, deleted on expiry, and an update for a missing id arrives
    Then all three events arrive, the delete with wasExpired true

  Scenario: Every CEvent subtype maps to its JS event and an unknown one to unknown
    Given a watch on a collection whose events are controlled by the test
    When each CEvent subtype and an unknown subtype are emitted
    Then each arrives as its JS type with its fields and the unknown one as "unknown"

  Scenario: A stream error reaches onError as a W8 error and later events still arrive
    Given a watch on a collection whose events are controlled by the test
    When the event stream emits a CItemReadException and then an event
    Then onError receives W8_UNREADABLE and the event still arrives

  Scenario: The adapter is not exported and reaches no web-only API
    Given the libraries directly under lib/
    Then none imports or exports the adapter
    And the adapter's package-local imports reach no dart:js_interop or package:web
