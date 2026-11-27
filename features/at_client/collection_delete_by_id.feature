Feature: An own collection item can be deleted by id

  AtCollection.delete takes a CItem, so a caller has to read an item before
  it can delete it. An item whose stored value this device cannot decode has
  no CItem, yet its key still names a record its owner may remove.
  deleteById deletes that record by (id, owner) and keeps every piece of
  delete's bookkeeping: the refusal while self-owned descendants exist, the
  seen-id cache eviction, the CItemDeleted event on this collection and the
  CSubItemDeleted events on its ancestors.

  # Threats. Each answer names the scenario that holds it.
  #
  # Race: the descendant scan runs before any key is deleted, exactly as it
  #   does for delete: "deleting an own item by id keeps the delete
  #   bookkeeping".
  # Replay: a delete that is repeated finds no self key the second time, so
  #   it emits no second CItemDeleted and removes nothing else: "deleting an
  #   own item by id keeps the delete bookkeeping".
  # DoS: a record that cannot be decoded can be removed by id, so one corrupt
  #   value does not pin its id in the store forever: "deleting an own item by
  #   id keeps the delete bookkeeping".
  # Forgery: deleteById reads no item and trusts no envelope, so an
  #   undecodable value cannot choose which key is removed: "deleting an own
  #   item by id keeps the delete bookkeeping".
  # Impersonation: deleteById deletes only keys owned by this collection's own
  #   atSign, never an owner the caller names, so another atSign's copy is out
  #   of reach: "deleting an own item by id keeps the delete bookkeeping".

  Scenario: deleting an own item by id keeps the delete bookkeeping
    Given an own sub-item "c1" of "p1"
    When the sub-collection deletes "c1" by id
    Then the stored key is gone and exists("c1", @alice) is false
    And exactly one CItemDeleted names owner @alice and id "c1"
    And the parent collection receives a CSubItemDeleted naming owner @alice, id "c1" and the "p1" ancestry
