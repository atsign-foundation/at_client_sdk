Feature: At pqActive, a share is sealed to the most specific namespace key the recipient advertises

  A share is a put or notify of a key whose owner, its sharedWith, is not the
  writer's atSign. Its levels are every namespace the key's full name (key and
  namespace, folded) ends with after a dot, most specific first, without the
  reserved ones; the full name itself is never a level, since its first label
  is the record's own id. A share is sealed to the recipient's key at the most
  specific level the recipient advertises, and a share that finds none is
  refused naming the most specific level. What the writer holds does not
  enter into it, and a share does not wait for the writer's start-up. A
  program can instead require one namespace with sealToNamespace: the share is
  sealed to the recipient's key there or not at all, and canSealTo answers
  beforehand whether it can be. When nothing the recipient advertises fits, the
  share falls back to legacy where the posture and allowLegacyCryptoFallback
  allow, and is refused otherwise; it never falls back to a broader namespace
  key. A NoPorts client, for instance, seals to a daemon's key at
  <device>.sshnp and treats its absence as a daemon that is not PQ-capable.
  A program serving such a mixed fleet runs one of two shapes. The main one
  is a posture that writes post-quantum by default and allows legacy
  encryption, PqPosture.pqActive.copyWith(disallowLegacyEncryption: false),
  with allowLegacyCryptoFallback: every send requires its <device>.sshnp, and
  a daemon advertising nothing there gets legacy through the fallback. The
  other is pqReady with allowLegacyCryptoFallback, which writes legacy by
  default: per send, the program asks canSealTo, and requests the
  namespace-key provider with sealToNamespace when it answers true, and
  legacy otherwise.
  A key the recipient advertises, once found, is used for 15 minutes without
  a lookup, and for up to 15 minutes more, with a warning, while a re-fetch
  fails with anything but a not-found; one its atServer no longer has is
  dropped at once. A level found missing is remembered for 30 seconds, and
  decides without a lookup until then. Only a not-found is a miss: any other
  failure at a level stops the walk there. canSealTo asks afresh past a
  remembered miss, and uses a found key. It never throws: it answers false,
  with a warning naming the cause, when the recipient's atServer cannot be
  reached or the advertisement there does not verify.
  Writes to the writer's own atSign are unchanged.

  Races: the level is chosen at each share from the recipient's advertisements
  as cached and fetched then. A share that races the recipient publishing a
  narrower level seals at the broader one, which every holder of that key
  opens. A key withdrawn between canSealTo and the send is treated as never
  advertised: legacy where the fallback is allowed, refused otherwise. The
  writer's own copy is sealed to a key she already holds; nothing is minted
  for it, so a share made before her start-up has published that key goes
  without the copy, and the first share after it has cuts a fresh content key
  with one.
  Replay: nothing new is sent beyond lookups on the writer's own authenticated
  connection; what is sealed, and the owner and key name bound into each
  envelope, are unchanged.
  DoS: at most one batch of lookups per share, of the levels neither found in
  the last 15 minutes nor found missing in the last 30 seconds, so a recipient
  is asked about the same levels at most once in 30 seconds, and a share that
  requires a namespace asks about that one alone; a miss is forgotten after
  30 seconds, so a sender remembers only the levels it found missing in that
  time; a key name of at most 248
  characters has at most 123 levels; an advertisement that does not verify is
  not cached, so only the writer's own next write asks again; no share waits.
  Forgery and impersonation: only the recipient's enrollments and atServer can
  publish its advertisements; every advertisement sealed to is verified as
  signed by an enrollment of the recipient whose _apsk its atServer serves; a
  more specific advertisement that does not verify refuses the share rather
  than leaving it to seal to a broader one; a required namespace must be one
  the key's name ends with. canSealTo answers false for an advertisement that
  does not verify, so a program that sends legacy on false does so for a
  record only the recipient's atServer can serve, with a warning naming it.

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

  Scenario: A share to a recipient advertising nothing is sealed with legacy encryption
    Given bob advertising no key at any level of x.todos.demos, and alice at pqActive allowing legacy encryption, with allowLegacyCryptoFallback
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

  Scenario: A found advertisement is served from the cache for 15 minutes
    Given bob's todos.demos advertisement fetched and verified less than 15 minutes ago
    When alice shares x.todos.demos with bob again
    Then no lookup is sent for todos.demos, and it is sealed under that key

  Scenario: An advertisement the re-fetch cannot refresh is served for 15 minutes more, then not at all
    Given bob's todos.demos advertisement fetched 15 minutes ago, and alice's atServer answering the re-fetch with a failure that is not a not-found
    When alice shares within the next 15 minutes
    Then it is sealed under the cached key, with a warning; after those 15 minutes the share throws that failure, and does not fall back to legacy

  @race
  Scenario: A key fresh when the walk began seals the share, even if it expires during the lookup
    Given bob advertising demos only, alice's copy of it fresh, and the batch for todos.demos answered after that copy has expired
    When alice shares x.todos.demos with bob
    Then only todos.demos is asked, and the share is sealed under bob's demos key

  Scenario: A batch entry that is not a record fails that level, which seals to its cached key within the stale grace
    Given alice holding bob's todos.demos advertisement past 15 minutes, and the batch answering that entry with data that is not a record
    When alice shares x.todos.demos with bob
    Then it is sealed under the cached key, with a warning

  Scenario: A share by a client with no atServer connection throws an AtException
    Given alice's client with no atServer connection
    When alice shares x.todos.demos with bob
    Then it throws an AtException rather than an Error

  Scenario: A not-found ends a cached advertisement at once
    Given bob's todos.demos advertisement cached, and bob's atServer now answering not-found for it
    When alice shares after the cache's 15 minutes
    Then nothing is sealed under the old key; the walk goes on to demos

  Scenario: A full miss is remembered for 30 seconds
    Given bob advertising nothing at any level of x.todos.demos, and alice's walk having found that less than 30 seconds ago
    When alice shares it again
    Then no lookup is sent, and the share is refused, or falls back, as the scenarios for a recipient advertising nothing say; the first share after 30 seconds walks again

  Scenario: A miss at a narrower level is remembered for 30 seconds
    Given bob advertising demos only, and alice's walk having missed todos.demos less than 30 seconds ago
    When alice shares x.todos.demos
    Then todos.demos is not looked up, and it is sealed under the cached demos key

  Scenario: A narrower key published inside the miss window is used by the first write after it
    Given bob advertising demos only, alice's walk having missed todos.demos, and bob publishing todos.demos within the next 30 seconds
    When alice shares before the 30 seconds are up, and once more after
    Then the first share is sealed under demos, and the second looks todos.demos up and is sealed under it

  Scenario: A batch entry that fails for any reason but not-found stops the walk
    Given bob advertising demos, and alice's atServer answering the todos.demos entry with an error that is not a not-found
    When alice shares x.todos.demos
    Then the share throws that failure, nothing is sealed under demos, and todos.demos is not remembered as a miss

  @race
  Scenario: A share requiring a namespace canSealTo has since found is sealed there
    Given a share requiring device1.sshnp refused because bob advertised nothing there, and bob since publishing it
    When canSealTo answers true for bob and device1.sshnp, and alice shares requiring it within 30 seconds
    Then the share is sealed under bob's device1.sshnp key

  @dos
  Scenario: Misses older than 30 seconds are forgotten
    Given shares that found levels of bob's missing more than 30 seconds ago
    When alice shares again
    Then only the levels this share found missing are remembered

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
    Given bob advertising a key for demos only, and alice at pqActive
    When alice shares x.todos.demos with bob, requiring the namespace todos.demos
    Then the write throws NamespaceKeyUnavailableException naming bob and todos.demos, nothing is sealed under bob's demos key, and demos is not looked up

  Scenario: A cached broader advertisement does not satisfy a required namespace
    Given bob's demos advertisement fresh in alice's cache from an earlier share, and nothing advertised at todos.demos
    When alice shares x.todos.demos with bob at pqActive, requiring the namespace todos.demos
    Then only todos.demos is looked up, the write throws NamespaceKeyUnavailableException naming bob and todos.demos, and the cached demos key seals nothing

  Scenario: A required namespace the recipient has not advertised falls back to legacy where allowed
    Given bob advertising a key for demos only, and alice at pqActive allowing legacy encryption, with allowLegacyCryptoFallback
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

  Scenario: canSealTo answers false, with a warning, when the recipient's atServer cannot be reached
    Given bob's atServer cannot be reached
    When the program asks canSealTo for bob and device1.sshnp
    Then the answer is false, and a warning names bob, device1.sshnp and the failure

  Scenario: canSealTo never throws, whatever asking fails with
    Given a key ring whose lookup fails with an Error rather than an Exception
    When the program asks canSealTo for bob and device1.sshnp
    Then the answer is false, and a warning names bob, device1.sshnp and the failure

  Scenario: canSealTo answers false, with a warning, when the advertisement does not verify
    Given bob's record at todos.demos not signed by any enrollment of bob's
    When the program asks canSealTo for bob and todos.demos
    Then the answer is false, a warning says the advertisement does not verify, and the next canSealTo looks it up again

  Scenario: A mixed fleet: each device's notification is sealed under its own namespace key, or sent with legacy encryption
    Given bob advertising keys for d1.sshnp and sshnp but not d2.sshnp, and alice at pqActive allowing legacy encryption, with allowLegacyCryptoFallback
    When alice notifies bob of npt_request.d1.sshnp requiring d1.sshnp, and of npt_request.d2.sshnp requiring d2.sshnp
    Then the first is sealed under bob's d1.sshnp key, the second is sent with legacy encryption, and bob's sshnp key seals neither

  Scenario: At pqReady, a share that requests no provider is sealed with legacy encryption, and no namespace key is looked up
    Given bob advertising a key for d1.sshnp, and alice at pqReady with allowLegacyCryptoFallback
    When alice notifies bob of npt_request.d1.sshnp, requesting no provider
    Then it is sealed with legacy encryption, and nothing is looked up

  Scenario: A mixed fleet at pqReady: canSealTo picks the namespace-key provider for one device and legacy for the other
    Given bob advertising keys for d1.sshnp and sshnp but not d2.sshnp, and alice at pqReady with allowLegacyCryptoFallback
    When alice asks canSealTo for each device's namespace, and notifies under the namespace-key provider requiring it where the answer is true, and under legacy otherwise
    Then canSealTo answers true for d1.sshnp and false for d2.sshnp, npt_request.d1.sshnp is sealed under bob's d1.sshnp key, npt_request.d2.sshnp is sent with legacy encryption, and bob's sshnp key seals neither

  @race
  Scenario: At pqReady, a key withdrawn between canSealTo and the send goes with legacy encryption, with a warning
    Given canSealTo answered true for bob and d1.sshnp, and bob since withdrawing that key while still advertising sshnp
    When alice notifies bob of npt_request.d1.sshnp under the namespace-key provider, requiring d1.sshnp
    Then it is sent with legacy encryption, a warning names the fallback, and bob's sshnp key seals nothing

  Scenario: The writer's copy is sealed to her key at her own level
    Given bob advertising notes.todos.demos, and alice holding a key for todos.demos
    When alice shares x.notes.todos.demos with bob
    Then her copy is named at notes.todos.demos and sealed to her todos.demos key, which its ns names, and nothing is minted

  Scenario: Before her start-up has published her key, a share goes without her copy, with a warning
    Given bob advertising todos.demos, and alice's start-up still to publish her todos.demos key
    When alice shares x.todos.demos with bob
    Then it is sealed under bob's key at once, she has no copy, nothing is minted, and a warning says her start-up has not yet published the key

  Scenario: The first share after her start-up publishes her key gets a fresh content key with her copy
    Given a share made before alice's start-up published her todos.demos key, and that key since published
    When alice shares y.todos.demos with bob
    Then a fresh content key is cut, and her copy of it is sealed to her todos.demos key

  Scenario: A value no namespace she holds covers gets no copy, with a warning
    Given bob advertising other.app, and alice holding a key for todos.demos only
    When alice shares x.other.app with bob
    Then she has no copy, nothing is minted, and a warning names the value

  Scenario: Bob's key at a level broader than hers leaves the share without her copy, with a warning
    Given bob advertising demos only, and alice holding a key for todos.demos
    When alice shares x.todos.demos with bob
    Then it is sealed under bob's demos key, she has no copy, nothing is minted, and a warning names both levels

  Scenario: A share stamps the value's own namespace, not the level it walked from
    Given bob advertising todos.demos
    When alice shares memo.17936 in namespace todos.demos with bob
    Then the value's ns is todos.demos
