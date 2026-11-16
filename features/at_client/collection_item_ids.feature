Feature: AtCollection checks every item id before using it in a key

  An item's id is the first segment of every key AtCollection writes or reads
  for that item. Every call that takes an id (create, upsert, draft, get,
  getOrNull, exists, getItems and getItemsAsStream) folds it to lower case and
  refuses, with ArgumentError and before any read or write, an id that is
  empty or contains ".", ":", "@", whitespace or a control character. create,
  upsert and draft also refuse an id that starts with "_". A new item's id,
  given to create or to upsert when no item has it, must be 1 to 64 characters
  of a-z, 0-9, "-" and "_", starting with a letter or digit. An id that create
  generates is 8 characters of a-z and 0-9. An item already stored under an id
  that the check accepts but that is outside that set keeps its id: it is
  listed, read by that id, changed through draft and update or through upsert,
  shared, and deleted. An id that starts with "_" is accepted by reads only:
  an item another Atsign shares under such an id is listed and read by it, and
  this Atsign's own keys that start with "_" are hidden, so get and getOrNull
  do not return its own item under such an id. subCollection folds a subName
  to lower case, and refuses one that is empty, contains ".", ":", "@",
  whitespace or a control character, or holds a character a key's name cannot.
  A notification or data event whose item id, ancestor id or subName the check
  refuses emits no event, a notification writes nothing to the local keystore,
  and a warning shows the id, escaped on one line, and its owner, never the
  value. An event whose key does not have an odd number of segments before the
  namespace emits no event, with the same warning. Every other event carries
  its item id and ancestor ids folded to lower case.

  Races: two callers in one process, or two clients of one Atsign, may use
  the same id at once. The check reads only the id string and runs before
  the first read or write, so no interleaving changes its answer, and
  folding at the same point makes two spellings of an id one item. The
  check-then-write in create for one given id is unchanged.
  Replay: cannot arise. No message, nonce or signature is added or changed,
  and an id is checked each time it is used.
  DoS: whoever supplies an id to the app, any Atsign that shares an item into
  the namespace, and any Atsign that can notify this one. create refuses an id
  longer than 64 characters before any read or write, and upsert refuses one
  once a read finds no item under it; reads accept an id of any length, and
  the check is linear in the id's length, an item another Atsign shares under
  an id starting with "_" can still be read by that id, and an event whose ids
  the check refuses is not emitted, so no event hands the app an id its reads
  refuse; each such event costs one warning and writes nothing to the local
  keystore, while each other notification costs a log line and a local write
  (the scenarios tagged @dos).
  Forgery: the app's own code supplies every id, and it holds this Atsign's
  keys and could write any key directly; the check matters when an app builds
  an id from input it did not write. Every call refuses an id containing ".",
  ":", "@", whitespace or a control character, so each key built from an id
  names that id's item in this collection, and each read matches only the keys
  of its own collection, and the error shows the id on one line (the scenarios
  tagged @forgery).
  Impersonation: cannot arise. An id is not an identity: update,
  updateSharedWith and delete refuse an item another Atsign owns, and an
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

  @forgery
  Scenario: Given an id containing U+2028, when create is called, then the ArgumentError's text holds no line or paragraph separator
    Given a collection "todos.demo" of @alice
    When create is called with the id "a", U+2028 and "b"
    Then the ArgumentError's text holds none of U+2028, U+2029 and U+0085
    And its invalidValue is the id as given

  @forgery
  Scenario: Given an id containing U+202E, when create is called, then the ArgumentError's text shows it escaped
    Given a collection "todos.demo" of @alice
    When create is called with the id "a", U+202E and "b"
    Then the ArgumentError's text does not hold U+202E and shows it as a six-character escape
    And its invalidValue is the id as given

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

  Scenario: Given an id starting with "_", when draft is called, then ArgumentError is thrown
    Given a collection "todos.demo" of @alice
    When draft is called with the id "_a"
    Then ArgumentError is thrown

  Scenario: Given a stored item whose id starts with "_", when upsert is called with that id, then ArgumentError is thrown and nothing is read or written
    Given a collection "todos.demo" of @alice holding a stored item with the id "_a"
    When upsert is called with the id "_a" and a new value
    Then ArgumentError is thrown
    And nothing is read or written

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

  @dos
  Scenario: Given an item @bob shares under an id starting with "_", when exists is called with that id and @bob, then it returns true
    Given a collection "todos.demo" of @alice holding an item @bob shares under the id "_a"
    When exists is called with the id "_a" and the owner @bob
    Then it returns true

  @forgery
  Scenario: Given an id containing U+0000, when get is called, then ArgumentError is thrown and nothing is read
    Given a collection "todos.demo" of @alice
    When get is called with the id "a", U+0000 and "b" and the owner @alice
    Then ArgumentError is thrown
    And nothing is read

  @forgery
  Scenario: Given an id containing U+009B, when get is called, then ArgumentError is thrown and nothing is read
    Given a collection "todos.demo" of @alice
    When get is called with the id "a", U+009B and "b" and the owner @alice
    Then ArgumentError is thrown
    And nothing is read

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

  @dos
  Scenario: Given an item @bob shares under an id containing a tab, when getItems is called, then it is not listed and a warning shows the id and @bob
    Given a collection "todos.demo" of @alice holding an item @bob shares under the id "x", a tab and "y"
    When getItems is called
    Then the item is not listed
    And a warning is logged that shows the id with the tab escaped and the owner @bob

  Scenario: Given a stored item with a 65-character id that this collection has found and that then expires, when upsert is called with that id, then ArgumentError is thrown and nothing is written
    Given a collection "todos.demo" of @alice for which exists has returned true for a stored item whose id is 65 "a" characters
    And that item expires
    When upsert is called with that id and a new value
    Then ArgumentError is thrown
    And nothing is written

  Scenario: Given a stored item with a 65-character id that cannot be read, when upsert is called with that id, then the item holds the new value
    Given a collection "todos.demo" of @alice holding a stored item whose id is 65 "a" characters
    And reading that item fails with an error other than not found
    When upsert is called with that id and a new value
    Then the item holds the new value

  # Sub-collection names

  Scenario: Given a subName containing ":", when subCollection is called, then ArgumentError is thrown
    Given a collection "todos.demo" of @alice holding an item "p1"
    When subCollection is called on "p1" with the subName "a:b"
    Then ArgumentError is thrown

  Scenario: Given a subName "Comments", when an item is created in that sub-collection, then getItems on it lists the item
    Given a collection "todos.demo" of @alice holding an item "p1"
    When subCollection is called on "p1" with the subName "Comments"
    And create is called on that sub-collection with the id "c1"
    Then getItems on that sub-collection lists "c1"

  Scenario: Given an item in the sub-collection "comments" of "p1", when subCollection is called with the subName "COMMENTS", then getItems lists that item
    Given a collection "todos.demo" of @alice holding an item "p1" with an item "c1" in its sub-collection "comments"
    When subCollection is called on "p1" with the subName "COMMENTS"
    Then getItems on that sub-collection lists "c1"

  @forgery
  Scenario: Given a subName containing "#", when subCollection is called, then ArgumentError is thrown
    Given a collection "todos.demo" of @alice holding an item "p1"
    When subCollection is called on "p1" with the subName "x#y"
    Then ArgumentError is thrown

  @dos
  Scenario: Given a notification from @bob whose key's subName contains "|", when it reaches the collection, then no event is emitted
    Given a collection "todos.demo" of @alice
    When a notification from @bob arrives for the key "@alice:c1.a|b.p1.todos.demo@bob"
    Then the collection emits no event

  @forgery
  Scenario: Given items in the sub-collections "a", "aa" and "a*" of "p1", when getItems is called on the sub-collection "a*", then it lists only that sub-collection's item
    Given a collection "todos.demo" of @alice holding an item "p1" with an item "c1" in its sub-collection "a", an item "c2" in its sub-collection "aa" and an item "c3" in its sub-collection "a*"
    When getItems is called on the sub-collection "a*" of "p1"
    Then it lists "c3" only

  Scenario: Given an item with no parents in its envelope, two levels under the sub-collection "a*" of "p1", whose ancestors are stored, when cleanupOrphans is called, then the item is not deleted
    Given a collection "todos.demo" of @alice holding an item "p1", an item "b1" in its sub-collection "a*", and an item "c1" whose envelope has no parents in the sub-collection "x" of "b1"
    When cleanupOrphans is called on the collection
    Then "c1" is not deleted

  # Ids that arrive in events

  @dos
  Scenario: Given a notification from @bob whose key's item id contains ":", when it reaches the collection, then no event is emitted
    Given a collection "todos.demo" of @alice
    When a notification from @bob arrives for the key "@alice:x:y.todos.demo@bob"
    Then the collection emits no event

  @dos
  Scenario: Given a notification from @bob whose key's item id contains ":", when it reaches the collection, then a warning shows the id and @bob and not the value
    Given a collection "todos.demo" of @alice
    When a notification from @bob arrives for the key "@alice:x:y.todos.demo@bob" with a value holding the text "v-secret"
    Then a warning is logged that shows the id "x:y" and the owner @bob
    And the warning does not contain "v-secret"

  @dos @forgery
  Scenario: Given a notification from @bob whose key's item id contains a newline, when it reaches the collection, then the warning is a single line
    Given a collection "todos.demo" of @alice
    When a notification from @bob arrives for a key whose item id is "x", a newline and "y"
    Then the warning holds no newline
    And it shows the id with the newline escaped

  @dos
  Scenario: Given a query watch and a notification from @bob whose key's item id contains a space, when it reaches the collection, then the watch emits no error
    Given a collection "todos.demo" of @alice with a query watch listening
    When a notification from @bob arrives for the key "@alice:x y.todos.demo@bob"
    Then the watch emits no error

  @dos
  Scenario: Given a delete notification from @bob whose key's item id contains ":", when it reaches the collection, then no event is emitted
    Given a collection "todos.demo" of @alice
    When a delete notification from @bob arrives for the key "@alice:x:y.todos.demo@bob"
    Then the collection emits no event

  @dos
  Scenario: Given a notification from @bob whose key's ancestor id contains ":", when it reaches the collection, then no event is emitted
    Given a collection "todos.demo" of @alice
    When a notification from @bob arrives for the key "@alice:c1.comments.x:y.todos.demo@bob"
    Then the collection emits no event

  @dos
  Scenario: Given a notification from @bob whose key's subName contains ":", when it reaches the collection, then no event is emitted
    Given a collection "todos.demo" of @alice
    When a notification from @bob arrives for the key "@alice:c1.a:b.p1.todos.demo@bob"
    Then the collection emits no event

  @dos
  Scenario: Given a notification from @bob with metadata whose key's item id is empty, when it reaches the collection, then nothing is written to the local keystore
    Given a collection "todos.demo" of @alice
    When a notification from @bob carrying metadata arrives for the key "@alice:.todos.demo@bob"
    Then nothing is written to @alice's local keystore
    And a warning is logged that shows the id "" and the owner @bob

  @dos
  Scenario: Given a notification from @bob with metadata whose key's item id contains ":", when it reaches the collection, then a warning shows the id and @bob and nothing is written to the local keystore
    Given a collection "todos.demo" of @alice
    When a notification from @bob carrying metadata arrives for the key "@alice:x:y.todos.demo@bob"
    Then a warning is logged that shows the id "x:y" and the owner @bob
    And nothing is written to @alice's local keystore

  @dos
  Scenario: Given a data event for a key @bob shares whose item id contains a tab, when it reaches the collection, then no event is emitted
    Given a collection "todos.demo" of @alice reading data events
    When a data event arrives for the key "cached:@alice:" followed by "x", a tab, "y" and ".todos.demo@bob"
    Then the collection emits no event

  @dos
  Scenario: Given a notification from @bob whose key's item id starts with "_", when it reaches the collection, then an update event with that id is emitted
    Given a collection "todos.demo" of @alice
    When a notification from @bob arrives for the key "@alice:_x.todos.demo@bob"
    Then the collection emits an update event with the id "_x" and the owner @bob

  Scenario: Given a notification from @bob whose key's item id is 65 characters, when it reaches the collection, then an update event with that id is emitted
    Given a collection "todos.demo" of @alice
    When a notification from @bob arrives for a key whose item id is 65 "a" characters
    Then the collection emits an update event with that id and the owner @bob

  @dos
  Scenario: Given a notification from @bob whose key's item id is "Zz", when it reaches the collection, then an update event with the id "zz" is emitted
    Given a collection "todos.demo" of @alice
    When a notification from @bob arrives for the key "@alice:Zz.todos.demo@bob"
    Then the collection emits an update event with the id "zz" and the owner @bob

  @dos
  Scenario: Given a query watch over an item @bob shares under the id "zz", when notifications from @bob arrive for "Zz" and "ZZ", then every snapshot holds that item once
    Given a collection "todos.demo" of @alice holding an item @bob shares under the id "zz", with a query watch listening
    When notifications from @bob arrive for the keys "@alice:Zz.todos.demo@bob" and "@alice:ZZ.todos.demo@bob"
    Then every snapshot the watch emits holds the item "zz" of @bob once

  @dos
  Scenario: Given getDescendant has returned an item through the ancestor id "abcd", when it is called with the ancestor id "ABCD", then it opens no further sub-collection
    Given a collection "todos.demo" of @alice holding an item "abcd" with an item "c1" in its sub-collection "comments"
    And getDescendant has returned "c1" for the ancestor "abcd" of @alice in "comments"
    When getDescendant is called for the ancestor "ABCD" of @alice in "comments" and the item "c1"
    Then it returns "c1"
    And no further notification subscription is opened

  @dos
  Scenario: Given getDescendant has returned an item through the subName "comments", when it is called with the subName "COMMENTS", then it opens no further sub-collection
    Given a collection "todos.demo" of @alice holding an item "p1" with an item "c1" in its sub-collection "comments"
    And getDescendant has returned "c1" for the ancestor "p1" of @alice in "comments"
    When getDescendant is called for the ancestor "p1" of @alice in "COMMENTS" and the item "c1"
    Then it returns "c1"
    And no further notification subscription is opened

  @dos
  Scenario: Given a notification from @bob whose key has two segments before the namespace, when it reaches the collection, then no event is emitted
    Given a collection "todos.demo" of @alice
    When a notification from @bob arrives for the key "@alice:a.b.todos.demo@bob"
    Then the collection emits no event
    And a warning is logged that shows "a.b" and the owner @bob

  @dos @forgery
  Scenario: Given a notification from @bob whose key's item id is "x@bob", when it reaches the collection, then no event is emitted
    Given a collection "todos.demo" of @alice
    When a notification from @bob arrives for the key "@alice:x@bob.todos.demo@bob"
    Then the collection emits no event

  @dos @forgery
  Scenario: Given a notification from @bob whose key's item id is "x@alice:y", when it reaches the collection, then no event is emitted
    Given a collection "todos.demo" of @alice
    When a notification from @bob arrives for the key "@alice:x@alice:y.todos.demo@bob"
    Then the collection emits no event
