Feature: Sync pushes past a write the atServer refuses for good

  Sync pushes this device's queued writes to the atServer in batches. A write
  the atServer refuses for good leaves the sync queue, logged with the code,
  and the device keeps its own copy, so the writes behind it still reach the
  atServer. A code at_commons does not list counts as a refusal for good. A
  write refused any other way stays queued, and sync sends it again.

  Races: a newer write to the same key that lands while the refused one is in
  flight stays queued and pushes next round, since the removal is
  version-checked.
  Replay: none arise; nothing sent or accepted changes.
  DoS: a write the atServer refuses for good is no longer sent again every
  round.
  Forgery and impersonation: none arise; the atServer checks every write this
  device pushes, and a drop removes only this device's own queued write.

  Scenario: A queued update the atServer refuses as unauthorized leaves the queue, and the entries behind it push
    Given a queued update of K that the atServer refuses as unauthorized
    When sync pushes
    Then that entry leaves the queue, a severe log line names K, the operation and the enrollment, and the entries behind it push in the same round

  Scenario: A queued delete the atServer refuses as unauthorized leaves the queue, and the entries behind it push
    Given a queued delete of K that the atServer refuses as unauthorized
    When sync pushes
    Then that entry leaves the queue, a severe log line names K, the operation and the enrollment, and the entries behind it push in the same round

  Scenario: A queued update refused with any other listed code stays queued and retries
    Given a queued update refused with a code at_commons' error_codes lists, other than AT0009, AT0032, AT0016, AT0022 and AT0003
    When sync pushes
    Then it stays queued and retries next round, as now

  Scenario: A queued write refused for good with AT0032, AT0016, AT0022 or AT0003 leaves the queue
    Given a queued update that the atServer refuses with AT0032, AT0016, AT0022 or AT0003
    When sync pushes
    Then that entry leaves the queue, a severe log line names K, the operation, the enrollment and the code, and the entries behind it push in the same round

  Scenario: A queued update refused with a code at_commons does not list leaves the queue at once
    Given a queued update of K that the atServer refuses with a code at_commons' error_codes does not list, such as AT0099
    When sync pushes
    Then that entry leaves the queue, a severe log line names K, the operation, the enrollment and the code, the device keeps its copy of K, and the entries behind it push in the same round
