Feature: Keys round-trip through put, get, delete and keys

  put, get, delete and keys act on keys written <key>.<namespace>@<atSign>.
  The client's namespace is the default; public and cached keys keep their
  flags; a key with no namespace says so. Values are strings or bytes; get of
  a key the atServer does not hold is null.

  Races: none arise; every call is one request in the session's own order.
  Replay: none arise; a repeated put overwrites the same key with the same
  value.
  DoS: none arise beyond the atServer's own limits; keys sends one scan.
  Forgery and impersonation: none arise; every key is written under the
  session's own atSign, authenticated by the passkey-held PKAM key.

  Scenario: put sends the key with the default namespace and resolves true
    Given an open client with namespace tally
    When put is called with { key: 'note' } and the value 'hi'
    Then the bridge receives the key with namespace tally and the value
    And put resolves true

  Scenario: put of bytes then get returns equal bytes
    Given an open session on an atServer
    When a Uint8Array is put and the same key is read with get
    Then get returns equal bytes

  Scenario: get of a key the atServer does not hold is null
    Given an open session on an atServer that holds no such key
    When get is called for that key
    Then get resolves null

  Scenario: delete then get of the same key is null
    Given an open session holding a value under a key
    When delete is called for that key
    Then a get of the same key resolves null

  Scenario: keys maps the bridge strings to AtKey objects
    Given an atServer holding rpc.req.1.tally@alice and @bob:note.tally@alice
    When keys is called with the filter 'rpc'
    Then the bridge receives the filter 'rpc'
    And the result is AtKey objects with key, namespace, sharedWith and sharedBy split out

  Scenario: sends public and cached through
    Given a key with public and cached set
    When it is converted for the bridge
    Then the bridge key carries public and cached with the client's namespace

  Scenario: sends the flags and no default namespace for a key that had none
    Given the key string public:plain@alice, which has no namespace
    When it is converted for the bridge
    Then the bridge key carries public and noNamespace
    And no default namespace is added
