Feature: Collections store, read and share items through the session

  session.collection(name, {type, eventSource, expiration}) resolves a
  collection bound to that name and type; expiration is in milliseconds. Its
  calls resolve plain JS values and reject with a {code, message} object
  carrying the collection's own code and, where known, id, owner, kind and
  failures. watch takes callbacks and returns the function that stops it.

  These scenarios describe the Dart bridge that @atsign/at_client_web wraps; the
  npm package turns {code, message} into AtError and the callbacks into async
  iterators, and specifies that in at_js.

  Scenario: collection passes name, type, eventSource and expiration
    Given an open session
    When collection is called with a name and {type, eventSource, expiration}, the expiration in milliseconds
    Then the session opens the collection with all four
    And the result has create, get, list, query, update, share, remove and watch

  Scenario: collection eventSource and expiration are optional
    Given an open session
    When collection is called with a name and only a type
    Then the bridge passes no eventSource and no expiration, leaving both to the session's defaults

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
    Given a collection whose list fails with each of the collection codes in turn
    When list is called
    Then each call rejects with that code, unchanged

  Scenario: collection bad arguments reject naming the parameter
    Given an open collection
    When get is called with a string for the address, create with a number for the data, query with a number for where, or share with a string for atSigns
    Then each rejects with code internal and a message naming that parameter

  Scenario: collection watch delivers events, including unknown, and unsubscribes (T6.5, T6.8)
    Given a collection watch with an event and an error callback
    When an updated event, an event of an unknown type and an error arrive, and the returned function is then called
    Then both events reach the event callback and the error reaches the error callback as a {code, message} object
    And that one call cancels the collection's watch once

  Scenario: collection watch needs a function and never throws
    Given an open collection
    When watch is called with a number in place of the event callback
    Then it returns {code: internal} instead of the stop function
    And nothing is thrown
