# implementation-plan.md — what is still owed

⛔ **This document records only what is still owed** (gkc, 2026-08-23). What has
been done is in the codebase and in `git log`; a rejected proposal or a
measurement that closed a question lives in [`decisions.md`](decisions.md),
because no commit can contain a thing that was never built.

**There is ONE PQ list, and it is [`## TODO`](#todo) below.** Every open item has
a priority and appears exactly once, as one or two sentences: the task, and the
reason where it is not obvious. Detail for an open item is a `###` section under
the list or a ruling in `detail/decisions.md`; everything discharged, and every
row as it stood before the 2026-09-11 reconciliation, is in
[`detail/implementation-plan.md`](detail/implementation-plan.md).

**Item ids are permanent.** An item keeps its `14.x` id wherever it sits, because
the ids are cited from the ledger and the sibling docs; nothing here is ever
renumbered.

**The priorities** (gkc, 2026-08-26):

| | |
| --- | --- |
| **P0** | on D1's critical path — including work blocked elsewhere; the `Blocked on` column carries startability |
| **P1** | must do before D1 closes |
| **P2** | should be done if there is time |
| **P3** | nice to have; explicitly after D1, or in another repo |

⚠️ **Re-derive before acting on any row.** Every figure in this project has been
wrong at least once by being carried forward; the commands are in
[Re-deriving the state](#re-deriving-the-state).

---

**D1 ends when every acceptance test passes and every rail is green, the posture
matrix included** (gkc, 2026-08-23): the acceptance set is complete, implemented
and verified, and nothing outside it moves the boundary. "In D1" means owed
before D1 closes, not defining when it closes — the release train, the carves and
R-2 follow it.

"All acceptance tests pass" is true today and is not yet that. The rail checks
structure — a scenario exists, ids resolve, counts match, and where a citation
pins THEN clauses each pin resolves to exactly one — while whether a cited test
really *establishes* its clause is the citation's own `proves:` judgement. The
clause meter is the measure; re-derive it, never quote it.

⛔ **A standing premise: no production `.atKeys` file or keychain entry holds any
PQ key material** (gkc, 2026-08-23). Any argument of the form "X already exists in
the world, so we must tolerate it" is therefore void here until somebody names the
holder. It is a statement about today: the moment a released build writes PQ
material, every question it closed is re-asked rather than re-cited.

**Other live projects keep their own lists** and are not in the table below:
[`docs/projects/wasm/`](../wasm/implementation-plan.md) (with the client storage
X series), [`docs/projects/bdd/`](../bdd/roadmap.md),
[`docs/projects/deprecations/`](../deprecations/plan.md), section 6 of
[`docs/projects/at-lookup-consolidation/plan.md`](../at-lookup-consolidation/plan.md),
and the knowledge base ([`docs/knowledge/README.md`](../../knowledge/README.md)).
Where one of them gates D1, a pointer row here names it.

---

## TODO

⛔ **The single list. One row per open item, bucketed by priority; a row says
what is owed in one or two sentences and links to a `###` section or a ruling
where more is needed.** The rows as they stood before the 2026-09-11
reconciliation, with every measurement they carried, are in
[the detail file](detail/implementation-plan.md#the-todo-table-as-it-stood-on-2026-09-11-before-the-reconciliation).

**The next move is: pick a P0; if none, a P1, and so on** (gkc, 2026-08-26). A
row whose `Blocked on` column says anything but Nothing is not pickable. Nothing
ranks within a bucket, there is no `[RECOMMENDED]` marker and no "next move"
section, and when more than one row in the highest non-empty bucket is
pickable, **ask gkc which** (his ruling, 2026-08-27).

**A row leaves this table when it is done — it does not gain a ✅.** What was
done is in `git log`; a row that is finished and still here is a defect, and a
rail enforces the direction (`docs_structure_test.dart`, *no TODO row names a
section whose body declares itself done*). `## PARKED` runs the opposite
convention on purpose: a parked row keeps its ✅, because what it must say is why
it stopped being parked.

### P0 — on D1's critical path

| Item | What is owed | Blocked on |
| ---- | ------------ | ---------- |
| **the acceptance catalogue's 4.0 pass** | When the 4.0 default flip lands, the same commit edits every `acceptance.md` clause that names a posture or `pqReady`, so the catalogue describes the tree it ships with — never before, and found from the flip's own diff rather than from a list here. | the 4.0 default flip: `AtClientPreference` still defaults `posture` to `PqPosture.legacy` |
| **the clause burn-down, objective 2: live proof** | Every clause proven only in-process gains a proof against a real atServer where feasible; `liveProofOwed` in `packages/at_client/test/acceptance/manifest.dart` names what owes one and why, and the suite prints both counts (`BURN-DOWN clauses proven: N of T server-proven: M of T`). Start with citations that name a live pack test but carry no `clauses:` list, reading each `proves:` first — some are unpinned on purpose. | Nothing |
| [14.18](#1418-the-remaining-d1-initial-development-sequence) **the release train** | Publish in dependency order — at_utils, at_commons, at_lookup, at_auth, at_client, at_client_flutter, at_onboarding_cli — and at_client cannot go before at_commons 5.18.0 and at_auth 4.0.0-rc2, which it pins. Re-derive tree-against-pub.dev with the loop in [Re-deriving the state](#re-deriving-the-state); merged is not published. | gkc — publishing is his act |
| **`primary`'s signing-root route after the migration** | Two questions for gkc now that an enrollment created by legacy-PKAM onboarding is fully privileged server-side: whether `primary`'s signing-root request and its `_apsk` route stay on the pre-post-quantum route; and UC-B5.1's recorded reason for being undrivable from `signing_root_pull_test.dart` is false now that `enroll:listns` answers a legacy connection, so the next catalogue pass corrects it. | gkc for the first; Nothing for the second |
| **`legacy` as a bare verb complement in the Dart tree** | The docs half is done; test prose under `packages/` and `tests/` still uses `writes`, `stays` or `remains legacy` with no axis named (28 sites on 2026-09-11). Rename each to name its axis — provider, posture or `-encrypted` — moving any `provenIn` citation whose test name changes in the same commit; the completion test and its control are in [Re-deriving the state](#re-deriving-the-state). | Nothing |

### P1 — must do before D1 closes

| Item | What is owed | Blocked on |
| ---- | ------------ | ---------- |
| **deprecation debt: `deprecated_member_use` across the workspace** | gkc ruled 2026-09-11 that at_auth, at_client, at_client_flutter and at_onboarding_cli do not publish carrying their deprecation warnings; that the F3 family clears in this pass; and that at_auth's own deprecated surface is **removed in the current rc** rather than a later major. The plan is [`docs/projects/deprecations/plan.md`](../deprecations/plan.md), which holds every figure, decision and what is owed: steps 0 to 5 done, step 6 done for at_onboarding_cli, step 7's three readings resolved, step 8 begun. Two decisions wait on gkc, stated in the plan at the steps that raise them. | Nothing |
| **the PQ e2e job fails on a keyfile lock nothing released** | `pqe2e_tests` went red once in eleven runs (2026-09-08) on `@bob🛠.nskey.atKeys.lock` held past its 10s acquire timeout but inside its 30s staleness window, so no waiter could break it; a client stopped mid-write is the suspected holder. Levers: a heartbeat a live holder refreshes, or find and close the abandonment — not the constants, since pairing them let a re-entrant acquire break its own caller's lock (tried and reverted). | Nothing |
| **a restored pre-retrofit `.atKeys` mints another uncapped enrollment** | at_auth decides "already retrofitted" from the keyfile alone, so a keyfile restored from a pre-retrofit backup retrofits again and leaves a further fully privileged, never-expiring enrollment. Probe it (retrofit, restore, start, `enroll:list`), then decide whether that is the intended sibling-clone case or the client should recognise its enrollment from the atServer. | Nothing |
| **advertisement fetch volume, `ttr` and client caching** | A wire capture showed 110 `_apsk` lookups in one short client run; and `EnvelopeSigning`'s `_apsk` cache resets its five-minute expiry on every read and never invalidates on a failed verification, so a busy verifier holds a superseded advertisement indefinitely and refuses everything the rotated signer writes. Measure the fetch volume after the negative-cache and `enroll:infons` changes, then rule on `ttr` and client caching together — a client cache with no `ttr` is a rotation that never takes effect. | Nothing. A measurement, then a ruling |
| **the PQ upgrade guide does not exist** | The retrofit clean-up instructions [ruling 118](detail/decisions.md#118-the-retrofit-cap-is-armed-by-the-successor-not-by-the-retrofit-2026-08-27) names, routed to a guide by [ruling 40](detail/decisions.md#40-rf-srv-is-the-mechanism-the-whole-model-stands-on-2026-08-05) item 7; `docs/projects/pq/` has no such file. | gkc, on where it lives |
| **there is no best-practices guide for application owners** | The only mitigation for the repopulation window after an nskey rotation: a guide carrying gkc's two-rollout recipe (rollout 1 mints old and new and seals to old; rollout 2 mints and seals to new), the two levers `keyEstablishmentAlgorithms` and `sealsToKeyAlgorithms` moving in different releases, and the English-to-French analogy. Whether it is one document with the upgrade guide is unsettled. | gkc, on whether it joins the upgrade guide |
| **step 3 of a signing migration has no lever** | A verifier cannot decline an algorithm it implements — `verifyEnvelope` takes `strongestOf(shared)` with no accepted set — so a retired signing key is a standing forgery surface ([ruling 120](detail/decisions.md#120-a-signing-migration-is-three-steps-and-the-third-has-no-lever-2026-08-28)). Build the verifier-side set mirroring `sealsToKeyAlgorithms`; it falsifies UC-G2.9 c3, which `unprovableClauses` enumerates for that reason. | Nothing |
| **the double-signing writer is dead code** | [Ruling 120](detail/decisions.md#120-a-signing-migration-is-three-steps-and-the-third-has-no-lever-2026-08-28) retired the two-signature overlap, so the plural-envelope writer can go, keeping the multi-signature reader (`SignedEnvelope.fromJson`'s differing-`kid` and differing-`typ` refusals stop an entry being appended in flight) and re-pointing the four tests that emit two signatures. | Nothing |
| **an orphaned enrolment may never expire** | A self-enrollment inherits its parent's `apkamKeysExpiryDuration`, and zero means never, so a subtree under a never-expiring parent is bounded by nothing. Decide whether a self-enrollment may inherit an unbounded expiry. | gkc's ruling |
| **the three crypto-agility matrices, live** | Specified in [`acceptance.md` section 17](acceptance.md#17-g2--crypto-agility--add-never-replace); the harness half is unbuilt. `_apsk` sign and verify (UC-G2.3, UC-G2.7, UC-G2.8), the pairwise substrate (UC-G2.1, UC-G2.4) and the nskey advertisement (UC-G2.2, UC-G2.10, UC-G2.11), each self-to-self and self-to-other against an advertiser offering one algorithm, both, or the other — one namespace per variation on the atSigns the packs already have. A one-entry `rsa2048` `_apsk` serialises as a bare string, so one-entry and two-entry are different wire shapes. | Nothing |
| **doc-set rails: anchors and table cells** | `docs_structure_test.dart` never opens a link's target, so a heading renamed in one file breaks links from another silently, and its "row says owed, body says done" guard cannot see a row that names no `###` section. Add a resolver over the doc set and widen the guard. | Nothing |
| [the four missing self-to-self mirrors](#the-four-missing-self-to-self-mirrors) | gkc's rule (2026-08-27): a put/notify or get/receipt row is about self-to-self or self-to-other, never both, and where one direction has a row so should the other. Four self-to-other rows have no mirror; rule which become catalogue rows, then write them and their scenarios — the denominator rises, correctly. | gkc's ruling |
| [the at_client carve stack](#the-at_client-carve-stack) | The nine-layer stacked-PR plan for the at_client release candidate lives only in gitignored `untracked/at-client-stacked-prs.md`; get it into git and make the five decisions the section names — a file in no layer never lands. | whoever cuts the stack |
| [arm 1 vs arm 3 bucketing](#arm-1-vs-arm-3-bucketing) | A ruling on which rows arm 1 owes; the measuring is done and arm 3 cannot be scoped until it is settled. | gkc's ruling |
| [a wildcard enrolment seeds nothing](#a-wildcard-enrolment-seeds-nothing) | An atSign reachable only through a wildcard (`*`) enrolment publishes no namespace keys, so nobody can seal to it; rule whether that is intended. | gkc's ruling |
| [content keys per scope](#content-keys-per-scope) | Rule whether one content key per writing enrollment per scope is the intent; if not, `CurrentCkPointer` needs a remote-first write through an atomic verb and rotation must supersede every content key in scope. | gkc's ruling, then the fix |
| [the late-arriving nskey private](#the-late-arriving-nskey-private) | Ruled 2026-09-07: a standing conveyance subscriber — a handler on the envelope listener `PqClientBootstrap` already runs, not a second listener — files nskey privates and content keys when they land, and only for a generation this client asked for (the reverted attempt filed any arrival). The analysis is the X6 row of [the wasm plan](../wasm/implementation-plan.md). | Nothing |
| **two clients of one atSign sharing a store** | Ruled 2026-09-07: sweep the e2e pack and the unit tree for two clients of one atSign sharing a local keystore (the functional pack is already isolated per file) — candidates are files with two or more `setCurrentAtSign`, `buildAtClient` or `fromAuthSession` calls for one atSign; a second client gets its own bundle (`forPrincipal`) or a hand-over. | Nothing |
| [14.18](#1418-the-remaining-d1-initial-development-sequence) **step 20's rotation arm** | Build the matrix's rotation arm — an enrollment followed by an `enroll:update` APKAM rotation mid-run — against a dedicated CRAM atSign; [14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) item 11 (a rotation that lands and is not persisted locks the enrollment out) is what it waits on. | the at_auth publish, and a dedicated CRAM atSign |
| **`AtRpc` request ids collide, and the responder drops the second request without a NACK** | `AtRpcReq.create` mints `reqId` from `microsecondsSinceEpoch`, so back-to-back ids repeat (926 of 1,000 measured): under `enableRequestMutex` the responder drops the second request silently, `AtRpcClient.call` overwrites the first caller's completer, and `call` has no timeout. NoPorts uses it. gkc prefers UUIDs — a 4.0 String-on-the-wire change, responders deployed first; a random 53-bit int is the non-breaking 3.x alternative — and either way `call` refuses a duplicate id and takes a timeout. | gkc's ruling |
| **the client half of ruling 128** | Drop `namespaces` from `selfRetrofit` and `retrofitIdentity` — exported through `at_client_mixins.dart`, so breaking — because a successor holds its predecessor's grants and may not choose them ([ruling 128](detail/decisions.md#128-a-retrofits-successor-holds-its-predecessors-grants-and-may-not-choose-them-2026-08-31)); the atServer half refuses, so this is cleanup. Challenge the eleven call sites' EQUAL verdicts before relying on the zero. | Nothing |
| **`retiredAt` on the `_apsk` advertisement** | Ruled 2026-08-31: `ApskSigningKey` gains a retirement timestamp, stamped when an entry moves to `retired`, so a verifier can date a key. A wire and at-rest change to `_apsk`, so the doc sweep and the JAMS unit tree land in the same commit; a record's `createdAt` is a caller assertion, not a clock to design against. | Nothing |
| **statements the revocation cascade falsified** | at_server #2781 shipped the cascade ([ruling 129](detail/decisions.md#129-revocation-cascades-to-descendants-and-the-roster-does-the-rest-2026-08-31)), so reword what was written for the world before it: `published_nskey_key_ring.dart`'s "the conveyance excludes nobody" dartdoc, `pairwise_secret_sharing_test.dart`'s "rotation buys nothing" `reason:`, UC-A5.2's `provenIn` filing roster-membership as proof of a hazard, and this table's orphaned-enrolment row; and [ruling 40](detail/decisions.md#40-rf-srv-is-the-mechanism-the-whole-model-stands-on-2026-08-05) item 2 must carry 129's guard that an un-revoke behind an unapproved predecessor is refused. | Nothing |
| **a v(N-1) `.atKeys` migration test** ([#2154](https://github.com/atsign-foundation/at_client_sdk/issues/2154)) | Nothing reads a keyfile written by the previously published at_auth (3.3.0, which `tests/pq_matrix/published/` resolves) or proves that build reads a version 1 document — the direction auth_cli's `pqReady` approver default ([ruling 137](detail/decisions.md#137-auth_cli-has-two-roles-and-they-take-opposite-postures-2026-09-08)) now exercises on every operator's keyfile. Check in a captured fixture with its version recorded, round-trip every field, and add a mutation that reddens when a reader drops a legacy field. | Nothing |

### P2 — should be done if there is time

| Item | What is owed | Blocked on |
| ---- | ------------ | ---------- |
| **the test-pack speed-up branch: what it still owes before its PR** | Branch `gkc-test-pack-speedup`, pushed 2026-09-11. Owed: the four live packs re-run at head (last at `e616e4cbc`); the functional pack at 0.707s a test against a 0.5s target, the gap in `seeding_tail_abandoned` (15.5s), `key_package_amendment UC-A2.5` (8.2s) and `pq_released_peer` (6.4s); and 21 fixtures across 11 files still minting an RSA keypair per test (`test_keypairs.dart` is the cache, keyed by (atSign, enrollmentId)). Rejected: suite-wide `Mock.throwOnMissingStub()`, and moving unit tests to `InMemoryAtClientStorage` — storage costs 3.25ms either way and an RSA keypair 142ms. | Nothing |
| **a client running as the atSign's own credential gets no revocation backstop** | `NskeySeeding.rotateIfRevoked` skips a client with no enrollment id or `primary`, as UC-G2.5 and [ruling 130](detail/decisions.md#130-a-revocation-is-discoverable-per-namespace-and-rotates-unconditionally-2026-08-31) point 8 accepted on a reason that no longer holds (the check makes its own `enroll:infons` call, and a legacy-PKAM connection authenticates as `primary`). Decide whether the atSign's own credential gets the backstop; if yes, one predicate, and the clause moves with it. | gkc's ruling |
| **switch `_enrollmentById` to `enroll:fetch`** | at_server 3.16.5 returns `metadata` on `enroll:fetch`, so approval no longer needs to filter the whole roster client-side. Decide first how the client treats an older atServer whose response has no `metadata` key — fall back to `enroll:list`, or require the newer server; never read absent as empty — then switch. | Nothing |
| **three client-startup paths read the whole roster to find their own record** | `NskeyRotation`, `NskeySeeding.authorisedNamespaces` and `selfRetrofit`'s signing-root step each fetch every enrollment to read one field of their own; redirect them to the memoised `LocalSecondary.getEnrollmentDetails()` (an `enroll:fetch` of the client's own enrollment), checking whether `selfRetrofit`'s freshly switched client can share the memo. On a grown roster each costs what the approval used to — 46.6s measured. | Nothing |
| **`subscribe()` returns before the monitor attaches** | A notification sent in that window is accepted by the atServer (`delivered` means server-to-server) and never handed to the live monitor; the record survives for `monitor:<epoch>` replay. The harness now polls `NotificationService.listening`; the product question is open — await attachment in `subscribe()`, redeliver, or expose the readiness check where an app would look for it. | Nothing |
| **tidy up the revoked enrollment backlog on `@ce2e1`–`@ce2e4`** | About 2,400 revoked enrollments per atSign from runs before `enrollment_setup.dart` gave each request a three-hour expiry. Deleting a revoked record releases its keypair for re-enrollment, which is why at_server will not reap them automatically and why this is a deliberate act. | gkc — he is taking it |
| **the functional pack's CI time stepped up about 20%** | Every run carrying `9c84011df` (the 2026-09-07 trunk merge-back) measures 8m23s–11m35s on stable against 5m30s–9m52s before it; the posture flip is not the cause, since every functional client names its posture. Decide whether two minutes a run is worth chasing; if so, bisect within the merge-back. | Nothing |
| **`useRemoteAtServer` on a key another atSign shared fails** | A receiver's `get` with `useRemoteAtServer = true` on a key another atSign shared issues an `llookup` of the uncached name against its own atServer and fails `key not found` (115 failures in one run) instead of a `lookup:` at the publisher. Decide whether the option resolves through `lookup:` or refuses the combination, and say so in its dartdoc. | Nothing |
| **`apsk_server_side_test.dart` poisons the shared atSign for the rest of the run** | It leaves two records on `@alice🛠` — a non-base64 literal over the attacker enrollment's `_apsk`, and a healed enrollment whose key package stays signed by a key its `_apsk` dropped — so every later `listForNamespace` logs SEVERE (314 lines in one CI run). Give the file its own atSign, or restore what it overwrites and restart the healed client. | Nothing |
| **`CkManager`'s missing-cut-time guard cannot fire** | `CkManager.ensureCurrent` returns early when the cached content key has no `cutAt`, but `putAsCurrent` always records one and the cache is in-memory, so the branch is unreachable and its comment describes a persistence that does not exist. Delete the guard and the comment (making the cache durable is a feature, not this). | Nothing |
| **where `mintAdvertisedSigningKey` lives was never put to gkc** | It sits in `packages/at_client/lib/src/enroll/signing_key_mint.dart` and at_onboarding_cli imports it across the package boundary; decide whether it belongs in at_auth beside the enrollment machinery that uses it. | gkc |
| **`runCliCommand` streams the CLI child's log unprefixed** | `tests/at_onboarding_cli_functional_tests/test/utils/at_client_cache.dart` writes the child's stdout verbatim into its own, so two processes' lines cannot be told apart. Prefix or pid-tag them and say so in the dartdoc, noting that `auth_cli` sets `root_level = 'shout'`, so an un-`-v`'d child reads like a stalled one. | Nothing |
| **test-helper cleanup: a required `signingAlgo`, and one `EnrolledClient`** | Make `enrolAndAuthenticate`'s `signingAlgo` required — its `rsa2048` default hands a PQ-posture caller a legacy enrollment that retrofits into a different id — and let the compiler enumerate the call sites; then port the e2e `EnrolledClient` copy (an ancestor 205 diff lines behind, lacking `signingAlgo`, `atKeysIo`, `keyExchangeMode`, `reuse` and the `kpid` getter), run the e2e pack, and move what is shared into a never-published `tests/packages/test_helpers`. | Nothing |
| **there is no supported way to wait for the PQ startup tail** | Nothing on the `AtClient` interface says when the unawaited PQ startup has finished writing the keyfile; the CLI pack reaches through `@experimental` `pqBootstrap.startupComplete`. Decide whether the interface carries it — an in-repo test can reach through, an application cannot. | gkc |
| **a rotating atSign could tell its senders** | A sender learns of a rotation only by re-resolving the advertisement, up to 30 minutes of ttl plus grace later, and keeps sealing to the superseded generation meanwhile. Every `.__ck.` conveyance record is addressed to a sender, which suggests a rotating atSign can enumerate exactly who must re-cut; probe that scan before designing on it. | Nothing. A probe first |
| **`notificationStatusEnum` is not an outcome, and its name says it is** | A dartdoc fix: with `checkForFinalDeliveryStatus: false`, or when a send fails before reaching the atServer, the field reads `undelivered` whatever happened and only `atClientException` distinguishes; the `on AtException` handler's comment says it sets `errored`, a value the enum lacks. Fix the comment first, then qualify the field and `NotificationResult`. | Nothing |
| **a pq enrolment costs a post-approval round trip** | A PQ enrollee must collect the key its approver encapsulated to its key package (polling `enrollmentApkamSymmetricKeyResolver`, 30s budget) where a legacy enrollee is done at approval. Measure it and decide whether the enrolment APIs say so. | Nothing |
| [14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) | Item 11 — an APKAM rotation that lands and is not persisted locks the enrollment out — is the owed work and step 20's arm waits on it; item 35 lands in `atGettingStarted`; the rest of the open items are examined-and-left or not PQ. Re-derive the open list with the section's command. | Nothing |
| **a retrofit leaves the enrolment record memo stale** | `LocalSecondary.getEnrollmentDetails()` memoises the record, `_settleEnrollmentIdentity` fills it with the predecessor's, and `_rederiveFromEnrollment` never clears it, so the client runs as the successor while the record describing what it may do is the predecessor's — benign only because a retrofit copies grants verbatim. Clear the memo on re-derivation. | Nothing |
| **at_lookup `OutboundMessageListener.read` leaves a stale reply queued** | `AT0014 "Unexpected response found"` pops one entry and clears the buffer without draining `_queue` or closing the connection, unlike the timeout paths beside it, so a stale queued response is handed to the next command. Drain or close. | Nothing |
| [14.50](#1450-the-e2e-teardown-revokes-enrollments-belonging-to-other-runs) | Scope the e2e teardown to the run that created the enrollments — a marker derived from `GITHUB_RUN_ID` that setup, suite and teardown can all read — so two overlapping CI runs stop tearing each other down ([#2197](https://github.com/atsign-foundation/at_client_sdk/issues/2197), five observations and one clean-room control). | Nothing |
| [14.47](#1447-the-at_client-unit-tree-has-a-cross-file-isolation-flake) | A unit-tree isolation flake in `local_secondary_sync_queue_test.dart`: green alone and in the full suite, red in one hand-constructed order nothing runs. Reproduce at rate before touching it. | a reproduction at rate |
| **at_client README says nothing about the PQ surface** | `packages/at_client/README.md` mentions none of the PQ startup, namespace-key seeding, `ensureReachable` or the send/receive asymmetry an app meets first (you can send the moment you are up; you cannot receive until your key is published). Decide how much of that surface belongs in a README, then write it. | Nothing |
| [14.16](detail/implementation-plan.md#1416-four-residuals-the-issue-tree-audit-surfaced-2026-08-09) **orphan growth** | Only ③'s orphan-growth half is owed — a decision before it is code; SS-4 resume was ruled NO RESUME. | the decision |
| **`docs/projects/` has no index of its live projects** | pq, wasm, bdd, deprecations, the at-lookup consolidation and the knowledge base each keep their own list, and this file's header names them; a ruling on where an index lives. | gkc |
| **key packages and envelopes are APKAM-signed with `rsa2048` by default** | The signature that authenticates a key package and an envelope defaults to `SigningAlgoType.rsa2048` — the one place RSA still touches the post-quantum path, an integrity rather than a confidentiality exposure. Rule on it rather than leaving it implicit. | gkc's ruling |
| **no non-test caller enrols at a PQ posture by default** | The CLI enroller defaults to `legacy` and only the approver commands to `pqReady` ([ruling 137](detail/decisions.md#137-auth_cli-has-two-roles-and-they-take-opposite-postures-2026-09-08)), so the creation-time signing-key mint runs outside tests only when a user passes `--posture`, and the retrofit path is what every default caller exercises. Decide whether that is acceptable for 3.x. | gkc's ruling |
| **the conveyance catch still swallows too much** | The conveyance read's broad `catch` swallows more than its dartdoc specifies (a record that is nowhere is not an error; everything else is). Probe what an absent record throws on the local and the remote leg, then swallow only that. | Nothing |
| **a signing key can be advertised before it is filed** | `apkam_signing.dart` documents the window where a mint has published but not filed, so an envelope signed in it verifies against nothing; reversing the order opens the mirror-image window. Fix by not signing during the transition, or by keeping the authentication key advertised until both writes land. | Nothing |
| **four refusals for two user errors, one of them uncatchable** | A sender that omits an algorithm and one that cannot implement it reach four refusals across three exception branches with contradictory advice, and `AtSigningVerificationException extends AtException`, so an app catching `AtClientException` misses one. Consolidate them; the supertype change is at_commons. | Nothing |
| **UC-A2.6 c2 is pinned by a citation that admits an unproven arm** | Its `proves:` says the revoked-while-connected arm is not proven, yet the clause counts as proven. at_server trunk closes every open connection carrying a revoked enrollment, so pin it live: hold E4's connection open, revoke over a second one, assert the first is closed rather than refused at reconnect. | Nothing |
| **an `at_lookup` unit test resolves a production FQDN** | `secondary_address_cache_test.dart` calls `root.atsign.wtf` from the unit pack (its own group name says move it) and its 30s finder deadline equals the test timeout, so the retry path it was written around never runs; it reddened an unrelated PR on 2026-09-06. Move it to a functional pack with a longer timeout. | Nothing |
| **the local e2e fixture cannot reproduce an APKAM enrollment-id defect** | `local_setup.dart` mints every local keyfile from `at_demo_data` with `enrollmentId: null` while declaring `authType: 'apkam'`, so a local run passes where CI's `end2end_test_14` catches an enrollment-id defect. Enrol for real, or say in its dartdoc that it cannot. | Nothing |
| **a store write in flight when `stop()` lands still reaches the closed store** | The stopped-flag guards cannot reach a write that already passed them, so a `closeAll()` after `stop()` still logs `Box not found` for the pull cursor and the notification watermark (four lines a run in two of three). Make `stop()` drain in-flight writes before it returns — a lifecycle change, so all three live packs. | Nothing |

### P3 — nice to have, explicitly after D1, or in another repo

| Item | What is owed | Blocked on |
| ---- | ------------ | ---------- |
| **a pull cut by `stop()` keeps none of its batches' progress** | `_syncFromServer` persists the pull cursor once after the last batch and the stop-path guard skips it, so a client stopped mid-pull re-pulls from its previous cursor (twenty clients in one CI job each pulled 711 commits from `-1`). Persist after each batch. | Nothing |
| **third-party dependency floors** | at_client declares seven floors below what it resolves (`path`, `crypto`, `uuid`, `archive`, `http`, `async`, `meta`), none checked against first use. Two questions: are they too low, and does at_client compile against the bottom of each range it admits. | Nothing |
| **the enroll roster carries no expiry** | `enroll:list`'s roster projection has no `expiresAt` (`enroll:fetch` carries one since at_server 3.16.5); an at_server change ruled by [decisions 118](detail/decisions.md#118-the-retrofit-cap-is-armed-by-the-successor-not-by-the-retrofit-2026-08-27). | Nothing. An at_server PR, after D1 |
| [the registrar certificate test](#the-registrar-certificate-test) | Three arms against a self-signed cert — the one S-5 behaviour change with a security consequence and no test. Post-D1 clean-up (gkc, 2026-08-23). | Nothing. It lands wherever at_auth is next touched |
| [14.44](#1444-residuals-from-the-at_chops-pr-review) | Post-D1 (gkc, 2026-08-23): at_chops 3.6.0's CHANGELOG owes the resolution-skew sentence, amended into that section in place; and `XWingCore.combine` sizes its buffer from its inputs while writing at literal offsets, so an over-long component is silently truncated — reject wrong-length inputs up front. | Nothing. Both ride the next at_chops touch |
| **a sequential, abort-on-failure `batch`** | A protocol enhancement (gkc, 2026-08-27): `batch` already runs its commands in order but carries on past a failure; an abort-on-failure form would close the mint locks' take-to-write windows structurally. Multi-repo — at_commons, at_client and at_server in one sweep — and two silent drops in the handler (a command no handler accepts, and a null error code) are prerequisites. | Nothing. A design and a cross-repo sweep, after D1 |
| **at_server: a String `apsk` on any enroll verb returns an internal error** | `EnrollParams.fromJson` casts `apsk` before validation and before the OTP check, on a verb an unauthenticated connection may send, so `"apsk":"x"` answers a Dart type-cast message instead of an `IllegalArgumentException`. Low severity; `apskLegacy` has the same shape. | Nothing, except that it lands in `at_server` |
| **at_lookup major: deleting the ladder makes a keystore mandatory** | Gates the later at_lookup major, not D1: the remaining ladder traffic is callers who supply no `AtKeysIo`, so deleting the ladder breaks every consumer that builds a client from a preference alone (at_tools' `at_cli` is one). A bridge is [measured in the consolidation plan](../at-lookup-consolidation/plan.md#blocks-the-major--deletion-does-not-remove-the-ladder-it-makes-a-keystore-mandatory). | Nothing. A decision about the bridge before it is code |
| **at_lookup major: `atLookUp.enrollmentId` has 51 uses, not 7** | Gates the later at_lookup major: [51 uses across 34 files](../at-lookup-consolidation/plan.md#blocks-the-major--atlookupenrollmentid-has-51-uses-not-the-7-first-recorded) from the analyzer — a grep on the member name over-counts and `atLookUp.enrollmentId` under-counts, because it is reached through at least eight receivers. | Nothing |
| **at_lookup major: the CLI's authenticator install is unit-green only** | The CLI's authenticator install has 54 unit tests and no live check, and its six construction sites are not uniform ([section 6 of the consolidation plan](../at-lookup-consolidation/plan.md)); the migration wants a runner exercising the CLI first. Re-derive the sites rather than quoting them. | Nothing |
| [the `monitor:` verb has no acknowledgement](#the-monitor-verb-has-no-acknowledgement) | A protocol seam across three repositories; the caller-side mitigation is built and live-proven. Not D1. | gkc scheduling it, after the release train |
| [atServer outbound connection pooling](#atserver-outbound-connection-pooling) | In `at_server`, and asked for as a discussion rather than a change. | gkc scheduling it |
| **doc-set reduction, phases 3–5** | Ruled by gkc 2026-08-23 for after D1: the end state is five files — `roadmap.md` (needs a pass), `design.md`, `acceptance.md`, `decisions.md` and this plan. Phases 1 and 2 landed 2026-08-23. | D1 closing |
| [14.46](#1446-executeverbs-sync-parameter-is-inert-on-both-secondaries) | Removal at 4.0: delete the inert `sync` parameter from all six declarations and let the compiler enumerate the remaining same-package sites; phase 1 (`@Deprecated`) shipped 2026-08-20, and the deprecation plan's F5 family holds it. | the 4.0 majors |
| [14.12](#1412-a-mintlegacymaterialfalse-atsign-cannot-write-a-public-record) | Not D1: it gates the post-R-2 stop-release, and until it closes `mintLegacyMaterial: false` is not to be recommended to anyone. Both moves it needs are B-3 phase 1, which is parked. | two unscheduled moves its body names |
| [14.29](#1429-the-residuals-1425-surfaced) | S-3's two small items — a keychain round-trip on a real device (needs an `integration_test` harness in at_client_flutter first) and `LocalKeystoreAtKeysIo`, whose owed-or-out-of-scope status the section flags; SS-2's `__ssenv` auto-notify is deferred, not owed. None blocks D1. | Nothing blocks D1 |
| [14.43](detail/implementation-plan.md#1443-the-functional-suites-convergence-race) residue | Not D1 and not PQ (gkc, 2026-08-23): at_client's general sync ordering, which no use case asserts; the test-side fix landed in `ccf4987a4`. | Nothing |
| [14.45](detail/implementation-plan.md#1445-an-expired-key-the-client-cannot-delete-pins-it-in-a-hot-loop) residue | In `at_persistence_secondary_server`: its keystore `get()` does not filter expired records. | Separately owned |
| [14.39](detail/implementation-plan.md#1439-pqposture-and-the-rollout-it-drives) **public-data signature verification** | Post-D1 and deliberately outside the catalogue (gkc, 2026-08-23): `pqActive` signs public data and nothing anywhere verifies it — not at_client, not any atServer — so a signature nobody checks is emitted knowingly. Undesigned. | a design |
| **at_server's `at_server_spec` hosted fallback** | at_server's `unit_tests` job runs `dart pub get` per package with no melos step, so a PR changing `at_server_spec` and `at_secondary_server` together tests the new server against the old published spec and stays green. gkc has left it for a considered decision. | gkc |
| **a functional client built on an empty keys store** | `crypto_era_default_test.dart` builds its client on an `InMemoryAtKeysIo` holding nothing, so the construction-time read logs "Could not read the keys" at warning on every functional run and the client runs as a null id. Write the demo keys into that store or stop passing one. | Nothing |

### The four missing self-to-self mirrors

**A ruling gkc asked for, drafted 2026-08-27 and deliberately not landed.**
Nothing in `acceptance.md` changes until it is settled, because adding a row
raises the burn-down's denominator and every new row owes a scenario.

**The rule this comes from** (gkc, 2026-08-27): a use case for `put` or `notify`
— or for the receiving side, `get` or notification receipt — is about **self to
self** *or* **self to other**, never both at once. And where one direction has a
row, so should the other.

Auditing every put/notify/read row against that, five pairs already hold:
UC-A3.1↔UC-A4.1, UC-A3.3↔UC-A4.2 (with UC-B4.1 carrying the fallback),
UC-A3.4↔UC-A4.4, UC-B3.1↔UC-B4.3 and UC-B3.2↔UC-B4.4. Nothing in the self
cluster lacks an other-side mirror — UC-A3.2 is seeding and UC-A3.5 is the
advertisement's shape, neither being a write row. **Four self→other rows have no
self→self mirror**, and they are not equally worth having:

| Would mirror | What the self row would assert | Can the tree tell it apart? |
| ------------ | ------------------------------ | --------------------------- |
| **UC-A4.5** — a sender follows the recipient's advertised algorithm, not its own preference | A self write seals under the algorithm **this atSign's own published nskey advertises**, even when `keyEstablishmentAlgorithms` names a different one. Fixture: a published X-Wing nskey and a preference configured for `ml-kem-1024` | **Yes, and this is the sharpest of the four.** `NskeyResolver.resolve` reads the published advertisement and then filters by `sealsToKeyAlgorithms`; a build that consulted the *minting* preference instead would be wrong. ⚠️ For a self write both values belong to the same atSign, so **a client reading the wrong one is invisible** — which is exactly the shape a bug hides in, and there is no row for it |
| **UC-A4.7** — no mutually supported construction is a refusal, not a guess | A client whose `sealsToKeyAlgorithms` has been narrowed past what its **own** advertisement offers is refused, and the refusal says so rather than reporting a cold start | **Yes, and the production code already names this exact case.** `NskeyResolver` throws `AtEncryptionException` rather than walking on, and its comment says why: *"a deployment that narrowed the list reads its own configuration as the recipient having published nothing."* The path exists, is commented for the self case, and nothing exercises it |
| **UC-A4.6** — the construction is negotiated from `suites` | A self write against this atSign's own advertisement listing only a retired construction is refused, and one listing the current construction gets the matching version byte | **Yes, but narrower.** `NskeyProvider._sealVersionFor` intersects what the build can open with the advertisement's `suites`, and for self that advertisement is one this atSign wrote — so a mismatch means an advertisement older than the build. A real upgrade scenario rather than a hypothetical, but less likely to be got wrong than the two above |
| **UC-A4.3** — multi-enrollment both ends | Every authorised enrollment of this atSign reads this atSign's own self data | **Weakest.** Largely covered already: UC-A3.1's Given has `alice1, alice2` both holding the private, approval-time conveyance is UC-A2.3, and an enrollment that missed the mint healing from a holder is UC-B5.11. A row would restate rather than add |

⛔ **The denominator moves and that is the honest direction.** Landing any of
these raises the total with the new clauses unproven, so the burn-down
percentage falls. That is what it should do: the clauses were always owed and
their absence was flattering the figure.

### The at_client carve stack

⚠️ **The design exists but is INVISIBLE to git.** gkc asked on 2026-08-25 for a
plan of stacked pull requests for the at_client release candidate — each layer
reviewable on its own, each with a description saying why and what rather than
how, the tests it adds, and where a reviewer should spend attention. It was built
and checked against the real diff, and it lives at
**`untracked/at-client-stacked-prs.md`**, which `/untracked/` in `.gitignore`
hides — so `git grep` cannot find it, nobody else has it, and a fresh session
searching the repo will conclude no such plan exists. **Nine layers**, cut on the
line that most of the branch is inert until one late layer switches it on: read
2, 3 and 7 properly, skim the rest.

**Five decisions it cannot make, and the stack cannot be cut until they are
made:**

1. Two files are claimed by two layers (`pq_signing_root.dart` and
   `pq_signing_chain.dart`, in both 4 and 6) — sized into 4, which would make 6
   about 2,300 lines smaller than its row says.
2. The unit suite is deliberately red in the middle of the stack, because two
   tests cover code that arrives later — while four layers say to verify with a
   whole-package run.
3. One new test file appears in two layers and lands in only one.
4. One layer says its wiring "lands elsewhere in the stack" without naming the
   layer, and is reviewed before that layer exists.
5. Four areas of the diff fell outside every layer — **a file in no layer never
   lands**.

⚠️ **One of those four is a trap worth keeping even after the stack is cut.** Two
already-published packages look like a formatter run and mostly are — 21 of 22
changed files in one and 7 of 8 in the other are byte-identical once all
whitespace is removed. But two are not, and one of them is a hand-written format
pin, which is the single kind of file that must never be skipped on the strength
of its neighbours. Test it by comparing each file with whitespace stripped, never
by reading line counts.

### Arm 1 vs arm 3 bucketing

⛔ **A RULING IS OWED FROM gkc, and it is not a research task** — the measuring is
done. [`acceptance.md`'s "Which rows arm 1
owes"](acceptance.md#which-rows-arm-1-owes) has both readings and the evidence;
nothing here repeats them.

In short: section 14's kind table says **3** transition rows, its arm-3 paragraph
names **12**, and four rows — UC-B1.1, UC-B1.2, UC-B4.4, UC-A5.3 — are assigned
to arm 1 and arm 3 at once, so the published "21 axis and consequence rows"
double-counts. The two readings differ in what arm 1 *is*: under the count an
arm-1 cell must drive a retrofit, so the arm stops being three static clients;
under the prose a retrofit is an edge and belongs to arm 3.

**Arm 1 as built sidesteps it** by covering only the 14 rows both derivations
agree on, so nothing is blocked — but arm 3 cannot be scoped until this is
settled, and the count table stays wrong until then.

### Content keys per scope

⚠️ **A defect found while diagnosing the atServer's pairwise-lookup bug, and
separate from it.** One content key per writing enrollment per scope, cut at that
enrollment's first write, with no re-minting — three sender enrollments produced
three CKs under `(bob, ns)` and three under `(alice, ns)`.

`CurrentCkPointer` is the only thing meant to converge them and cannot as
written: it is put **`localOnly`** into each enrollment's own store and reaches
siblings only by sync, so cold enrollments writing together each read no pointer
and each mint. `CkManager._resumeCurrent`'s "cutting a fresh one" fired **zero**
times across the run. Sync dropped four of those pointer writes, logging
`sync queue race: __ckcur.… missing persisted record; removing`.

**Why it matters beyond waste**: `rotateContentKey` supersedes only the CK in
hand, so a rotation asking for forward secrecy leaves the other enrollments' keys
live and their data readable — **read from the source, not run**.

**What a fix needs, if the ruling goes that way**: the pointer written
remote-first through an atomic verb or behind an interlock, and rotation
superseding every CK in scope rather than the one in hand.

### A wildcard enrolment seeds nothing

⚠️ **Found 2026-08-26 while answering a question about a demo, and the doc
comment that hid it has been corrected in the same commit.**
`NskeySeeding.authorisedNamespaces()` skips `*` and `__manage`, and its dartdoc
said a wildcard enrollment "mints on demand when it writes into a specific one
instead". **There is no such path.**

**Measured, not reasoned:**

- `PublishedNskeyKeyRing.mintAndPublish` has exactly **one** production caller
  in at_client — `NskeySeeding.seed()`. The ring's `_mintUnlessPublished` is
  reachable only from `mintAndPublish` itself.
- Writing does not mint. `NskeyProvider._nskeyOwnerOf` is
  `atKey.sharedWith ?? recordOwner`, so an outbound share resolves the
  **recipient's** nskey; a sender consults its own only for self data, and
  consulting is not minting.
- So a client whose enrolment authorises only `*` mints nothing at startup and
  nothing later. It publishes no advertisement, and every peer trying to seal
  to it gets `NamespaceKeyUnavailableException`.

✅ **SETTLED 2026-08-26, measured against a live atServer** in a local
ephemeral environment by the at_talk demo session, which is where this was
costing real time. A first (CRAM) enrolment IS wildcard-only:

| Enrollment ID | Status | AppName | DeviceName | Namespaces |
| --- | --- | --- | --- | --- |
| `d118c77f-…` | approved | firstApp | firstDevice | `{__manage: rw, *: rw}` |

`_isSeedable` skips both, so `authorisedNamespaces()` returns empty and `seed()`
mints nothing, ever.

⚠️ **Confirmed behaviourally as well as by reading, and the positive control is
what makes it evidence**: an atSign onboarded `pqReady` and run at `pqReady`
with `namespace: 'ai6bh'` had **no** `public:__nskey.ai6bh@…` — while
`public:pq_signing_root@…` WAS present in the same scan. So the PQ bootstrap
ran and what is missing is specifically the namespace-key step, rather than the
whole path being cold.

**The consequence, and it is the reason this is P1 rather than a curiosity:**
every freshly onboarded atSign is unreachable as a recipient — a pqActive
sender gets `NamespaceKeyUnavailableException` from it in every namespace —
until some app enrols with a real namespace. Which makes the app-enrolment path
the only route out of that state.

**Why it matters if it is reachable:** the atSign is invisible as a recipient
for every namespace, permanently, with no error on its own side — the failure
lands on whoever tries to reach it.

⚠️ **The same shape already bit the e2e suite for a different reason.** The
⚠️ block at the top of `tests/at_end2end_test/test/pq/nskey_recipient_not_ready_test.dart`
records a control that only passed when another file had happened to mint
`@bob`'s key first, because being sent to mints nothing. Read it before
designing any fix.

### The late-arriving nskey private

**The receiver-side half of the pqActive notification drop, and the only part
still owed.** File a late-arriving nskey private **only for a generation this
client actually asked for**. The reverted attempt filed any arrival, which is
what breached the seeding guarantee.

⚠️ **Two things the earlier framing got wrong**, kept because both are easy to
re-derive incorrectly. Addressing was never the problem. And
`PublishedNskeyKeyRing._mint` was said to "never reach `_convey`, so a generation
minted during rotation still leaves that client's store unprimed" — half right:
`NskeyRotation.rotateNamespaceKey` *does* push the successor to the roster, but
it never primed **its own** secret store, so the one enrollment certain to hold
the successor was the only one that could not serve a pull for it. That half is
**closed**: it now calls `putIfNewer` before the fan-out, exactly as the mint-time
convey does.

⚠️ **One consequence is stated in that method's dartdoc and was verified against
the answer path before it shipped**: `excludeEnrollmentIds` filters the rotation
PUSH and not a later PULL, so an excluded enrollment still on the namespace
roster can ask for the successor and be answered — rotation-to-exclude is not a
revocation on its own.

**Re-derive the rate**, never quote it — five runs of `runLocal.sh` with a named
`VIRTUALENV_IMAGE`, then per run `grep -c "Dropping parked notification"` and
check whether the pqActive receiver logged `Filed the nskey private`, against the
`##GRID## up:` lines that map each cell to its `runningAs` id.

### The registrar certificate test

⛔ **POST-D1 CLEAN-UP, not a D1 gate** (gkc, 2026-08-23). **The registrar's switch
to validating TLS certificates is untested, here and in CI.** `RegistrarService`'s
default client used to accept ANY certificate — `badCertificateCallback` returning
true unconditionally, on calls carrying the registrar API key. It is now a plain
`package:http` client that validates, with the bypass behind
`RegistrarIoClient.allowBadCertificates`, off by default and shouted when used.

**Neither arm has a test**, and CI cannot catch a regression: `RegistrarIoClient`
appears in **zero** CI job logs (control: `RegistrarService` appears), and
`RegistrarIoClient.create()` has **no in-tree caller at all** — it is a public
opt-in for consumers, which is deliberate, so do not delete it as dead code.

⚠️ **Attempted and parked 2026-08-22, so the next reader does not start cold.**
The shape works: mint a cert at test time with
`openssl req -x509 -newkey rsa:2048 -nodes -subj /CN=localhost` (**do not commit a
PEM** — push protection blocks private keys), serve it with
`HttpServer.bindSecure`, and point `RegistrarService` at `localhost:<port>`, which
`Uri.https` accepts as an authority. **Three arms, and the third is the positive
control that proves the server is up**: the default client refuses,
`RegistrarIoClient.create()` with the flag off refuses, and with the flag on
succeeds. ⚠️ A probe got one import short: it needs
`import 'package:at_auth/at_auth.dart';`, which is what exports
`RegistrarApiEndpoint`.

### The `monitor:` verb has no acknowledgement

⚠️ **NOT D1, and it is a protocol seam across three repositories.** A client
writes `monitor:` and there is nothing to read back — at_server's
`MonitorResponseHandler` returns the empty string on success — so it cannot tell
acceptance from refusal, and reports a connection as up the moment the command is
*written*.

Specified upstream as
[at_protocol#367](https://github.com/atsign-foundation/at_protocol/issues/367)
with three open sub-issues: at_commons
[#2175](https://github.com/atsign-foundation/at_client_sdk/issues/2175) (a
`prompts` parameter on the verb, opt-in and additive, and it ships first),
at_server [#2764](https://github.com/atsign-foundation/at_server/issues/2764)
(answer the command, and terminate every notification with a prompt), and
at_lookup
[#2176](https://github.com/atsign-foundation/at_client_sdk/issues/2176) (send it,
wait for the answer, frame on the prompt).

⛔ **A correction to that specification, to settle BEFORE anyone builds it.** #367
says the acknowledgement lets "a refused `monitor:` be reported as a failure".
Today `monitor:` is **not** refused: `MonitorVerbHandler.processVerb` checks only
that the connection is authenticated, subscribes it, and the refusal then happens
per notification inside `_sendNotification` via `isAuthorized`, dropping each one
with a server-side warning the app never sees. A replay does not rescue it either
— replayed notifications go through the same check. So the acknowledgement ALONE
does not fix the case #367 leads with; at_server must also decide the refusal **at
`monitor:` time**. #2764 gestures at this ("A refusal must be answerable too") as
an aside rather than as the work. ✅ Verified independently against at_server by
the session working there, 2026-08-25.

**The caller-side mitigation is already built and live-proven** — `AtRpc.ready()`
and `AtRpc.listenerReadyTimeout`, with `sendRequest` awaiting readiness when
`isClient`. That closes the exposure for at_client's own callers; it does not
close the protocol gap.

### atServer outbound connection pooling

⚠️ **IN ANOTHER REPO (`at_server`), and gkc asked for it as a discussion rather
than a change** — 2026-08-24, when he took pool keying out of the concurrency
fix: *"I'd rather serialize on a single connection for now, and have a longer
discussion on how to handle outbound connection pooling and concurrency at a
later date"*. Recorded so the deferral does not read as a decision.

**What that discussion has to weigh**, all established while diagnosing the
pairwise-lookup defect:

- Every relayed lookup to a remote atSign now serialises behind every other one,
  and a request queued on the mutex is waiting *before* its 5 s read budget even
  starts, because the timeout begins after acquisition.
- `InboundConnectionImpl.equals` matches on remote **address and port** rather
  than object identity, so keying on "the real inbound connection" is not the
  identity keying it sounds like.
- `NotifyConnectionsPool.getOutboundClient` has the same non-atomic
  get/connect/add shape that the fix repaired in `getClient`.
- `PolVerbHandler` holds a third `DummyInboundConnection`, so pol's
  `lookUp`/`plookUp` share a pooled client with relayed lookups at
  `handshakeRequired: false`.

**Four residual findings belong to this discussion**, all pre-existing and none
claimed by the fix: `poolSize` is not enforced across different pool keys, so
concurrent misses for different atSigns can take the pool past its declared
maximum; an evicted client is dropped without `close()`, leaking its socket;
`OutboundMessageListener` can queue a bare `@atSign@` prompt as its own entry when
the response and the prompt arrive in separate socket reads, and `read()` accepts
a bare prompt as valid — a mis-pairing channel a mutex does not touch, since
making an exchange's two steps adjacent never validates or drains the queue; and
there is no bound on a slow-but-alive peer.

⛔ **Changing `DummyInboundConnection.equals` was never in scope and must not be
folded in** — `NotifyConnectionPool.getOutboundClient` builds a fresh dummy per
call and relies on that match to reuse a connection at all, so identity equality
there would open a connection per notification.

### 14.29 The residuals 14.25 surfaced

**S-3 — a keychain round-trip on a real device.** Nothing exercises `.atKeys`
through a real device keychain: this repo has no `integration_test` harness
(verified 2026-08-23 — no such directory and no pubspec dependency anywhere in
the tree) and at_client_flutter's keychain tests mock the platform channel
(`packages/at_client_flutter/test/keychain_io_impl_test.dart`,
`test/keychain_storage_test.dart`). Unblocking it means standing up an
`integration_test` harness in at_client_flutter first. Does not block D1.

**SS-2 / DEP4 — `__ssenv` auto-notify: deferred, do not build.** The
2026-08-03 ruling took DEP4 off SS-2 once the correctness argument behind it
was withdrawn, so what remains is a pure optimisation — an atServer that emits
the wake-up itself on a put to an `__ssenv` key, after which senders can set
`sendWakeUpNotification = false`
(`packages/at_client/lib/src/secret_sharing/pairwise_secret_sharing.dart:140`,
whose dartdoc already states the coupling). It needs parity across every
atServer implementation in one sweep, and the starting state is clean:
`__ssenv` matches nothing in any of them. Re-derive rather than quoting that —
`git -C ~/dev/atsign/repos/<repo> grep -c "__ssenv" <ref>` per implementation,
each run beside a control that matches, and name the ref because these
checkouts sit on feature branches.

⚠️ **Also owed, and nearly lost in the 2026-08-23 cut:** S-3's SECOND
remaining item is dropped. The section says plainly "S-3 — two, both small"
and then names both; the triage's owed list carries only the first (the
keychain round-trip). `LocalKeystoreAtKeysIo` is the other. I am unsure
whether it is owed or a standing out-of-scope ruling —
detail/implementation-plan.md:476 says "`LocalKeystoreAtKeysIo` over the 5.x
keystore is **out of scope** (2026-07-17 ruling)" — so per the brief I am
classifying it OWED and flagging the uncertainty. Either way it must not
vanish: if it is owed it is invisible work, and if it is a not-building ruling
it is a guard, and both survive.



### 14.18 The remaining D1 initial-development sequence

The live state is the release-train row in [`## TODO`](#todo), and step 20's
rotation arm is its own P1 row. This section keeps the carve recipe, because
links cite it.

**Carving a package PR from the spike.** One worktree per package, off
`origin/trunk`, so the PR carries that package alone; the branch name uses
hyphens where the package uses underscores (`at_lookup` → `gkc-pq-d1-at-lookup`).

```bash
git worktree add /tmp/carve-<pkg> -b gkc-pq-d1-<pkg-hyphenated> origin/trunk
git -C /tmp/carve-<pkg> checkout gkc-pq-d1-spike -- packages/<pkg>
git -C /tmp/carve-<pkg> diff gkc-pq-d1-spike --stat -- packages/<pkg>   # a list to justify line by line
```

⚠️ **A major version is not package-only**: a pub workspace refuses to resolve if
any member's constraint excludes the new version, and every job then dies at
`dart pub get` with a failure that looks nothing like a version problem. Widen
every member's constraint in the same commit (`git grep -n -P '^\s+at_<pkg>:' --
'*pubspec.yaml'`). Analyze and test the package **and its consumers**, dispatch
CI first (nothing fires on push on the spike, and CI's bare `dart analyze` reads
`benchmark/`, which `dart analyze lib test` never opens), and raise with the org
template. Order, from the pubspecs: at_commons → at_chops → at_lookup →
at_server_status → at_auth → at_client (stacked PRs) → at_client_flutter →
at_onboarding_cli. Each carve merges to trunk on its own; ⛔ **the spike branch
itself never merges**.

### 14.19 Small items, raised 2026-08-12 and not yet acted on

The items live in
[`detail/implementation-plan.md`](detail/implementation-plan.md#1419-small-items-raised-2026-08-12-and-not-yet-acted-on);
struck ones are done. Re-derive the open ones — never read a count from a
heading, this one has been stale in six homes:

```bash
awk '/^### 14.19 /,/^#### 14.19.1/' docs/projects/pq/detail/implementation-plan.md \
  | perl -ne 'print "$1\n" if /^(\d+)\. (?!~~)/'
```

Of the open ones, item 11 — an APKAM rotation that lands and is not persisted
locks the enrollment out permanently — is the owed work, and step 20's rotation
arm waits on it; 35 lands in `atGettingStarted`; 14 is not PQ; 10 is an
unexplained functional run with two disproven theories; 20, 21 and 26 were
examined and deliberately left.

### 14.12 A `mintLegacyMaterial:false` atSign cannot write a public record


⛔ **NOT D1 (gkc, 2026-08-23) — it gates the post-R-2 stop-release.** Until it
closes, `mintLegacyMaterial: false` must not be recommended to anyone. The
flag is honoured at activation — no RSA keypair is minted and no
`public:publickey` is published — but the resulting atSign then cannot publish
anything, because **every public write is signed with the legacy encryption
private key**: `put_request_transformer.dart` `_signPublicData` throws
`AtPrivateKeyNotFoundException('Failed to sign the public data')` when it is
absent. The post-quantum path itself needs two public writes — the
enrollment's `_apsk` anchor to the signing root, and the nskey advertisement —
and both fail. Sync fails alongside them ("Self encryption key is not set for
current atSign"), there being no `selfEncryptionKey` either.

**Owed, and neither move is scheduled here:** public-record signing moves onto
the ML-DSA signing root rather than the RSA encryption keypair — the same swap
IS-1 made for inter-server auth — and self data moves off `selfEncryptionKey`
onto the nskey path (B-3 phase 1, [PARKED](#parked)). The stop-release cannot
ship before both, and [decisions
42](detail/decisions.md#42-the-to-define-list-ruled-2026-08-05) item 10 has
the release default resolving null→false in the major after R-2.

Pinned live: the opt-out arm of
`tests/at_functional_test/test/pq_legacy_interop_live_test.dart` expects the
public write to fail with that exact reason, so whoever fixes this gets a red
test naming the row that was waiting for it.

⚠️ **Also owed, and nearly lost in the 2026-08-23 cut:** Two things beyond the
two code moves the triage lists. (a) A standing do-not-recommend guard on the
flag, stated twice in the section — it is a live constraint on anyone writing
docs or advising a user, and it is not recoverable from any commit. (b) The
pointer to the live test that ASSERTS the current broken behaviour. Without
(b) the builder who does the owed work gets a red functional test and has to
work out from scratch whether they broke something; the section wrote that
pointer down precisely so they would not.



### 14.11 `deprecated_member_use` findings across the workspace

gkc ruled on 2026-09-11 that the whole debt gates publication; the list is
[`docs/projects/deprecations/plan.md`](../deprecations/plan.md), and this heading
stays because links cite it. Two facts it keeps: **use the analyzer, never a
grep** — `enrollmentId` is a legitimate identifier in hundreds of places and only
the analyzer knows which uses are of the deprecated member — and the credential
ladder's replacement is the `AtAuthenticator` seam in at_auth, whose constructors
take the algorithms as required arguments so a migrated call site cannot inherit
an algorithm it did not choose.

### 14.50 The e2e teardown revokes enrollments belonging to other runs

**The e2e teardown revokes enrollments belonging to other runs.**
`tests/at_end2end_test/test/enrollment_teardown.dart` fetches *every*
`EnrollmentStatus.approved` enrollment on the shared `@ce2e1`–`@ce2e4` atSigns
and revokes each with `force: true`, and fetches every
`EnrollmentStatus.pending` one and denies it — neither loop filters to what
its own run created, so two overlapping CI runs tear each other down. A
run-unique marker already exists: `enrollment_setup.dart:110` submits with
`appName: 'wavi-$random'` (`random = Uuid().v4().hashCode`, line 101) and
`Enrollment` exposes `appName`
(`packages/at_client/lib/src/response/enrollment.dart`). What is missing is
agreement between the two steps — setup, suite and teardown are **three**
separate `dart test` invocations
(`.github/workflows/at_client_sdk.yaml:324`, `:331` and `:340`) sharing no
in-process state — so derive the marker from something both can read (`GITHUB_RUN_ID` is
the obvious candidate) and filter both loops on it. ⚠️ Green CI runs are not
evidence this is fixed: every green window since the diagnosis had no other
run in flight, so the mechanism had no opportunity to fire — it is a rate, not
a kind. ✅ **That sentence was CORROBORATED rather than falsified on
2026-08-31**, when the concurrency was counted for the first time: the two red
windows carried 4 and 3 concurrent `at_client_sdk` runs, both green windows
carried the same single long-running one and nothing else, and a run dispatched
with **zero** in flight went 11 of 11 green. The constant present in every
window cannot be the discriminator, which is what makes it a differential
rather than a tally.

⛔ **The mechanism, the evidence and the proposed fix now live in
[at_client_sdk#2197](https://github.com/atsign-foundation/at_client_sdk/issues/2197).**
What stays here is the WORK, which is still owed; the captured instances and
their timestamps belong in the issue. Do not let the two drift.

⚠️ **Also owed, and nearly lost in the 2026-08-23 cut:** A "looks like a
second defect and is not" ruling. If it goes, the next reader who sees
`PathNotFoundException` in an `end2end_test_14` log opens a second
investigation into a symptom that has already been attributed.



### 14.47 The at_client unit tree has a cross-file isolation flake

⛔ **Not a D1 gate (gkc, 2026-08-23) — hygiene.**
`packages/at_client/test/local_secondary_sync_queue_test.dart` is green alone
and green in the alphabetical full suite; it reddens only in one
hand-constructed order nothing actually runs, so no rail as invoked is at
risk. **Reproduce** (~10 runs; it failed 1 in 4, with 3 green re-runs of the
identical invocation): `cd packages/at_client && dart test --concurrency=1
test/pq_signing_root_test.dart test/nskey_minting_test.dart
test/nskey_rotation_test.dart test/local_secondary_sync_queue_test.dart`. The
failure: `'public key write enqueues with op=updateAll'` read
`['@bob:phone.wavi@alice', 'public:email@alice']` where only the second entry
was expected. ⚠️ **That entry cannot have leaked from an earlier test** — the
failing assertion is the **first** `test()` in the file (`:55`) and
`@bob:phone.wavi@alice` is built by the **second** (`'shared key write
enqueues with op=updateAll'`, `:77`), so it is state surviving from a
*previous run*. Start at `tearDownLocalSecondary` (`:38`): its `Hive.close()`
+ `Directory('test/hive').deleteSync(recursive: true)` sits inside a `catch`
that only `print`s `teardown error: …`, `setUp` is empty (`:52`) and
`setUpLocalSecondary` never clears the store — so one swallowed teardown
leaves the next run's first test attached to the old queue. Grep any run's
output for `teardown error:`. 20 at_client test files share the `test/hive`
path (`git grep -lc "test/hive" -- packages/at_client/test | wc -l`). Distinct
from
[14.43](detail/implementation-plan.md#1443-the-functional-suites-convergence-race),
which is the functional pack against a live atServer.

⚠️ **Also owed, and nearly lost in the 2026-08-23 cut:** The section names its
reproduction recipe as the thing worth keeping, and the triage's owed line
("reproduce the four-file ordering failure at rate") does not carry the recipe
itself. The specific four-file order is the whole finding — the section says
the alphabetical full suite never produces it — so it is not derivable by
anyone re-running the suite. Low risk given only ~6 of 29 lines are called
archaeology, but the command and the file order must land inside the owed
line, not beside it.

⚠️ **Also owed, and nearly lost in the 2026-08-23 cut:** Two closed questions,
neither in any commit: (a) the 14.46 edits were tested as a cause and the test
settled nothing, stated with the numbers rather than as a conclusion; (b) a
deliberate refusal to pool this with 14.43, with the reason. Losing (a)
invites the next reader to blame 14.46; losing (b) invites merging two
investigations the doc set has twice decided to keep apart.



### 14.46 `executeVerb`'s `sync` parameter is inert, on both secondaries

**14.46 Remove `executeVerb`'s inert `sync` parameter — at_client/at_lookup
4.0, not D1.** The parameter is read by no implementation; what decides
whether a local write is enqueued for client→server sync is `cameFromServer`
(and `localOnly`) in `LocalSecondary._update`/`_delete`. Phase 1 has shipped —
all six declarations carry `@Deprecated(… 'Removed in 4.0.')`: at_client's
`Secondary` (`lib/src/client/secondary.dart:14`), `LocalSecondary`
(`lib/src/client/local_secondary.dart:310`), `RemoteSecondary.executeVerb` and
`executeAndParse` (`lib/src/client/remote_secondary.dart:211`, `:236`), and
at_lookup's `AtLookUp` (`lib/src/at_lookup.dart:119`) and `AtLookupImpl`
(`lib/src/at_lookup_impl.dart:383`). Phase 2 deletes the parameter and lets
the compiler enumerate the remaining in-package call sites, which are silent
today because `deprecated_member_use` does not fire inside the declaring
package.

**at_server's mldsa65 dispatch comment is stale — lands in at_server, not
here.** On `origin/trunk`, both
`packages/at_secondary_server/lib/src/utils/apkam_signature_verifier.dart:89-90`
and
`packages/at_secondary_server/test/apkam_signature_verifier_test.dart:182-183`
say `AtChopsImpl` for mldsa65 "selects `MlDsa65PureDartAlgo`, then calls the
deprecated `verify()`". Since at_chops 3.6.0 it dispatches to
`PkamMlDsa65SigningAlgo` (`packages/at_chops/lib/src/at_chops_impl.dart:271`,
`:298`), whose verify is synchronous. Two sites, not one.

⚠️ **Also owed, and nearly lost in the 2026-08-23 cut:** The standing
HANDS-OFF guard on `docs/projects/pq/post-quantum-cryptography.md` is not in
the triage's owed list for 14.46 (which lists only the 4.0 parameter deletion
and the at_server comment). It is a do-not-do instruction of exactly the class
the triage kept as OWED for 14.29's SS-2, and it explicitly replaced an
instruction that pointed the other way. Deleting it means the next reader sees
an untracked, un-railed .md sitting in the project's own docs tree and
re-derives the sentence this bullet was written to kill — 'either finish and
track it or delete it' — against gkc's private notes, which have no undo.



### 14.44 Residuals from the at_chops PR review

**at_chops 3.6.0's CHANGELOG owes the resolution-skew sentence.** ⛔ **POST-D1
(gkc, 2026-08-23)** — it rides the next at_chops touch, amending the 3.6.0
section in place. The consumer-facing consequence to state, one sentence
beside the `0x01` removal: two installs of released at_client 3.14.0, resolved
either side of at_chops 3.6.0 reaching pub.dev, cannot read each other's
pairwise `__ssenv` envelopes in either direction for the envelopes' 7-day ttl
— at_chops 3.5.0 and older hardcode seal version `0x01`, and 3.6.0's open set
is `{0x02, 0x03}`. The durable record already exists: [ruling 110's
addendum](detail/decisions.md#110-the-0x01-seal-version-is-retired-stop-emitting-before-removing-2026-08-18).
Verified absent 2026-08-23 — `packages/at_chops/CHANGELOG.md` has no match for
skew, pairwise, 7-day or 3.14.0.

**`XWingCore.combine` writes at hardcoded offsets.** ⛔ **POST-D1 (gkc,
2026-08-23).** In
`packages/at_chops/lib/src/algorithm/encryption/x_wing_core.dart`, `combine`
sizes its buffer from the four inputs' actual lengths and then writes at
literal 0/32/64/96/128, so the two disagree for any component that is not 32
bytes. Correct for X-Wing today — every caller passes components whose lengths
the underlying primitives fix at 32. Measured rather than reasoned: a
**short** input throws `StateError: Too few elements` from `setRange`, so only
an **over-long** one is silently wrong — it truncates to 32 and leaves the
buffer's tail zeroed, yielding a shared secret neither party can detect is
wrong. Not introduced by this branch: `origin/trunk` carries the same shape in
`x_wing_pure_dart.dart` and `x_wing_ffi.dart`; extracting them widened the
reach (the trunk copies were library-private, the shared one is
package-visible) rather than creating the risk. Fix by rejecting wrong-length
inputs up front against `sharedSecretLength` — not by tracking offsets with a
cursor — so the guard states the contract instead of silently accommodating a
violation of it.

⚠️ **Also owed, and nearly lost in the 2026-08-23 cut:** The owed item is
"write a specific sentence into a published package's CHANGELOG", and the
sentence's CONTENT is in the ~45 lines the triage calls archaeology. What the
skew actually is — which two builds, in which direction, for how long —
appears in no commit (the reply that promised it is a PR comment, and the
durable record is ruling 110's addendum in detail/decisions.md). Keep the
statement of the consequence alongside the owed line, plus the constraint that
it amends the existing 3.6.0 section in place rather than opening a new
heading.

⚠️ **Also owed, and nearly lost in the 2026-08-23 cut:** A rejected proposal
with its reason: persisting `hashLength` in the passphrase envelope was the
obvious fix and was deliberately not taken. A reader seeing an envelope that
persists salt/memory/iterations/parallelism but not hashLength will re-derive
"obvious gap, persist it". The reasoning does survive in a source comment —
but only on `origin/gkc-pq-d1-at-auth`, not on this branch and not on trunk,
so on the spike the reason exists in this section alone.

## PARKED

Set aside deliberately. A row here exists to stop someone building it, so
the reason is the point of the row.

| Item  | What it is                                           | Why it is parked |
|-------|------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| [14.14](detail/implementation-plan.md#1414-a-client-with-no-enrollment-id-is-treated-as-fully-privileged) | A client with no enrollment id is fully privileged, and signs as `primary` | ✅ **CLOSED 2026-08-23 — both halves were already ruled, and nobody had closed the row.** Privilege: the resolver's own dartdoc says a client with no enrollment id authenticates with the atSign's own keys, *"which is full privilege by construction rather than by grant"*. Identity: [14.18](#1418-the-remaining-d1-initial-development-sequence) step 13 ruled that such a client publishes its `_apsk` under `primary` deliberately, as the only writer for an `_apsk` no `enroll:request` can carry. Kept so the question is not re-derived |
| [14.7](detail/implementation-plan.md#147-noports-carries-its-own-copy-of-the-envelope-shape) | NoPorts carries its own copy of the envelope shape | ⛔ **NOT D1 (gkc, 2026-08-23).** Its own text says a migration here does **not** break NoPorts — it signs with the encryption keypair and fetches `getRemotePK`, not `_apsk`. The obligation to name it as a second migration is conditional and **has not fired**: it needs RFC 7515 to become a **consumer-facing** claim, and measured 2026-08-22 the string appears in `design.md` and `detail/decisions.md` and in no file under `packages/` |
| S-5 residual | **Two String vocabularies stay untyped** | ⛔ **Considered and left, not a task.** The keyId slot prefix (`auth`/`sign`/`root`, taken by `AtKeys.keyIdPrefix` and `isRoleKeyId`) is **not** a `CryptographicMaterialRole`: typing it as one was tried on 2026-08-22 and reverted when the compiler rejected every call site. `keyAlgo`, the secret-sharing protocol id, is a third vocabulary again. Recorded so the next reader does not re-derive that these are the same thing |
| 14.26 | A false comment in at_server's `at_metadata_builder` | ⛔ **NOT PART OF D1** (gkc, 2026-08-16). It lands in at_server, off `trunk`, and nothing in D1 waits on it. Detail: [14.26](detail/implementation-plan.md#1426-a-comment-in-at_server-is-now-false) |
| 14.1  | The signing root's `keys[]` shape                    | SUPERSEDED by decisions 101 and 14.22. Kept for the reasoning; two of its conclusions are now false |
| 14.13 | A passive-by-default flag                            | FOLDED AWAY 2026-08-11 into the rollout axis (14.18 step 19). Kept for its survey |
| 14.21 | The signing root cannot be rotated                   | RULED the same day by decisions 101. Kept so 14.22 is legible against it |
| 14.23 | Per-generation nskey records                         | ⛔ REJECTED — do NOT build. 14.24 shipped instead; the body is kept so it is not re-derived |
| KE-2  | The `enroll:update` **writer**                       | **Writer built and live-proven 2026-08-19.** `KeyPackageMinting` is a startup step reconciling the advertised key package against `AtClientPreference.keyEstablishmentAlgorithms` (which replaced the singular `keyEstablishmentAlgo` in the same pass); it mints, files, retires and republishes, unit-tested and isolated by mutation. Verb merged to at_server `trunk`; the client receiver answers at every held kpid. ⚠️ This cell said "nothing mints a second KEM key and re-advertises, so a package cannot gain one" — false since that landed. UC-A2.5 and UC-A2.6 are `PROVEN`, cited to `tests/at_functional_test/test/key_package_amendment_live_test.dart` — the acceptance burn-down is back to **0 skipped**, and the `ke2` blocker constant is deleted. ⚠️ **Three clauses of those rows are NOT proven and deliberately not claimed** (a superseded kpid's envelope still opening, peer negotiation, and the revoked-enrollment gate) — plan 14.19 item 36. Issue #2133 |
| B-3   | Stop **conveying** the legacy `selfEncryptionKey`    | Narrower than it reads: the key's *use* is retired by the release cadence (R-2 flips `disallowLegacyEncryption`), so this is only relaxing `enroll:approve` to accept an approval that omits `encryptedDefaultSelfEncryptionKey` — every atServer implementation, one sweep — then ceasing to mint and convey it. Ecosystem-gated by decisions 37. Issue #2128 |
| KF-1  | `.atKeys`-at-rest protection + backup/restore        | Off the GA critical path. Issue #2129 |
| S-5   | at_auth 4.0.0 WASM barrel split                      | **DONE 2026-08-22** — awaits publish |
| S-6   | Consumer constraint bumps onto at_auth ^4.0.0        | **DONE 2026-08-22** — at the `-rc1` floor |
| R-2   | at_client 4.0.0 posture defaults                     | After D1. **The default `PqPosture` becomes `pqActive`** ([ruling 113](detail/decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18)) — one value, replacing the two coupled edits it used to be. Still a pure default-flip carrying no code of its own. Issue #2016.<br><br>⚠️ **R-2 is TWO stages across two majors again, superseding the one-stage reading below.** [ruling 138](detail/decisions.md#138-the-posture-ladder-moves-back-a-stage-2026-09-08) moved the ladder back on 2026-09-08: at_client 3.x defaults to `legacy`, 4.x to `pqReady`, 5.x to `pqActive`. So R-2 is `legacy` → `pqReady` at 4.0.0 and a further `pqReady` → `pqActive` at 5.0.0. ⚠️ **This paragraph used to read** *"R-2 is now a ONE-STAGE step, not two. The shipped default moved `legacy` → **`pqReady`** on 2026-08-26, so R-2 is `pqReady` → `pqActive`"* — that default is reverted, unpublished and spike-only, so nothing in the field moves with it — the two axes ruling 113 names as the only difference between them (the data signing key becomes ML-DSA, and post-quantum writes become the default). This row said "and now after 14.39" while 14.39's posture work was owed; it landed |
| D2-1  | Carve `at/pqmls` + D1-E shape fixes                  | D2, out of D1 |

---

## Re-deriving the state

Run these rather than trusting a row. No figure lives here: the command is the
value, and a number written beside one has rotted every time.

```bash
# The clause meter — proven and server-proven — prints on every run of the suite.
cd packages/at_client && dart test test/acceptance --concurrency=1 | grep BURN-DOWN
# Which rows owe live proof, which are exempt, which clauses cannot be proven, and why.
grep -n "^  'UC-" packages/at_client/test/acceptance/manifest.dart

# The release train: the tree's version beside the newest on pub.dev.
# The versions LIST, never `latest` — `latest` hides prereleases.
for pkg in at_commons at_utils at_chops at_lookup at_server_status at_auth at_client at_client_flutter at_onboarding_cli; do
  printf '%-20s tree %-12s pub.dev %s\n' "$pkg" \
    "$(grep -m1 '^version:' packages/$pkg/pubspec.yaml | cut -d' ' -f2)" \
    "$(curl -s https://pub.dev/api/packages/$pkg | jq -r '.versions[-1].version')"
done

# CI. Nothing fires on push on the spike, so the newest run is only as new as the
# last dispatch; dispatch at each new head and read it. CI's at_client job runs a
# bare `dart analyze` that reads benchmark/, which `dart analyze lib test` skips.
gh run list --branch gkc-pq-d1-spike --limit 4 --json headSha,conclusion,workflowName \
  --jq '.[] | [.headSha[0:9], .workflowName, .conclusion] | @tsv'
gh workflow run at_client_sdk.yaml --ref gkc-pq-d1-spike
# One job's rate over recent runs (functional_tests, pqe2e_tests, end2end_test_14).
for r in $(gh run list --branch gkc-pq-d1-spike --workflow at_client_sdk.yaml --limit 20 --json databaseId --jq '.[].databaseId'); do
  gh run view "$r" --json jobs --jq '.jobs[] | select(.name|startswith("functional_tests")) | [.name,.conclusion] | @tsv'
done | sort | uniq -c | sort -rn

# 14.19: the open small items (struck ones are done). Against detail/, where they live.
awk '/^### 14.19 /,/^#### 14.19.1/' docs/projects/pq/detail/implementation-plan.md \
  | perl -ne 'print "$1\n" if /^(\d+)\. (?!~~)/'

# The citation denominator. ⛔ rm first — provenIn APPENDS, and a stale file reads as twice the corpus.
cd packages/at_client && rm -f /tmp/cit.jsonl && \
  ACCEPTANCE_LEDGER=/tmp/cit.jsonl dart test test/acceptance --concurrency=1 >/dev/null
python3 -c "import json;r=[json.loads(l) for l in open('/tmp/cit.jsonl')];print(len(r),'citations,',sum(1 for x in r if not x.get('clauses')),'unpinned')"
git grep -c 'provenIn(' -- packages/at_client/test/acceptance | awk -F: '{s+=$2} END {print s}'   # the second derivation, +2 in proven_elsewhere.dart

# Acceptance: what is skipped, and on which blocker. Anchor on "}, skip:" — a bare "skip:" matches prose about skips.
grep -rn "}, skip:" packages/at_client/test/acceptance/*_test.dart
grep -n "blocked:\|owed:" packages/at_client/test/acceptance/blockers.dart

# The `legacy` vocabulary completion test (P0), control first: the control line must print.
printf 'the client writes legacy and stops\n' | perl -ne 'print "CONTROL OK\n" if /\b(writes|written|stays|remains)\s+legacy(?!\s*(provider|posture|-encrypted))/'
find packages tests -name '*.dart' -not -path '*/.dart_tool/*' -print0 \
  | xargs -0 perl -ne 'print "$ARGV:$.: $_" if /\b(writes|written|stays|remains)\s+legacy(?!\s*(provider|posture|-encrypted))/; close ARGV if eof'

# The rails. The exit code is the verdict, never the count.
cd packages/at_client && dart analyze lib test && dart format . -o none --set-exit-if-changed && dart test --concurrency=1
for p in at_auth at_lookup at_commons at_chops at_onboarding_cli at_policy; do (cd packages/$p && dart test --concurrency=1); done
cd packages/at_client_flutter && flutter analyze       # `dart analyze` skips a Flutter package silently
for t in at_functional_test at_end2end_test at_onboarding_cli_functional_tests at_onboarding_cli_functional_tests_proxy; do (cd tests/$t && dart analyze test); done

# The four live packs, each through its own runner (the atsign-live-testing skill has the fixture rules).
# Pin the image by building it from a ref you name: no label on at_virtual_env:local says which atServer it holds.
VIRTUALENV_IMAGE=<a-ref-you-named> bash tests/at_functional_test/runLocal.sh
VIRTUALENV_IMAGE=<a-ref-you-named> bash tests/at_end2end_test/runLocal.sh 26000 test -x pq
VIRTUALENV_IMAGE=<a-ref-you-named> bash tests/at_end2end_test/runLocal.sh 26000 test/pq -x legacy-server
VIRTUALENV_IMAGE=atsigncompany/virtualenv:vip-p3.15.0 bash tests/at_end2end_test/runLocal.sh 26000 test/pq -t legacy-server
bash tests/at_onboarding_cli_functional_tests/runLocal.sh 47000
bash tests/at_onboarding_cli_functional_tests_proxy/runLocal.sh 48000
```

⛔ **There is no command for "which atServer build is in `at_virtual_env:local`".**
The image's `org.opencontainers.image.revision` label describes the published
base image, not the binaries compiled into it. Build from a ref you name:
`git -C <at_server> worktree add --detach <dir> <ref>`, compile
`at_secondary_server` and `at_root_server` with `docker run --rm -v "<dir>:/app"
-w /app/packages/<pkg> dart:3.11.2 sh -c 'dart pub get && dart compile exe
bin/main.dart -o <name>'` (a detached worktree, because the in-container `dart pub
get` rewrites `.dart_tool` with `/app` paths), copy both into
`tools/build_virtual_environment/ve/contents/atsign/{root,secondary}/`, and
`docker build` there.

**After D1** comes the release programme, ending with R-2, the at_client 4.0.0
posture flip to `pqActive`
([ruling 113](detail/decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18)):
a pure default flip carrying no code of its own, so anything the posture needs
lands in D1 before it. The ordered publish list is
[detail — what still has to be published, in order](detail/implementation-plan.md#what-still-has-to-be-published-in-order);
re-derive it with the loop above before acting on it.
