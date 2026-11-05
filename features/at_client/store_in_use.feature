Feature: A store another process holds is refused, naming where it is

  A Hive store is held by one process at a time: its files are locked while
  it is open. A second process that opens a client on the same location is
  refused with AtStorageInUseException, which names the location, rather
  than with the raw lock failure.

  Races: the operating system's file lock decides which process holds the
  store; the refusal changes only what the second one is told.
  Replay and DoS: none arise; nothing is sent, and the refusal comes at once.
  Forgery and impersonation: none arise; the refusal names only the store's
  location, which the program gave.

  Scenario: A second process on a store in use is refused naming the store
    Given a process holding a Hive store open
    When a second process opens a client on the same location
    Then the open throws AtStorageInUseException naming the location
