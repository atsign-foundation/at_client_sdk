Feature: The todos examples interoperate at pqActive

  The CLI todos example (collections_todos.dart) and the Flutter todos app
  both run at PqPosture.pqActive in namespace todos.demos. A todo one shares
  with the other's atSign is sealed to the recipient's namespace key, and
  read there.

  Races: each app's first write waits for its own start-up to seed its
  namespace key, as every pqActive client's does. A share needs the
  recipient's key, so each shares only once the readiness check reports the
  other's key published.
  Replay, DoS: none arise beyond what any pqActive share has.
  Forgery and impersonation: a share is sealed to the recipient's namespace
  key, whose advertisement is verified against its publisher's _apsk;
  neither example carries a key or a secret in its source.

  Scenario: A todo shared between the CLI example and the Flutter app at pqActive is read on the other side, both ways
    Given the CLI todos example as @alice and the Flutter todos app as @bob, both at pqActive and online
    When @alice shares a todo with @bob from the CLI example, and @bob shares one with @alice from the Flutter app
    Then each app lists the other's todo with its title intact
