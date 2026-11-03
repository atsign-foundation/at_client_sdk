Feature: A collection writes a share only after its own copy

  create and update write an item's own copy first, then each recipient's
  copy. When the own copy cannot be written, no recipient's copy is
  written and no recipient the item no longer names is removed: the
  CollectionOpException names the own copy, and its results list each
  recipient's copy as OpNotAttempted. So a recipient never holds an item
  its owner's clients cannot list, update or delete.

  Races: the outcome is the same whichever of the atSign's clients takes a
  namespace's mint lock first; a write either lands its own copy and then
  its shares, or writes nothing.
  Replay and DoS: none arise; a refused own copy sends nothing further.
  Forgery and impersonation: none arise; what is written, and for whom, is
  unchanged when the own copy is written.

  Scenario: A create whose self copy fails writes no share
    Given an enrollment of @alice that holds no private for the current generation of "todos"
    When it calls create(obj: t, sharedWith: {@bob})
    Then it throws CollectionOpException naming the self copy, @bob holds no copy of the item, and no client of @alice or @bob lists it
