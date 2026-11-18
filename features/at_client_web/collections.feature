Feature: Collections store, read and share items through the session

  session.collection(options) returns a collection bound to a name and type.
  Its calls resolve plain JS values and reject with an AtError that carries the
  collection's own code and fields.

  Scenario: collection passes name, type, eventSource and expiration
    Given an open session
    When collection is called with a name, a type, an eventSource and an expiration
    Then the collection is opened with all four

  Scenario: collection eventSource and expiration are optional
    Given an open session
    When collection is called with only a name and a type
    Then the collection opens with no eventSource and no expiration

  Scenario: collection create maps data, id and sharedWith
    Given an open collection
    When create is called with data, an id and sharedWith
    Then the adapter receives them and the item comes back as a plain JS object

  Scenario: collection get defaults the owner to the session and resolves null
    Given an open collection
    When get is called with an id and no owner
    Then the owner is the session's atSign
    And an item that does not exist resolves null

  Scenario: collection list and query return {items, unreadable}
    Given a collection holding readable and unreadable items
    When list or query is called
    Then each resolves {items, unreadable}

  Scenario: collection update, share and remove map their arguments
    Given an open collection
    When update, share and remove are called
    Then the adapter receives each call's arguments

  Scenario: collection item data is a null-prototype object
    Given an item whose data has keys named __proto__ and toString
    When get is called
    Then the data and every object nested in it has no prototype
    And all of its keys are present

  Scenario: a data key named __proto__ arrives as data, not a prototype
    Given item data from JSON with a key named __proto__
    When create is called
    Then the key reaches the adapter as an ordinary data key

  Scenario: a collection failure rejects with its code and fields
    Given a failure in the collection adapter
    When a collection call is made
    Then it rejects with the failure's code and its fields

  Scenario: collection bad arguments reject naming the parameter
    Given an open collection
    When a call is made with a malformed argument
    Then it rejects with code internal and a message naming the parameter

  Scenario: collection watch delivers events, including unknown, and unsubscribes
    Given a collection watch with an event and an error callback
    When events of every type and an error arrive and the returned function is called
    Then each event and the error reach their callbacks
    And the adapter's subscription is cancelled once

  Scenario: collection watch needs a function and never throws
    Given an open collection
    When watch is called with a value that is not a function
    Then it answers a rejection object with code internal
