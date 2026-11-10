Feature: A collection lists only its own items and the shares addressed to it

  A collection's items are the records its atSign writes in its namespace and
  the shares other atSigns address to it there. A public record in the
  namespace, its own or one its atServer cached from another atSign, is never
  an item: every item scan and both event sources leave out a key that is
  public, cached or not.

  Races: none arise; the rule is on a key's shape, whenever it arrives.
  Replay: none arises; nothing sent or accepted changes.
  DoS: the listing no longer depends on records another atSign publishes.
  Forgery and impersonation: an item reaches a collection only as a record
  its atSign wrote or a share addressed to it.

  Scenario: A peer's public record never becomes an item of a collection that shares with it
    Given @alice's collection "list.todos" and @bob, a recipient of one of its items
    And @bob publishes public:__nskey.list.todos@bob, holding any value, an item envelope included
    When @alice shares another item with @bob and any client of @alice lists the collection
    Then getItems() lists only items @alice wrote or that were shared with @alice, and never @bob's public record
    And the collection's updates and deletes streams emit nothing for that record
