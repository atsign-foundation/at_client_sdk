Feature: A dotted namespace grant covers locally what it covers on the atServer

  An enrollment may be granted a dotted namespace, such as cmp.rotation. The
  atServer reads a key's namespace as its last segment and also matches a
  grant against the key's name, so cmp.rotation covers x.cmp.rotation. The
  client's local access check decides the same way, so a record the atServer
  lets the enrollment read or write is readable and writable locally too. It
  follows the atServer in two more ways: a public key is read whatever the
  grant, and no local operation reaches a __manage key. And a queued write
  the atServer refuses for good leaves the sync queue with a warning, so the
  writes behind it still reach the atServer.

  Races: none arise; the check reads the enrollment's grants, which this does
  not change.
  Replay: none arise; nothing sent or accepted changes.
  DoS: none arise; the check walks the grants once per key, as the atServer
  does.
  Forgery and impersonation: none arise; a grant covers locally exactly the
  keys it covers on the atServer, and sync stores only records the atServer
  sent this enrollment.

  Scenario: An enrollment granted a dotted namespace puts, gets, deletes and lists its keys locally
    Given an enrollment granted {cmp.rotation: rw}
    When it puts, gets, deletes or lists x.cmp.rotation@bob locally
    Then each succeeds

  Scenario: Sync stores a record under a dotted grant locally
    Given an enrollment granted {cmp.rotation: rw}
    When sync brings y.cmp.rotation@bob down
    Then it is stored locally

  Scenario: A dotted grant does not cover a key beside or above it
    Given an enrollment granted {cmp.rotation: rw}
    When it gets x.rotation@bob or x.other.rotation@bob
    Then it is refused

  Scenario: A grant covers a key in a dotted namespace beneath it
    Given an enrollment granted {rotation: rw}
    When it gets x.cmp.rotation@bob
    Then it succeeds

  Scenario: PQ seeding reads the advertisement of a dotted namespace it was granted
    Given an enrollment granted {cmp.rotation: rw}
    When it starts
    Then its PQ seeding reads public:__nskey.cmp.rotation@bob without "insufficient privilege"

  Scenario: A record sync refuses is logged at warning, naming the key and the enrollment
    Given an enrollment granted {cmp.rotation: rw}
    When sync refuses a record
    Then it logs at warning naming the key and the enrollment

  Scenario: A public key outside the grant is read locally, as the atServer allows, and not written
    Given an enrollment granted {cmp.rotation: rw}
    When it gets public:x.other@bob locally
    Then it succeeds, as the atServer allows
    When it puts public:x.other@bob
    Then it is refused

  Scenario: A grant naming the namespace wins over * locally, even when it gives less
    Given an enrollment granted {*: rw, wavi: r}
    When it puts x.wavi@bob locally
    Then it is refused

  Scenario: No local operation reaches a __manage key
    Given any enrollment
    When it puts or gets k.x.__manage@bob or x.__manage@bob locally
    Then it is refused

  Scenario: A queued update the atServer refuses as unauthorized leaves the queue, and the entries behind it push
    Given a queued update of K that the atServer refuses as unauthorized
    When sync pushes
    Then that entry leaves the queue, a warning names K, the operation and the enrollment, and the entries behind it push in the same round

  Scenario: A queued delete the atServer refuses as unauthorized leaves the queue, and the entries behind it push
    Given a queued delete of K that the atServer refuses as unauthorized
    When sync pushes
    Then that entry leaves the queue, a warning names K, the operation and the enrollment, and the entries behind it push in the same round

  Scenario: A queued update refused with any other code stays queued and retries
    Given a queued update refused with a code other than AT0009, AT0032, AT0016, AT0022 and AT0003
    When sync pushes
    Then it stays queued and retries next round, as now

  Scenario: A queued write refused for good with AT0032, AT0016, AT0022 or AT0003 leaves the queue
    Given a queued update that the atServer refuses with AT0032, AT0016, AT0022 or AT0003
    When sync pushes
    Then that entry leaves the queue, a warning names K, the operation, the enrollment and the code, and the entries behind it push in the same round

  Scenario: An enrollment granted read only stores what sync brings it, and its own put is still refused
    Given an enrollment granted {ns: r}
    When sync brings x.ns@bob down
    Then it is stored locally, and a local put of x.ns@bob by that enrollment is still refused
