Feature: AtEasy, a typed-collection facade over AtClient

  AtEasy opens typed collections by name, runs create, update, share,
  remove, where, orderByPath, limit and watch over upstream AtCollection,
  and filters items by the collection's declared type tag. It is pure Dart
  with no web-only imports.

  Races: the namespace registry and query evaluation are synchronous in one
  isolate. update reads, then writes, through AtCollection exactly as a
  direct caller does. share is a read-modify-write, so two concurrent calls
  on one item can drop a recipient; the method documents it, since upstream
  has no add-only operation.
  Replay: none arises; AtEasy adds no wire messages or nonces, and events
  come from the existing collection stream.
  DoS: where and orderByPath run in memory over the AtCollection.getItems
  results and limit(n) caps the output. Each watch read is capped by
  readTimeout (30 seconds by default). The expiration and
  readTimeout must be positive. The registry grows only with the
  namespaces the app opens, never with remote input.
  Forgery and impersonation: items are read through AtCollection, whose
  signature checks are unchanged. The type tag only filters visibility and
  grants nothing. Writes go out as the client's own atSign, and an item's
  owner comes from its record key, not from its data.

  Scenario: A bare name is qualified with the app and a dotted name is used raw
    Given an AtEasy for app "demo"
    When it opens collection("todos") and collection("x.y")
    Then AtClient.collection is called for "todos.demo" and "x.y" once each

  Scenario: An empty app is refused
    Given no app suffix
    When AtEasy is constructed with app: ""
    Then it throws ArgumentError

  Scenario: An empty type is refused
    Given an AtEasy for app "demo"
    When it opens collection("todos", type: "")
    Then it throws ArgumentError

  Scenario: A zero or negative expiration is refused
    Given an AtEasy for app "demo"
    When it opens collection("todos", type: "Todo") with expiration 0 and then a negative expiration
    Then it throws ArgumentError
    And AtClient.collection is never called

  Scenario: A zero or negative readTimeout is refused
    Given a client for AtEasy with app "demo"
    When AtEasy is constructed with readTimeout 0 and then a negative readTimeout
    Then it throws ArgumentError

  Scenario: Reopening a namespace with a different type is refused
    Given "todos.demo" is open with type "Todo"
    When it opens collection("todos", type: "Other")
    Then it throws StateError

  Scenario: A failed upstream open is evicted so the next call opens again
    Given the upstream open of "todos.demo" fails
    When the app calls collection("todos") again after the failure
    Then it gets a new instance, not the failed one

  Scenario: Reopening a namespace with the same settings returns the same collection
    Given "todos.demo" is open
    When it opens collection("todos") with the same type, expiration and eventSource
    Then it gets the identical instance and upstream is opened once

  Scenario: Reopening a namespace with a different expiration or eventSource is refused
    Given "todos.demo" is open
    When it opens it with another expiration, or another eventSource
    Then it throws StateError

  Scenario: A bare name and its qualified form share one collection
    Given collection("todos") is open in app "demo"
    When it opens collection("todos.demo")
    Then it gets the identical instance and upstream is opened once

  Scenario: The qualified form of an open namespace with a different type is refused
    Given collection("todos") is open with type "Todo"
    When it opens collection("todos.demo", type: "Other")
    Then it throws StateError

  Scenario: The upstream open carries writeTypeTag and neither fromJson nor typeTag
    Given an AtEasy for app "demo"
    When it opens collection("todos", type: "Todo")
    Then AtClient.collection gets writeTypeTag "Todo", no fromJson, no typeTag, and cleanupOrphansOnCreation false

  Scenario: Expiration is passed through and eventSource maps to the upstream EventSource
    Given an AtEasy for app "demo"
    When it opens collections with eventSource data, both and notifs
    Then upstream gets the same expiration and EventSource.data, .both and .notifs

  Scenario: An unknown eventSource is refused
    Given an AtEasy for app "demo"
    When it opens a collection with eventSource "bogus"
    Then it throws ArgumentError

  Scenario: A create returns the item with its data, owner, type and no sharing
    Given an open collection of type "Todo" owned by @alice
    When it calls create({title: "a"}, id: "i1")
    Then the item has that id and data, owner @alice, type "Todo", no sharedWith and no ancestors

  Scenario: An update replaces the data and a missing id is refused
    Given item "i1" exists
    When it calls update("i1", ...) and update("nope", ...)
    Then "i1" holds the new data, and "nope" throws StateError "no item nope"

  Scenario: An update ignores an unreadable peer item that shares the id
    Given @alice owns "a1" and @bob shared an unreadable "a1" with her
    When @alice calls update("a1", ...)
    Then her own item is replaced and the peer item is ignored

  Scenario: An update keeps sharedWith
    Given @alice's item "i1" is shared with @bob
    When she calls update("i1", ...)
    Then the data changes and @bob stays in sharedWith

  Scenario: An update keeps expiresAt and leaves an available item without availableAt
    Given @alice's item "i1" has an explicit expiresAt and is available now
    When she calls update("i1", ...)
    Then expiresAt is unchanged and availableAt stays null, because upstream drops an availableAt that has passed and hides an item whose availableAt is ahead

  Scenario: An update re-stamps a legacy untagged item with the declared type
    Given @alice's item "n1" was written without a type tag, so it reads as "n/a"
    When she calls update("n1", ...) on a "Todo" collection
    Then the item now carries type "Todo"

  Scenario: An update of an id whose only item is an unreadable peer item is refused
    Given the only item with id "b1" is @bob's, shared with @alice and unreadable
    When @alice calls update("b1", ...)
    Then it throws StateError whose message starts "no item "

  Scenario: An update or remove of another owner's item names the owner
    Given @bob owns "b1" and shared it with @alice
    When @alice calls update("b1", ...) and remove("b1")
    Then both throw StateError naming @bob as the owner, and nothing is written

  Scenario: A share adds recipients, keeps existing ones and normalises names
    Given @alice's item "i1" is shared with @carol
    When she calls share("i1", ["bob"])
    Then sharedWith is {@carol, @bob}, in the result and in later reads

  Scenario: A remove deletes the item and a missing id is refused
    Given item "i1" exists
    When it calls remove("i1") twice
    Then the first deletes it and the second throws StateError "no item i1"

  Scenario: A remove of a parent with a child needs cascade
    Given item "p1" has a sub-item
    When it calls remove("p1"), then remove("p1", cascade: true)
    Then the first throws StateError, and the second deletes the parent and its child

  Scenario: Each where operator works on nested and missing paths
    Given items with flat, nested, null and missing values
    When it runs where() with ==, !=, <, <=, >, >=, isNull and isNotNull
    Then each returns exactly the matching ids, and a missing path reads as null

  Scenario: Chained where clauses combine with AND
    Given three items with different done and prio values
    When it chains two where() calls
    Then only items matching both are returned

  Scenario: A where on mixed types excludes them and rejects map values
    Given items whose prio is a number, a string, null, a bool and a map
    When it runs where("prio", "<", 5) and where("prio", "<", "m"), then where("prio", "==", {})
    Then each ordering keeps only same-type matches without throwing, and the map value throws ArgumentError

  Scenario: An unknown where operator is refused by name
    Given an open collection
    When it calls where("x", "like", "a%") or where("x", "~", 1)
    Then it throws ArgumentError naming the operator

  Scenario: An ordered query with a limit returns the first items in either direction
    Given three items with due 3, 1 and 2
    When it runs orderByPath("due").limit(2), ascending and descending
    Then it returns the two lowest, or the two highest, in order

  Scenario: A query skips an unreadable peer record
    Given @alice owns "a1" and @bob shared "b1", "b3" and an unreadable "b2" with her
    When she calls get() and runs where("due", ">=", 1).orderByPath("due", descending).limit(2)
    Then get() returns "a1", "b1" and "b3", the ordered query returns "b3" then "a1", and neither throws

  Scenario: Mixed values sort in a total order with an id tie-break
    Given items whose due is null, bool, number, string and map, with equal numbers
    When it runs orderByPath("due") twice and descending
    Then the order is null, bool, num, String, other with ids breaking ties, the same each time, and exactly reversed when descending

  Scenario: Items tagged with another type are hidden and untagged items are kept
    Given items tagged "Todo", "Other" and untagged in one namespace
    When it calls get()
    Then the "Todo" and untagged items are returned, the untagged one with type "n/a"

  Scenario: An item tagged with another type cannot be updated
    Given @alice's item "o1" is tagged "Other"
    When she calls update("o1", ...) on a "Todo" collection
    Then it throws StateError "no item o1"

  Scenario: Each upstream change is delivered once and cancel stops delivery
    Given a watch on a collection holding "t1"
    When an update and a delete of "t1" arrive, then the watch is cancelled and another update arrives
    Then onEvent gets "updated" with the item and "deleted" without it, and nothing after cancel

  Scenario: An unreadable peer record is delivered with a null item and no error
    Given a watch with an onError, and @bob's shared record "b1" is unreadable
    When an update event for "b1" arrives
    Then onEvent gets "updated" for owner @bob with item null and onError is not called

  Scenario: An error while handling an event goes to onError and later events still arrive
    Given a watch with an onError
    When handling one event fails in the keystore, then a second event arrives
    Then onError gets the error once and the second event is delivered

  Scenario: A watch read that never completes is delivered with a null item after the read timeout
    Given an AtEasy with a 50 ms readTimeout and an item read that never completes
    When an update event for the item arrives
    Then after the timeout onEvent gets "updated" with item null and onError is not called

  Scenario: A watch error with no onError reaches the zone and later events still arrive
    Given a watch with no onError, inside a guarded zone
    When handling one event fails, then a second event arrives
    Then the zone's error handler gets the error and the second event is delivered

  Scenario: Id-only events pass the type filter and a foreign-tag update is dropped
    Given @alice's item "o1" is tagged "Other"
    When an update of "o1", a delete of "o1" and an update of a missing "gone" arrive
    Then the delete and the missing-item update are delivered with item null, and the "Other" update is dropped

  Scenario: The facade and its package-local imports reach no web-only API
    Given the source of at_easy.dart and the package files it imports
    When the test scans them
    Then none uses dart:js_interop or package:web
