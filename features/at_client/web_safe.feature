Feature: at_client 4.0.0 builds for the web, with a pure-Dart memory storage

  at_client.dart reaches no dart:io, so a program built for the browser can
  import it. The client stays local-first: it keeps its keystore, sync queue
  and watermarks in the AtClientStorage it is given. memory.dart's storage is
  pure Dart and holds everything in memory, so a web build can use it; Hive
  and SQLite stay native. What needs a filesystem or a TLS socket comes from
  at_client_io.dart.

  Races: the memory storage keeps the claim rules every storage has, so one
  client holds it at a time, and each instance is a store of its own, so two
  clients never share one by accident.
  Replay: a client on the memory storage starts each process with no
  notification watermark and resumes from when its notification service
  started, so nothing is delivered twice; what was sent while no process ran
  is not delivered, until a durable browser storage exists.
  DoS: the memory storage holds what the atSign syncs to it, as the native
  storages do on disk; nothing new is read from the network.
  Forgery and impersonation: the storage is claimed by (atSign, enrollment)
  as every storage is, values stay ciphertext, and the io split moves no
  authentication path.

  Scenario: at_client.dart reaches no platform library
    Given at_client 4.0.0
    When wasm_shakedown walks at_client.dart and memory.dart
    Then neither reaches dart:io, directly or through another package
    And each compiles with dart2wasm

  Scenario: A web program can build a client on the memory storage
    Given a program that opens an atSign from in-memory keys on the memory storage, then puts, gets, deletes and lists keys
    When it is compiled with dart2wasm
    Then it compiles, and nothing it reaches imports dart:io

  Scenario: The memory storage meets the storage contract
    Given the memory storage
    When the storage contract the Hive and SQLite storages pass runs against it
    Then it passes

  Scenario: A client on the memory storage works local-first
    Given a client on the memory storage that has synced with its atServer
    When it puts a value and reads it back
    Then the read is answered from the memory storage, and the value reaches the atServer by sync

  Scenario: Two memory storages share nothing
    Given two clients of the same atSign, each on its own memory storage
    When one puts a value
    Then the other's storage does not hold it until sync brings it there

  Scenario: Nothing outlives a memory storage
    Given a client on the memory storage
    When it stops and its storage closes
    Then nothing was written to disk, and a new memory storage starts empty

  Scenario: A native program keeps what it had
    Given a native program that reads its keys from a file and connects over TLS
    When it imports at_client_io.dart beside at_client.dart
    Then FileAtKeysIo and secureSocketLookUps are there, and it opens, syncs and notifies as it did on at_client 3

  Scenario: Every client is given its storage
    Given at_client 4.0.0
    When an app opens an atSign without passing a storage
    Then the app does not compile until it names one

  Scenario: No deprecation promises removal in 4.0
    Given at_client 4.0.0
    When its library's deprecations are read
    Then none promises removal in 4.0, in v4 or at the next major
