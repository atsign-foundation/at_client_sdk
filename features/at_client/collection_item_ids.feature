Feature: AtCollection checks every item id before using it in a key

  An item's id is the first segment of every key AtCollection writes or reads
  for that item. Every call that takes an id (create, upsert, draft, get,
  getOrNull, exists, getItems and getItemsAsStream) folds it to lower case
  and refuses, with ArgumentError and before any read or write, an id that
  is empty or contains ".", ":", "@", whitespace or a control character.
  create, upsert and draft also refuse an id that starts with "_". A new
  item's id, given to create or to upsert when no item has it, must be 1 to
  64 characters of a-z, 0-9, "-" and "_", starting with a letter or digit.
  An id that create generates is 8 characters of a-z and 0-9. An item
  already stored under an id outside that set keeps its id: it is listed,
  read by that id, changed through draft and update or through upsert,
  shared, and deleted. subCollection refuses a subName that is empty or
  contains ".", ":", "@", whitespace or a control character.

  Races: two callers in one process, or two clients of one atSign, may use
  the same id at once. The check reads only the id string and runs before
  the first read or write, so no interleaving changes its answer, and
  folding at the same point makes two spellings of an id one item. The
  check-then-write in create for one given id is unchanged.
  Replay: cannot arise. No message, nonce or signature is added or changed,
  and an id is checked each time it is used.
  DoS: whoever supplies an id to the app, and any atSign that shares an item
  into the namespace. An id longer than 64 characters is refused before any
  read or write, the check is linear in the id's length, and an item another
  atSign shares under an id starting with "_" can still be read by that id
  (the scenarios tagged @dos).
  Forgery: the app's own code supplies every id, and it holds this atSign's
  keys and could write any key directly; the check matters when an app
  builds an id from input it did not write. Every call refuses an id
  containing ".", ":", "@", whitespace or a control character, so each key
  built from an id names that id's item in this collection, and the error
  shows the id on one line (the scenarios tagged @forgery).
  Impersonation: cannot arise. An id is not an identity: update,
  updateSharedWith and delete refuse an item another atSign owns, and an
  item's owner comes from its key's sharedBy.

  # Every call that takes an id

  @forgery
  Scenario: Given an id containing ":", when create is called, then ArgumentError is thrown and nothing is read or written
    Given a collection "todos.demo" of @alice
    When create is called with the id "a:b"
    Then ArgumentError is thrown
    And nothing is read or written

  @forgery
  Scenario: Given an id containing "@", when create is called, then ArgumentError is thrown and nothing is read or written
    Given a collection "todos.demo" of @alice
    When create is called with the id "a@b"
    Then ArgumentError is thrown
    And nothing is read or written

  Scenario: Given an id containing a space, when create is called, then ArgumentError is thrown and nothing is read or written
    Given a collection "todos.demo" of @alice
    When create is called with the id "a b"
    Then ArgumentError is thrown
    And nothing is read or written

  @forgery
  Scenario: Given an id containing a newline, when create is called, then ArgumentError is thrown and nothing is read or written
    Given a collection "todos.demo" of @alice
    When create is called with an id of "a", a newline and "b"
    Then ArgumentError is thrown
    And nothing is read or written

  @forgery
  Scenario: Given an id containing a newline, when create is called, then the ArgumentError's text is a single line
    Given a collection "todos.demo" of @alice
    When create is called with an id of "a", a newline and "b"
    Then the ArgumentError's text holds no newline
    And it shows the id with the newline escaped

  Scenario: Given an empty id, when create is called, then ArgumentError is thrown and nothing is read or written
    Given a collection "todos.demo" of @alice
    When create is called with the id ""
    Then ArgumentError is thrown
    And nothing is read or written

  Scenario: Given an id starting with "_", when create is called, then ArgumentError is thrown and nothing is read or written
    Given a collection "todos.demo" of @alice
    When create is called with the id "_a"
    Then ArgumentError is thrown
    And nothing is read or written

  Scenario: Given an id containing ".", when create is called, then ArgumentError is thrown and nothing is read or written
    Given a collection "todos.demo" of @alice
    When create is called with the id "a.b"
    Then ArgumentError is thrown
    And nothing is read or written

  @forgery
  Scenario: Given an id containing ":", when upsert is called, then ArgumentError is thrown and nothing is read or written
    Given a collection "todos.demo" of @alice
    When upsert is called with the id "a:b"
    Then ArgumentError is thrown
    And nothing is read or written

  @forgery
  Scenario: Given an id containing ":", when draft is called, then ArgumentError is thrown
    Given a collection "todos.demo" of @alice
    When draft is called with the id "a:b"
    Then ArgumentError is thrown

  @forgery
  Scenario: Given an id containing "@", when draft is called, then ArgumentError is thrown
    Given a collection "todos.demo" of @alice
    When draft is called with the id "a@b"
    Then ArgumentError is thrown

  Scenario: Given an id containing ":", when get is called, then ArgumentError is thrown and nothing is read
    Given a collection "todos.demo" of @alice
    When get is called with the id "a:b" and the owner @alice
    Then ArgumentError is thrown
    And nothing is read

  Scenario: Given an id containing ":", when getOrNull is called, then ArgumentError is thrown and nothing is read
    Given a collection "todos.demo" of @alice
    When getOrNull is called with the id "a:b" and the owner @alice
    Then ArgumentError is thrown
    And nothing is read

  @forgery
  Scenario: Given an id containing "@", when exists is called, then ArgumentError is thrown and nothing is read
    Given a collection "todos.demo" of @alice
    When exists is called with the id "a@b" and the owner @alice
    Then ArgumentError is thrown
    And nothing is read

  Scenario: Given an id containing ":", when getItems is called with that id, then ArgumentError is thrown and nothing is read
    Given a collection "todos.demo" of @alice
    When getItems is called with the id "a:b"
    Then ArgumentError is thrown
    And nothing is read

  Scenario: Given an id containing ":", when getItemsAsStream is called with that id, then ArgumentError is thrown and nothing is read
    Given a collection "todos.demo" of @alice
    When getItemsAsStream is called with the id "a:b"
    Then ArgumentError is thrown by the call, before a stream is returned
    And nothing is read

  @dos
  Scenario: Given an item @bob shares under an id starting with "_", when get is called with that id and @bob, then it returns the item
    Given a collection "todos.demo" of @alice holding an item @bob shares under the id "_a"
    When get is called with the id "_a" and the owner @bob
    Then it returns that item

  # A new item's id

  @dos
  Scenario: Given an id of 65 characters, when create is called, then ArgumentError is thrown and nothing is read or written
    Given a collection "todos.demo" of @alice
    When create is called with an id of 65 "a" characters
    Then ArgumentError is thrown
    And nothing is read or written

  Scenario: Given an id of 64 characters of a-z, 0-9, "-" and "_", when create is called, then get returns the item by that id
    Given a collection "todos.demo" of @alice
    When create is called with a 64-character id of lowercase letters, digits, "-" and "_"
    Then get with that id and the owner @alice returns the item

  Scenario: Given an id starting with "-", when create is called, then ArgumentError is thrown and nothing is read or written
    Given a collection "todos.demo" of @alice
    When create is called with the id "-a"
    Then ArgumentError is thrown
    And nothing is read or written

  Scenario: Given an id containing "*", when create is called, then ArgumentError is thrown and nothing is read or written
    Given a collection "todos.demo" of @alice
    When create is called with the id "a*b"
    Then ArgumentError is thrown
    And nothing is read or written

  Scenario: Given no item with a 65-character id, when upsert is called with that id, then ArgumentError is thrown and nothing is written
    Given a collection "todos.demo" of @alice holding no item with the id of 65 "a" characters
    When upsert is called with that id
    Then ArgumentError is thrown
    And nothing is written

  Scenario: Given no id, when create is called, then the item's id is 8 characters of a-z and 0-9
    Given a collection "todos.demo" of @alice
    When create is called with no id
    Then the returned item's id is 8 characters, each a-z or 0-9

  # Upper case

  Scenario: Given the id "Todo-1", when create is called, then the item returned has the id "todo-1"
    Given a collection "todos.demo" of @alice
    When create is called with the id "Todo-1"
    Then the returned item's id is "todo-1"

  Scenario: Given an item created with the id "todo-1", when get is called with "TODO-1", then it returns that item
    Given a collection "todos.demo" of @alice holding an item created with the id "todo-1"
    When get is called with the id "TODO-1" and the owner @alice
    Then it returns the item whose id is "todo-1"

  # An item already stored under an id outside the new-item set

  Scenario: Given a stored item whose id is 65 characters, when getItems is called, then it lists the item under that id
    Given a collection "todos.demo" of @alice holding a stored item whose id is 65 "a" characters
    When getItems is called
    Then the item is listed with that id

  Scenario: Given a stored item whose id starts with "-", when get is called with that id, then it returns the item
    Given a collection "todos.demo" of @alice holding a stored item with the id "-a"
    When get is called with the id "-a" and the owner @alice
    Then it returns that item

  Scenario: Given a stored item whose id is 65 characters, when a draft with that id and a new value is passed to update, then the item holds the new value
    Given a collection "todos.demo" of @alice holding a stored item whose id is 65 "a" characters
    When draft is called with that id and a new value, and the draft is passed to update
    Then get with that id returns the new value

  Scenario: Given a stored item whose id contains "*", when upsert is called with that id, then the item holds the new value
    Given a collection "todos.demo" of @alice holding a stored item with the id "a*b"
    When upsert is called with the id "a*b" and a new value
    Then get with that id returns the new value

  Scenario: Given a stored item whose id starts with "-", when updateSharedWith adds @bob, then a copy for @bob is written
    Given a collection "todos.demo" of @alice holding a stored item with the id "-a"
    When updateSharedWith is called on it with @bob
    Then a copy of the item for @bob is written

  Scenario: Given a stored item whose id is 65 characters, when delete is called, then no key of the item remains
    Given a collection "todos.demo" of @alice holding a stored item whose id is 65 "a" characters
    When delete is called on it
    Then no key of the item remains

  # Sub-collection names

  Scenario: Given a subName containing ":", when subCollection is called, then ArgumentError is thrown
    Given a collection "todos.demo" of @alice holding an item "p1"
    When subCollection is called on "p1" with the subName "a:b"
    Then ArgumentError is thrown
