Feature: A collection read that fails in transit fails the listing, not the item

  AtCollection.getItemsAsStream yields a CItemReadException for a record this
  device cannot decode, so a caller can list the rest and know which item is
  unreadable. A transport failure is a different thing: the atServer did not
  answer, so nothing is known about the record. Such an error is yielded raw,
  and a listing that meets one fails with it.

  # Threats. Each answer names the scenario that holds it.
  #
  # Race: a read that times out says nothing about the record, so the listing
  #   fails with the transport error instead of continuing past a record
  #   another device may only have been slow to serve: "a read that times out
  #   fails the listing instead of marking the item unreadable".
  # Replay: a stored value that does not decode is still an unreadable record,
  #   however often it is read: "a value that cannot be decoded is still
  #   reported unreadable".
  # DoS: a slow or unreachable atServer cannot turn a whole collection into
  #   unreadable items for a caller to clean up: "a read that times out fails
  #   the listing instead of marking the item unreadable".
  # Forgery: a peer cannot make a transient failure look like corrupt data and
  #   trigger cleanup, because only a decode failure is reported per item:
  #   "a read that times out fails the listing instead of marking the item
  #   unreadable".
  # Impersonation: a refusal is still reported per item, and never read as a
  #   transport failure: "a read refused as unauthorised is still reported
  #   unreadable".

  Scenario: a read that times out fails the listing instead of marking the item unreadable
    Given a collection holding one item whose read times out
    When the collection is listed
    Then the listing fails with the timeout error and no CItemReadException is yielded
    And the same holds when the read fails because the atServer cannot be reached

  Scenario: a value that cannot be decoded is still reported unreadable
    Given a collection holding one item whose stored value is not a valid envelope
    When the collection is listed
    Then the listing fails with a CItemReadException naming the item

  Scenario: a read refused as unauthorised is still reported unreadable
    Given a collection holding one item whose read is refused as unauthorised
    When the collection is listed
    Then the listing fails with a CItemReadException naming the item
