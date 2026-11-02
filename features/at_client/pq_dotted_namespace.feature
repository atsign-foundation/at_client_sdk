Feature: At pqActive, a record in a dotted namespace is sealed to that namespace's key

  A namespace may be dotted, such as the todos examples' todos.demos. A key
  read from its string form, as AtCollection builds every record's, names
  only its last label as its namespace. A share is sealed to the recipient's
  key as pq_share_level.feature has it. For a write to the client's own
  atSign, every write site (the readiness check, the content-key pre-pass,
  the data provider and content-key rotation) asks NskeyResolver for one
  start level instead: the longer of the key's own
  namespace and the most specific namespace this client holds a namespace
  private for that the key's whole name ends with, after a dot. A bare
  namespace, as the readiness check is given, matches a held namespace only
  by being equal to it. The held set is read from what this client has filed,
  folded, without the reserved namespaces. The walk goes up from the start
  level, as it does today. Most specific is the sealing rule, not the access
  rule: the atServer still decides who may read a key.

  Races: the held set is read at each write from what this client has filed,
  so a private filed mid-session counts from the next write; a write that
  races the filing seals at the level it held before, which every holder of
  that level opens.
  Replay: none arise; what is sealed, and the owner and namespace bound into
  each envelope, are unchanged.
  DoS: the start level comes from the device, with no round trip, and the
  walk goes only up from it, so a record's own name, or a sub-collection's
  parent id, adds no namespace-key lookups.
  Forgery and impersonation: the start level is a namespace this client holds
  a private for, or the key's own namespace, as today; a name matches a held
  namespace only by ending with "." and it, so x.mydemos never matches demos
  and a dotted record id cannot leave its collection's namespace; the walk
  only goes up, so no key name reaches a namespace below or beside the start.

  Scenario: A collection record in a dotted app namespace is written and read at pqActive
    Given a client at pqActive in namespace todos.demos, holding its todos.demos private
    When it creates a todo in its todos collection
    Then the todo is sealed under todos.demos's namespace key, and reads back

  Scenario: A todo shared in a dotted namespace opens for the recipient
    Given alice and bob, each at pqActive in namespace todos.demos
    When alice shares a todo with bob
    Then bob opens it with his todos.demos namespace key

  Scenario: A sub-collection record is sealed under the app namespace
    Given a todo with notes, at pqActive in todos.demos
    When a note is added
    Then it is sealed under todos.demos's namespace key, and no namespace key is looked up at a level named after the todo

  Scenario: A key read from its string form is sealed like one built with its namespace
    Given a client at pqActive holding a todos.demos private
    When it puts AtKey.fromString("x.todos.demos@alice")
    Then the value is sealed under todos.demos's key, as AtKey with key x and namespace todos.demos is

  Scenario: An explicit narrower namespace under a broader holding starts at the narrower level
    Given a client of alice's holding only the demos private, and bob publishing keys for demos and todos.demos
    When it shares AtKey with key x and namespace todos.demos with bob
    Then the value is sealed under bob's todos.demos key, as it is today

  Scenario: The writer's level absent at the recipient seals at the recipient's broader level
    Given an enrollment of alice's granted todos.demos only, holding its private, and bob publishing a key for demos and none for todos.demos
    When it shares x.todos.demos with bob
    Then the value is sealed under bob's demos key, the share has no sibling copy, and a warning names demos

  Scenario: A grant spelt in capitals covers its key
    Given a client holding a private filed for a namespace spelt Todos.Demos
    When it puts AtKey.fromString("x.todos.demos@alice")
    Then the value is sealed under todos.demos's key

  Scenario: A name that only ends with a held namespace's letters is not covered
    Given a client at pqActive holding a demos private only, with no key published for mydemos
    When it puts a value whose key is x.mydemos
    Then the write throws NamespaceKeyUnavailableException naming mydemos, and nothing is sealed under demos's key

  Scenario: A bare namespace as a key is not covered by that namespace
    Given a client at pqActive holding a todos.demos private only, with no key published for demos
    When it puts AtKey.fromString("todos.demos@alice")
    Then no content key is cut, and the write throws NamespaceKeyUnavailableException naming demos

  Scenario: Of two held levels, the more specific seals, and the writer reads it back
    Given a client granted demos rw and todos.demos r, holding privates for both
    When it puts a value whose key is x.todos.demos
    Then it is sealed under todos.demos's key, and the writer reads it back

  Scenario: A broader-grant reader without the narrower private cannot open the value
    Given a value sealed under todos.demos's key, and a reader granted demos that holds no todos.demos private
    When the reader gets the value, or is notified of it
    Then get throws NskeyPrivateUnavailableException naming todos.demos, and the notification is parked, then dropped after six minutes with a warning

  Scenario: Rotating the content key of a key read from its string form rotates at the start level
    Given a client holding a todos.demos private, and a value at AtKey.fromString("x.todos.demos@alice")
    When its content key is rotated
    Then the new content key is cut at todos.demos, the level the value was sealed at

  Scenario: The start level is worked out offline
    Given a client holding a todos.demos private, offline
    When it asks where AtKey.fromString("x.todos.demos@alice") starts
    Then the answer is todos.demos, read from what it has filed, with no request to the atServer

  Scenario: A namespace private filed after start is used from the next write
    Given a client that started holding a demos private only, and later files a todos.demos private
    When it then puts AtKey.fromString("x.todos.demos@alice")
    Then the value is sealed under todos.demos's key

  Scenario: A key outside every held namespace is not sealed to a narrower one
    Given a client at pqActive holding a todos.demos private only, with no key published for demos
    When it puts a value whose key is x.demos
    Then the write throws NamespaceKeyUnavailableException naming demos, and nothing is sealed under todos.demos's key

  Scenario: A key's name cannot steer the seal to a broader namespace's key
    Given a client holding a todos.demos private, with another enrollment of its atSign publishing a key for demos
    When it puts a value whose key is x.todos.demos
    Then the value is sealed under todos.demos's key, not demos's

  Scenario: A value written before the fix still opens
    Given a value written at pqActive under a key read from its string form, recording demos as its ckNs
    When the client reads it after the fix
    Then it opens under the recorded ckNs
