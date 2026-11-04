Feature: At pqActive, a write its client's start-up has yet to give a namespace key waits for it

  A pqActive client's start-up mints and publishes the namespace keys for the
  namespaces it may write in: its preference namespace, or an enrollment's
  writable grants. Start-up runs after the client opens, so a write to the
  client's own atSign made at once can find no key yet. Such a write waits
  for start-up's seeding step to finish, then works out its start level and
  resolves again; if there is still no key it refuses as before. A write
  waits when the atServer has answered that no key is published and start-up
  will seed a namespace that covers the key, or when the key it found is
  broader than a namespace start-up has said it will seed covering the key.
  A write that holds no private for its namespace's current generation
  waits, within the same bound, while start-up's ask to the atSign's other
  enrollments for that generation is outstanding. A share does not wait: it is sealed to the recipient's key, as
  pq_share_level.feature has it. Reads do not seal, and are unchanged.

  Races: a write never mints to find its own value's key; only start-up
  does, once per namespace, and the write waits for it. Two write paths
  still mint by design, through the same mint lock as start-up: a share
  whose sender holds no key at the recipient's level mints one for the
  sender's own copy, and a write to the atSign's own key mints a new
  generation when the rotation policy asks for one. After the step a
  waiting write resolves whatever start-up published or adopted, including a
  key another enrollment minted first. A write after the step has finished
  does not wait.
  Replay: nothing new is written or read, so none arise.
  DoS: a waiting write holds no connection and makes no request while it
  waits; every waiting write shares one signal; each waits at most 30
  seconds; a write with no atServer, or in a namespace start-up will not
  seed, does not wait; stop ends every wait at once. A write waits at most
  30 s whatever start-up does; no new asks are sent.
  Forgery and impersonation: what a write seals to, and for whom, is
  unchanged; waiting only delays when the existing rule is applied. A key's
  name cannot make start-up mint, since start-up mints only the namespaces
  this client is authorised for.

  Scenario: A write in the client's namespace right after it opens waits for start-up's key
    Given a pqActive client in namespace todos.demos whose start-up has not yet published a todos.demos key
    When it puts AtKey.fromString("x.todos.demos@alice") right after opening
    Then the put completes once start-up has published the todos.demos key, sealed under that key

  Scenario: An enrollment's write in a namespace it is granted waits the same way
    Given a pqActive enrollment granted todos.demos rw whose start-up has not yet published a todos.demos key
    When it puts a value in todos.demos right after opening
    Then the put completes once start-up has published the todos.demos key, sealed under that key

  Scenario: A write in a namespace start-up will not seed refuses without waiting for a mint
    Given a pqActive client in todos.demos whose start-up has not finished, granted nothing covering other.app
    When it puts a value in other.app
    Then the write throws NamespaceKeyUnavailableException naming other.app without waiting for a key to be minted

  Scenario: A write after start-up has finished seeding refuses at once
    Given a pqActive client whose start-up has finished seeding without publishing a todos.demos key
    When it puts a value in todos.demos
    Then the write throws NamespaceKeyUnavailableException naming todos.demos at once

  Scenario: A client whose start-up seeds nothing refuses at once
    Given a pqActive client with seedNamespaceKeys off, or with no key source
    When it puts a value in its namespace before any key is published there
    Then the write throws NamespaceKeyUnavailableException at once

  Scenario: The wait is bounded
    Given a pqActive client whose start-up has not published a todos.demos key 30 seconds after a write began waiting
    When the 30 seconds pass
    Then the write throws NamespaceKeyUnavailableException naming todos.demos and saying start-up has not yet published its key

  Scenario: A first write with no atServer ends at once
    Given a pqActive client that has never held a todos.demos key, with no atServer reachable
    When it puts a value in todos.demos
    Then the write fails at once, naming the todos.demos namespace key and the unreachable atServer, as it does today

  Scenario: A write the offline restart already allows does not wait
    Given a client restarted with no atServer reachable, holding and having verified its todos.demos key
    When it puts a value in todos.demos
    Then the write succeeds locally without waiting for start-up

  Scenario: Stopping the client ends a waiting write
    Given a write waiting for start-up to publish the todos.demos key
    When the client is stopped
    Then the write throws StoppedException at once

  Scenario: Writes waiting together share one seeding
    Given several writes in todos.demos waiting for start-up
    When start-up publishes the todos.demos key
    Then every write is sealed under that one key, start-up minted it once, and no write minted or asked for a mint

  Scenario: A seeding that fails ends the wait with its reason
    Given a write waiting for start-up to publish the todos.demos key
    When start-up's seeding of todos.demos fails
    Then the write throws NamespaceKeyUnavailableException naming todos.demos and carrying start-up's reason

  Scenario: A start-up that cannot read its grants ends the wait with its reason
    Given a write waiting for start-up, which has yet to say which namespaces it seeds
    When start-up cannot read its grants
    Then the write throws NamespaceKeyUnavailableException carrying start-up's reason

  Scenario: A key another enrollment minted first is the one a waiting write seals to
    Given a write waiting for start-up, and another enrollment of alice's publishing todos.demos's key first
    When start-up adopts that key
    Then the write is sealed under the adopted key

  Scenario: A write that finds only a broader key waits for the namespace start-up will seed
    Given start-up will seed todos.demos and the search finds only demos published
    When a write under todos.demos is made before seeding finishes
    Then it waits for seeding and seals at todos.demos

  Scenario: A wait for a narrower namespace that runs out resolves again
    Given start-up will seed todos.demos and the search finds only demos published
    When the wait runs out before seeding finishes
    Then the write resolves again and seals at todos.demos once that is published

  Scenario: A write before start-up has said what it seeds does not wait for a narrower namespace
    Given start-up has not yet said what it seeds, and the search finds demos published
    When a write under todos.demos is made
    Then it does not wait

  Scenario: An enrollment's write before start-up reads its grants waits for the namespace its keyfile recorded
    Given an APKAM enrollment whose keyfile records todos.demos, before start-up reads its grants
    When a write finds only demos
    Then the write waits for seeding

  Scenario: An enrollment whose keyfile records no grants does not wait before start-up reads them
    Given an APKAM enrollment whose keyfile records no grants, before start-up reads its grants
    When a write finds only demos
    Then the write does not wait

  Scenario: A namespace the grant read adds is waited for
    Given start-up said it seeds todos.demos, from the grants its keyfile recorded
    When its grant read adds other.app
    Then a write in other.app waits for seeding

  Scenario: A write whose key is published as the wait runs out goes ahead
    Given a write waiting for start-up's seeding step
    When its key is published but the step has not finished as the wait runs out
    Then the write goes ahead under that key

  Scenario: A write right after opening completes once start-up has seeded, and a share at once
    Given bob's client, whose start-up seeded his todos.demos key beforehand, and alice's client just opened
    When alice puts a value in todos.demos and shares one with bob at once
    Then both complete, sealed under alice's and bob's todos.demos keys

  Scenario: A write that misses while its start-up ask is outstanding waits for the answer
    Given an enrollment of @alice that holds no private for the current generation of todos, whose start-up has asked the other enrollments for it
    When it writes in todos before an answer is filed
    Then the write waits, at most 30 seconds, and succeeds once a holder's answer is filed; with no answer by then it throws naming the generation as not yet conveyed

  Scenario: A write made before start-up asks for its key's private waits for the ask and its answer
    Given an enrollment missing the current generation's private, and its start-up yet to ask for it
    When it writes
    Then the write waits for start-up's ask and its answer, at most 30 seconds in all, and goes on
