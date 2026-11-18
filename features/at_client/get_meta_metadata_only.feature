Feature: getMeta reads a key's metadata without its value

  getMeta(key, getRequestOptions) returns the metadata stored for a key and
  reads nothing else, so it decrypts nothing and answers for a record whose
  value this client cannot open. It sends the lookup where get would:
  useRemoteAtServer set to true asks the atServer, set to false asks local
  storage, and unset follows AtClientPreference.remoteLocalPref; an uncached
  key another Atsign owns is always looked up on the atServer, and a local: key
  is never sent. It returns null when the record is held but not visible now
  (not yet available, or expired and not yet removed). It throws
  AtKeyNotFoundException when no record is held, AtKeyException for an invalid
  key, AtClientException when the lookup fails any other way, and
  StoppedException once the client has stopped. It fills a missing sharedBy on
  the key it is given, as get does, and changes nothing else on it.

  Races: a record can be written, deleted or expire between two calls, or
  between getMeta and the call that acts on its answer. Each call answers for
  one moment, and the caller that acts on it owns the gap, as with get.
  Whoever wins holds this Atsign's keys and could write the record directly.
  Replay: cannot arise. No message, nonce or signature is added; the lookup
  rides the client's own authenticated connection, as the llookup:all it
  replaces did.
  DoS: whoever supplies keys to the app, and any Atsign whose atServer answers a
  lookup. A call is one lookup and no scan; the answer is metadata, smaller than
  the value, and nothing is decrypted or fetched to decrypt it. A body that is
  not metadata is refused, never retried.
  Forgery: the answering atServer holds every record under this Atsign and could
  write any of them; another Atsign's atServer answers only for keys it owns,
  and for a key owned by another Atsign the metadata returned is that Atsign's
  claim about its own record, as with get. The answer names no key, so what it
  says about isPublic and isCached is ignored: both come from the key asked for.
  Impersonation: cannot arise. The lookup runs under this client's own
  connection and enrollment and asserts no identity; an enrollment without
  access to the key's namespace is refused by the atServer and by local storage,
  and the refusal is the same for a held and a missing record.

  Scenario: Given a record in local storage whose value this client cannot decrypt, when getMeta is called with no options, then its metadata is returned and nothing is sent to the atServer
    Given a client with the default AtClientPreference
    And local storage holds a self key whose value fails to decrypt
    When getMeta is called with that key and no options
    Then the key's Metadata is returned
    And no command reaches the atServer
    And get with the same key throws

  Scenario: Given a record only the atServer holds, when getMeta is called with useRemoteAtServer true, then llookup:meta reaches the atServer and its metadata is returned
    Given a client with the default AtClientPreference
    And the atServer holds a self key that local storage does not
    When getMeta is called with that key and GetRequestOptions that set useRemoteAtServer to true
    Then llookup:meta for that key reaches the atServer and no other command does
    And the key's Metadata is returned

  Scenario: Given a client whose preference reads from the atServer only, when getMeta is called with options that leave useRemoteAtServer unset, then the lookup reaches the atServer
    Given a client whose remoteLocalPref is remoteOnly
    And the atServer holds a self key
    When getMeta is called with that key and GetRequestOptions that set only bypassCache
    Then llookup:meta for that key reaches the atServer

  Scenario: Given a client whose preference reads from the atServer only, when getMeta is called with useRemoteAtServer false, then only local storage is asked
    Given a client whose remoteLocalPref is remoteOnly
    And local storage holds a self key
    When getMeta is called with that key and GetRequestOptions that set useRemoteAtServer to false
    Then the key's Metadata is returned
    And no command reaches the atServer

  Scenario Outline: Given a key of each kind, when getMeta is called with no options, then the metadata-only lookup for that kind is sent to the secondary get would use
    Given a client of @alice with the default AtClientPreference
    And a <kind> key
    When getMeta is called with that key and no options
    Then <command> is sent to <secondary>
    Examples:
      | kind                        | command                                  | secondary             |
      | self                        | llookup:meta:k.ns@alice                  | local storage         |
      | shared by @alice with @bob  | llookup:meta:@bob:k.ns@alice             | local storage         |
      | public of @alice            | llookup:meta:public:k.ns@alice           | local storage         |
      | cached from @bob            | llookup:meta:cached:@alice:k.ns@bob      | local storage         |
      | shared with @alice by @bob  | lookup:meta:k.ns@bob                     | the atServer          |
      | public of @bob              | plookup:meta:k.ns@bob                    | the atServer          |

  Scenario: Given a local: key, when getMeta is called with useRemoteAtServer true, then the lookup stays on the device
    Given a client of @alice
    And local storage holds a local: key
    When getMeta is called with that key and GetRequestOptions that set useRemoteAtServer to true
    Then llookup:meta for that key is sent to local storage
    And no command reaches the atServer

  Scenario Outline: Given a key shared with the client by another Atsign, when getMeta is called with useRemoteAtServer false, then the lookup still goes to the atServer
    Given a client of @alice with the default AtClientPreference
    And a <kind> key of @bob
    When getMeta is called with that key and GetRequestOptions that set useRemoteAtServer to false
    Then <command> is sent to the atServer
    Examples:
      | kind                | command                  |
      | shared with @alice  | lookup:meta:k.ns@bob     |
      | public              | plookup:meta:k.ns@bob    |

  Scenario: Given a key of another Atsign, when getMeta is called with bypassCache, then the lookup asks the atServer to skip its cached copy
    Given a client of @alice
    And a public key of @bob
    When getMeta is called with that key and GetRequestOptions that set bypassCache to true
    Then plookup:bypassCache:true:meta:k.ns@bob is sent to the atServer

  Scenario Outline: Given a record that is held but not visible now, when getMeta is called, then it returns null
    Given a client of @alice
    And <leg> holds a self key that is <state>
    When getMeta is called with that key and options that choose <leg>
    Then null is returned
    Examples:
      | leg           | state                                     |
      | local storage | not yet available                         |
      | local storage | past its expiry and not yet removed       |
      | the atServer  | not yet available                         |
      | the atServer  | past its expiry and not yet removed       |

  Scenario: Given an atServer that answers a metadata lookup with an empty response, when getMeta is called, then it returns null
    Given a client of @alice
    And the atServer answers a metadata lookup for a self key with an empty response
    When getMeta is called with that key and GetRequestOptions that set useRemoteAtServer to true
    Then null is returned

  Scenario Outline: Given no record under a key, when getMeta is called, then it throws AtKeyNotFoundException
    Given a client of @alice
    And <leg> holds no record under a self key
    When getMeta is called with that key and options that choose <leg>
    Then AtKeyNotFoundException is thrown
    Examples:
      | leg           |
      | local storage |
      | the atServer  |

  Scenario Outline: Given a lookup that fails with an error other than not found, when getMeta is called, then it throws AtClientException
    Given a client of @alice
    And a lookup on <leg> fails because <cause>
    When getMeta is called with a self key and options that choose <leg>
    Then AtClientException is thrown
    And nothing is returned
    Examples:
      | leg           | cause                                                          |
      | the atServer  | the atServer's address refuses the connection                  |
      | the atServer  | the atDirectory refuses the connection                         |
      | the atServer  | the atServer answers AT0009 for an enrollment without access   |
      | the atServer  | the atServer refuses the session with AT0401                   |
      | the atServer  | the atServer does not answer in time                           |
      | local storage | the enrollment has no access to the key's namespace            |

  Scenario Outline: Given a client that has stopped, when getMeta is called, then it throws StoppedException
    Given a client that has been stopped
    When getMeta is called with a self key and options that choose <leg>
    Then StoppedException is thrown
    Examples:
      | leg           |
      | local storage |
      | the atServer  |

  Scenario Outline: Given an atServer answer that is not metadata, when getMeta is called, then it throws AtClientException and returns nothing
    Given a client of @alice
    And the atServer answers a metadata lookup with <body>
    When getMeta is called with a self key and GetRequestOptions that set useRemoteAtServer to true
    Then AtClientException is thrown
    Examples:
      | body                         |
      | a JSON list                  |
      | a JSON string                |
      | text that is not JSON        |
      | an object with an expiresAt that is not a date |
      | an object whose ttl is a string                |

  Scenario: Given an atServer answer that claims the key is public and cached, when getMeta is called with a self key, then the metadata says neither
    Given a client of @alice
    And the atServer answers a metadata lookup for a self key with a body whose isPublic and isCached are true
    When getMeta is called with that key and GetRequestOptions that set useRemoteAtServer to true
    Then the returned Metadata has isPublic false and isCached false
    And its other fields are those of the body

  Scenario: Given a public key of another Atsign, when getMeta is called, then the returned metadata is public and not cached
    Given a client of @alice
    And the atServer answers a metadata lookup for a public key of @bob
    When getMeta is called with that key
    Then the returned Metadata has isPublic true and isCached false

  Scenario: Given a key shared with the client by another Atsign, when getMeta is called, then it returns that Atsign's metadata for the key
    Given a client of @alice
    And @bob has put a key shared with @alice on @bob's atServer with a ttl of one hour
    When getMeta is called with that key and no options
    Then the metadata returned has a ttl of one hour
    And it is not public

  Scenario: Given a public key of another Atsign, when getMeta is called, then it returns that Atsign's metadata for the key
    Given a client of @alice
    And @bob has put a public key on @bob's atServer with a ttl of one hour
    When getMeta is called with that key and no options
    Then the metadata returned has a ttl of one hour
    And it is public

  Scenario: Given an enrollment without access to a namespace, when getMeta is asked for a record in it that is held and for one that is missing, then both fail the same way
    Given a client whose enrollment has no access to namespace "ns"
    And the atServer holds one record in "ns" and none under a second key
    When getMeta is called for each key with useRemoteAtServer true
    Then AtClientException is thrown for both
    And the two exceptions carry the same message apart from the key

  Scenario: Given a record this client can open, when getMeta is called, then it returns the Metadata that get returns for the key
    Given a client of @alice
    And local storage holds a self key whose value this client can decrypt
    When getMeta and get are called with that key
    Then the Metadata from getMeta equals the metadata of the AtValue from get

  Scenario: Given a key with metadata of its own, when getMeta is called, then the key keeps that metadata
    Given a self key whose metadata sets ttr to 777
    And local storage holds a record under it with a different ttr
    When getMeta is called with that key
    Then the key's metadata still sets ttr to 777

  Scenario: Given an invalid key, when getMeta is called, then it throws AtKeyException and sends nothing
    Given a client of @alice
    And a key with an empty name
    When getMeta is called with that key
    Then AtKeyException is thrown
    And nothing is looked up locally or on the atServer
