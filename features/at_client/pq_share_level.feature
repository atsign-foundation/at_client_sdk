Feature: At pqActive, a share is sealed to the most specific namespace key the recipient advertises

  A share is a put or notify of a key whose owner, its sharedWith, is not the
  writer's atSign. Its levels are every namespace the key's full name (key and
  namespace, folded) ends with after a dot, most specific first, without the
  reserved ones; the full name itself is never a level, since its first label
  is the record's own id. A share is sealed to the recipient's key at the most
  specific level the recipient advertises. What the writer holds does not
  enter into it, and a share does not wait for the writer's start-up. A
  program can instead require one namespace with sealToNamespace: the share is
  sealed to the recipient's key there or not at all, and canSealTo answers
  beforehand whether it can be. When nothing the recipient advertises fits, the
  share falls back to legacy where the posture and allowLegacyCryptoFallback
  allow, and is refused otherwise; it never falls back to a broader namespace
  key. A NoPorts client, for instance, seals to a daemon's key at
  <device>.sshnp and treats its absence as a daemon that is not PQ-capable.
  A key the recipient advertises, once found, is used for 15 minutes without
  a lookup, and for up to 15 minutes more while its atServer cannot be
  reached; one its atServer no longer has is dropped at once. A level found
  missing is remembered for 30 seconds, and decides without a lookup until
  then. canSealTo asks afresh past a remembered miss, and uses a found key.
  Writes to the writer's own atSign are unchanged.

  Races: the level is chosen at each share from the recipient's advertisements
  as cached and fetched then. A share that races the recipient publishing a
  narrower level seals at the broader one, which every holder of that key
  opens. The writer's own copy goes through the mint lock start-up uses.
  Replay: nothing new is sent beyond lookups on the writer's own authenticated
  connection; what is sealed, and the owner and key name bound into each
  envelope, are unchanged.
  DoS: at most one batch of lookups per share, of the levels neither found in
  the last 15 minutes nor found missing in the last 30 seconds, so a recipient
  is asked about the same levels at most once in 30 seconds; a key name of at
  most 248 characters has at most 123 levels; no share waits.
  Forgery and impersonation: only the recipient's enrollments and atServer can
  publish its advertisements; every advertisement sealed to is verified as
  signed by an enrollment of the recipient whose _apsk its atServer serves; a
  more specific advertisement that does not verify refuses the share rather
  than leaving it to seal to a broader one; a required namespace must be one
  the key's name ends with.

  Scenario: The most specific key the recipient advertises seals the share
    Given bob advertising keys for demos and todos.demos, and alice holding no namespace private
    When alice shares x.todos.demos with bob, built from its string form
    Then it is sealed under bob's todos.demos key

  Scenario: The writer's own namespaces do not decide a share's level
    Given alice holding a todos.demos private, and bob advertising a key for demos only
    When alice shares x.todos.demos with bob
    Then it is sealed under bob's demos key

  Scenario: Every level of the key's name is walked
    Given bob advertising keys for notes.todos.demos and todos.demos
    When alice shares note1.t42.notes.todos.demos with bob
    Then it is sealed under bob's notes.todos.demos key

  Scenario: A name that only ends with an advertised namespace's letters is not covered
    Given bob advertising a key for demos only
    When alice shares x.mydemos with bob at pqActive
    Then nothing is sealed under bob's demos key, and the share throws NamespaceKeyUnavailableException

  Scenario: A recipient advertising nothing for the name refuses a share at pqActive
    Given bob advertising no key at any level of x.todos.demos
    When alice shares x.todos.demos with bob at pqActive
    Then the write throws NamespaceKeyUnavailableException naming bob and todos.demos, at once

  Scenario: Below pqActive with the fallback allowed, such a share is sealed with legacy encryption
    Given bob advertising no key at any level of x.todos.demos, and alice below pqActive with allowLegacyCryptoFallback
    When alice shares x.todos.demos with bob
    Then it is sealed with legacy encryption, and a warning names the fallback

  Scenario: A share does not wait for the writer's start-up
    Given alice's client right after opening, before its start-up has published any key, and bob advertising todos.demos
    When it shares x.todos.demos with bob
    Then it is sealed under bob's todos.demos key without waiting

  Scenario: A notification does not wait for the writer's start-up
    Given alice's client right after opening, before its start-up has published any key, and bob advertising todos.demos
    When it notifies bob of x.todos.demos
    Then the notification is sealed under bob's todos.demos key without waiting

  Scenario: The recipient's levels are looked up in one batch
    Given nothing of bob's cached, and bob advertising keys for demos and todos.demos
    When alice shares note1.t42.notes.todos.demos with bob
    Then her client sends one batch of lookups, one for each level, and verifies only bob's todos.demos advertisement

  Scenario: A recipient's key, once found, is used for 15 minutes without a lookup
    Given a share that found bob's todos.demos key
    When alice shares x.todos.demos with bob again within 15 minutes
    Then it is sealed under that key, and nothing is looked up

  Scenario: Past 15 minutes, a key whose atServer cannot be reached is used for up to 15 minutes more
    Given bob's todos.demos key found more than 15 minutes ago, and bob's atServer out of reach
    When alice shares x.todos.demos with bob
    Then it is sealed under the key found before

  Scenario: Past 15 minutes, a key its atServer no longer has is not used
    Given bob's todos.demos key found more than 15 minutes ago and since removed, and his demos key still advertised
    When alice shares x.todos.demos with bob
    Then it is sealed under bob's demos key

  Scenario: A recipient advertising nothing for a name is remembered for 30 seconds
    Given a share of x.todos.demos refused because bob advertised nothing for it, and bob since publishing todos.demos
    When alice shares x.todos.demos with bob within 30 seconds, at pqActive
    Then the share is refused without a lookup

  Scenario: After 30 seconds, a recipient that advertised nothing is asked again
    Given a share of x.todos.demos refused because bob advertised nothing for it, and bob since publishing todos.demos
    When alice shares x.todos.demos with bob after 30 seconds
    Then her client looks bob's levels up again, and it is sealed under bob's todos.demos key

  Scenario: Within 30 seconds of a narrower miss, the broader key is used without a lookup
    Given a share of x.device1.sshnp sealed under bob's sshnp key because bob advertised nothing at device1.sshnp, and bob since publishing device1.sshnp
    When alice shares x.device1.sshnp with bob within 30 seconds
    Then it is sealed under bob's sshnp key, and nothing is looked up

  Scenario: After 30 seconds, a newly published narrower key is used
    Given a share of x.device1.sshnp sealed under bob's sshnp key because bob advertised nothing at device1.sshnp, and bob since publishing device1.sshnp
    When alice shares x.device1.sshnp with bob after 30 seconds
    Then her client looks device1.sshnp up once, and it is sealed under bob's device1.sshnp key

  Scenario: canSealTo asks afresh, whatever a share found missing
    Given a share that found bob's device1.sshnp missing, and bob since publishing device1.sshnp
    When the program asks canSealTo for bob and device1.sshnp within 30 seconds
    Then device1.sshnp is looked up, and the answer is true

  Scenario: canSealTo answers from a key a share found
    Given a share that found bob's todos.demos key within the last 15 minutes
    When the program asks canSealTo for bob and todos.demos
    Then the answer is true, and nothing is looked up

  Scenario: The windows are 15 minutes for a found key, 15 more out of reach, and 30 seconds for a miss
    Given a client's default key ring and resolver
    Then a found key is kept 15 minutes, out of reach 15 minutes more, and a share's miss 30 seconds

  Scenario: A more specific advertisement that does not verify refuses the share
    Given bob's record at todos.demos not signed by any enrollment of bob's, and a key of bob's for demos that verifies
    When alice shares x.todos.demos with bob
    Then the share throws AtSigningVerificationException, and nothing is sealed under bob's demos key

  Scenario: A required namespace is sealed to without walking
    Given bob advertising keys for demos and todos.demos
    When alice shares x.todos.demos with bob, requiring the namespace demos
    Then it is sealed under bob's demos key, and no other level is looked up

  Scenario: A required namespace the recipient has not advertised refuses at pqActive
    Given bob advertising a key for demos only
    When alice shares x.todos.demos with bob at pqActive, requiring the namespace todos.demos
    Then the write throws NamespaceKeyUnavailableException naming bob and todos.demos, and nothing is sealed under bob's demos key

  Scenario: A required namespace the recipient has not advertised falls back to legacy where allowed
    Given bob advertising a key for demos only, and alice below pqActive with allowLegacyCryptoFallback
    When alice shares x.todos.demos with bob, requiring the namespace todos.demos
    Then it is sealed with legacy encryption, never under bob's demos key

  Scenario: A required namespace the key's name does not end with is refused before any lookup
    When alice shares x.todos.demos with bob, requiring the namespace other.app
    Then the write throws ArgumentError, and nothing is looked up

  Scenario: A required namespace on a write to the writer's own atSign is refused
    When alice puts x.todos.demos for herself, requiring the namespace todos.demos
    Then the write throws ArgumentError

  Scenario: A program can ask whether it can seal to a namespace
    Given bob advertising a key for device1.sshnp
    When the program asks canSealTo for bob and device1.sshnp
    Then the answer is true

  Scenario: A broader key does not answer canSealTo
    Given bob advertising a key for sshnp only
    When the program asks canSealTo for bob and device1.sshnp
    Then the answer is false

  Scenario: canSealTo throws when the answer cannot be established
    Given bob's atServer cannot be reached
    When the program asks canSealTo for bob and device1.sshnp
    Then it throws rather than answering false

  Scenario: The writer's copy goes to her own key covering the recipient's level
    Given bob advertising todos.demos, and alice holding a key for demos
    When alice shares x.todos.demos with bob
    Then the content key is also conveyed to alice's demos key, and nothing is minted

  Scenario: Holding nothing covering that level, the writer mints her key there
    Given bob advertising todos.demos, and alice holding no key covering it, in namespace todos.demos
    When alice shares x.todos.demos with bob
    Then alice's todos.demos key is minted and carries her copy

  Scenario: The writer mints nothing at a level below her own namespace
    Given bob advertising t42.notes.todos.demos, and alice in namespace todos.demos holding no key covering it
    When alice shares note1.t42.notes.todos.demos with bob
    Then it is sealed under bob's t42.notes.todos.demos key, nothing is minted, the share goes without her copy, and a warning says why
