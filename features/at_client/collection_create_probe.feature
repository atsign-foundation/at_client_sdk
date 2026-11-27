Feature: A collection create with an id checks the store before writing

  AtCollection.create with an explicit id asks the store whether that id is
  held, so a create never overwrites an item another writer owns. The check
  is a metadata lookup: when it fails, the create fails too, with the
  lookup's own cause, rather than guessing that the id is free. An item
  deleted or expired elsewhere is created again, because the check reads the
  store and not this process's seen-id cache.

  # Threats. Each answer names the scenario that holds it.
  #
  # Race: a check that fails is not treated as "absent", so a create whose
  #   existence check failed writes nothing and cannot overwrite a concurrent
  #   writer: "create with an id does not overwrite when the existence check
  #   fails".
  # Replay: create reads the store each time instead of the seen-id cache, so
  #   an id left in the cache by an earlier create does not replay an
  #   already-exists refusal after the item was deleted elsewhere: "create
  #   with an id succeeds after the item was deleted elsewhere".
  # DoS: one create with an id makes one metadata probe, local then atServer
  #   at most, and a failed probe stops before any write, so a failing lookup
  #   cannot be retried in a write loop: "create with an id does not
  #   overwrite when the existence check fails".
  # Forgery: the probe reads metadata only and never a value, so a forged or
  #   undecodable record cannot choose whether an id is free: "create with an
  #   id does not overwrite when the existence check fails".
  # Impersonation: the probe asks only for this collection's own key,
  #   `<id>.<namespace>@<self>`, so another atSign's item cannot make a
  #   create succeed or fail on its behalf: "an upsert whose existence check
  #   fails behaves as before".

  Scenario: create with an id does not overwrite when the existence check fails
    Given an item "i1" held only on the atServer
    And a metadata lookup of "i1" sent to the atServer fails with a timeout
    When create is called with the id "i1"
    Then the create rejects with that timeout, not a StateError
    And no put is made and the atServer still holds the original item

  Scenario: create with an id succeeds after the item was deleted elsewhere
    Given an item "i1" created through the collection
    And the item is deleted elsewhere while the seen-id cache still holds it
    When create is called with the id "i1"
    Then the metadata lookup is made and the create writes the item

  Scenario: an upsert whose existence check fails behaves as before
    Given a metadata lookup of "i1" sent to the atServer fails with a timeout
    When upsert is called with the id "i1"
    Then the item is written, as before

  Scenario: create with an id whose local lookup fails is refused as existing
    Given an item "i1" in local storage
    And a local metadata lookup of "i1" fails for a reason other than absence
    When create is called with the id "i1"
    Then the create rejects with a StateError and writes nothing
