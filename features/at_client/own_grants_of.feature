Feature: A client reads its own enrollment's grants through the package library

  ownGrantsOf(atClient) is exported from package:at_client/at_client.dart, so
  a platform package or an app reads the namespaces and access its client's
  own enrollment holds without importing from src/. It answers null for the
  primary enrollment, whose *:rw limits nothing, and otherwise a map from
  namespace to access, with * and __manage among the keys when granted.

  Races: none arise; it reads the enrollment list once and changes nothing.
  Replay: none arise; nothing sent or accepted changes.
  DoS: none arise; one list read, filtered by the client's own enrollment id.
  Forgery and impersonation: none arise; it selects the record by the
  client's own enrollment id and the atServer stays the authority on every
  operation.

  Scenario: A client with an approved enrollment reads its grants
    Given a client whose enrollment is granted {buzz: rw, __manage: rw, *: r}
    When it calls ownGrantsOf
    Then the answer is {buzz: rw, __manage: rw, *: r}

  Scenario: The primary enrollment has no grants to read
    Given a client with no enrollment id, or the primary one
    When it calls ownGrantsOf
    Then the answer is null and no enrollment is listed

  Scenario: An enrollment the atServer does not list answers an empty map
    Given a client whose enrollment id is absent from the atServer's list
    When it calls ownGrantsOf
    Then the answer is an empty map

  Scenario: The function is nameable from the package library
    Given a file that imports only package:at_client/at_client.dart
    When it names ownGrantsOf
    Then it compiles
