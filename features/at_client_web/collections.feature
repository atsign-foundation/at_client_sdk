Feature: Collections store, read and share items through the session

  session.collection(name, {type, eventSource, expiration}) resolves a
  collection bound to that name and type; expiration is in milliseconds. Its
  calls resolve plain JS values and reject with a {code, message} object
  carrying the collection's own code and, where known, id, owner, kind and
  failures. watch takes callbacks and returns the function that stops it.

  These scenarios describe the Dart bridge that @atsign/at_client_web wraps; the
  npm package turns {code, message} into AtError and the callbacks into async
  iterators, and specifies that in at_js.

  # Threats. Each answer names the scenario that holds it.
  #
  # Race: concurrent writes to one item in an adapter run sequentially so no
  #   write overwrites another, and closing the session stops collection calls
  #   and watches ("concurrent update, share and remove on one item run
  #   sequentially without losing writes", "collection operations and watch
  #   reject with closed after session close").
  # Replay: watch delivers events from authenticated AtCollection notifications
  #   only while open and stops on cancel or session close ("collection watch
  #   delivers events, including unknown, and unsubscribes (T6.5, T6.8)").
  # DoS: data nesting is capped at 64 levels both inbound and outbound,
  #   unreadable items never fail list/query, and non-plain objects are rejected
  #   ("collection data that is an array or too deep rejects naming data", "A
  #   list reports an item nested 100000 levels deep without overflowing the
  #   stack", "non-plain JS objects in collection arguments reject naming the
  #   parameter").
  # Forgery: item data crosses to JS as null-prototype objects and bridge reads
  #   inspect only own properties so Object.prototype pollution cannot alter
  #   arguments ("collection item data is a null-prototype object (T6.3)",
  #   "a data key named __proto__ arrives as data, not a prototype",
  #   "prototype-polluted Object.prototype fields are ignored across bridge
  #   calls").
  # Impersonation: items are addressed by validated (id, owner) with owner
  #   defaulting to the session atSign and invalid owner rejected ("collection
  #   get defaults the owner to the session and resolves null", "invalid address
  #   owner rejects with invalid_argument naming owner").

  Scenario: collection passes name, type, eventSource and expiration
    Given an open session
    When collection is called with a name and {type, eventSource, expiration}, the expiration in milliseconds
    Then the session opens the collection with all four
    And the result has create, get, list, query, update, share, remove and watch

  Scenario: collection eventSource and expiration are optional
    Given an open session
    When collection is called with a name and only a type
    Then the bridge passes no eventSource and no expiration, leaving both to the session's defaults

  Scenario: opening a notification-backed collection starts listening on notificationService
    Given an open session whose notification monitor is not yet listening
    When collection is opened with eventSource notifs or default both, and separately with data
    Then startListening is called for notifs and default both, and not for data

  Scenario: collection create maps data, id and sharedWith
    Given an open collection
    When create is called with data, an id and sharedWith
    Then the collection receives the data, the id and the sharedWith list
    And create resolves the created item as a JS object

  Scenario: collection get defaults the owner to the session and resolves null
    Given an open collection
    When get is called with an id and no owner
    Then the item is looked up under the session's atSign
    And an owner given without @ is looked up in @name form
    And an item that does not exist resolves null

  Scenario: collection list and query return {items, unreadable}
    Given a collection holding readable and unreadable items
    When list or query is called
    Then each resolves {items, unreadable}
    And query passes each {path, op, value} clause on, a missing value as null

  Scenario: collection update, share and remove map their arguments
    Given an open collection
    When update is called with an address and data, share with an address and atSigns, and remove with an address
    Then the collection receives each call's id, owner and arguments, the owner defaulting to the session's atSign
    And remove passes cascade as given, false when left out, and resolves no value

  Scenario: concurrent update, share and remove on one item run sequentially without losing writes
    Given an item in an open adapter
    When update and share (or remove) are started concurrently for that item
    Then they execute one after the other for that (id, owner)
    And the second operation sees the state written by the first without losing writes

  Scenario: collection operations and watch reject with closed after session close
    Given an open collection handle from a session
    When session.close() is called
    Then subsequent collection calls reject with closed and watch returns {code: closed}
    And any active watch is cancelled

  Scenario: collection item data is a null-prototype object (T6.3)
    Given an item whose data has keys named __proto__ and toString, a nested object and an object inside an array
    When get is called
    Then the data and each object inside it have no prototype
    And all of its keys are present

  Scenario: a data key named __proto__ arrives as data, not a prototype
    Given item data from JSON with a key named __proto__
    When create is called
    Then the collection receives __proto__ as an ordinary data key beside the others

  Scenario: a collection failure rejects with its code and fields (T6.4)
    Given a collection whose share fails with COLLECTION_PARTIAL_FAILURE
    When share is called
    Then it rejects with that code and the failure's message, id, owner, kind and failures

  Scenario: every collection code reaches JS unchanged
    Given a collection whose list fails with each of the collection kinds in turn
    When list is called
    Then each call rejects with that kind's code from js-api.md 6.1

  Scenario: collection bad arguments reject naming the parameter
    Given an open collection
    When get is called with a string for the address, create with a number for the data, query with a number for where, or share with a string for atSigns
    Then each rejects with code invalid_argument and a message naming that parameter

  @impersonation
  Scenario: invalid address owner rejects with invalid_argument naming owner
    Given an open collection
    When get, update, share or remove is called with an address whose owner is not a valid atSign
    Then each rejects with code invalid_argument naming owner without its value
    And the rejection carries code, message and the address id folded to lower case, and nothing else
    And no call reaches the collection, for that owner or for the session's own atSign

  Scenario: non-plain JS objects in collection arguments reject naming the parameter
    Given an open collection
    When create is called with Date, Uint8Array, Map or array in opts or nested data
    Then each rejects with code invalid_argument naming the parameter

  Scenario: prototype-polluted Object.prototype fields are ignored across bridge calls
    Given extra properties defined on Object.prototype
    When create, collection, notify, remove and query omit optional fields
    Then none of the polluted Object.prototype fields is read

  Scenario: collection data that is an array or too deep rejects naming data
    Given an open collection
    When create or update is called with an array as the data, or create with data nested 100 levels deep or with a cyclic object
    Then each rejects with code invalid_argument and a message naming data

  Scenario: collection item data nested deeper than 64 levels rejects with COLLECTION_ITEM_TOO_DEEP
    Given a collection whose item data nests 65 levels, and one that nests 64
    When get is called
    Then the 65-level item rejects with COLLECTION_ITEM_TOO_DEEP and the 64-level item resolves

  Scenario: tooDeep from collection item preserves id and owner
    Given an item whose data nests 65 levels deep
    When get rejects with COLLECTION_ITEM_TOO_DEEP across the bridge
    Then the rejection carries the item's id and owner

  Scenario: collection get errors carry id and owner
    Given an open adapter
    When get fails with an invalid id or unexpected error
    Then the rejection carries id and owner

  Scenario: collection list safely skips malformed unreadable keys without throwing in onError
    Given a collection listing containing an unreadable key whose key.toString() throws InvalidAtKeyException
    When list is called
    Then list completes without hanging and logs a sanitized warning

  Scenario: A list reports an item nested deeper than 64 levels as unreadable with COLLECTION_ITEM_TOO_DEEP
    Given an item another atSign shared whose data nests 65 levels
    When list is called
    Then the other items are returned and unreadable holds that item with code COLLECTION_ITEM_TOO_DEEP

  Scenario: A query reports an item nested deeper than 64 levels as unreadable with COLLECTION_ITEM_TOO_DEEP
    Given an item another atSign shared whose data nests 65 levels
    When query is called
    Then the matching items are returned and unreadable holds that item with code COLLECTION_ITEM_TOO_DEEP

  Scenario: A remove of an own item nested deeper than 64 levels resolves
    Given an item of the session's own whose data nests 65 levels
    When remove is called
    Then the item is deleted and the call resolves

  Scenario: A share of an own item nested deeper than 64 levels rejects with COLLECTION_ITEM_TOO_DEEP and writes nothing
    Given an item of the session's own whose data nests 65 levels
    When share is called
    Then the call rejects with COLLECTION_ITEM_TOO_DEEP and the item's recipients are unchanged

  Scenario: An update of an own item nested deeper than 64 levels replaces its data and resolves
    Given an item of the session's own whose data nests 65 levels
    When update is called with new data
    Then the data is replaced and the call resolves with the new data

  Scenario: A list reports an item nested 100000 levels deep without overflowing the stack
    Given an item another atSign shared whose data nests 100000 levels
    When list is called
    Then the call resolves and unreadable holds that item with code COLLECTION_ITEM_TOO_DEEP

  Scenario: collection watch delivers events, including unknown, and unsubscribes (T6.5, T6.8)
    Given a collection watch with an event and an error callback
    When an updated event, an event of an unknown type and an error arrive, and the returned function is then called
    Then both events reach the event callback and the error reaches the error callback as a {code, message} object
    And that one call cancels the collection's watch once

  Scenario: collection watch needs a function and never throws
    Given an open collection
    When watch is called with a number in place of the event callback
    Then it returns {code: invalid_argument} instead of the stop function
    And nothing is thrown

  Scenario: a collection rejection keeps code, message, id, owner, kind and failures
    Given a collection whose calls fail as a missing item, another owner's item, a failed open with a StateError and a partial write failure
    When each call rejects
    Then the missing item rejects COLLECTION_ITEM_NOT_FOUND with message 'item not found' and kind "StateError"
    And the other owner's item rejects COLLECTION_ITEM_NOT_OWNER with a message naming the id and both atSigns and no kind
    And the failed open rejects COLLECTION_FAILED with message 'operation failed' and kind "StateError"
    And the partial failure rejects COLLECTION_PARTIAL_FAILURE with kind "CollectionOpException" and one {op, recipient, kind} per failed write
    And each carries the item's id and owner where it has them

  Scenario: list and query report each unreadable record with the same code as before
    Given a listing with one record that cannot be read and one whose data nests 65 levels
    When list or query is called
    Then unreadable holds {id, owner, code} with COLLECTION_ITEM_UNREADABLE for the first and COLLECTION_ITEM_TOO_DEEP for the second

  Scenario: a repeated collection call builds a fresh adapter each time
    Given an open session
    When collection is called three times for one name, type and options, once with the name already ending in the namespace
    Then each call returns its own handle and the session keeps no adapter

  Scenario: two handles with different eventSource and expiration serialise on one namespace, id and owner
    Given two handles on one collection opened with different eventSource and expiration
    When each removes the same item, the id differing only in case
    Then the second starts after the first finishes, and an operation on another id does not wait

  Scenario: the item lock map is empty once the operations complete
    Given several operations on one item have finished
    Then the session holds no item lock

  Scenario: close clears the item lock map
    Given an operation is holding an item lock
    When the session closes
    Then the session holds no item lock
