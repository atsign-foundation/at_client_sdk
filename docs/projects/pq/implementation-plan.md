# implementation-plan.md — what is still owed

⛔ **This document records only what is still owed** (gkc, 2026-08-23). What has
been done is in the codebase and in `git log`; it is not repeated here. The one
exception is a claim somebody would otherwise re-derive — a rejected proposal, a
measurement that closed a question — and those live in
[`decisions.md`](decisions.md), because a rejection is a decision and no commit
can contain a thing that was never built.

**There is ONE list, and it is [`## TODO`](#todo) below.** Every open item has a
priority and appears exactly once. Detail for an open item is a `###` section
under the list; everything discharged is in
[`detail/implementation-plan.md`](detail/implementation-plan.md).

**Item ids are permanent.** `14.13` and `14.19 item 11` are cited from
production dartdoc and from `blockers.dart`, so an item keeps its id wherever it
sits. Nothing here is ever renumbered.

**The priorities**, agreed with gkc 2026-08-26:

| | |
| --- | --- |
| **P0** | on D1's critical path — including work blocked elsewhere; the `Blocked on` column carries startability |
| **P1** | must do before D1 closes |
| **P2** | should be done if there is time |
| **P3** | nice to have; explicitly after D1, or in another repo |

⚠️ **Re-derive before acting on any row below.** Every "current state" table in
this project has been wrong at least once by being carried forward; the commands
that re-derive them are in
[Re-deriving the state](#re-deriving-the-state) at the end.

---

**D1 ends when every acceptance test passes and every rail is green, the posture
matrix included** — ruled by gkc 2026-08-23. What D1 requires is that the
acceptance set is **complete, implemented and verified**. Everything else is a
judgement call, and nothing outside the acceptance set can move the boundary.

⚠️ **Two earlier forms of that definition are wrong and both were in this file.**
It read "ends at step 34 — the spike carved into stacked PRs and merged", and
then "ends when at_auth 4.0.0 is published, the staged status value is added and
step 20's rotation arm is green". The carves, the publishes and the rotation arm
are all still owed and still sequenced — they are simply not what *defines* the
boundary. "In D1" means "owed before D1 closes"; it does not mean "defines when
D1 closes". R-2 still follows D1.

⛔ **"All acceptance tests pass" is true today and does not yet mean what this
definition needs.** Every catalogue row reads `PROVEN` and every live one has a
scenario — **73 rows, 72 live, UC-C1.3 withdrawn** at the time of writing, and
that pair moves whenever a row lands, so re-derive it from `acceptance.md`'s
own summary sentence rather than from here — but the rail checks
**structure**: that a scenario exists, that ids resolve, that counts match, and,
where a citation pins THEN clauses, that each pin resolves to exactly one.

⚠️ **Almost no citation pins anything, and this sentence used to read as
though they generally did** ("since the clause level landed, that a citation
pins the THEN clauses it claims"). Measured 2026-08-26 at `c014e4fa5`:
**13 of 145 citations carried `clauses:`; the other 132 kept the old
all-or-nothing verdict.** ⛔ **That was 2026-08-26 and BOTH the figure and the
conclusion it carried are dead.** Re-derived 2026-08-29: **159 of 268 pinned,
109 unpinned — 59%**, not 9%. The sentence that stood here called the clause
level ~~"a facility that is 9% adopted, not a property the catalogue has"~~, and
a reader planning from it would have been planning around a facility barely in
use. ⚠️ **The lesson is the shape, not the number**: the figure carried a date
stamp, the stamp read as absolution, and the *conclusion built on it* was left
standing for three days after the figure moved. Do not restate any percentage
here — re-derive it. Omitting `clauses:` remains legal by design: `provenIn`'s
dartdoc says so, and the ledger reports such a row as having unpinned clauses
rather than pretending they are covered. Re-derive, never quote:

```bash
cd packages/at_client && rm -f /tmp/cit.jsonl &&   ACCEPTANCE_LEDGER=/tmp/cit.jsonl dart test test/acceptance --concurrency=1 >/dev/null
# ⛔ rm first — provenIn APPENDS, and a stale file reads as ~2x the citations
python3 -c "import json;r=[json.loads(l) for l in open('/tmp/cit.jsonl')];print(len(r),'citations,',sum(1 for x in r if not x.get('clauses')),'unpinned')"
```

And what no rail checks at all is whether the cited test really *establishes*
the clause; that judgement is the citation's, written in `proves:`. Reading
those is the [acceptance audit](#the-acceptance-audit), which is finished —
the reading it describes was done on 2026-08-26 and what it found is
[a row of its own](#the-clause-burn-down-every-provable-then-clause-proven).

---

⛔ **A STANDING PROJECT PREMISE, and it settles more arguments than it looks
like it should.** **No production `.atKeys` file or keychain entry holds any PQ
key material** (gkc, 2026-08-23).

The consequence is the one worth carrying: **any argument of the form "X already
exists in the world, so we must tolerate it" is void here until somebody names
the holder.** As of 2026-08-23 this fact had closed three separate questions that
each looked like a real compatibility constraint — [14.19 item
11](detail/implementation-plan.md#1419-small-items-raised-2026-08-12-and-not-yet-acted-on)'s
"wait for the fleet" gate before emitting a staged status, item 23's "who holds
a `version: 1` keyfile with an empty `keys` array", and both questions left open
beneath [ruling 114](detail/decisions.md#114-a-signer-waits-for-its-own-mint-the-mint-alone-does-not-superseded)
(durable pre-mint auth-fallback envelopes, and the verifier's pre-mint cache
asymmetry). Each needed a PQ-material holder to exist, and none does.

⚠️ **It is a statement about today, not a licence.** The moment a released build
starts writing PQ material, every one of those questions becomes reachable and
has to be re-asked rather than re-cited from here.

⚠️ **A second workstream is open and is NOT in the list below** — the knowledge
base, agreed with gkc 2026-08-20. ⛔ **It is the ONLY one**: the at_lookup
consolidation used to be a second uncarved exception, discoverable only from
`~/.claude/` memory, and its three open items were moved into the bands below
on 2026-08-27 (P2 and P3). If you find a third, it belongs in the list rather
than in a sentence like this one. Its plan, format, rail design and ordered
method are in [`docs/knowledge/README.md`](../../knowledge/README.md), which is a
scaffold with no nuggets written yet. If that is what you are here for, open that
file instead.

---

## TODO

⛔ **The single list, and the only one. One row per open item, bucketed by
priority.** A row's "what is owed" is the whole of what is owed; where that
needs more than a sentence, the row links to a `###` section below or to
[`detail/implementation-plan.md`](detail/implementation-plan.md).

**The next move is: pick one of the P0s. If there are no P0s, pick a P1, and so
on.** That is the whole rule (gkc, 2026-08-26). A row whose "Blocked on" column
says anything other than Nothing is not pickable, so it does not compete.

⛔ **There is no `[RECOMMENDED]` marker and no `## THE NEXT MOVE` section** —
both were deleted on 2026-08-26. A single recommendation sitting above the table
is one fact with two homes, and it drifted every time: it twice carried two
`[RECOMMENDED]` markers at once, it went on recommending work that had shipped,
and it kept its own copy of what was blocked beside the column that already said
so. The buckets are the ranking. Nothing ranks within a bucket, and nothing needs
to.

⛔ **When more than one row in the highest non-empty bucket says `Blocked on:
Nothing`, ASK GKC WHICH** (his ruling, 2026-08-27). That is the tie-break, and it
is deliberately not a rule: any rule strong enough to choose would be a second
ranking, which is the thing the paragraph above deletes. Document order carries
no meaning, so a session that picks by it has guessed.

⚠️ **A row leaves this table when it is done — it does not gain a ✅ STATUS.**
There is nowhere to move it to: what was done is in `git log`. ⚠️ **The rule is
about a row's status, not about the word appearing in its prose**, and it read
unqualified until 2026-08-27, when a cold read counted four ✅s in this table and
called them defects by its own wording. A ✅ inside a "what is owed" cell,
marking which *part* of a live row has landed, is the cell doing its job — a
seeding row whose reproduction is done and whose loop rate is not needs to say
both. What is forbidden is a row that is *finished* and still here. A rail enforces the
direction (`packages/at_client/test/acceptance/docs_structure_test.dart`, "no
TODO row names a section whose body declares itself done").

⛔ **`## PARKED` runs the OPPOSITE convention, deliberately, and neither section
said so until a cold read asked.** Parked rows keep a `✅ DONE` or `✅ CLOSED`
marker in place, because what a parked item needs to say is *why it stopped
being parked* — a row that simply vanished would read as never having been
considered. So a ✅ in `## TODO` is a defect and a ✅ in `## PARKED` is the
record working. Do not "tidy" one to match the other.

### P0 — on D1's critical path

⚠️ **P0 no longer means "startable now"** (gkc, 2026-08-31). It means **on the
critical path**, and the `Blocked on` column says whether a row can be started.
The two were conflated, which forced anything blocked in another repo out of P0
however directly it blocked goal 1 — every provable THEN clause proven. A row waiting on
an at_server push or an at_commons publish belongs here if a clause cannot be
proven without it; what it is waiting for goes in the third column, which is
what that column is for.

| Item | What is owed | Blocked on |
| ---- | ------------ | ---------- |
| [the clause burn-down: every provable THEN clause proven](#the-clause-burn-down-every-provable-then-clause-proven) | **The definition of done, and the campaign to reach it** (gkc, 2026-08-27). **Objective 1:** every **provable** THEN clause in the catalogue proven by some test — restated 2026-08-31 (gkc). It used to read *every THEN clause*, and one clause cannot be proven by construction, so the objective as written was unreachable and the burn-down’s `N of T` implied a target of `T` that nothing could ever hit. The exceptions are enumerated in `unprovableClauses` in `packages/at_client/test/acceptance/manifest.dart`, each carrying the reason it cannot be closed, and two rails keep the list honest: one fails if an entry names a use case or clause index that does not exist, or names a clause that has since been PROVEN (an entry that has been overtaken must be deleted, not left standing); the other prints `REACHABLE  provable clauses: P of T   proven: N   still to prove: K` beside the burn-down. Today the list holds exactly one clause — **UC-G2.9 c3**, which asserts that step 3’s verifier-side accept lever DOES NOT EXIST: building the lever falsifies the clause, and pinning the absence would count a hole as proven. ⛔ **This is NOT the third state rejected at the foot of this row.** That rejection forbade splitting the proven figure by what a clause is waiting on; the proven count here is still one number over the whole catalogue. What the list changes is the *denominator’s* reachable part, so the target can be read off rather than assumed. **Objective 2:** every clause proven only in-process gains a proof against a real atServer wherever feasible. Read the meter by running the acceptance suite: it prints `BURN-DOWN  clauses proven: N of T   server-proven: M of T`. ⚠️ **A pin is a claim, not a run** — `tool/acceptance_ledger.dart` is what says the cited test passed. This row **absorbs the old "what the citation audit left owed"**, whose five findings (F16, F15, F8, F1, F3) are clause gaps by another name.<br><br>✅ **Sixteen clauses closed, 2026-08-28 and 29**, and one WITHDRAWN. The test files that did it are named here, which was necessary because no rail could see them at the time: the naming rail walked `tests/` for `pq_*_test.dart` alone, so a file under `packages/at_client/test/` was out of its root and a file under `tests/` not named `pq_*` was out of its filter. ✅ **Both gaps are now covered** — the root takes in every package's `test/` tree, and a second rail requires every file a `provenIn` citation names to appear in the doc set, which reaches these whatever they are called. The names below are kept as the record of what closed each clause, not because anything now depends on them being here. **UC-G2.6 c4 and c6** in `packages/at_client/test/nskey_seeding_test.dart` and `packages/at_client/test/nskey_minting_test.dart`: c4 measured as a COUNT of the kids `_addMissing` attempts to convey, so a re-send shows as a second entry instead of being invisible; c6 by minting under one enrollment and adding under another, with a control reading the signer before the add. **UC-G2.11 c1 and c2** in `tests/at_functional_test/test/nskey_rollout_ladder_live_test.dart` — two real enrollments of one atSign at different algorithm configurations against a live atServer, which UC-G2.11's `liveProofOwed` entry said no pack did; that entry is now spent and deleted. ⚠️ **The live file runs both installs at `PqPosture.legacy` with the seeding driven by hand**, because a seeding posture makes each client's tail take the mint lock at the production two-minute ttl and the second install's add is then refused — the interlock working, not a defect. What that file proves is the mint, the add and the data path; not their scheduling. **UC-B1.3 c1** across `tests/at_end2end_test/test/pq/retrofit_e2e_test.dart`, `packages/at_client/test/pq_signing_root_test.dart`, `packages/at_client/test/secret_sharing_approver_test.dart` and `tests/at_functional_test/test/enrollment_namespace_gate_test.dart` — four of its parts, three of which already had proofs that nothing had pinned. What was genuinely missing was the *reason* the decline gives: `requestPrivateIfAbsent` returns 0 for three different causes — already holding the root, having no enrollment id, and not being entitled — so a silent decline leaves an operator no way to tell them apart, and the log is the only signal. Asserted with the privileged arm of the same method as its control. **UC-A3.4 c3** in `tests/at_functional_test/test/nskey_self_notify_live_test.dart`, whose last arm destroys the receiving enrollment's monitor socket, notifies from the sender over its own verb connection, and asserts the value arrives and decrypts after the reconnect. ⚠️ **It was unwritable until [ruling 125](detail/decisions.md#125-a-hive-stores-identity-is-its-storage-path-not-its-atsign-2026-08-28)**: two enrollments of one atSign shared a Hive box whatever `hiveStoragePath` each was given, so they shared the notification replay watermark — a self notification reaches every listening monitor of the atSign, the SENDER's received this one and advanced the shared watermark past it, and the receiver's reconnect then asked for everything after the notification it had missed. Putting both enrollments back on one path reddens the arm with exactly that diagnosis. ⚠️ **The same fix exposed three tests that were green for the wrong reason** — see the P1 row on removing the override. **UC-A2.3 c1** in `tests/at_functional_test/test/enrollment_namespace_gate_test.dart`, which gains a second test for the row's last sentence — the ordinary records an application reads and writes, as against the `__ssenv` delivery channel its first test already covered. Both verbs, because the atServer answers them separately: an `llookup` and an `update` in the ungranted namespace are each refused under their own verb name, while both succeed in the granted one on the same connection, with the approver reading both records first so the refusals are a gate rather than an absent record. **The behaviour was probed against a live atServer before any assertion was written** — a clause about what a server enforces cannot be settled by reading the client. **UC-G2.7 c4** across `packages/at_client/test/nskey_rotation_test.dart` and `packages/at_client/test/published_nskey_key_ring_test.dart`, the second of which already existed and was unpinned. ⛔ **Its JUSTIFICATION was false and the assertion was not.** The clause said three writers produce a retired entry — the key package's mint, the signing key's mint and the signing root's — and there are two: `PqSigningRoot._publish` is the root record's only writer, emits a single-entry `keys` list carrying no `status`, and production says beside it that *no rotation exists to repair it with*, so nothing can add a second entry. Corrected in the catalogue in the same commit. A test written to the three-writer sentence would have gone red and the natural fix would have been to weaken it until it passed, which is how a false clause gets enshrined. The new arm proves the generational half: after a rotation every entry of the successor is still offered for new work — an absence, asserted over the whole list with the list proven non-empty — and what opens history is the previous generation's private, still filed. Mutation-proven against production: dropping `offeredForNewOperations` from `bestKeyFor` reddens the reader arm. ⛔ **UC-G2.7 c5 was WITHDRAWN the same day** (gkc): it scoped the row against UC-G2.3 rather than asserting a behaviour, and nothing could close it — after a retirement and after a compromise the key material is in the same state, so the two differ only in the status token, of which `KeyEntryStatus` has one. Pinning it against an unknown token would have proven UC-G2.3's clause under this row's name. The sentence stays under the row as prose, and the denominator went 190 to 189. **UC-B1.1 c3** in a new file, `tests/at_end2end_test/test/pq/retrofit_cap_value_e2e_test.dart`, which measures the cap as a VALUE rather than as an outcome. `retrofit_retirement_e2e_test.dart` proves what the cap does, but runs at a **zero-hour** grace where `min(now + grace, its own remaining lifetime)` always takes `now` — so an atServer that set the expiry unconditionally would satisfy every assertion in it. The new file runs at the ordinary grace with three parents straddling it: one expiring in an hour keeps its own expiry, one expiring in 2000 hours is pulled in by more than a day, and one with no expiry at all gains one. ⚠️ **Every comparison is between two values the atServer produced**, never against the test process's clock, which would be measuring clock agreement between two machines. Three things the probe behind it established, none of them guessable: `apkamKeysExpiryDuration` is honoured on an ordinary OTP enrollment and reaches the wire as `apkamKeysExpiryInMillis`; the enrollment record stays at `<id>.new.enrollments.__manage@<atSign>` after approval, there being no `.approved.` address; and **the cap is per-parent, not per-atSign** — retrofitting one leaves its siblings at record version 1, which is what makes the file safe on an atSign other rows share. **UC-A5.1 c2** across `tests/at_functional_test/test/nskey_rotation_live_test.dart` and `packages/at_client/test/ck_manager_test.dart`. The live file proved the keys — published, pushed, excluded, retained — and never that the data path then picks the successor up, so a rotation whose successor no writer used would have satisfied every assertion in it. It now writes on the nskey data path either side of the rotation and reads which generation each content key's conveyance was sealed to: same client, same ring, same namespace, and the rotation the only thing that changed. The unit file carries the peer half — a sender re-checking on its next `ensureCurrent` and cutting a fresh CK rather than sealing to the superseded generation. ⚠️ **The conveyance is read LOCALLY, through `getMeta`.** A self conveyance is written local-first and reaches the atServer when sync gets round to it, so asking the atServer races the push and fails with *does not exist in keystore* — the address right and the record not yet travelled; nothing in that pack syncs. **UC-A2.1 c4** in a new file, `tests/at_functional_test/test/pq_scoped_enrollment_self_read_test.dart`. Its two halves were each covered separately and never together: `pq_native_app_enrollment_test.dart` shows an ML-DSA enrollment is post-quantum from birth but is fully privileged and reads nothing, and `enrollment_namespace_gate_test.dart` shows the atServer refusing a scoped enrollment the envelope channel of an ungranted namespace but authenticates with RSA-2048 and never builds a client. One enrollment now does both — ML-DSA APKAM, opening @alice's own record in its granted namespace, refused the other namespace's key channel on the same connection. Submitting the same enrollment as `rsa2048` reddens it, because the client then retrofits onto a replacement. ⚠️ **A scoped enrollment cannot heal a missing private by pulling** — the per-enrollment secret-request gate serves only fully privileged requesters — so what this proves is the approval-time PUSH; and the read must come after `pqBootstrap.startupComplete`, because the sweep that files an arriving private is a fire-and-forget startup step. Without that wait it fails with *no nskey private held … or has not yet received that generation*, which is true and is not the claim. **UC-A4.1 c3** in `tests/at_end2end_test/test/pq/nskey_multi_enrollment_test.dart`, whose two live enrollments of @bob are the fixture the arm needed. @alice shares a second post-quantum record into a namespace the second enrollment was never granted; @bob's atServer refuses it the fetch, naming the verb, the enrollment id and the namespace, while the same client reads the granted namespace on the same call — so only the grant varies. Making the fully privileged client the refused one reddens it, printing the decrypted value: the refusal is a property of the reader, not of the record. ⚠️ **It cannot be shown by `llookup` on @bob's atServer** — a record @alice shares lives on ALICE's atServer, so that verb answers *does not exist in keystore* whatever the grants are, which is an absent record dressed as a gate. That is what the first attempt did, and its control caught it. **UC-A4.4 c3** in the same file, and NOT in the `monitor_reconnect_live_test.dart` its row named — that file shows a queued notification surviving an outage with one atSign notifying itself and no namespace key in it, which is a different claim. The second enrollment's monitor socket is closed, @alice sends again from her own client on a different socket to a different atServer, and the value still opens on the key that enrollment already held. ⚠️ **The outage has to be proven, not staged**: a notification handed to a live monitor and one replayed to a reconnecting one satisfy the same assertion, so the connection-down event is watched for before the close and gated on before anything is sent; removing the close reddens that gate with an empty event list. ⚠️ **`isNotifying` cannot serve as that gate and reads as though it can** — it is a session flag cleared only by `stopNotifications`, and the reconnect loop reads it to decide whether to keep trying, so it stays true across exactly the drop being staged. `AtLookUp.notificationConnectionUp` is the observable that answers it. **UC-A4.4 c1** in `tests/at_end2end_test/test/pq/nskey_notify_test.dart`, which delivered the cross-atSign notification to a single bob client and so could not see the failure the clause names — delivered to every monitor, readable on one. It gains a second authorised enrollment of @bob on a monitor of its own, holding no nskey private of its own, so opening the value means the namespace private reached it by conveyance. Its monitor is gated on a notification actually arriving before anything is sent, since `subscribe()` returns before the socket has written `monitor:` and the monitor asks for no backlog; the atServer's own `statsNotification` is both the gate and the positive control. Mutation-proven: subscribing that enrollment with `shouldDecrypt` false reddens the value assertion with the ciphertext while the frame still arrives. **UC-A4.3 c1** in `tests/at_end2end_test/test/pq/nskey_multi_enrollment_test.dart`, which already ran one alice client against two of bob's enrollments and so established only half a clause that also says *whichever of alice's enrollments wrote it*. It gains a second enrollment of @alice — its own store, because a content key is a client-side cache and a shared store would let alice2 resume the current-CK pointer alice1 left behind — writing a second record that both of bob's enrollments then read. The differing `ckKid` is what carries the claim, and it is mutation-proven: moving that write back onto alice1 reddens exactly that assertion, because `CurrentCkPointer` is read from local storage. bob's second enrollment needs no such separation — nskey privates are filed through `AtKeysIo`, and an enrollment made by the e2e fixture carries an in-memory one of its own. **UC-B5.6 c1** across `tests/at_functional_test/test/nskey_rotation_live_test.dart` and `packages/at_client/test/nskey_rotation_test.dart` — the clause bundles four assertions and two of them were unasserted, which is why it stood unproven while the row above it read PROVEN. Live: the refusal now has to carry the retry guidance as well as the cooldown's name, since an error that says only *refused* sends an operator looking for a stuck lock to clear and there is none — nothing releases a mint lock but its ttl. Unit: the namespace `revokeEnrollmentAndRotate` could not rotate is named at **SEVERE**, because a namespace that failed is simply absent from the returned outcomes and is otherwise indistinguishable from one that needed nothing. That log assertion carries its own control — an INFO line the same call emits regardless — so an unbound recorder is reported as unbound instead of passing every level assertion by matching nothing.<br><br>⛔ **PROPOSED AND REJECTED 2026-08-28: do not add a third state to distinguish "needs a test" from "needs a feature".** Some unproven clauses wait on a test and others on an unbuilt mechanism — the signature key identifier, the durable revocation record, step 3's verifier lever — and it is tempting to declare blockers for the second kind so the figure reads honestly. gkc ruled against it: one number is easier to hold than three, the distinction is discoverable by reading the rows, and [`decisions.md` 35](detail/decisions.md#35-the-owed-a-test-backlog-reached-zero-2026-08-04) already records that conflating *blocked* with *owed* made this very burn-down **misleading in both directions at once**. The project killed an "in progress" state on the same reasoning. Adding states risks the measure becoming something to game rather than something to close | Nothing |
| [14.18](#1418-the-remaining-d1-initial-development-sequence) **the release train** | **gkc publishes at_auth 4.0.0-rc1**, then carve at_client (stacked) → at_client_flutter → at_onboarding_cli. Six of the eight positions are through by merge; what is left is publishes | gkc, and the first thing owed is a DECISION rather than a publish. ⚠️ **Merged is not published — and at_auth&#39;s `4.0.0-rc1` is a version collision waiting to happen.** pub.dev holds no at_auth 4.x, while `origin/trunk` AND this branch both declare `version: 4.0.0-rc1`; trunk&#39;s at_auth is 19 commits behind the spike and still carries the two-clause `_apsk` form guard the spike replaced with the BREAKING one-clause fix. Publish rc1 from trunk and the version number is spent: the spike&#39;s BREAKING change has no heading left to land under, and `at_client` pins `at_auth: ^4.0.0-rc1`, so a later at_client carve resolves the fix-less rc1 from pub.dev. **Three ways out and they are different decisions:** re-carve at_auth from this spike, cut `4.0.0-rc2`, or publish rc1 knowingly. ⛔ **No doc anticipated this** — `git grep -P 'rc2\|re-?carve' -- docs/` returns nothing against 5 files for `rc1`. Measured 2026-08-31 |
| **at_commons publish owed** | **Publish it.** Both changes are on trunk under one `5.17.0` heading — [#2194](https://github.com/atsign-foundation/at_client_sdk/pull/2194) (`enroll:infons`) and [#2182](https://github.com/atsign-foundation/at_client_sdk/pull/2182) (`Metadata.fromJson` preserves a null `ttl`/`ttb`/`ttr`). Nothing here waits on more code. ⛔ **at_server keeps a local `infons` syntax override until this publishes** — it inserts the token into at_commons' pattern rather than copying it, and carries a tripwire test that reddens the day a published at_commons defines it, so the removal does not depend on anyone remembering | gkc — publishing is his act |
| **at_chops 3.6.1** | **Publish it.** [PR #2181](https://github.com/atsign-foundation/at_client_sdk/pull/2181) merged to trunk on 2026-08-24 and pub.dev still tops out at `3.6.0`. Independent of at_auth and of the spike | gkc |
| **at_server: the retrofit cap is armed by the successor** | ⛔ **A POINTER ROW, not a second home for the design** (gkc, 2026-08-31). What is owed is in [ruling 118](detail/decisions.md#118-the-retrofit-cap-is-armed-by-the-successor-not-by-the-retrofit-2026-08-27); the behaviour is specified by [UC-B2.2](acceptance.md#92-uc-b22--grace-period-variant) c1. Neither is restated here and nothing but the pointer belongs in this cell. ⚠️ **Ruling 118 says the catalogue tracks this and not a plan row**, and its reasoning stands — an unproven clause IS the D1 gate. The row exists because a reader working P0 top-down would otherwise never learn that the clause waits on another repo; gkc ruled 2026-08-31 that a pointer row satisfies that without giving the design two homes | a **VE image built from a server carrying it**. ✅ [PR #2781](https://github.com/atsign-foundation/at_server/pull/2781) MERGED 2026-09-01 at `45846a7b`, so at_server owes nothing here; our packs talk to `at_virtual_env:local`, which nothing in this repo builds, so the clause cannot be proven against a real atServer until that image exists. ⚠️ **This cell named at_server as the blocker through three states in two days — `unpushed with no PR`, then `open as of 2026-08-31`, then merged — and went on naming at_server after the thing it waited for had landed**, which made the row neither pickable nor honestly blocked. Re-derive: `gh pr view 2781 --repo atsign-foundation/at_server --json state,mergedAt` |
| **at_server: revocation cascades to descendants** | ⛔ **A POINTER ROW, not a second home for the design** (gkc, 2026-08-31), on the same terms as the row above. What is owed is in [ruling 129](detail/decisions.md#129-revocation-cascades-to-descendants-and-the-roster-does-the-rest-2026-08-31); the behaviour is specified by [UC-A5.3](acceptance.md#63-uc-a53--enrollment-revocation) c2. ⚠️ **This replaces the ruling 121 row struck 2026-08-31.** [121](detail/decisions.md#121-a-revocation-publishes-what-it-obliges-2026-08-28) is SUPERSEDED by 129 and 130, so that row was owed work that no longer exists: its client half — a durable client-written revocation record, and a client-side subtree walk over `parentEnrollmentId` — is retired, and what took its place is the atServer's own durable revocation event log, read back as a per-namespace moment through `enroll:infons`. ⚠️ **This said "the atServer-stamped `revokedAt`" until 2026-08-31** — at_server removed that field in favour of the log, so 121's record SHAPE survives and only its writer moved, whose client work is the `UC-G2.5 c5` row above | at_server — ✅ **[PR #2781](https://github.com/atsign-foundation/at_server/pull/2781) MERGED 2026-09-01** at `45846a7b`, and `gkc-retrofit-successor-grants-and-cap` is deleted from the remote. ⚠️ **This cell said `open as of 2026-08-31` and, earlier that same day, `unpushed with no PR`** — three states in two days, which is why nothing here quotes a sha or a commit count. Re-derive: `gh pr view 2781 --repo atsign-foundation/at_server --json state,mergedAt` ⛔ **AND MERGING #2781 WILL NOT CLOSE `UC-A5.3` c2.** The cascade climbs `parentEnrollmentId` by key, but the atServer sweeps expired records (`deleteExpiredKeys()`), so a link that has expired is GONE and the chain is severed — and each successor's ttl restarts at its own write, so under any finite key-expiry posture the earlier links expire first. Reported by the at_server session 2026-08-31 and filed as [at_server#2782](https://github.com/atsign-foundation/at_server/issues/2782). Closing the clause needs ancestry that OUTLIVES the enrollment record, so that is the real blocker, not this PR |
| **UC-G2.5 c5's at_client half, and the at_commons publish it waits on** | **Design settled 2026-08-31** in [ruling 130](detail/decisions.md#130-a-revocation-is-discoverable-per-namespace-and-rotates-unconditionally-2026-08-31); this row is the build. **Three pieces, two of them buildable now.** ⓵ `Enrollment.fromJSON` must stop dropping **`status`** — the wire carries it and the model keeps six fields, none of them this; same shape as `parentEnrollmentId`. ⚠️ **This asked for `revokedAt` too until 2026-08-31, and that half is now DEAD WORK rather than owed** — at_server removed the field from `EnrollDataStoreValue` and so from `enroll:list`. A stored record still carrying one decodes, and re-encoding drops it. ⓶ **An `add` must preserve the advertisement record's `updatedAt`** by asserting the atServer's own previous value back, while a **rotation must not** assert one and takes a fresh stamp. That is what makes `updatedAt` mean *when this generation was minted* — `PublishedNskeyKeyRing.add` rewrites `public:__nskey.<ns>@<owner>`, so left alone it moves the stamp and a revoke-then-add sequence disarms the trigger entirely. ⛔ **Do not re-apply the blanket "never assert `:uAt`"** that an earlier draft of 130 carried; the rule is add-asserts, rotation-does-not. ⓷ The check in `seed()`: for each authorised namespace, call **`enroll:infons:<ns>`** and rotate when its `lastRevokedAt` is later than the advertisement record's `updatedAt`. Rotate when the advertisement's stamp cannot be read but a moment was returned; rotate **nothing** when the namespace answer cannot be read at all. The rotation is **unconditional** — it does not ask `NskeyRotationPolicy`, whose shipped default returns false and would leave the mechanism inert for anyone who has not opted in. ⚠️ **⓷ is blocked and ⓵⓶ are not.** `enroll:infons` is ✅ **on at_server `origin/trunk`** as of 2026-09-01 (`45846a7b`, 6 files), and the verb token ships in **at_commons 5.17.0**, which is **unpublished** — see the release-train row. at_server runs a local override until then, guarded by a tripwire test that reddens the day a published at_commons defines `infons`. ⚠️ **Two clients get no check at all** and that is accepted: one holding no enrollment id returns before fetching anything, and one whose fetch throws discards the list. ⚠️ **A long-running client does not notice until it restarts** — the revoker rotates immediately and this is the backstop for when it could not | Nothing — ⓵ and ⓶ are buildable now. ⓷ additionally waits on at_commons 5.17.0 publishing **and** at_server's `enroll:infons`. ⚠️ **This cell named only the blocked piece until 2026-08-31**, which made the whole row unpickable under the `Blocked on: Nothing` rule while two thirds of it was startable; the at_server half was missing from it entirely. ⚠️ **That half is now HALF-discharged and this cell said the verb was absent from at_server `origin/trunk` until 2026-09-01** — it merged at `45846a7b`. What remains is a **VE image built from a server carrying it**: our packs talk to `at_virtual_env:local`, which nothing in this repo builds, so ⓷ cannot be proven against a real atServer until that image exists |
| **at_server legacy-PKAM enrollment: the client-side half of the `primary` migration** | ⛔ **REDESIGNED at_server-side on 2026-09-03, and the earlier design in this row is withdrawn.** This row used to describe an atServer that EAGERLY created a housekeeping enrollment beside the flat key. What landed instead MIGRATES: the credential at `privatekey:at_pkam_publickey` is moved into a real enrollment with the literal id `primary` — approved, `*:rw` plus `__manage:rw`, no expiry, no parent — and the flat key is deleted, so there is one credential and one record rather than two copies that can diverge. A bare `pkam:` is then answered as `primary`, and an `enroll:request` from such a connection is a RETROFIT of `primary`: auto-approved, carrying `primary`'s grants exactly, recording `retrofitPredecessorEnrollmentId`. ⛔ **A POINTER ROW for the atServer design, not a second home for it** — it lives in that repo's `docs/enrollment-review-findings.md`, section "The rulings", on branch `gkc-legacy-pkam-retrofit-and-review-fixes` (PR #2787, draft as of 2026-09-04). ✅ **What was owed HERE is done, 2026-09-04, except the removal below.** ① The two fixtures that enrolled a key another enrollment already holds now mint a fresh keypair per request (`tests/at_functional_test/test/enrollment_test.dart`); the atServer refuses a duplicate with `AT0032` in any status. ② `tests/at_onboarding_cli_functional_tests/test/pq_pre_enrollment_retrofit_test.dart` is rewritten: the roster holds `primary` from the moment the fixture installs the credential, so it goes one record before the retrofit and two after, the successor is selected by id rather than `.single`, and the predecessor field is pinned. ③ The eight shipping comments claiming `primary` carries `no enrollment record` are corrected — the accurate statement is that such a CLIENT cannot NAME its enrollment, which is why every one of those code paths still branches as it does. ⚠️ **Still owed here:** at_auth's client-side self-approval (`enrollment_submitter.dart`, the `selfApproves` flag, the symmetric key minted only to approve itself, and the branch that fires on a `pending` answer) is now unreachable against a current atServer, which auto-approves. gkc ruled 2026-09-01 that an atServer too old to auto-approve need not be supported, so it comes out. ⚠️ **The 2026-09-04 live runs did NOT settle whether the path is dead, and their green must not be read as saying so.** All three packs passed against an image built from at_server `d9600850`, but the submitter logs that branch at `info` under the logger `EnrollmentSubmitter`, and the CLI pack sets `AtSignLogger.root_level` to `WARNING`, so the line cannot appear whether or not it ran: the logger's name is absent from all three transcripts, which is a fact about the log level and not about the code. What would settle it: re-run that one file with the level at `info` and grep the logger name, or pin it server-side on the auto-approve. ⚠️ **Also owed, and it is a DECISION rather than a fix:** a legacy client is now fully privileged server-side while this tree still models it as holding nothing. Three places behave on the old model — namespace seeding gives it only its preference namespace, the signing-root step is skipped for it, and its `_apsk` is published directly rather than through `enroll:update`. Nothing is broken; each needs gkc to say whether the client should now act as the root it is. ⚠️ **And one acceptance consequence:** `enroll:listns` now answers a legacy connection, so the reason UC-B5.1 is recorded as undrivable from `tests/at_functional_test/test/signing_root_pull_test.dart` is false; whether the row becomes provable there is for the next catalogue pass. | Nothing for the three items already done. The removal and the live re-run are blocked on a VE image built from at_server `7118d2e4`; the three model questions are blocked on gkc |

### P1 — must do before D1 closes

| Item | What is owed | Blocked on |
| ---- | ------------ | ---------- |
| **at_server now revokes a non-root retrofit predecessor at the successor's first authentication** | at_server [#2797](https://github.com/atsign-foundation/at_server/pull/2797) replaces the 30-day cap with immediate revocation: at the successor's first `pkam:` the predecessor's approval children are re-parented onto the successor and the predecessor is revoked with a `superseded` history event; every other holder of its keyfile is refused AT0027 on its next command; the stamp is renamed `predecessorSettledAt` (decoder reads both at rest, wire emits the new name only); the predecessor no longer gets an `expiresAt`; `apkamSelfEnrollmentGraceHours` is gone. This tree pins the cap: `tests/at_end2end_test/test/pq/retrofit_cap_value_e2e_test.dart` (UC-B1.1) and `retrofit_retirement_e2e_test.dart` (UC-B2.1/B2.2), and `at_client_impl.dart`'s comment "the atServer caps a parent enrollment on success". Adapt those, grep the tree for `predecessorCapArmedAt` read off the wire, and amend `acceptance.md`/`design.md` where they state the cap as the contract. Adapting before the merge would redden the packs against today's image, so the order is merge first. | at_server #2797 merging and `dev_env` rebuilding |
| **at_server: a `*:rw` enrollment can forge signatures as another enrollment** | ⛔ **gkc is closing this himself** (stated 2026-09-01) — recorded here because our tree DOCUMENTS the property as holding and reasons from it. `packages/at_client/lib/src/crypto/nskey/pq_signing_chain.dart:79` says *"`_apsk` writes are restricted to the owning enrollment's own authenticated connection, so the signer is not a permitted writer"* and uses that as the justification for the parent-signs/child-publishes design. **That sentence is false until this lands**, and it is a claim about at_server made in at_client's shipping dartdoc. ⚠️ **Verified from at_server `origin/trunk`, not taken on report:** `isForeignPerEnrollmentReservedKey` returns false for any key starting with `public:` (`abstract_verb_handler.dart:166`), and `_apsk` lives at `public:_apsk.<enrollmentId>.a.__e@<atSign>`; the predicate feeds `isAuthorizedSync`, which takes an `operation` and is the general decision, so the exemption reaches WRITES; and `_protectedKeys` is four entries, none of them `_apsk`. The server's own comments say the per-enrollment reserved space is *private to the enrollment that owns it* and that the guard exists to deny *"one with `'*:rw'`, which would otherwise reach it via the wildcard fallback"* — so this needs the **wildcard**, and pointedly NOT `__manage`: an enrollment that cannot approve, deny, revoke or even `enroll:fetch` another enrollment can overwrite its published signing-key advertisement. **Consequence here:** verification resolves the record wholesale (`getApkamPublicKey(signerAtSign, id)` → `verifyEnvelope(signerPublicKey:)`), so a co-tenant can withdraw a victim's advertised key — unverifying everything it signed — or substitute one and forge. ⛔ **The `kid` lookup narrows NOTHING here**; an earlier note of mine said it did. An attacker who writes the record controls the algorithm set and the kid set, so naming the key is free to them. ⚠️ **NOT probed against a live atServer** — the decision path was read, the write was not attempted | Nothing — gkc is taking it |
| **a restored pre-retrofit `.atKeys` mints ANOTHER uncapped enrollment** | ⚠️ **Found in the 2026-08-30 wrap-up, read from source and NOT probed.** at_auth decides a keyfile is already retrofitted by looking in the KEYFILE (`enrollment_submitter.dart`, active `privateAuthentication` material with an enrollment id), so a keyfile restored from a backup taken before the retrofit has none and retrofits again. On the pre-enrollment path there is no parent to cap — `_capEnrollmentExpiry` has exactly ONE call site on at_server `origin/trunk`, in the apkam branch, applied to the parent — and the record is written with the request's own expiry, which defaults to zero, meaning never. So each restore leaves a further fully privileged, never-expiring enrollment and supersedes none of the earlier ones. For an ENROLLED client this is bounded, because the atServer caps the parent. **Settle it with a probe before treating it as true**: retrofit, restore the old keyfile, start again, read `enroll:list`. Then decide — it may be correct (it is the sibling-clone case, which is deliberate) or it may want the client to recognise its own enrollment from the atServer rather than only from the keyfile. | Nothing |
| **the at_persistence_secondary_server override must come out** | The workspace root carries a `dependency_overrides` entry pointing `at_persistence_secondary_server` at a merge sha of at_server, which fixes [ruling 125](detail/decisions.md#125-a-hive-stores-identity-is-its-storage-path-not-its-atsign-2026-08-28) — `hiveStoragePath` was silently ignored for the second AtClient of an atSign in one process, so co-located clients shared one keystore and one sync queue. **Two things are owed, in order:** at_persistence_secondary_server publishes (pub.dev tops out at **5.2.1**, published 2026-08-11, which predates the fix); then the override is deleted here and the constraint raised past whatever version carries the fix. ✅ **The merge is DONE and this row listed it as the first of three** — PR 2776 merged 2026-08-30 at `5c0e603c`, verified an ancestor of at_server trunk. ⚠️ **This cell said the committed override pins the BRANCH, and warned that a force-push would change what the tree compiles against, until 2026-08-31.** It pins a **sha** now, and the real hazard was the opposite one: the branch was DELETED on merge, so every cold checkout failed `dart pub get` with *Could not find git ref* (exit 69) while this machine kept working off its `~/.pub-cache` mirror. `pubspec.lock` is gitignored, so nothing else caught it. ⚠️ **at_client's own half is already on this branch and does not depend on the publish**: `AtSyncQueue` takes a storage path, and at_client tests close `HiveInstances.closeAll()` as well as the global `Hive.close()` — count them with `git grep -l 'HiveInstances.closeAll' -- packages/at_client/test \| wc -l` rather than from a figure here, which said **four** and was already five. Those stop compiling the moment the override is removed without the published fix behind it <br><br>⚠️ **The fix exposed three tests that were green for the wrong reason, all now corrected — do not "simplify" them back.** `pq_advance_ladder_test` gave every rung its own storage path, so its central claim — *nothing an install wrote stops being readable when it upgrades* — was only ever asserting that one store reads its own writes; it now uses **one** directory across rungs, as an install upgrading in place does. `pq_posture_grid_test`'s *"each with its own store"* checked that a DIRECTORY existed, which was true under the bug because the encryption-secret `<sha>.hash` lands at the path a client names even when its box opens elsewhere; it now asserts a `.hive` file. And `side_by_side_storage_test`'s own sync-queue arm read an in-memory replay taken at open, so it passed with the queue back on the global instance until the second client was built AFTER the first's write. ⚠️ `sync_multiple_client_test` drives two clients of ONE atSign at two paths and was therefore driving one store — it needed no change and still passes, which is the evidence that real sync works | a publish. ⚠️ **This said &#34;merging, then a publish&#34; until 2026-08-31**: [PR #2776](https://github.com/atsign-foundation/at_server/pull/2776) merged to at_server trunk on 2026-08-30 (merge commit `5c0e603c`), so only the publish is left — trunk declares 5.3.0 and pub.dev tops out at 5.2.1. ⚠️ Check it with `gh pr view`, not `git merge-base --is-ancestor`: the branch was deleted after the merge, and that command exits non-zero for a MISSING ref exactly as it does for an unmerged one |
| [14.11](#1411-deprecated_member_use-findings-across-the-workspace) **bucket B** | Migrate the **88** credential-ladder uses (`enrollmentId` 75, `signingAlgoType` 13) onto the `AtAuthenticator` seam. 26 in `lib/`, 62 in `test/`, across at_client, at_onboarding_cli, at_client_flutter and at_auth. It is what "that package's own work is done" means in [14.18](#1418-the-remaining-d1-initial-development-sequence), so it gates the carves | Nothing |
| **advertisement fetch volume, ttr and client caching** | Three questions, one subject, raised by gkc 2026-08-26 after a wire capture showed **110 `_apsk` lookups in a single short client run** — more than either control atSign made. (1) Why are there so many? Establish what re-fetches, and whether anything is re-reading per operation what it could hold. (2) Should an advertisement carry a `ttr`, and if so how long — it is a public record that peers must not read stale after a rotation, and rotation is the revocation lever. (3) How should a client cache advertisements it has fetched, and for how long? ⛔ **These interact**: a client-side cache with no server-side `ttr` is a rotation that does not take effect, and a `ttr` shorter than a session is the fetch volume in (1) by design.<br><br>⚠️ **A change on 2026-08-27 moved this baseline and the measurement must be taken after it, not before.** `NskeyResolver` no longer answers null from a remembered miss: when a walk finds nothing *and* the memory made it skip a level, it re-walks the skipped levels for real. That is deliberately paid only where a resolution is about to return null — for a write, one about to throw — so a repeated write that *resolves* is unchanged. But a client repeatedly writing toward a recipient who has published nothing now re-probes each time instead of once per window, which is exactly the shape question (1) is counting. Read [the write-up](#how-the-negative-cache-falsified-three-clauses) before attributing any number here<br><br>⛔ **A FOURTH question, and it is a defect rather than a measurement — found 2026-08-28 by reading, not by running.** The `_apsk` cache in `EnvelopeSigning` is **on by default** (`AtClientEnvelopeSigner`: `cacheExpiry: 5 minutes, resetOnLookup: true`) and `lookupPubKey` **cancels and recreates the timer on every read** — so the expiry slides from the last READ, and a signer verified more often than every five minutes is cached **indefinitely** in that verifier's process. Walk the `pqReady → pqActive` swap the project already ships: `reconcileSigningKeys` retires `rsa2048`, mints `mldsa65` and republishes `_apsk`; a busy verifier still holds the rsa-only advertisement, the envelope now carries an ML-DSA signature, `shared` is empty and it refuses with *"no algorithm in common"*. ⛔ **And the refusal is self-sustaining**: `getApkamPublicKey` resets the timer *before* verification is attempted, and `verifyEnvelopeSignature` catches the failure and rethrows with context **without invalidating the key it just failed against**. Recovery needs a five-minute lull in traffic to that peer, or a process restart. It reaches beyond app envelopes: the same path verifies **nskey advertisements** (`published_nskey_key_ring.dart:126`) and signing-chain links, so a wedged verifier cannot validate an advertisement and therefore cannot seal to that peer at all. ⚠️ **Same class as the negative cache fixed on 2026-08-27** — answering from memory and never re-checking — in a different cache. **Unproven by measurement**: the probe is a live differential with three arms, and the one that matters is *keep verifying every 60s and see whether it EVER recovers*, which a short test would miss | Nothing. It needs a measurement, then a ruling |
| **the PQ upgrade guide does not exist** | The cleanup deliverable, ruled instructions-not-tooling by [decisions.md 118](detail/decisions.md#118-the-retrofit-cap-is-armed-by-the-successor-not-by-the-retrofit-2026-08-27), which names the content it must carry. [Decision 40](detail/decisions.md#40-rf-srv-is-the-mechanism-the-whole-model-stands-on-2026-08-05) item 7 routed that content to a guide on 2026-08-05 and `docs/projects/pq/` has no such file. It is here rather than in the catalogue because a document is not a THEN clause | gkc, on where it lives |
| **there is no best-practices guide for application owners** | **The mitigation for the repopulation window, and it is the only one** (gkc, 2026-08-27). Between an nskey rotation and the adds that repopulate it, a sender whose policy refuses everything in the generation is refused outright. **Open it with gkc's analogy (2026-08-28), which is the clearest statement of the whole thing:** a company's official language is English and it wants to change to French — rollout 1 teaches everyone to speak and understand French while they go on speaking English; rollout 2 is when everyone speaks French. It extends to the asymmetry: **encryption is a conversation** (ask which languages the other person speaks, pick one, never say anything twice) and **signing is a notice on the wall** (you do not know who will read it, so covering a reader who has not learnt French means posting both languages, at twice the paper). **The recipe gkc gave on 2026-08-27, which the guide must carry verbatim in substance:** **rollout 1** mints both the old and the new algorithms and seals only to the **old** — every advertisement gains the new material while nothing senders do changes, so it cannot strand anybody; **rollout 2** mints only the new and sends only to the new, after which rotation's garbage collection retires the old by itself and a loud refusal to a peer that skipped rollout 1 is correct. The two levers are `keyEstablishmentAlgorithms` (what this atSign mints) and `sealsToKeyAlgorithms` (what this client will seal to), and the whole recipe is that they move in **different** releases. It must also say that `AtClientPreference.sealsToKeyAlgorithms` **is** the send-policy lever — an ordered list where omitting an algorithm refuses it. ⚠️ **This row claimed that lever's dartdoc "does not say" so, and was false when written on 2026-08-28**: it has said *"Narrowing it is choosing to refuse … the write is refused rather than downgraded"* since 2026-08-19. What the guide owes is reaching an app developer, not the dartdoc's content. ⚠️ **Distinct from the PQ upgrade guide row**, which is about retrofit cleanup; whether they are one document is unsettled | gkc, on whether it joins the upgrade guide |
| **step 3 of a signing migration has no lever** | **Ruled 2026-08-28** as [decisions.md 120](detail/decisions.md#120-a-signing-migration-is-three-steps-and-the-third-has-no-lever-2026-08-28). A verifier cannot decline an algorithm it implements: `verifyEnvelope` takes `strongestOf(shared)` with no minimum-algorithm check, no signature-count check, and no accepted-algorithms field for **signatures**. The encryption side already has one — `keyEstablishmentAlgorithms`, *"the receiver's side of the choice"* by its own dartdoc. So a **retired signing key is a standing forgery surface**: it stays advertised so history verifies, nothing dates an envelope, and whoever breaks that algorithm can mint one that verifies. What is owed is the verifier-side set, mirroring `sealsToKeyAlgorithms`, narrowing `shared` before `strongestOf` and refusing with both sides named. ⚠️ **Not every caller may be narrowed** — verifying one's own advertisement is not the same act as verifying a peer's data. It gates [UC-G2.9](acceptance.md#179-uc-g29--step-3-has-no-lever-so-a-retired-signing-key-verifies-forever) **c3 — the one clause in the catalogue that cannot be proven**, because the clause asserts this lever DOES NOT EXIST and building it therefore *falsifies* the clause rather than proving it. ⛔ **So this row does not block goal 1, and stays P1** even though the clause it gates is unproven; the exception is enumerated in `unprovableClauses` in `packages/at_client/test/acceptance/manifest.dart`. What the work does close is the standing forgery surface above, which is why it is still owed before D1 | Nothing |
| **the double-signing writer may now be dead code** | **Consequence of [decisions.md 120](detail/decisions.md#120-a-signing-migration-is-three-steps-and-the-third-has-no-lever-2026-08-28)**, which retired the two-signature overlap: it covers nothing a verifier can insist on, and the three-step ladder replaces it. ✅ **The blast-radius sweep reported 2026-08-28 and the change is contained.** Neither the signing root nor the APKAM fallback can produce a plural envelope — the root returns a bare map with one ML-DSA signature and never uses the envelope shape; the fallback returns a one-element list. A chain link can, but only by borrowing the data-signing keys, so plurality has exactly one source and `heldSigningKeys.length == dataSigningKeyAlgorithms.length`. **No library code produces a plural envelope**: three production call sites, one funnel, and every two-member set in the tree is in `packages/at_client/test`. ⛔ **The multi-signature READER must stay** — `SignedEnvelope.fromJson`'s differing-`kid` and differing-`typ` refusals stop an attacker APPENDING an entry in flight, which a single-key writer does nothing to prevent. Removing both because "we no longer sign twice" opens exactly the hole they close. Two tests are CITED from the catalogue as pinning the writer (`apkam_signing_keys_test.dart` and the arm added to `signing_key_minting_test.dart` on 2026-08-28), and both were deliberately kept when their clause citations were withdrawn. ⚠️ **Four tests in total emit two signatures** and would go red — the count in [ruling 120](detail/decisions.md#120-a-signing-migration-is-three-steps-and-the-third-has-no-lever-2026-08-28) is the one to work from; these two are simply the ones the catalogue names | Nothing. The blast radius reported 2026-08-28 and the change is contained |
| **an orphaned enrolment may never expire** | Found 2026-08-28 alongside the cascade gap, and independent of it. A self-enrollment inherits its parent's `apkamKeysExpiryDuration` at creation, and **a zero duration is the keystore's "never expires"** — so a subtree spawned under a never-expiring parent is bounded by nothing at all once revocation fails to reach it. Even with the cascade built this stays true of any enrollment the cascade misses. Decide whether a self-enrollment may inherit an unbounded expiry | gkc's ruling |
| **the `_apsk` sign/verify matrix is untested** | **Tests, asked for by gkc 2026-08-27.** ⚠️ **The specification landed 2026-08-28** as [`acceptance.md` section 17](acceptance.md#17-g2--crypto-agility--add-never-replace) — this row is the harness half, which no clause can express: which pack, which shape, one namespace per variation. It would prove UC-G2.3, UC-G2.7 and UC-G2.8. Originally: the same shape as the encrypt/decrypt matrix and for the same reason: `_apsk` is an array so that a signing-algorithm upgrade is an *add*. Sign **and** verify, self→self and self→other, against an advertiser offering `rsa2048` only, both, or `mldsa65` only. Nothing today asserts that adding an entry leaves the existing one verifying, or that a one-algorithm reader accepts a two-entry advertisement — ⛔ **and `bareApskValueOf` makes this sharper than it looks**: a single active `rsa2048` entry serialises as a **bare string** and everything else as the array, so the one-entry and two-entry cases are different wire shapes, not different lengths | Nothing |
| **the secret-sharing substrate's matrix is untested** | **Tests, asked for by gkc 2026-08-27.** ⚠️ **Specification landed 2026-08-28** in [section 17](acceptance.md#17-g2--crypto-agility--add-never-replace); this row is the harness half. It would prove UC-G2.1 and UC-G2.4. The third operation pair: encrypt/decrypt through the pairwise substrate — key packages and `__ssenv` — against a recipient whose key package advertises x-wing only, both, or ml-kem-1024 only. UC-A2.5 proves the *add* live (a package gains a second key, the original kid stays active, an envelope at the old kid still opens) and `key_package_amendment_live_test.dart`'s negotiation arm proves a sender picks by its own order over a both-advertising recipient. What is missing is the rest of the grid, and the self→self direction entirely | Nothing |
| **the advertised-algorithm matrix is untested** | **Tests, asked for by gkc 2026-08-27.** ⚠️ **Specification landed 2026-08-28** in [section 17](acceptance.md#17-g2--crypto-agility--add-never-replace); this row is the harness half. It would prove UC-G2.2, UC-G2.10 and UC-G2.11 — and UC-G2.11 is the self→self direction this row already calls the one a bug hides in. Send **and** receive, **self→self** and **self→other**, against a receiver advertising **x-wing only**, **both**, or **ml-kem-1024 only** — twelve cells, and today almost none of them run. What exists is one live negotiation arm over a **both**-advertising recipient (`key_package_amendment_live_test.dart`, two senders differing only in `sealsToKeyAlgorithms` order) and unit coverage of the selector; there is no live x-wing-only or ml-kem-only *recipient* anywhere, and nothing at all for the self→self direction. ⚠️ **The self→self cells are the ones a bug hides in**: with one atSign the configured `keyEstablishmentAlgorithms` and the published advertisement both belong to it, so a client consulting the wrong one is invisible — see [the mirrors](#the-four-missing-self-to-self-mirrors), whose UC-A4.5 row is this matrix's specification half. ⛔ **The receive side is not the send side reversed**: a holder opens every construction its KEM supports (`openableSuitesFor`), while a sender takes the first of its own order the recipient offers, so an ml-kem-only recipient and an ml-kem-only *sender* exercise different code.<br><br>**How to build it** (gkc, 2026-08-27): **one namespace per variation**, not one atSign per variation — an nskey is scoped to `(owner, namespace)`, so a single recipient can advertise x-wing for one namespace and ML-KEM for another by setting `keyEstablishmentAlgorithms` before each `mintAndPublish`. That keeps the whole matrix on the atSigns a pack already has, and avoids the exclusive-atSign trap (a test that publishes a signing root poisons rows asserting its absence). ✅ **The "both" column is producible, since 2026-08-28.** This said it needed checking, on the grounds that `PublishedNskeyKeyRing` minted under `keyEstablishmentAlgorithms.first` — one key per nskey generation — so a both-advertising *key package* was mintable and a both-advertising *nskey* might not be. The mint now writes a key per configured algorithm and `add` puts one client's material into an existing generation, so a both-advertising nskey is produced by setting `keyEstablishmentAlgorithms` before `mintAndPublish`, exactly as the key package's is | Nothing |
| **no rail resolves a cross-file `#anchor`** | **A rail, and it would guard a property that currently HOLDS rather than fix a break.** Found by a cold read 2026-08-27, whose manual pass was the first time this doc set's cross-file anchors had ever been resolved — every link in both live docs resolved. `docs_structure_test.dart` checks that no *linked* heading slug is duplicated, that the ledger index and its bodies correspond, and that the catalogue's counts agree; it never opens a link's target. The edit-time hook catches a bad anchor in the file being written, so the hole is **a heading renamed in one file and linked from another** — which happened on 2026-08-27 (`Two clauses pinned…` → `Clauses pinned…`) and was caught only because the same session moved the pointer. ⚠️ Scripted doc edits bypass the hook entirely.<br><br>⚠️ **Evidence arrived the same day the row was written: I wrote TWO broken anchors on 2026-08-27**, both after that cold read had flagged exactly this shape. One pointed at a **table row**, which is not a heading and can never be one; the other was invented outright for a section that does not exist. Both were caught only by resolving every anchor by hand, which is the check this row proposes. ⛔ **So it is no longer "a rail guarding a property that holds"** — the property does not hold reliably, it is held up by whoever remembers to check | Nothing |
| [the four missing self-to-self mirrors](#the-four-missing-self-to-self-mirrors) | **A ruling from gkc on which become catalogue rows**, then the rows and their scenarios. He set the rule 2026-08-27: a `put`/`notify` row — or a `get`/notification-receipt row — is about self→self **or** self→other, never both, and where one direction has a row so should the other. Five pairs already hold; **four self→other rows have no self→self mirror** and they are not equally worth having. The section ranks them with what each would assert and whether the tree can tell it apart: UC-A4.5's and UC-A4.7's mirrors both have live production paths that nothing exercises for self, and UC-A4.7's is *commented for exactly that case*. ⛔ **Landing any of them raises the denominator** and the burn-down percentage falls, which is correct — the clauses were always owed and their absence flattered the figure | gkc's ruling |
| [the at_client carve stack](#the-at_client-carve-stack) | Get the nine-layer stack plan into git, and make the **five decisions** it cannot make for itself. A file in no layer never lands | Whoever cuts the stack |
| [arm 1 vs arm 3 bucketing](#arm-1-vs-arm-3-bucketing) | **A ruling from gkc** — the measuring is done. Arm 3 cannot be scoped and the catalogue's count table stays wrong until it is settled | gkc's ruling. Nothing else |
| [a wildcard enrolment seeds nothing](#a-wildcard-enrolment-seeds-nothing) | **A ruling from gkc** on whether an atSign reachable only through a wildcard (`*`) enrolment is expected to publish namespace keys. Today it publishes none, so nobody can seal to it in any namespace, and the doc comment that said otherwise was false | gkc's ruling. The measuring is done |
| [content keys per scope](#content-keys-per-scope) | **A ruling from gkc** on whether one content key per writing enrollment per scope is the intent. If not: `CurrentCkPointer` needs a remote-first write through an atomic verb, and rotation needs to supersede every CK in scope | gkc's ruling, then the fix |
| [the late-arriving nskey private](#the-late-arriving-nskey-private) | File a late-arriving nskey private **only for a generation this client actually asked for**. The reverted attempt filed any arrival, which breached the seeding guarantee | Nothing |
| [14.18](#1418-the-remaining-d1-initial-development-sequence) **step 20's rotation arm** | Add the `pending` enrollment status value and build the rotation arm against its own dedicated CRAM atSign. ⛔ There is **no** fleet-adoption wait — see the standing premise | The at_auth publish, and a dedicated CRAM atSign |
| **CI at head** |  ⛔ **NO VERDICT LIVES IN THIS CELL, deliberately.** ⚠️ **It said "RED AT HEAD, and unverified since" until 2026-08-31**, and a run that had already happened falsified it: the newest run was `e2af5db26` on 2026-08-28, SUCCESS, and an ancestor of HEAD — every red it named was 2026-08-27 or earlier. The standing fact is not a colour but a DISTANCE, because nothing fires on push here. Re-derive before reading anything below: `gh run list --branch gkc-pq-d1-spike`. ⛔ **RECURRING — this row never completes**, which a cold read on 2026-08-27 found it failing to say: its cell states a green result and nothing about what remains, so it reads as done while sitting in P1. What is owed is a dispatch-and-read **at each new head**, because nothing fires on push here. Dispatch both workflows at head and read them. "Every rail green" is half of D1's definition, and **nothing fires on push on this branch** — the workflows are `workflow_dispatch` plus `push`/`pull_request` on `trunk` only, so the newest run is only ever as new as the last manual dispatch. ⚠️ **Dispatch matters beyond staleness**: CI's at_client job runs a **bare** `dart analyze` that reads `benchmark/`, which the routine `dart analyze lib test` never opens — that hid five errors for six days. ⛔ **And docs are build inputs here**, so a plan edit alone can redden the acceptance rail. Re-derive, never quote:<br>`gh run list --branch gkc-pq-d1-spike --limit 4 --json headSha,conclusion,workflowName --jq '.[] \| [.headSha[0:9], .workflowName, .conclusion] \| @tsv'`<br>`gh workflow run at_client_sdk.yaml --ref gkc-pq-d1-spike` ⚠️ **A format-gate risk found 2026-08-27, and it predates any current work.** `packages/at_client/test/acceptance/manifest.dart` and `a3_self_data_test.dart` **as committed at `762a91c38`** fail `dart format . -o none --set-exit-if-changed` under local Dart **3.12.2 stable**, while three untouched neighbours pass — the diverging constructs are an empty-condition `for (;;)` and a wrapped ternary, both places the formatter changed style between versions. CI installs `sdk: stable` **unpinned** (`actions/setup-flutter-and-dart/action.yaml:41`), so whether the gate is red at head depends on what stable is on the day. ⛔ **Do not "fix" this with a write-format** — that churns committed code to whichever style the local SDK happens to hold, which is the trap the toolchain rules already name. Dispatch CI and read the gate before touching a byte. ⚠️ **A rail gap found by a cold read 2026-08-27: `docs_structure_test.dart` does NOT check that a link RESOLVES.** Its group is *no LINKED heading is duplicated* — it collects slugs without resolving the target, so a **renamed heading breaks every link to it silently**. That happened the same day: renaming `### Three clauses pinned…` to `### Two clauses pinned…` left a dead anchor in the plan and the suite stayed green. The edit-time hook catches this on files it sees; a heading renamed in one file and linked from another is the hole. Worth a rail that resolves each cross-file `#anchor` across the doc set. ⚠️ **A cold read on 2026-08-27 did that check by hand for the first time and it came back clean** — every link in both live docs resolves — so the rail would be guarding a property that currently holds rather than fixing a break. | Nothing. ✅ **Dispatched and read 2026-08-27**: green, 11 of 11 jobs, at `44617edb6`. The format gate above **fired and was fixed** — 17 files, all of them ones we had edited since the previous green, so `stable` moving was ruled out rather than assumed. ⚠️ **CI runs Dart 3.13.2 and this machine has 3.12.2**, so formatting locally is a guess CI judges; it happened to be right. ⚠️ The run is behind the head by however many doc commits have landed since — re-derive with `git rev-list --count 44617edb6..HEAD` rather than reading a number here. It said "two" and was falsified by the commit that introduced it <br><br>⚠️ **The green in this cell is stale, found by a cold read 2026-08-28.** Two later `at_client_sdk` runs both **failed** — `9414f8bd2` and `02999c453`, the latter an ancestor of HEAD. ⛔ **But it is not an unattributed red**: `02999c453`'s failing job is `pqe2e_tests`, the notify namespace fold diagnosed and fixed in `d43a5acb3` — **the very next commit**. ⚠️ **That was true on 2026-08-28 and is not now**: a later run the same day, `e2af5db26`, SUCCEEDED and is an ancestor of HEAD, so the reds above are superseded rather than standing. What remains true is the distance between the newest run and head — re-derive it, and never read a colour out of this cell. ⛔ **No count here** — one was written as "six" on 2026-08-28 and was already seven when the commit carrying it landed, in the very cell that records that trap two sentences earlier. Re-derive: `git rev-list --count 02999c453..HEAD`. Re-derive with `gh run list --branch gkc-pq-d1-spike`; never read a result out of this cell |
| **two shipping dartdocs assert a security property the tree does not have** | **Found 2026-08-29 by an adversarial review of the secret-sharing substrate, and neither is about any in-flight change.** `secret_store.dart:65-70` says key material the SDK needs to survive a restart is filed into `AtKeys` instead, *"which keeps the atSign's private keys out of whatever backend an app happens to supply"*. Five sites write exactly that material into the store — every held nskey private re-primed at each client start (`nskey_seeding.dart:370`), a freshly minted one (`:525`), a rotated one (`nskey_rotation.dart:198`), the atSign-level signing-root **private** (`pq_signing_root.dart:1048`) and every arriving conveyed secret (`pairwise_secret_sharing.dart:990`) — and `putSecret` calls `_persist()` on every write, handing `persistence.save` the complete list with `Secret.value` as plaintext base64. `nskey_private_filing.dart:36-39` likewise promises a filed private lands with *"the at-rest protection those implementations already provide"*, which is untrue of `FileAtKeysIo` with no passphrase. The SDK ships no persistence implementation, so this bites only apps that wire one — which is the documented supported case (*"platform keystore, biometric storage"*). What is owed is a ruling on which half moves: the promise or the behaviour. Related at-rest work is already tracked as KF-1 in `roadmap.md` and this row must not duplicate it | Nothing |
| **`AtRpc` request ids collide, and the responder drops the second request without a NACK** | **Found 2026-08-29 while dartdocking the RPC traps. A defect, not a doc gap: there is no caller-side way to avoid it, because the id is minted inside the factory.** `AtRpcReq.create` uses `reqId: DateTime.now().microsecondsSinceEpoch` (`packages/at_client/lib/src/rpc/at_rpc_types.dart:17`), and the clock ticks about once per 15-20 microseconds on this machine, so ids minted back to back repeat. Measured 2026-08-29: **926 of 1000 mints collided (92.6%), and 968 of 1000 adjacent pairs were identical**; 10,000 mints yielded 553 distinct values. <br><br>Three consequences, worst first. **(1)** With `enableRequestMutex`, the responder puts an **immutable** record named `${reqId}.session_mutexes...` with a 30s ttl (`at_rpc.dart:483-488`) whose key does **not** include the requester, so two genuinely different requests colliding inside that window look like one request delivered twice: the second loses the immutable put and the responder returns at `at_rpc.dart:462` without even a NACK. That arm is cross-process, so awaiting each call does not avoid it. **(2)** `AtRpcClient.call` does `completerMap[reqId] = Completer()` and then returns `completerMap[reqId]!.future` (`at_rpc.dart:60,63`), so a second call in the same tick overwrites the first's completer: the first caller's future never completes, and both callers receive whichever response arrives first. **(3)** `call` has **no timeout**, so each of those is a permanent hang rather than an error. <br><br>⛔ **Live outside this tree.** `sshnoports` trunk uses AtRpc in 7 Dart files; `noports_core/lib/src/npa/npa_impl.dart:152` sets `enableRequestMutex: true`; `noports_core` pins `at_client: ^3.11.0`, so it takes any 3.x published here. `sshnpd_impl.dart:1992-2018` also reimplements the same completerMap pattern with the same overwrite, and caches the id per client atSign at `:2002` — sshnpd sends one auth-check request per incoming client connection, which is exactly the several-in-one-tick shape. <br><br>**What is owed is a ruling from gkc, then the fix.** He would prefer **UUIDs** (2026-08-29). The obstacle is that `reqId` is not only a payload field: it is carried in the atKey name (`request.${reqId}...` at `at_rpc.dart:333`, `${respType}.${reqId}...` at `:594`) and parsed back with `int.parse` at both ends (`:429` responder, `:545` requester), which logs a warning and **drops** the message on failure. So a String id is a major-version, reader-ships-first change: every responder must be deployed before any requester mints one, and with sshnpd on customer machines that window is long. The non-breaking alternative is a random 53-bit int from `Random.secure()` — 53 bits being the largest range every JSON parser round-trips exactly — giving a collision chance of about N²/2⁵⁴, or 5×10⁻⁹ at 10,000 live ids. Nothing reads the id as a time: every `.reqId` use in at_client and in all seven NoPorts files stores, compares or echoes it, with no arithmetic and no ordering. Whichever way it goes, `call` should also **refuse** a duplicate id rather than overwrite one (the `AtRpcReq({required reqId})` constructor is public, so callers can supply and repeat their own), and should take a timeout | gkc's ruling: UUID (breaking — String on the wire, responders deployed first, 4.0) or a random int (non-breaking, ships in 3.x) |
| **the client half of ruling 128** | **Drop `namespaces` from `selfRetrofit` and `retrofitIdentity`, and the scoped signing-root branch with it** ([ruling 128](detail/decisions.md#128-a-retrofits-successor-holds-its-predecessors-grants-and-may-not-choose-them-2026-08-31), gkc 2026-08-31). Both are exported through `at_client_mixins.dart`, so this is a **breaking** change to public API. ⚠️ The at_server half REFUSES rather than forces, so it is safe to land first and this is cleanup rather than a coordination gate. Eleven call sites were measured against their own predecessors and none narrows — but that rig was built to refute *narrowing* verdicts, so no EQUAL verdict was ever challenged. **Challenge the EQUALs before relying on the zero**: removing a required parameter is exactly where a missed caller compiles fine here and breaks a consumer outside the tree | Nothing |
| **`retiredAt` on the `_apsk` advertisement** | **Ruled 2026-08-31** (gkc). `ApskSigningKey` is `{kid, alg, pub, status}` — a verifier can see *that* a key is retired but never *when*, so there is nothing to compare a record date against. The advertiser stamps a retirement timestamp when it moves an entry to `retired`. ⚠️ It is a wire **and** at-rest shape change to `_apsk`, so it owes the doc sweep and the JAMS unit tree in the same commit. ⛔ A record's `createdAt` is a **caller assertion** the atServer honours (`:cAt`), not a server attestation — do not design against it as an unforgeable clock | Nothing |
| **ruling 129's blast radius: 14 statements still assert the retired client-side subtree walk** | **Swept 2026-08-31 over 9,139 files** (unignored recursive, so 5,966 more than `git grep` alone sees; `git status` empty, so no untracked misses). ✅ **Already corrected:** ruling 121's doctrinal sentences — it said the exclusion set must be the subtree and ordered client-side work FIRST, both superseded — **UC-A5.3** c2, rewritten to assert the cascade, and **UC-G2.5** c4, WITHDRAWN 2026-08-31 rather than rewritten, because UC-A5.3 already asserts the cascade and restating it would claim one behaviour under two rows (denominator 232 → 231). Its closing *"both halves are unbuilt"* is corrected too: the record is unbuilt, the walk is retired. ⛔ **Still asserting the retired design, FALSIFIED:** UC-A5.2 c2's closing sentence; `acceptance.md`'s *"Both halves are unbuilt"*; the UC-A5.x `Impl/verify` paragraph calling the subtree clauses unpinned; `implementation-plan.md`'s row scheduling client-side-subtree-first; `detail/acceptance.md`'s clause-gap register listing the one-element exclusion set as a defect owed a fix — it is now correct behaviour and that entry is spent; `detail/decisions.md` section 122's tail citing a subtree gap; and `a5_rotation_test.dart`'s GIVEN/WHEN/THEN comment, the only `.dart` file asserting the retired framing. ⚠️ **True today, false the day the cascade ships, so reword rather than delete:** `published_nskey_key_ring.dart`'s *"the conveyance excludes nobody"* dartdoc; `pairwise_secret_sharing_test.dart`'s `reason:` prose that excluding the predecessor *"buys nothing"*; the UC-A5.2 `provenIn` filing roster-membership-is-the-whole-gate as proof of a HAZARD when post-cascade it proves the mechanism suffices; and `implementation-plan.md`'s *"any enrollment the cascade misses"*, an empty set once the cascade is transitive. ⛔ **Separately owed:** [ruling 40](detail/decisions.md#40-rf-srv-is-the-mechanism-the-whole-model-stands-on-2026-08-05) item 2 is the canonical statement of unrevoke semantics and says only *"unrevoke restores the named enrollment"* — it must carry 129's guard, that the atServer refuses an un-revoke whose predecessor is not currently `approved` | Nothing |
| **a v(N-1) `.atKeys` migration test** ([#2154](https://github.com/atsign-foundation/at_client_sdk/issues/2154)) | **Nothing in any pack reads a keyfile written by a previously published at_auth**, and D1 publishes at_auth 4.0.0-rc1 with keyfile changes — so this is the only test that would catch the new build failing to read a 3.3.0 document. Verified 2026-09-01 rather than inherited: a fixture IS checked in at `packages/at_auth/test/data/@alice🛠_key.atKeys`, but it came from `2f844f097 feat: at_auth package initial commit` and **nothing records what wrote it** — that directory holds the one file and no version note — so it cannot serve as the v(N-1) capture. Four at_auth tests read it (`at_keys_io_test`, `at_keys_test`, `assurance_test`, `at_auth_test`) and assert PRESENCE only: six `isNotNull` fields, plus authentication and assurance. `at_keys_io_test.dart` does hold three read→flush cycles and **all three write their own file first** from a synthesized `AtKeys` into a temp path — exactly the defect the issue names, showing only that the writer and reader agree with each other; a fourth uses the `legacyAtKeys()` helper the issue names. ⚠️ **The issue names `pq_rollout_matrix_test.dart`, which DOES NOT EXIST** — the matrix is `tests/pq_matrix/`, with `packages/at_client/test/acceptance/g1_rollout_matrix_test.dart` on the acceptance side. Its substance holds: `published/lib/arm.dart` and `published/bin/read_apsk.dart` carry no keyfile handling at all. ✅ **The capture dependency the issue calls the hard part is ALREADY SATISFIED** — `tests/pq_matrix/published/pubspec.lock` resolves **at_auth 3.3.0**, the previous published at_auth, so that arm can write the fixture. Acceptance is the issue's: the document checked in with its package version recorded beside it, every field surviving a read → mutate → flush cycle, backend-agnostic and naming any legacy Hive box explicitly, and a mutation that reddens it when a reader drops a legacy field. ⚠️ **`detail/implementation-plan.md` states this as owed in S-3's body and in section 14.25's table** — those are history; this row is the one home | Nothing |

### P2 — should be done if there is time

| Item | What is owed | Blocked on |
| ---- | ------------ | ---------- |
| **`CkManager`&#39;s missing-cut-time guard cannot fire** | **Found 2026-08-31 while writing [UC-A5.6](acceptance.md#66-uc-a56--where-a-lever-is-deliberately-not-asked-and-where-a-yes-is-refused-out-loud).** `CkManager.ensureCurrent` returns early when the cache holds a current content key with no recorded `cutAt`, and the comment explains the absence as a cache entry predating cut-time recording. **There is no such entry.** `ContentKeyCache` is in-memory and built per client (`crypto.dart` is its only production construction site); `putAsCurrent` is the sole writer of all three `current` maps and always records a cut-time (`cutAt ?? DateTime.now().toUtc()`); `evict` removes the three together; and nothing in the workspace subclasses or reimplements the class or passes `cutAt: null` — measured with `grep -rn "extends ContentKeyCache\|implements ContentKeyCache"` (0) and `grep -rn "cutAt: null"` (0). So the branch is unreachable and its justification describes a persistence the cache does not have. ⛔ **It was written as an acceptance clause and removed rather than kept** — stating it would enshrine dead code as the specification. **Two ways out, and they are different decisions:** delete the guard and the comment, or make the cache durable, which is a real feature (a restart currently re-resumes from the conveyance record instead). Deleting is the smaller claim and the one the evidence supports. | Nothing |
| **where `mintAdvertisedSigningKey` lives was never put to gkc** | ⛔ **A decision I said I would bring back and did not** — the transcript has me saying it is "a public-API placement call in at_auth rather than something I should pick silently", and then picking it silently. It sits in `packages/at_client/lib/src/enroll/signing_key_mint.dart`, exported from `at_client_mixins.dart`, with three consumers: `pq_native_onboard`, `self_retrofit`, and **`at_onboarding_cli`, which imports it across a package boundary** — the smell that prompted the question. Either it belongs in at_auth beside the enrollment machinery that uses it, or at_client is the right home and the cross-package import is fine; both are defensible and neither is written down. Surfaced by the wrap-up's transcript sweep, 2026-08-30. | gkc |
| **`runCliCommand` streams the CLI child's log unprefixed, so two processes are indistinguishable in one transcript** | `tests/at_onboarding_cli_functional_tests/test/utils/at_client_cache.dart` does `proc.stdout.transform(utf8.decoder).listen(stdout.write)` — the child's output goes verbatim into the parent's stdout with no prefix. Loggers that carry the atSign (`SyncService (@x)`, `AtClientImpl (@x)`) can still be told apart; the ones that matter for PQ diagnosis cannot — `AtClientSecretSharing`, `SigningKeyMinting` and `VerbEnrollmentDirectory` name neither an atSign nor a pid. **Measured 2026-08-30:** a whole line of reasoning was built on attributing barrier warnings to the approver by adjacency to a neighbouring log line, and adjacency in an interleaved stream is not evidence. The only instrument in that harness that attributes unambiguously is the `StateError` from `proc.exitCode.timeout` naming the command. <br><br>**Owed**: prefix the child's lines (e.g. `at_activate>` ) or tag them with the pid, and say so in `runCliCommand`'s dartdoc so the next reader does not repeat the inference. Also note there that `auth_cli` sets `AtSignLogger.root_level = 'shout'`, so an un-`-v`'d child logs almost nothing and a silenced child reads exactly like a stalled one. | Nothing |
| **the CLI functional pack cannot run beside the main one** | `tests/at_onboarding_cli_functional_tests` binds the same ports as `tests/at_functional_test` (64, 443, 25000-25999, 6379), so the two cannot run together — run them sequentially, or shift one with the `BASE_PORT` argument its `runLocal.sh` takes. ⚠️ Salvaged 2026-08-29 from a struck-through row that was otherwise spent: the row's claim (that the CLI pack had no local harness) was false and had been retracted, but this consequence of the harness it does have was true and lived nowhere else | Nothing |
| **test-helper cleanup: a shared package, and no silent `signingAlgo` default** | **Proposed by gkc 2026-08-28, and I agree with it.** Three parts.<br>**1. Make `enrolAndAuthenticate`'s `signingAlgo` REQUIRED** and fix the resulting compile errors. It defaults to `rsa2048` today, so a caller passing a post-quantum posture silently gets a legacy enrollment that retrofits itself on first client construction and comes up as a **different enrollment id**. That is not hypothetical: it cost this session three rounds of a live test failing on its own controls before the cause was traced. It is also exactly the *“a cross-cutting change that must reach every call site: make the parameter required and let the compiler enumerate them”* shape — the two axes (`signingAlgo` and the preference's `authenticationKeyAlgorithm`) must be chosen together, and a default lets one move without the other.<br>**2. Reconcile the drift** — see the row above; the e2e copy is an ancestor missing `signingAlgo`, `atKeysIo`, `keyExchangeMode`, `reuse` and the `kpid`/`kpidOrNull` split.<br>**3. A `tests/packages/test_helpers` package**, never published, holding what is genuinely shareable across the test packs. The drift is the argument for it: *“Keep them in step if the enrollment flow changes”* is a convention, and the measured result of relying on it is 200 diff lines. ⚠️ **A same-package precedent exists and is deliberately NOT this**: `packages/at_client/test/test_utils/recorded_logs.dart` was extracted on 2026-08-28 when a third copy of one log-capture helper was about to be written, and it stayed inside at_client because that is where all three copies were. It is a candidate for the shared package the day a live pack needs to assert a log level, and not before.<br><br>⚠️ **One caveat, offered rather than a blocker.** A shared package couples the packs: a change wanted by the functional suite lands in the e2e suite too, and the e2e suite is slower and harder to run, so a breakage there is found later. That is a real cost — but it is the cost of *noticing*, where the drift's cost is not noticing. Worth taking. ⚠️ **Do the required-parameter change FIRST**, while there are still two copies: the compiler will enumerate every call site in both packs, which is a free inventory of what each actually needs before deciding what belongs in the shared package | Nothing |
| **the two `EnrolledClient` helper copies have drifted** | **Found 2026-08-28 while tracing why an enrolled client signs under a different id from the one the helper returns.** `tests/at_functional_test/lib/src/enrolled_client.dart` (264 lines) and `tests/at_end2end_test/lib/src/enrolled_client.dart` (169) are **200 diff lines apart**, and the e2e copy's own header says *“Deliberately a copy … Keep them in step if the enrollment flow changes.”* They are not in step.<br>The e2e copy is a strict **ancestor**, not a divergent fix — checked, because a copy can carry something the canonical one lacks and this one does not. What it is missing: the `signingAlgo` parameter (it hard-codes `rsa2048`, so **every** enrollment it makes retrofits under a PQ posture with no way to opt out), the `atKeysIo` parameter, `keyExchangeMode`, `reuse: true`, legacy mode, and `kpid`/`kpidOrNull` — where it still has a plain `final String kpid` rather than the throwing getter that tells a caller why a legacy-mode enrollment has none.<br><br>**What was done now:** the `enrollmentId` dartdoc was hardened in BOTH copies, each worded against its own code — the e2e one says it has no `signingAlgo` and always retrofits, because a doc asserting what other code does is a doc that ships a false claim. **What is owed** is porting the parameters, which is a change to a pack this session could not run: `at_end2end_test` needs its own virtualenv and its only consumer of the helper is `test/pq/nskey_multi_enrollment_test.dart`. ⚠️ **Do not port blind** — the `kpid` field becoming a getter changes what a legacy-mode caller sees, and the e2e pack must be run, not merely analyzed | Nothing |
| **there is no supported way to wait for the PQ startup tail** | **An interface gap, found 2026-08-28 while fixing the onboarding functional test.** A client's PQ startup runs as `unawaited(_pqBootstrap!.startup())` (`at_client_impl.dart:754`) and its steps write the `.atKeys` file through `AtKeysIo.update`. An application that must know the tail is quiet — before deleting or replacing the keyfile, before exiting, before handing the file to another process — has nothing on the `AtClient` interface to ask. `AtClient.ensureReachable(namespace)` is the supported wait and answers a narrower question: it publishes **one** namespace's advertisement, which is a single startup step of twelve. The only thing that answers *has the startup finished* is `PqClientBootstrap.startupComplete`, reached through `AtClientImpl.pqBootstrap`, which is `@experimental` — so a caller needs both a downcast off the interface and an `ignore` for `experimental_member_use`. `tests/at_onboarding_cli_functional_tests/test/at_onboarding_cli_test.dart` now does exactly that, in `quiesceStartupTail`, and the comment there records why `ensureReachable` was not used. ⚠️ **The decision is whether the interface should carry it**, not whether the test should — an in-repo test can reach through, an application cannot without taking on the experimental marker | gkc, on whether this belongs on the interface |
| **a rotating atSign could tell its senders, and probably can** | **A post-compromise-security tightening, raised by gkc 2026-08-28.** A sender learns of a recipient's rotation only by re-resolving that recipient's advertisement — `CkManager.ensureCurrent` compares the cached generation kid against the advertised one on every write and cuts a fresh content key when they differ, which its own dartdoc calls the only signal there is. `PublishedNskeyKeyRing` holds a peer's advertisement for `advertisementTtl` (15 minutes) plus `advertisementStaleGrace` (15 more if a re-fetch fails), so after a rotation a sender can keep sealing to the superseded generation — the one a revoked enrollment still opens — for that long. Shortening the ttl bounds it directly, at one `plookup` per destination per period. ⚠️ **UNMEASURED and the interesting half:** `ckConveyanceKey` addresses a conveyance `sharedBy` the sender and `sharedWith` the recipient, so every sender that has conveyed a content key to an atSign has left a `.__ck.` record addressed to it — which suggests a rotating atSign can enumerate exactly the peers that must re-cut, from its own atServer, and notify them. Probe that scan before designing anything on it; the addressing is read from the code, the enumerability is not | Nothing. It needs a probe before a design |
| **the enroll responses that return details carry no expiry** | An at_server change, ruled by gkc 2026-08-27 and recorded in [decisions.md 118](detail/decisions.md#118-the-retrofit-cap-is-armed-by-the-successor-not-by-the-retrofit-2026-08-27). ⛔ **POST-D1**, which is why it is a row and not a THEN clause: `acceptance.md` is D1's burn-down target, so a post-D1 behaviour cannot live in it | Nothing. It needs an at_server PR |
| **`notificationStatusEnum` is not an outcome, and its name says it is** | **A dartdoc fix, not a behaviour change** — raised by the at_talk demo session 2026-08-26 and routed here by gkc, because every app author meets it and only one of them is that session. `NotificationResult.notificationStatusEnum` initialises to `undelivered`. With `checkForFinalDeliveryStatus: true`, which is the **default**, `_waitForAndHandleFinalNotificationSendStatus` polls and sets it from the atServer, so it means what it says. Pass **`false`** and that method returns early: the field is never assigned on the success path, so an accepted send, a refused send and a failed send all read `undelivered`. The only signal left is `atClientException == null`, which no field name suggests. ⚠️ **Verified here against the source, and the request understated one thing and overstated another**: the enum *is* assigned `delivered` on the default path, so the trap is narrower than "only ever assigned undelivered" — it needs the caller to opt out of polling. And the `on AtException` handler's own comment reads *"Setting notificationStatusEnum to errored"* while it sets `undelivered`, naming a value the enum does not have (`{delivered, undelivered}`). **Owed, and the comment comes first**: a reader who reaches that handler while debugging is told the distinction they are hunting for exists, goes looking for where `errored` is set, and concludes their build is stale — worse than an undocumented field, which at least does not mislead. Then the qualifier on `notificationStatusEnum` and on `NotificationResult`, naming `atClientException == null` as what to read instead. ✅ **Confirmed by the requesting session 2026-08-26**: `bin/at_talk.dart` passes `checkForFinalDeliveryStatus: false`, so the mis-scored cells were the inert opted-out path and the narrowing above is the accurate statement of the defect. ⛔ **No change to when the exception is caught rather than thrown was asked for, and none should be smuggled into a docs fix**.<br><br>⚠️ **A second, narrower shape found live 2026-08-27, and it survives the default.** A send-side failure never reaches the atServer, so the polling that assigns the enum has nothing to poll: the call returns `undelivered` with the real cause in `atClientException`, **whatever `checkForFinalDeliveryStatus` says**. Observed with a cold-start refusal. So the field reads the same for "the atServer said undelivered" and for "this never left the device", and only the exception distinguishes them — which is the same trap as the opt-out path, reached by a different route | Nothing |
| **a pq enrolment costs a post-approval round trip** | Measure it, and decide whether the enrolment APIs should say so. A legacy enrollee carries its own symmetric key in and is done at approval; a pq enrollee must then **collect** the key the approver encapsulated to its key package, polling for the envelope (`enrollmentApkamSymmetricKeyResolver`, 30 s budget, 2 s interval). ⚠️ **Found 2026-08-26 by it breaking two tests**, not by design review: two authorisation tests in the CLI functional pack wait 10 s before approving and have a 30 s budget, and under the `pqReady` default that no longer fit — they now name `legacy` because they assert authorisation, not key exchange. The pin keeps them honest; it does not measure the cost | Nothing. It needs a measurement and then a judgement about whether callers are told |
| [the registrar certificate test](#the-registrar-certificate-test) | Three arms against a self-signed cert. The last S-5 behaviour change that exercises nothing, and the only one with a security consequence. ⛔ **POST-D1 clean-up, not a gate** (gkc, 2026-08-23) | Nothing. It lands wherever at_auth is next touched |
| [14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) | Item 8 is the only one still waiting on a ruling. Items 20 and 21 are examined-and-left, not work; item 35 lands in `atGettingStarted` | gkc, on item 8 |
| **at_auth `enrollment_submitter`** | Both defects are fixed in at_auth on both branches. What is left: **the at_client half of (b)** is not on the at_auth carve branch, because at_client's PQ secret sharing is not there at all. ⛔ **Do not apply the one-liner the review recommends** — it breaks the PQ OTP flow; see [detail](detail/implementation-plan.md#the-enrollment_submitter-review-and-why-the-recommended-fix-is-wrong) | gkc scheduling it |
| **a retrofit leaves the enrolment record memo stale** | `LocalSecondary.getEnrollmentDetails()` memoises into a field for the object's lifetime (`enrollment ??=`), and `_settleEnrollmentIdentity` is what populates it — with the OLD record, because it reads appName/deviceName/grants off it in order to carry them over. `_rederiveFromEnrollment` rebuilds the signer, the lookup and the id and does **not** clear it, so afterwards the client runs as the new enrolment while the record describing what it may do is the old one's. ⚠️ **Benign today and only by luck**: the retrofit copies the grants verbatim, so both records answer `isEnrollmentAuthorizedForOperation` identically. Two live readers — that gate on every non-`local:` local write, and `PqClientBootstrap._reconcileEnrollmentSnapshot`, which writes the stale record's appName/deviceName/namespaces into the keyfile under the NEW id. Found by a sweep after the [retrofitted-enrolment fix](#a-retrofitted-enrolment-cannot-run-an-authenticated-verb) and verified here | Nothing |
| **at_lookup `OutboundMessageListener.read`** | `AT0014 "Unexpected response found"` pops one entry off `_queue` and clears `_buffer` **without draining the queue or closing the connection**, unlike both timeout paths beside it. A stale queued response is then handed to the next command, offsetting every read after it. It fired in none of the relayed-lookup runs that found it; it is a hazard on its own merits | Nothing |
| [14.42](#1442-why-enrollment-setup-takes-four-minutes) | Why `enrollment_setup.dart` takes ~4 minutes. gkc asked for the cause, 2026-08-20 — not a D1 gate, but owed to him rather than plan-generated hygiene | ⛔ **@ce2e-only — it does not reproduce locally** |
| [14.50](#1450-the-e2e-teardown-revokes-enrollments-belonging-to-other-runs) | Scope the e2e teardown to the run that created the enrollments | Nothing. Needs no permission and no publish. ⚠️ **It cost a red on this branch 2026-08-27**: an `at_client_sdk` run on **trunk** overlapped a run on this branch (12:37–12:47 against 12:24–12:49) and the enrollment was denied mid-run at 12:44:42 — *"Cannot approve a denied enrollment"*. The next run, with no concurrent one, passed. **N=2 bounds no rate**; what it does show is that the collision is between runs rather than within one. ⚠️ **A THIRD occurrence 2026-08-27 18:08–18:25**, same signature — `AT0027 … revoked` **19 times** across six unrelated e2e files (`bypasscache`, `concurrent_notify`, `deletion_key`, `encryption`, `key_stream`, `notify`), all `@ce2e1`/`@ce2e4`. The overlapping run was found rather than assumed: `ek/fix-onboard-passphrase` ran 18:09–18:21, **entirely inside** that window. So it is now three observations, all cross-run, and the branch is not the variable — the *concurrency* is. ⛔ **This costs somebody a red roughly every time two branches build at once, and it is nobody's code that is wrong** ⚠️ **A FOURTH and FIFTH on 2026-08-31**, both `end2end_test_14`, both the *"Cannot approve a denied enrollment"* signature: runs at 19:35 and 20:01, carrying **4** and **3** concurrent `at_client_sdk` runs. ✅ **And the control that had been missing** — a run dispatched at 21:03 with **zero** others in flight went **11 of 11 green**, on newer code than either red. Five observations and one clean-room control. Filed with the timestamps as [#2197](https://github.com/atsign-foundation/at_client_sdk/issues/2197) |
| [14.47](#1447-the-at_client-unit-tree-has-a-cross-file-isolation-flake) | A unit-tree isolation flake in `local_secondary_sync_queue_test.dart`. Green alone and green in the full suite; red only in one hand-constructed ordering nothing runs | Reproduce at rate first |
| [14.44](#1444-residuals-from-the-at_chops-pr-review) | Two remain, both ⛔ **POST-D1** (gkc, 2026-08-23): at_chops 3.6.0's CHANGELOG owes the resolution-skew sentence (amend that section in place), and `XWingCore.combine` sizes its buffer from its inputs' actual lengths while writing at literal offsets 0/32/64/96/128 | Nothing. Both ride the next at_chops touch |
| **third-party dependency floors** | at_client alone declares **seven** below what it resolves — `path`, `crypto`, `uuid`, `archive`, `http`, `async`, `meta` — all minor or patch gaps, none checked against first use. The sibling floors were swept 2026-08-25; these were not.<br><br>⚠️ **And the gap runs the OTHER way too, which nothing here was watching.** at_client declares `at_persistence_secondary_server: ^5.1.0` and this workspace resolves **5.1.0**, so every pack exercises that version and only that version — while any consumer resolving fresh today takes **5.2.1**, which we have never run against. Found 2026-08-26 by the at_talk demo session, whose external resolution took 5.2.1 while mine took 5.1.0 and neither side would have noticed. That layer owns local storage, the commit log and the keystore. ⚠️ The same version pair already cost time once, when the local keystore's expired-record handling was characterised from 5.2.1's source while the workspace resolved 5.1.0 — the claims held in 5.1.0 by luck. "Readable as interchangeable" is what makes this expensive | Nothing. Two questions, not one: are the seven floors too low, and is at_client actually correct against the top of the range it already admits |
| **at_client README says nothing about the PQ surface** | Raised 2026-08-27 while adding `AtClient.ensureReachable`. `packages/at_client/README.md` is 382 lines and mentions **none** of: the PQ startup, namespace-key seeding, reachability, or the send/receive asymmetry that an app meets first. Grep it for `startup`, `reachab`, `seed`, `nskey`, `pq`, `post-quantum` — zero hits. ⚠️ **The consequence is the one the at_talk demo session actually hit**: an app author meets the asymmetry — you can send the moment you are up, you cannot receive until your key is published — only when a *peer* reports them as unreachable, which names the wrong party. The dartdoc on `ensureReachable` now states it, but a dartdoc is read by someone who already found the method. ⛔ **Pre-existing rather than something the PQ work broke**, and deliberately not smuggled into the feature commit | Nothing. It needs a decision about how much of the PQ surface belongs in a README at all |
| **at_auth README** | `packages/at_auth/README.md` describes `FileAtKeysIo` at `:144` and `:191` and never mentions `at_auth_io.dart`, which is the barrel it now lives behind. One or two sentences where `FileAtKeysIo` is first named | Nothing |
| [14.16](detail/implementation-plan.md#1416-four-residuals-the-issue-tree-audit-surfaced-2026-08-09) | Only ③'s **orphan-growth** half is owed here, and it is a decision before it is code. SS-4 resume was ruled NO RESUME | The decision |
| **rebuild `at_virtual_env:local`** | The concurrent-relayed-lookup fix merged to at_server trunk; the local tag is whatever tree last built it, so it did not become a fixed atServer by virtue of the merge. Rebuild from a named ref before the next live run that needs one. ⛔ Trunk is now a **fixed** arm — an unfixed control has to come from `a37e3e3b` | Nothing. The recipe is in [Re-deriving the state](#re-deriving-the-state) |
| **a sequential, abort-on-failure `batch`** | **A protocol enhancement, raised by gkc 2026-08-27**: "do these N things in this sequential order, abort when any one fails". ⛔ **Multi-repo** — at_commons, at_client/at_lookup and at_server in one coordinated sweep. **What `batch` does today**, read from `at_server` **`origin/trunk`** (`batch_verb_handler.dart`) rather than from the local checkout, which is on another branch: it takes `batch:<json>`, a list of `{id, command}`, runs them **in the given order**, and returns `{id, response}` for each. The ordering is already there. What is missing is the **abort**: each command is wrapped in its own `try`, an `Exception` becomes an error response and the loop **carries on**, so a batch whose third command failed still runs the fourth. There is no all-or-nothing and no rollback. **Why it matters here:** it would remove the mint lock's take-to-write window *structurally* rather than by shortening it, which is all [the CPU hoist](#a-client-that-exits-during-its-startup-tail-abandons-seeding) could do — a create-lock-then-write sequence that aborts as one leaves no window in which a client holds the lock and has not yet written. The same shape recurs wherever this design writes a guard record and then the thing it guards: the signing-root mint under `_rootlock`, and any future write-once-then-publish pair. ⚠️ **Two silent drops found in that handler while checking, and they are prerequisites rather than extras** — an abort-on-failure contract is unimplementable while a command can vanish without a verdict. (a) A command no handler accepts is skipped with **no response entry at all**; (b) when `getErrorCode` returns null the failure is logged `severe` and, again, **no response is added** — so the response list can be shorter than the request list, and only an id-set comparison reveals it. Also `on Exception` does not catch `Error`, which escapes the loop and abandons the rest of the batch with no per-command verdict for any of them | ⚠️ **It would also shrink the signing-root mint lock's ttl.** That lock is held for `signingRootMintLockTtl` because the winner must survive several round trips, and the ttl is simultaneously how long a client that died mid-mint is refused on its next start — see [ruling 124](detail/decisions.md#124-the-signing-roots-mint-lock-is-sized-against-starvation-not-contention-2026-08-28), which sized it. A batch collapses the round trips, so the ttl could shrink to the measured mint cost. Nothing. A design and a cross-repo sweep, both after D1 |
| **the "ONE list" claim is still false — `docs/projects/wasm/` is a whole second project** | ⛔ **Found by a cold read 2026-08-27, after the at_lookup carve-out was supposedly the last one.** `docs/projects/wasm/` holds **seven** documents including a `plan.md` with `## 8. Task backlog` (P1–P4, with undone rows) and `## 9. Open questions`. The PQ plan mentions WASM once, as a discharged at_auth barrel split, and the "it is the ONLY one" sentence added 2026-08-27 is therefore **wrong on the day it was written**. ⚠️ **Do not fix this by adding a third carve-out sentence** — that is the pattern that hid at_lookup. Either its open items come into these bands, or `docs/projects/` gets an index that names every live project and the PQ plan stops claiming to be the only list. Three other unlisted homes the same read found: `detail/implementation-plan.md` **§15.1** (a 13-row open-work table, in the file that is supposed to hold only discharged material, and it **disagrees with the live P1 row on a figure** — 71 credential-ladder uses against 88); the at_lookup plan's `monitor:multiplexed` item, which says *"Owed elsewhere"* and appears in no list; and **20 `lib/` doc comments citing planning-doc paths**, enumerated by `file:line`, which violate a global non-negotiable <br><br>⚠️ **And two of its links resolve to a path that does not exist, found 2026-08-28 while resolving the whole doc tree.** ⚠️ This row first said the links "leave the repository", which its own evidence contradicted in the next sentence — they resolve *inside* the repo, to a directory that is not there. `docs/projects/wasm/implementation-plan.md` lines 278 and 314 point at `../../../plans/wasm/api-designing.md` and `../../../plans/wasm/key-storage.md`, which resolve to `<repo>/plans/wasm/` — a directory that does not exist. A doc sending a reader outside the repository is a broken handoff whatever the target holds, and nothing in this tree checks that project's links. Recorded here rather than fixed, because the wasm workstream is not this one ⚠️ **And a second leak, found by a cold read 2026-08-29:** `docs/projects/at-lookup-consolidation/plan.md` carries a *"Next is the deletion's preconditions"* sentence — a ranked next move living outside this table, in a project the memory index calls FINISHED. Its three items were carved into the P2 and P3 rows here, so the sentence now duplicates them and a reader landing there is told to start work that is already listed. Reported rather than fixed: it arrived after this wrap-up's fix pass ⚠️ **One more second home found by a cold read 2026-08-31, flagged in place rather than fixed.** `detail/implementation-plan.md` section 15 was headed *"D1 burn-down — the single index of what D1 owes"* and its own table of contents said *"start here for what is left"* — it is retitled as a superseded snapshot, but its `### 15.1 Open work` table still holds live rows duplicated from `## TODO` (step 20&#39;s rotation arm among them), so reconciling it row by row and leaving a pointer is still owed. | Nothing. It needs a ruling on where the index of projects lives |
| **`roadmap.md` says it is "one of six docs" and there are seven** | Trivial and recorded because it is the *same* miscount memory already carries a correction for — `post-quantum-cryptography.md` is the omitted one. `ls docs/projects/pq/*.md \| wc -l` returns 7. The memory copy got fixed and the repo doc carrying the identical error did not, which is the direction the rules say to watch | Nothing |
| **key packages and envelopes are APKAM-signed with `rsa2048` by default** | **Raised 2026-08-29 by the same review, as the one place RSA still touches the post-quantum path.** No post-quantum key is ever *conveyed* under RSA — every conveyance is KEM-sealed and `sendEnvelope` has no classical branch, which was measured and adversarially refuted three ways. But the signature that authenticates a key package and an envelope defaults to `SigningAlgoType.rsa2048` (`enrollment_key_package.dart:76`), so an adversary who breaks RSA can forge a key package advertisement or an envelope signature. That is an active attack on the conveyance's **integrity**, not a harvest-now-decrypt-later read, so it does not touch the confidentiality invariant — but it is the remaining RSA dependency in the substrate and deserves a ruling rather than being left implicit | Nothing |
| **no non-test caller is known to reach `sendEnrollRequest` at a PQ posture** | ⛔ **Carried over 2026-08-31 from `untracked/pq-data-signing-key-states.md`, which was deleted that day when its design moved into [`design.md` 9.8](design.md#98-the-data-signing-key-an-enrollment-owns-from-birth). This was the one item in its "Not asserted" list with no tracked home** — the other three are either recorded elsewhere (the `getApkamPublicKey` cache, more sharply, in this file's own advertisement-fetch row) or spent. **The question:** the whole creation-time minting design turns on an enrolment being created at `pqReady` or `pqActive`, and it was never established that anything but a test does that. ⚠️ **It is a reachability claim, so grep the CALLERS, not the capability** — `sendEnrollRequest` is reached through `at_activate enroll` and through `AtOnboardingService`, and a caller that names no posture gets `AtClientPreference`'s default, which is `pqReady`. So the likely answer is "every default caller", and if that is right the row closes by recording it rather than by building anything. Worth an hour, because a NO would mean the creation-time path is unexercised outside tests and the heal path is what everything actually uses | Nothing |
| **the conveyance catch still swallows too much** | The read now rethrows `CryptoProviderNotRegistered` and logs the rest, but the broad `catch` remains. Its own dartdoc specifies the inverse: *a record that is nowhere is not an error*, and everything else is. **Probe what an absent record actually throws on the local and the remote leg**, then swallow only that. Deliberately deferred 2026-08-31 rather than guessed at | Nothing |
| **a signing key can be advertised before it is filed** | `apkam_signing.dart` names the window in its own dartdoc: a mint publishes before it files, so on an enrollment holding no signing key a read takes the authentication fallback *at the moment the advertisement stops naming it, and the envelope verifies against nothing*. ⚠️ **Reversing the order does not fix it** — the keyfile would then hold a key the advertisement does not name, and an envelope signed with it verifies against nothing for the same reason. The fix is not to sign during the transition, or to keep the authentication key advertised until both writes land. Reachable only by an enrollment that authenticates post-quantum and holds no signing key | Nothing |
| **four refusals for two user errors, one of them uncatchable** | Withdrawing UC-G2.10 c6 surfaced this. A sender that omits an algorithm and one that cannot implement it reach **four** refusals across three exception branches, and two give opposite advice for the same symptom. ⚠️ `AtSigningVerificationException` extends `AtException`, not `AtClientException`, so an application catching `AtClientException` around a write catches three of the four and misses that one. Changing its supertype is an at_commons change with cross-package blast radius | Nothing |
| **predecessor/successor vocabulary sweep** | **Ruled 2026-08-31** (gkc): a retrofit's two enrollments are **predecessor** and **successor**; parent/child is reserved for the approver ↔ requester relationship. Swept in the ledger and in the clauses touched that day; **24 hits in the PQ doc set and 8 in `packages` were measured** and the rest are unswept. ⛔ In this repo they are all prose — `parentEnrollmentId` appears in **zero** `.dart` files here. Renaming that at_server field is a separate decision with its own blast radius, it being on the wire and at rest ⚠️ **Three more collisions, found by a cold read 2026-09-01 and NOT yet swept.** `primary` now names both the housekeeping enrollment's literal id and the ordinary adjective — `design.md` uses the bare word for *first in the algorithm list* and the backticked one for the enrollment id, ~2100 lines apart — and the disambiguator *housekeeping enrollment* appears in one test comment and nowhere in `docs/`. ⛔ **Aggravated by a standing instruction**: the writing rule that replaces *load-bearing* with *primary* manufactures this collision in the one doc set where `primary` is a wire literal. `owner` names both an id-less connection and the atSign, and the tree is mid-migration from the first sense to `primary` with no doc recording the rule. `legacy enrollment` reads as either the pre-retrofit enrollment being capped or the housekeeping one. | Nothing |
| **UC-A2.6 c2 is pinned by a citation that admits an unproven arm** | The `proves:` text ends *"⚠️ NOT proven: an enrollment revoked while it holds an already open, already authenticated connection — this arm reconnects"*, and the clause is counted proven anyway. Under the project's own strict rule that is an over-claim no rail can see. ✅ **It is now closable live**: at_server `trunk` closes every open connection carrying a revoked enrollment id, and the ordering race that made it unreliable was fixed 2026-08-12. Hold E4's authenticated connection open, revoke over a second connection, assert the existing connection is closed rather than merely refused at reconnect | Nothing |
| **three plan sentences still describe a retired exemption as live design** | `preserveFirstEnrollmentOnRetrofit` is retired by [ruling 118](detail/decisions.md#118-the-retrofit-cap-is-armed-by-the-successor-not-by-the-retrofit-2026-08-27), and three sentences in this file still reason from it — including settled-question 6, *"What caps the legacy root credential afterwards?"*, whose answer the ruling inverts. Found by grepping the retired mechanism's vocabulary unscoped; not fixed in the same session by gkc's choice | Nothing |

### P3 — nice to have, explicitly after D1, or in another repo

| Item | What is owed | Blocked on |
| ---- | ------------ | ---------- |
| **an invariant nobody wrote down: no ML-DSA-authenticating client without a data signing key** | Flagged during the design discussion as "worth naming" and then not named — it appears in no doc and no comment (grepped 2026-08-30). It follows from ruling 113's coherence rules rather than from any single decision, which is exactly why it has no home: `AtClientPreference` refuses an empty `dataSigningKeyAlgorithms` beside a non-rsa2048 authentication key, so the combination cannot be constructed. Worth one sentence in [113](detail/decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18), because a reader meeting the refusal has no way to see that it is an invariant rather than a validation quirk. | Nothing |
| **at_server: revoking the first enrollment does not retire its key material** | ⚠️ **A READING, not a measurement — three files on at_server `origin/trunk` at `5c0e603c`, and deliberately not probed.** The CRAM branch writes `privatekey:at_pkam_publickey` = the first enrollment's APKAM public key (`enroll_verb_handler.dart:387-389`). Exactly two references to that record exist in all of `at_secondary_server/lib` — that put and `pkam_verb_handler.dart:74`'s get — so nothing else writes it, revoke included. A holder of the first enrollment's private key can therefore present it with **no** enrollment id, land on the `pkamLegacy` branch, and be granted **full unscoped access**, because `isAuthorized` returns true unconditionally for a null enrollment id (`abstract_verb_handler.dart:216-219`) — after that enrollment has been revoked. **Settle it with a probe before treating it as true**: enrol, revoke, then authenticate with the same keypair and no enrollment id. If it holds, the fix is a decision, not a derivation — the record cannot simply be cleared on revoke, because on a pre-enrollment atSign it is the only credential there is, and clearing it locks the owner out. Surfaced 2026-08-30 while measuring commit 7's route ([why](#why-commit-7-needs-no-atserver-change)), which is where the reading of each of those three files is recorded. | Nothing, except that it lands in `at_server` |
| **at_server: a String `apsk` on any enroll verb returns an internal error** | Measured 2026-08-30 against a live atServer: `enroll:update:{"enrollmentId":"…","apsk":"x"}` answers `Internal server error : type 'String' is not a subtype of type 'Map<String, dynamic>?' in type cast` instead of an `IllegalArgumentException`. `EnrollParams.fromJson` casts `json['apsk'] as Map<String, dynamic>?`, and that parse runs at `enroll_verb_handler.dart:109`, **before** `_validateParams` at `:114` and before the OTP check — and `enroll:request` is allowed on an unauthenticated connection (`:94`), so an unauthenticated caller reaches it. Low severity: a Dart type name is all that leaks. It is still an unhandled cast on a public verb, and `apskLegacy`'s `as String?` has the same shape. Found in passing while probing commit 7's route. | Nothing, except that it lands in `at_server` |
| **at_lookup major: deleting the ladder makes a keystore mandatory** | Moved into this list 2026-08-27 — previously reachable only from `MEMORY.md`, so a session reading the repo concluded it was not owed. ⛔ **Gates the later at_lookup MAJOR, not D1**; the consolidation itself is finished and shipped as a minor. [Measured](../at-lookup-consolidation/plan.md#blocks-the-major--deletion-does-not-remove-the-ladder-it-makes-a-keystore-mandatory) by attributing 107 ladder authentications: the remaining traffic is **not un-migrated code**, it is callers who supply **no `AtKeysIo`** and correctly get no authenticator. So deleting the ladder makes a keystore **required** to authenticate — breaking for every consumer that builds a client from a preference alone, and at_tools' `at_cli` is named as exactly such a consumer, outside this tree. A bridge exists and the ladder shows it: its legacy leg signs with an empty public half, a shape at_auth already builds elsewhere | Nothing. A decision about the bridge before it is code |
| **at_lookup major: `atLookUp.enrollmentId` has 51 uses, not 7** | Moved into this list 2026-08-27, same reason. ⛔ **Gates the later at_lookup MAJOR.** [51 uses across 34 files](../at-lookup-consolidation/plan.md#blocks-the-major--atlookupenrollmentid-has-51-uses-not-the-7-first-recorded) workspace-wide, from `dart analyze` rather than a grep. ⚠️ **Two denominators, and quoting one for the other is the error already made**: "how many modules ask the lookup which enrollment they are" is 7; "how many uses break when the member goes" is 51. ⛔ **Do not re-derive with a grep on the member name** — it is reached through at least eight differently-named receivers, so a bare `enrollmentId` grep over-counts wildly and `atLookUp.enrollmentId` **under**-counts, returning 9. Only the analyzer separates them by receiver type | Nothing |
| [the `monitor:` verb has no acknowledgement](#the-monitor-verb-has-no-acknowledgement) | A protocol seam across three repositories. ⚠️ **NOT D1.** The caller-side mitigation is already built and live-proven | gkc scheduling it, after the release train |
| [atServer outbound connection pooling](#atserver-outbound-connection-pooling) | ⚠️ **In another repo (`at_server`), and gkc asked for it as a discussion rather than a change** | gkc scheduling it |
| **doc-set reduction, phases 3–5** | ⛔ **RULED BY gkc 2026-08-23, AFTER D1 — do not start it while D1 is open.** End state is five files: `roadmap.md` (stale, needs a pass), `design.md`, `acceptance.md`, `decisions.md` and this plan. Phases 1 and 2 landed 2026-08-23 | D1 closing |
| [14.46](#1446-executeverbs-sync-parameter-is-inert-on-both-secondaries) | **Removal at 4.0** — delete the parameter from all six declarations and let the compiler enumerate the ~76 remaining same-package sites. Phase 1 (`@Deprecated`) shipped 2026-08-20 | The 4.0 majors |
| [14.12](#1412-a-mintlegacymaterialfalse-atsign-cannot-write-a-public-record) | ⛔ **NOT D1** — it gates the post-R-2 stop-release. Both moves it needs are B-3 phase 1, which is parked | Two unscheduled moves its body names |
| [14.29](#1429-the-residuals-1425-surfaced) | SS-2's `__ssenv` half is *deferred, not owed* — a pure optimisation since the 2026-08-03 ruling took DEP4 off it. Two small S-3 items, none blocking | Nothing blocks D1 |
| [14.43](detail/implementation-plan.md#1443-the-functional-suites-convergence-race) residue | ⛔ **NOT D1, and NOT PQ** (gkc, 2026-08-23) — it is at_client's general sync, and no use case asserts sync ordering. The test-side fix landed in `ccf4987a4` | Nothing |
| [14.45](detail/implementation-plan.md#1445-an-expired-key-the-client-cannot-delete-pins-it-in-a-hot-loop) residue | ⚠️ **In another repo: `at_persistence_secondary_server`.** Its keystore `get()` does not filter expired records | Separately owned |
| [14.39](#1439-pqposture-and-the-rollout-it-drives) **public-data signature verification** | ⛔ **POST-D1, and deliberately not in the acceptance catalogue** (gkc, 2026-08-23). Stated plainly because it reads as an omission otherwise: `pqActive` already **signs** public data and nothing anywhere verifies it — not at_client, not any atServer — so we emit a signature no one checks, knowingly | Design. Undesigned |
| **`acceptance-report.json` is ignored only on this branch** | ⚠️ **Deferred by gkc 2026-08-25 — recorded so the deferral is not silent.** `.gitignore` here carries `acceptance-report.json`, `citations.jsonl` and `acceptance-ledger.md`; **trunk carries none of them** | Nothing. It resolves itself when this branch lands; until then, name files rather than directories when staging on the carve |
| **at_server's `at_server_spec` hosted fallback** | In another repo, and gkc has deliberately left it for a considered decision. at_server's `unit_tests` job runs `dart pub get` per package with no melos step, so a PR changing `at_server_spec` and `at_secondary_server` together tests the new server against the old published spec, green | gkc |
| **eight ragged table rows in `detail/implementation-plan.md`** | Measured 2026-08-30 while moving a row body there, with a checker that splits on the unescaped separator so a correctly-escaped `\|` is not reported as a break: **8 rows carry a different cell count from their table's header.** ⚠️ **The line numbers this row used to list had ALREADY ROTTED** — it named 8464 and 8467, which are now a prose line and a table HEADER; the two ragged rows moved to 8484 and 8487 as the file grew. A row that exists to point at malformed rows pointed at the wrong ones, which is the same defect it reports. Re-derive rather than quoting, and the command is the citation: split each row of each table on the unescaped `\|` and compare its cell count with its header's. They pre-date that day — the same eight are present at the commit before it, two of them merely shifted by the insert. ⚠️ **A ragged row still RENDERS**, as a plausible row with its content in the wrong column, which is worse than a broken one. Two of the eight (8464, 8467) sit under a header naming *Item* and *What is owed*, the shape where the displaced cell is a `Blocked on` — invisible to the rule that picks the next task. The other six are in demoted bodies where nothing is picked. **Fix by rebuilding each row from its cells**, never by appending: split on the unescaped separator, replace the one cell, rejoin; then re-count every row of that table. Re-derive rather than trusting these line numbers, which move with every insert above them | Nothing |
| **#2161's deferral note is now false, and gkc declined to correct it** | ⛔ **A REJECTED PROPOSAL, recorded so it is not raised a third time.** [#2161](https://github.com/atsign-foundation/at_client_sdk/issues/2161) is closed, and its *Deliberately not doing now* section says the `AtLookupImpl.signingAlgoType` default *“rides the next at_lookup version whenever one is opened for another reason”*. That did not happen: at_lookup reached `3.7.0-rc1` without it, and the defect was instead fixed one layer up in at_auth — `authenticatorForChops` now requires `signingAlgo` and `hashingAlgo` ([#2198](https://github.com/atsign-foundation/at_client_sdk/pull/2198), merged 2026-09-01). So a reader of that issue is told the wrong thing about where the fix went. gkc was offered the correction twice on 2026-09-01 and declined both times; it is a comment on a closed issue, not code. ⚠️ **The deprecated field itself needs nothing** — it dies with the credential ladder in the next major, and requiring it or making it nullable is breaking, so neither could land in 3.x | Nothing — this is a record, not a task |
| **at_lookup major: the CLI's authenticator install is unit-green only** | ⛔ **Found missing from every list by a cold read 2026-09-01** — memory asserted this had been moved into this table on 2026-08-27 and it had not, so it has been owed by nobody since. The harness half IS discharged: `tests/at_onboarding_cli_functional_tests/runLocal.sh` exists and the pack passes locally. What survives is in [section 6 of the consolidation plan](../at-lookup-consolidation/plan.md): the CLI's authenticator install has **54 unit tests and no live check**, and its six remaining construction sites are not uniform — some authenticate, one only checks `isOnboarded`, and two send a bare `from:` through a proxy. Installing an authenticator is harmless where unused, since it only runs when authentication is required, but the absence of a live check means the migration wants a runner exercising the CLI first. Re-derive the sites rather than quoting them; the plan names line numbers that will have moved | Nothing |
| **`docs/knowledge/sdk.md` cites line numbers in nugget BODIES, which its own rule forbids and its rail cannot see** | **Found by a cold read 2026-09-01.** `README.md` rules that Evidence cites a PATTERN, not a coordinate, because *“a line number that rots usually keeps resolving and now points at something unrelated, so it reads as verified while being wrong”*. Five coordinates survive in nugget PROSE rather than in Evidence bullets, and `knowledge_test.dart` only scans lines beginning `**Evidence:**` or `- `, so the rail is blind to them. All five were verified correct at the ref they name, which is precisely the state the rule calls dangerous. ⚠️ **The fix is not only to rewrite them** — a rail that cannot see half its own file's citations is the deeper defect; widening the scan is what stops this recurring | Nothing |

### Why commit 7 needs no atServer change

⛔ **This section used to propose an atServer change and leave its central
question open. Both were wrong, and both were settled by measurement on
2026-08-30** — two throwaway probes against a live `at_virtual_env:local`, run
from `tests/at_functional_test` and deleted afterwards. A pre-enrollment atSign
can create an approved, fully privileged enrollment for itself on **today's**
atServer, and the credential question the proposal called "the crux" is already
answered by a mechanism the atServer ships.

**What is genuinely refused is one branch, not the outcome.** A pre-enrollment
atSign authenticates with the flat `at_pkam_publickey`.
`pkam_verb_handler.dart:72-76` takes the no-enrollment-id branch, sets
`AuthType.pkamLegacy` and leaves `enrollmentId` null on the connection.
`enroll_verb_handler.dart:406` gates the self-enrolment **auto-approve** on
`authType == AuthType.apkam`, and `:410-414` refuses a null parent id outright,
so such a connection cannot enter that branch. Read from at_server
`origin/trunk` at `5c0e603c`; that much of the original reading holds. What did
not hold was reading "this branch refuses it" as "the atServer refuses it".

**The route that works: request, then approve on the same connection.**
`isAuthorized` returns **true unconditionally** for a connection whose
enrollment id is null (`abstract_verb_handler.dart:216-219`), and
`_handleApproveDenyRevokeUnrevoke` authorises through it — so the pre-enrollment
client is its own approver. An authenticated connection is asked for no OTP
(`enroll_verb_handler.dart:300`), so the request carries nothing the client does
not already hold; it lands `pending`, and the next verb on the same connection
approves it.

Measured, one connection, one test:

| step | the atServer answered |
| ---- | --------------------- |
| `enroll:request` — appName, deviceName, a fresh APKAM public key, `{"*": "rw", "__manage": "rw"}`, the symmetric key RSA-wrapped to the atSign's encryption public key, **no OTP** | `{"enrollmentId":"e893f69a-…","status":"pending"}` |
| `enroll:approve` on the same connection, payload built as `EnrollmentApprover` builds it | `{"status":"approved","enrollmentId":"e893f69a-…"}` |
| `pkam:enrollmentId:…` under the newly minted keypair | authenticated |
| `enroll:list` | `namespaces {"*":"rw","__manage":"rw"}`, `approval.state approved`, `apkamKeysExpiryInMillis 0` |

⛔ **Both probes were deleted after they were read, so neither table above nor
the `@bob🛠` one below can be re-run from anything in this tree.** What survives
as a rail is `pq_pre_enrollment_retrofit_test.dart`, which re-establishes the
same preconditions from scratch on every run; the tables are evidence for a
ruling, not a harness. Re-deriving them means re-writing the probes.

⚠️ **What that proves is the verb path, not key conveyance.** The probe sent the
approve IVs under field names the atServer does not read, so the stored
encryption keys are not decryptable by the new enrollment — irrelevant to the
question asked, which was whether the atServer accepts the sequence, and stated
here so nobody reads the row as "the enrollment is fully provisioned".

**The control that makes this a measurement rather than a coincidence.** The
first probe's control was inert: an `enroll:update` carrying a String where the
wire type is a Map, which crashed the handler before authorisation and so
discriminated nothing. Rewritten, it reads the atServer's own words —
`enroll:update` is self-only, and its refusal **names the caller**, so a
connection carrying an enrollment id is distinguishable from one that is not.
It answered

> `enroll:update is self-only: this connection is authenticated as the owner,
> not cd365c8a-…`

which is the atServer stating that this connection carries no enrollment id, the
property the whole route rests on.

**The one thing commit 7 had to get right, and did.** `preventDuplicateEnrollRequest` runs
on this path — it is skipped for CRAM and for apkam, and this is neither.
Measured: a second self-enrolment naming the same `(appName, deviceName)` is
refused with *"Another enrollment with id … exists … in approved state"*, while
one naming a different device lands `pending` — the positive control, without
which the refusal could have been about the second request rather than about the
duplicate. **So sibling clones of one pre-enrollment keyfile must retrofit under
distinct device names**, which is what they should do anyway: two devices
deserve two distinguishable enrollments.

#### Question 6 answered — nothing caps the legacy root credential, and nothing should

The proposal called this the crux and left it unresolved: after the retrofit the
flat `at_pkam_publickey` stays valid, a permanent, unexpiring, fully privileged
credential. Three things settle it, and none is new work.

**It is not specific to pre-enrollment atSigns — it is what the atServer already
does.** The apkam self-enrolment branch caps the parent, *except* when the parent
is the atSign's FIRST enrollment, which
`AtSecondaryConfig.preserveFirstEnrollmentOnRetrofit` exempts, **defaulting
true** (`config.yaml` line 225). The reason recorded beside it is exactly the one
that arises here: it is the one credential this server cannot re-issue, so
retiring it stays the owner's explicit act. On both paths the atSign's root
credential survives its own retrofit, by design.

**On a CRAM-onboarded atSign the flat key IS the first enrollment's key.** The
CRAM branch writes `at_pkam_publickey` = the first enrollment's APKAM public key
(`enroll_verb_handler.dart:387-389`, *"store this apkam as default pkam public
key for old clients"*). Exactly two references to that record exist in all of
`at_secondary_server/lib` — that put and the pkam handler's get — so nothing
else ever touches it. The two cases are one case.

**The owner's act exists today and is one verb.** `at_pkam_publickey` is a
protected key: a scoped enrollment is refused, a `*:rw` enrollment without
`__manage` is refused, and **a root enrollment may write it** — three tests in
at_server's `root_key_authz_test.dart`, each asserting the stored value rather
than merely the throw. A pre-enrollment retrofit produces a root enrollment, so
the owner can retire the legacy credential whenever they choose. Measured on
`@bob🛠`, its own atSign because the last step destroys shared state:

| step | measured |
| ---- | -------- |
| the flat key, after the retrofit | authenticates |
| `update:privatekey:at_pkam_publickey <a public key whose private half is discarded>`, from the new root enrollment | accepted |
| the flat key again | `AT0401 pkam authentication failed` |
| the new enrollment again | authenticates |

⛔ **Overwrite, never delete.** `delete:privatekey:at_pkam_publickey` is refused
as a syntax error — the delete grammar requires an atSign and this record has
none. Writing a public key nobody holds the private half of is what retires it.

⛔ **And it must NOT be part of the retrofit.** Sibling clones of one
pre-enrollment keyfile share the flat keypair, and the retrofit mints a *fresh*
APKAM keypair per enrollment (at_auth: *"a new enrollment never reuses the legacy
key object"*), so overwriting the record at retrofit time locks out every clone
that has not yet upgraded — with no CRAM secret left to recover with. That is the
harm `preserveFirstEnrollmentOnRetrofit` exists to prevent, arriving by another
route.

#### The remaining questions, and what each is now

| # | Question | Answer |
| - | -------- | ------ |
| 1 | May a `pkamLegacy` connection self-enrol, auto-approved? | It does not need to be auto-approved. It requests and approves, on one connection, today |
| 2 | What grants? | Whatever it asks for. The connection is unscoped, so there is nothing to bound it by and no escalation to check. `_validateParams` requires a non-empty set only for an apkam connection or an OTP request, so a client must name its grants deliberately; the probe used `{"*": "rw", "__manage": "rw"}` |
| 3 | Does it overwrite `at_pkam_publickey`? | **No** — it locks out every sibling clone, as above |
| 4 | Is `preventDuplicateEnrollRequest` skipped? | It is not, and cannot be without a server change. The client uses distinct device names |
| 5 | A new `AuthType`? | Moot on the route that works. `AuthType.pkamLegacy` is set at exactly one production site and only where the enrollment id is absent, so it already *is* the discriminator if one is ever wanted |
| 6 | What caps the legacy root credential afterwards? | **Nothing, deliberately** — the same answer `preserveFirstEnrollmentOnRetrofit` already gives for the first enrollment. The retirement act is the owner's, and it exists |

**What an atServer change would still buy, and it is small.** Widening the
auto-approve branch to `AuthType.pkamLegacy` would save one round trip, close a
brief `pending` window, and let sibling clones share one `(appName, deviceName)`.
None was a correctness gap, and each of the branch's four parent-dependent
mechanisms — `verifyNoEscalation`, `parentEnrollmentId`, the inherited key-expiry
posture and the cap — would need a no-parent answer first. Optional, and it was
not what commit 7 turned out to wait on.

#### What commit 7 turned out to be

✅ **Built 2026-08-30, in two packages and no atServer change.**

- **at_client** — `_settleEnrollmentIdentity` no longer returns at
  `enrollmentId == null`. A pre-enrollment atSign compares as rsa2048, because
  the flat key is what at_lookup signs with, so a post-quantum posture moves it
  exactly as it moves a legacy enrollment. What its new enrollment asks to be
  comes from `AtClientImpl.firstEnrollmentIdentity()`. ⛔ **Its device name is
  `firstDevice-<uuid>`, not the bare constant this section's plan named.** The
  bare constant is a permanent silent failure: sibling clones of one keyfile all
  name the same pair, so the first device upgrades and every other one is refused
  at every start, for ever, with nothing on the device saying why.
- **at_auth** — `_handleSelfEnrollmentRequest`, in
  `packages/at_auth/lib/src/enroll/enrollment_submitter.dart`, mints a symmetric
  key, wraps it to the atSign's own encryption public key on the **request**, and
  then approves over the same connection through the ordinary
  `EnrollmentApprover`. Wrapping to the atSign's own key is what keeps the
  record's copy recoverable, so nothing is stranded by a key minted in a process
  that then forgets it. ⛔ **Filing it into the keyfile instead was rejected, and
  the reason is a trap worth knowing**: `AtKeys.toAtChops()` switches on
  `apkamSymmetricKey` — its presence is what the class uses to tell an APKAM
  keyfile from a PKAM one — so writing that field into a pre-enrollment keyfile
  silently changes how every reader interprets it, and 69 files across the
  workspace touch it. ⚠️ **The discriminator is the SESSION's enrollment id, not
  the connection's**, because `pending` has a second cause — an APKAM
  self-enrolment against an atServer too old to auto-approve — and that one keeps
  its deny-and-throw.
- **at_client**, third change — `_settleEnrollmentIdentity` gained an `on Error`
  clause beside its `on Exception` one. Its dartdoc promises nothing is fatal,
  and `retrofitIdentity` throws `ArgumentError` while an `AtKeysIo` may throw
  `UnimplementedError` from `read`. Unreachable behind the old null guard;
  reachable now for every default-preference client.

⚠️ **The consequence nobody asked for, ruled INTENDED by gkc on the day.**
`AtOnboardingPreference extends AtClientPreference`, so its default posture is
`pqReady` as well — which means `at_onboarding_cli`'s `authenticate()` on a
pre-enrollment atSign now self-enrols it and rewrites its `.atKeys`. Every
`at_activate` command does that. It is what already happened to an **enrolled**
atSign at a post-quantum posture; the null-id guard was the only asymmetry. Two
tests were re-fixtured at `PqPosture.legacy` — both legacy-shaped groups of
`tests/at_onboarding_cli_functional_tests/test/at_onboarding_cli_test.dart`, on
every call rather than only the two that noticed, because one atSign in one
process holds one posture and a client cached at another is refused outright.

**What proves it, and what each proof is worth.**

- `packages/at_client/test/first_enrollment_identity_test.dart` — the identity a
  client with no enrollment asks for, and a pin tying the constants to at_auth's
  own `AtOnboardingRequest` defaults, which are field defaults no other package
  can reference. Mutation: returning the bare constant reddens exactly the two
  device-name assertions, quoting their own reasons.
- `packages/at_client/test/pre_enrollment_retrofit_drive_test.dart` — the
  DECISION, driven through `AtClientImpl.create` rather than through the
  pieces, and added because nothing in at_client drove it: re-adding the
  `enrollmentId == null` return left all 1688 unit tests green, and only a
  Docker-dependent pack on a separate CI job noticed. It asserts the
  `enroll:request` the client puts on the wire — the app, the device and the
  grants it chose — because asserting that it merely *tried* would be
  asserting the test double. Mutation: re-adding that return reddens exactly
  the post-quantum arm, quoting *"a client with no enrollment id … sent no
  enroll:request. Commands seen: []"*, while the legacy control stays green.
- `packages/at_auth/test/at_self_enrollment_test.dart` — a group whose two arms
  differ in the session's enrollment id and in nothing else, meeting the same
  `pending` response. Its control is that an APKAM retrofit is still denied.
  Mutations: never-self-approve reddens exactly the two new arms, and with the
  right failure — *"expected the self-enrollment to be auto-approved; the
  atServer returned status pending"*; always-self-approve reddens the control
  plus twelve pre-existing tests.
- `tests/at_onboarding_cli_functional_tests/test/pq_pre_enrollment_retrofit_test.dart`
  — the live proof. It makes `@barbara🛠` genuinely pre-enrollment by hand
  (CRAM once, then the flat key and nothing else — deliberately **not**
  `onboard()`, which would create the enrollment whose absence is the point) and
  asserts against the atServer over a connection it opens with the flat key:
  roster empty before, one approved enrollment after, `{*: rw, __manage: rw}`, a
  device name starting `firstDevice-`, and the flat credential still
  authenticating afterwards. `@jagan🛠` at `PqPosture.legacy` is the control and
  stays at zero. ⚠️ **The pack runs at `WARNING`, so the mechanism's own INFO
  lines are absent from a green run** — what carries it is the device name,
  which the preference cannot produce, and `approved`, which a `pkamLegacy`
  connection cannot reach without the self-approve leg.
- **Not proven by the functional pack.** It went 199/199 unchanged, and four
  clients newly took the widened door — all four declined, on empty in-memory
  keyfiles. That run establishes no regression and nothing about the feature.

**Measured 2026-08-30:** unit at_auth 363, at_client 1688, at_onboarding_cli 69,
at_client_flutter 37; functional 199/199; CLI pack 21/21 against a baseline of
19/19 measured by stashing; e2e 67/67, where no client took the widened door at
all. ⚠️ **A `62` for that pack appears in the detail plan's demoted section and
is a DIFFERENT run** — an earlier one whose five failures were self-inflicted
edits since reverted; 62 + 5 = 67, and the pack has 67 tests. Neither figure is
wrong; they are two runs, which is why both docs say to re-derive. Re-derive rather than quoting these — the commands are in
[Re-deriving the state](#re-deriving-the-state).


### The acceptance audit

⛔ **A D1 GATE, and the one D1's own definition rests on** (gkc, 2026-08-23).
**The rationale, in gkc's words:** *"we have literally hundreds of functional and
end to end tests which cover the acceptance tests together. But there is no
definitive place where it is easy to see the entirety of the pq project's
acceptance tests being proven. The posture matrix test is the logical place to
build test out."* So the problem is **legibility, not coverage**.

**The build is done.** Arms 1–3, the ledger, its local driver, its wiring rail
and the clause level all landed between 2026-08-23 and 2026-08-24; arm 4 was
cancelled. Their design and measurements are in
[ruling 115](detail/decisions.md#115-the-acceptance-suite-is-4-arms-and-a-ledger-not-one-grid-2026-08-23)
and in
[detail](detail/implementation-plan.md#15-the-lettered-d1-gates-g0g8-as-they-were-discharged).

⛔ **THE READING IS DONE — every cluster and the bucket that belonged to none,
finished 2026-08-26.** What it was: read each scenario's `proves:` prose against
the test it cites and record where the citation does not establish the clause.
The pins compute the *known* overclaim; they cannot tell you a cited test proves
something narrower than the clause it is attached to, and that judgement is what
no rail can make.

**What it covered.** 161 citations, measured 2026-08-26 by the recorder and
again by `git grep -c 'provenIn('` minus the two declarations in
`proven_elsewhere.dart`, which agree. ⛔ **Re-derive rather than quoting that
figure, and `rm -f` the file first** — `provenIn` appends, so a stale file reads
as twice the corpus. The command is in
[Re-deriving the state](#re-deriving-the-state).
Cluster A (37 citations, 20 rows), C1 (25, 6), B (42, 25), G1 (37, 16), and the
cross-cutting bucket (14 citations over 6 of its 10 scenarios). **Eighteen
findings, thirteen closed and five open** — re-derive both by tallying the
`F<n>` headings in that detail file, since one of them recorded itself CLOSED
in its body while its heading was never struck, and every command keying on
headings counted it open.

⚠️ **The bucket is the part worth remembering.** Four clusters were audited, each
one finished, and none of them was the corpus: the passes were scoped by the
`UC-` ids in the catalogue, and a scenario with no id belongs to no cluster, so
the cross-cutting invariants sat at `—` in the enumeration table from the day it
was built. An audit organised by the ids in a catalogue cannot see work that has
no id. It held the largest legibility gap in the corpus.

**What is left is the fixing**, and it is a row of its own:
[the clause burn-down](#the-clause-burn-down-every-provable-then-clause-proven).

**The running record, the method and every finding** are in
[detail — the citation audit](detail/acceptance.md#the-citation-audit--cluster-a-2026-08-26)
and the cluster sections below it. The headline findings, one line each:

- **UC-A4.5** — its central clause was true in the code and established by
  neither citation, because both arms co-varied the sender's configuration with
  the recipient's. Closed by an isolating arm in
  `packages/at_client/test/nskey_kem_selection_test.dart`.
- **C1** — a posture axis pinned by nothing, proven by a mutation that left 1573
  tests green; a count stale in six places; a row reading PROVEN while its axis
  reached no production caller; a scenario still describing the pre-flip default.
- **B** — UC-B0.1 stated "No partial state on the server" unconditionally while
  its own second scenario disproved it. ⛔ **The number a reader counting PROVEN
  cannot see: 22 of B's 28 rows have LIVE proof** — three rest wholly on unit
  citations and three cite nothing at all. Not a defect, since PROVEN means a
  scenario asserts it and runs; it is what the status column does not
  distinguish.
- **G1** — the catalogue refused an empty `keys` array that the code, the
  scenario and the citations had all accepted since 2026-08-22; and two clauses
  whose proof existed in the tree and was cited from a neighbouring row or from
  no row at all.
- **cross-cutting** — the security clause of "advertised recipient keys are
  signed and verified" was described in a comment naming two test files and
  cited nowhere, while 16 of the 17 rejection tests in those files carried no
  citation. ⚠️ **A comment naming a test file is not a citation** — it reads like
  one, it is usually true, and the ledger counts none of it.

⛔ **Enumerate with the suite's own recorder, and `rm` the file first** —
`provenIn` appends, and a stale file reads as twice the citations. The command
is in that detail section; it cost a wrong figure of 284 before one file run
alone exposed it.

**Coverage was never the gap**, measured 2026-08-23 **against the 69-row
catalogue of that date**: of its 68 live rows, 59 had live proof of some kind
and 9 had none (12 LIVE_DIRECT, 43 LIVE_PARTIAL, 4 LIVE_INCIDENTAL, 9
NO_LIVE_PROOF), and only 29 of the 69 use-case ids were nameable anywhere in the
live suite. ⚠️ **Dated deliberately: the catalogue is 73 rows now**, so these
are a snapshot rather than the current state — the figure to trust for cluster B
is the one the audit measured directly, 22 of 28 rows with live proof.

⚠️ **`tests/` holds 6 Dart packages, of which 4 are live test packs.** The other
2 are `tests/pq_matrix/{published,scenario}` — the child processes the pair grid
spawns, which is why the `published` column can hold a released at_client this
tree cannot. ⚠️ **This read "7 … `{current,published,scenario}`" until
2026-08-26**, which was true when written and stopped being true when
`tests/pq_matrix/current` was deleted; the sentence survived because its own
warning was about a *different* miscount. Count with
`find tests -name pubspec.yaml`, never `tests/*/` — a depth-2 glob returns 4 and
reads as the whole answer.

⚠️ **The live corpus is 4 packs, not 2**, and this entry was scoped to 2 of them
for a long time. `tests/at_onboarding_cli_functional_tests` and
`tests/at_onboarding_cli_functional_tests_proxy` are live packs as well. ⚠️ **This
read "no citation reaches either" until 2026-08-31 and had been false since
2026-08-26**: three citations reach the CLI pack over two rows — UC-G3.11 cites
`pq_pre_enrollment_retrofit_test.dart` twice and UC-B1.4 cites
`pq_native_enroll_test.dart` once. None reaches the **proxy** pack, which is the
half that still holds. The CLI one builds clients from a `PqPosture` in two
arms — which makes it the best live evidence for UC-C1.6 and a second live proof
of UC-A1.1.

⚠️ **A citation count is not a coverage count.** An earlier pass reported "27 of
68 have no live proof" when what it had measured was 27 with no live proof *cited
from their acceptance scenario*. Do not restate it as coverage.

### Crypto agility, and the matrices that would prove it

**The property, as gkc states it** (2026-08-27): converging *all* advertisements
on an array — enrollment key packages, nskeys and `_apsk` — exists so that an
algorithm upgrade is an **ADD by the advertiser**. Nobody coordinates a flag
day; apps upgrade through successive rollouts and the wire moves when both ends
happen to be ready. **Add, never replace** is the whole design.

⛔ **It does not hold for all three today, and the exception is the nskey.**

| Advertisement | Can the advertiser ADD? | Evidence |
| ------------- | ----------------------- | -------- |
| **enrollment key package** | ✅ **Yes.** `KeyPackageMinting` mints across the whole `AtClientPreference.keyEstablishmentAlgorithms` list, and `reconcileKeyPackage` adds one at the next start after a preference edit — no rotation | Proven live: `key_package_amendment_live_test.dart`. A package created with one key gains a second, **the original kid stays `active`**, `suites` widens, and an envelope already sealed to the old kid still opens |
| **`_apsk`** | ✅ **Structurally yes** — `apskAdvertisement({required List<ApskSigningKey> keys})`, and `bareApskValueOf` collapses to a bare string only for a single active `rsa2048` entry, so the array is the general case | ⚠️ **Untested as an agility property.** **Five** producers write it — three call `apskAdvertisement` directly (`enrollment_submitter`, `enrollment_updater`, `pq_signing_root`) and two go through `apskValueOf`, the function that *chooses the wire shape* (`signing_key_minting.dart`, `apkam_signing.dart`). ⚠️ It said "three" until 2026-08-27, counting only the direct callers and omitting the minting path — the one a matrix author most needs. Nothing asserts that adding an entry leaves the existing one verifying, or that a one-algorithm reader accepts a two-entry advertisement |
| **nskey** | ✅ **YES, since 2026-08-28.** ⚠️ This said **NO**, quoting `_prepareMint`'s own *"an nskey is one key: only the enrollment's own key package advertises the whole configured list"*. The mint now writes a key per configured algorithm, and `PublishedNskeyKeyRing.add` joins one client's newly minted material to an existing generation in place | The **reader** shipped first and correctly (`NskeyAdvertisement.usableFor` walks `keys[]`), and the writer followed. ⚠️ Reader-ships-first was **not** free: `NskeyProvider` read the advertisement's single-key `alg`/`publicKey`/`nskeyKid` getters and could not address a second entry at all — fixed the same day, before the writer landed |

✅ **RULED 2026-08-27, and the investigation below it is superseded** — see
[decisions.md 119](detail/decisions.md#119-crypto-agility-each-advertisement-adds-and-the-signer-chooses-2026-08-27).
An nskey generation reaches its full set in **two** steps: a **rotation** mints
only new material and carries nothing forward, and a client that then finds its
own algorithm missing mints it and **adds** it to the current generation in
place, under the mint lock. Rotation is therefore also the garbage collection —
an algorithm nobody still runs never comes back — and an add never removes, so
nothing flaps.

⚠️ **Three conclusions this section used to carry were retracted in reaching
that, and each is worth keeping because each looked right.**

- *"The expensive part is that `nskeyKid` stops being a generation's identity,
  so `CkManager.ensureCurrent` must compare generations."* **False under the
  ruled design.** Fresh-only material means a rotation changes every `kid`, so
  every peer re-cuts; an add changes the preference-narrowed `kid` only for
  clients that prefer the added algorithm, so exactly those take it up. The
  existing comparison is correct and no change is owed.
- *"A rotation could carry the old keys forward."* Ruled out: it leaves nothing
  to ever remove an algorithm, and it hands a revoked enrollment back the private
  it already holds, because `revokeEnrollmentAndRotate` reaches the mint through
  the same `rotateNamespaceKey`.
- *"The minting client could compute the fleet's superset from the authorised
  enrollments' key packages."* Impossible: **only a build that implements an
  algorithm can mint material for it**, so no client can mint on another
  version's behalf. That single fact forecloses every pre-population scheme and
  is why population is incremental.

**What survives:** a private is filed and conveyed per `nskeyKid`, so more
algorithms means more `__ssenv` traffic — read the advertisement-fetch-volume row
before attributing any number there. The reader costs nothing (`usableFor`
already walks `keys[]`), one signature covers the document however many entries,
and the mint lock is one per `(owner, namespace)` regardless.

**The window, and whose it is.** Between a rotation and the adds that repopulate
it, the generation is a strict subset of what the fleet needs, so a sender whose
policy refuses everything in it is refused outright. That is the application
owner's to manage, by the ladder this project uses on itself: roll out the new
**receive** capability first, so receivers begin minting the new material while
senders still seal to the least-preferred member of their allowed set; roll out
the new **send** policy second, after which a loud refusal is the right answer.

✅ **They landed on 2026-08-28 as [`acceptance.md` section 17](acceptance.md#17-g2--crypto-agility--add-never-replace),
eleven use cases (`UC-G2.1`–`UC-G2.11`) — count the clauses rather than reading a
figure here; it said 53 until 2026-08-28, when the next commit made it 54 — with scenarios in
`packages/at_client/test/acceptance/g2_agility_test.dart`.** This paragraph
listed five drafts and said they were "drafted, not landed"; where each went:

| The draft | Where it landed |
| --------- | --------------- |
| a reader accepts more entries than it understands | **split three ways**, one per advertisement — UC-G2.1, UC-G2.2, UC-G2.3 — because each parses independently |
| an ADD moves nothing peers already address | UC-G2.4, plus UC-G2.5 and UC-G2.6 for the nskey's two-step path, which is not an in-place add |
| a sender picks from the intersection under its own fixed order | **already existed** as [UC-A4.5](acceptance.md#55-uc-a45--a-sender-follows-the-recipients-advertised-algorithm-not-its-own-preference); no new row |
| no shared entry is a refusal, never a guess | **already existed** as [UC-A4.6](acceptance.md#56-uc-a46--the-construction-is-negotiated-from-suites-and-no-shared-entry-is-a-refusal); no new row |
| a retired entry stops being OFFERED but keeps opening history | UC-G2.7, with the signature-matching half split out as UC-G2.8 |

Three rows have no draft above them because the section grew past this list:
UC-G2.9 — which was the two-signature escape hatch when this was written and is
now its refutation — and the ladder pair UC-G2.10 and UC-G2.11.

**The three matrices are the evidence, one per operation pair**, each run
send-and-receive × self→self and self→other × advertiser offering `{A}`, `{A,B}`,
`{B}` — one namespace per variation:

- **encrypt / decrypt**, the nskey data path — the row *the advertised-algorithm
  matrix is untested*, in P1 above. (Named rather than linked: it is a table row,
  not a heading, so there is nothing to anchor to.)
- **sign / verify**, `_apsk`.
- **encrypt / decrypt in the secret-sharing substrate**, key packages and
  `__ssenv`.

⚠️ **A matrix cell is not a use case, and neither replaces the other.** The
matrix says *this combination works*; the use case says *why that combination
existing is what removes the flag day*. The clauses are proven by the cells, and
a cell with no clause is a test nobody can say the purpose of.

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

### How the negative cache falsified three clauses

**Found by the clause sweep on 2026-08-27 and then measured**, because three
separate clauses turned out to contradict the tree in the same way and one cause
is likelier than three coincidences.

**What the tree does.** `NskeyResolver` remembers *misses*
(`nskey_resolver.dart` — `missMemory`, defaulting to `const Duration(minutes:
15)`; `_missedAt`, keyed `owner|namespace`; `_recentlyMissed`, which makes
`resolve` **skip the probe entirely**). The resolver is not per write: a client
builds one `CkManager` and therefore one resolver, and `crypto.dart` says so in
as many words — *built once per client*. So the first write toward a recipient
who has not published stamps a miss, and every later probe of that recipient is
skipped for the rest of the window.

**Measured live** (an e2e probe against the local virtualenv, since a claim
about mechanism is a hypothesis until something names it):

| step | result |
| ---- | ------ |
| bob has no key for the namespace | `false` — the premise |
| `isReadyFor(bob, ns)` before | `false` |
| alice's first `put` toward bob | throws — **and this is what warms the miss** |
| bob mints and publishes; **control**: a *fresh* key ring on alice's own client asks for bob's key | **`true`** — bob is genuinely reachable |
| `isReadyFor(bob, ns)` on the same client | **`false`** |
| alice's second `put` on the same client | **throws** |

The control is what makes it a measurement rather than a guess: a ring that never
probed sees bob's key over the same connection at the same moment the client that
did probe cannot.

**Why it matters beyond the clauses.**

- **It is app-visible through the pre-flight query.** `CryptoRuntime.isReadyFor`
  resolves through the *same* resolver
  (`symmetric_aes_gcm_provider.dart`), so an app that asks "can I reach bob yet?"
  is told no for up to fifteen minutes after the answer became yes. Its dartdoc
  — *"'yes' here is as current as the write's own would be"* — is true and
  reads as a freshness guarantee; both are stale together.
- **The refusal an app is shown asserts something false.** It says the namespace
  "has never been used or authorised there", which was true when the miss was
  stamped and is not true when the message is produced.
- **Nothing can clear it.** `NskeyKeyRing.forget` and
  `PublishedNskeyKeyRing.forgetRemote` invalidate the *ring*; the resolver's
  negative cache has no equivalent, and the resolver skips the probe **before**
  the ring is consulted, so forgetting the ring entry changes nothing. The only
  reset is a new client.
- **It sits against `ensureCurrent`'s own stated purpose.** That method's dartdoc
  says *"the re-fetch is the point, not an optimisation … the only way it learns
  of a rotation"*. Rotations are safe, because only misses are remembered and a
  rotation is a changing hit. Cold starts are not.

⚠️ **The cache's own justification never mentions the owner.** It reasons about
not re-probing the *levels* of a composed namespace on a repeated write — a real
cost, and the unit tests that cover it measure exactly that. But the key includes
`owner`, so the optimisation reaches a dimension its reasoning does not.

**The ruling** (gkc, 2026-08-27): **a remembered miss may make a resolution
cheaper, never wrong.** `NskeyResolver.resolve` walks with the memory as before;
if it *hits*, nothing changes. If it finds nothing **and** the memory made it
skip a level, it re-walks the skipped levels for real before answering null.

⚠️ **A narrower fix was ruled and then withdrawn the same hour, and why is worth
keeping.** The first ruling was to make `CryptoRuntime.isReadyFor` bypass the
cache — appealing because a *query* means "now", and because a hit already clears
the remembered miss, so an app that pre-flighted would unblock its own next write
too. gkc asked when an app would *not* pre-flight. The answer settled it:
`isReadyFor` has **zero production callers**, so "an app that pre-flights" was no
app at all. It would have left every ordinary `put`, every `notify`, the natural
catch-and-retry, every background write, and all self data exactly as broken.
**The lesson is general** — a fix routed through an API nobody calls is a fix
nobody gets.

**Where the cost lands.** A repeated write that resolves walks no further than it
did before, which is the case the optimisation was built for. The extra probes
fall only on a resolution about to return null — for a write, one about to throw
— so a caller already in its error path pays them.

**Proven both ways.** Unit (`nskey_resolver_test.dart`): a key published after a
miss is found on the very next resolve; a resolution that skips nothing probes
each level once, so the second walk does not double an ordinary cold write; and
a repeated cold resolve pays the walk again, deliberately. Reverting `resolve` to
the single walk reddens the first and third while the pre-existing
*a level already found empty is not re-probed* guard and the no-waste test both
stay green — so the optimisation is not entangled with the fix. Live
(`pq_cold_start_recovery_test.dart`): mutated once per assertion, the readiness
arm and the write arm each redden on their own, with the control — a key ring
that never probed, on the same client over the same connection — green in both.

⛔ **That live file is separate from `nskey_recipient_not_ready_test.dart` and
uses `thirdAtSign`, and it has to be.** A successful nskey write publishes the
writer's signing root, and `retrofit_e2e_test.dart` asserts `firstAtSign` has
none — that row is about the root being *created* by the retrofit. Written as a
second test inside the sibling file it took two unrelated rows down with it, and
the failure it produced blamed a virtualenv that had in fact been recycled: the
e2e compose file declares no volumes, so every run starts clean. **The
precondition was the destructive write**, exactly as the tree's own rule says.

### The clause burn-down: every provable THEN clause proven

**What done means** (gkc, 2026-08-27), and the reason every earlier audit
failed to answer it. Done is *every **provable** THEN clause proven* — the
clauses that cannot be proven by construction are enumerated in
`unprovableClauses` in `packages/at_client/test/acceptance/manifest.dart`
(gkc, 2026-08-31), and there is one — and every instrument
this catalogue had measured **rows**. A row reads `PROVEN` on a single
citation however many separate things its THEN states, so the row-level
verdict could not come out badly and could not reassure anybody — which is
what weeks of measuring produced.

Two columns, tracked separately, both printed by the acceptance suite on every
run:

```
BURN-DOWN  clauses proven: <N> of <T>   server-proven: <M> of <T>
```

⚠️ **`<N>` and `<M>` are deliberate.** Both figures were written out here and in
`acceptance.md` on 2026-08-27 and were stale within the hour — and disagreed with
each other, 95 against 93, while the tree said 99. A number with two homes and no
rail over either is a number that lies; the live figures are in `manifest.dart`,
where a guard fails in both directions if they drift from the tree.

- **proven** — some citation pins the clause. Objective 1 is every clause.
- **server-proven** — the citation pinning it drove a real atServer.
  Objective 2 is to raise this wherever a live test is feasible, which
  [the evidence standard](acceptance.md#0-purpose-scope--how-to-read-this-doc)
  says is everywhere it is not impossible.

⚠️ **The denominator counts clauses AS WRITTEN, and the clusters do not slice
their prose the same way — so a percentage from one cluster does not compare
with a percentage from another.** Some rows state each asserted behaviour on its
own `*And*` line; others pack several into one `*Then*`, controls included.
UC-G1.2's single `*Then*` carries three separate behaviours (the new material is
active, the legacy keypair is left byte-identical, and the resolver returns the
new id), and UC-G1.7's carries its assertion *and* its control arm; a row in
section 18's style would state each of those separately. Neither convention is
wrong, but they measure differently in both directions: the packed form yields
fewer clauses that are each **harder** to pin, since a clause is pinned only
when every arm of it is established, and the split form yields more clauses that
are each easier. Read the total as *how finely this catalogue chose to state
itself*, never as a count of behaviours, and re-derive per-cluster densities from
`clausesOf()` in `manifest.dart` rather than assuming they are alike. Recorded
2026-08-31, after a burn-down move of +30 clauses from eleven rows prompted the
question; the eleven were not unusually dense against the catalogue as a whole,
only against the neighbouring cluster written in the packed style.

⚠️ **A jump in `proven` is not by itself a jump in evidence.** A clause written
*after* the code and its tests is pinnable the moment it is written, so a
catalogue catching up with work already landed raises both columns together
while nothing new has been proven. Section 18 is the worked example: of the
citations backing its clauses, exactly one names a test written by the same
work — the commit that wrote the clauses added no test at all — and that one
moved the count by nothing, because its clause was already pinned by a sibling
citation. The rest name tests that already existed. What such a move buys is real —
the behaviours become checkable and the tests become findable — but it is
bookkeeping, and it should be reported as bookkeeping.

⚠️ **Pins are strict.** A clause is pinned only when the cited test
establishes it *as written*. Clauses routinely carry several arms in one
sentence — a value and a refusal, a shape and its control — and a test proving
two arms of three leaves the clause unpinned with the missing arm recorded.
Pinning generously would make a full burn-down worth nothing.

⚠️ **A pin is a claim, not a run**, and the two guards say different things.
`catalogue_test.dart` checks that every pin resolves to exactly one clause and
that the recorded counts match the tree, failing in **both** directions so a
landed pin and its count move in one diff. `tool/acceptance_ledger.dart` is
what says the cited test actually ran and passed.

**Where the remaining work is enumerated**, measured 2026-08-27 by reading every
clause against the tree — ⚠️ **and the enumeration has not kept up.** Two clusters
landed after that measurement and neither is in any of the four lists below:
section 18's eleven `UC-G3.x` rows (2026-08-31, +30 clauses) and section 6's
`UC-A5.4`/`UC-A5.5`/`UC-A5.6` (2026-08-31, +15). Between them they carry **two**
of the unproven clauses — `UC-A5.5` clause 3, *"there is no third ask"*, and one
in section 18 — so a reader working the four lists top-down will not reach them.
`grep -c 'UC-G3' detail/acceptance.md` returns 0. Re-derive which clauses are
unproven from the tree rather than from these lists:

| List | Size | What it is |
| ---- | ---: | ---------- |
| [the partial clauses](detail/acceptance.md#the-partial-clauses--objective-1s-remaining-work) | count the table | a test exercises the clause and does not establish it as written. **The in-process ones are all closed**; all that remain are live and are the only route that raises server-proven. ⚠️ **Read the array-shape warning above before writing a test for any of them** — three of the six examined on 2026-08-27 were superseded clauses rather than test gaps |
| [clauses owed a citation](detail/acceptance.md#the-proven-clauses-still-owed-a-citation) | 0 | proven, but no citation names the proof. ⚠️ **Was 33, then 1, and is now empty** — the last, UC-A2.4's `pqSeal ver 0x03`, was withheld until the live test stopped asserting the byte against the function that generates it. Pinned to the raw literal 2026-08-27, with the discrimination measured against a consistent wire renumbering rather than reasoned about |
| [pinned but partial](detail/acceptance.md#clauses-pinned-in-the-tree-that-the-map-calls-partial) | 1 | pins that predate the mapping, where the cited test misses an arm. Candidate over-claims — if they do not survive review the recorded figure falls. ⚠️ **Was 2**: UC-G1.1 c2 was closed 2026-08-27 by an arm on a *retrofitted* keyfile, the only shape where the flat field and the resolver both answer and disagree. It defends the figure rather than raising it — the clause was already counted, by a test that never called `authenticate` |
| [section 17's clauses](detail/acceptance.md#section-17--the-crypto-agility-clauses-and-what-each-waits-on) | count them | never mapped, and the **bulk of what is unproven**. Most were not test gaps: they described the plural nskey mint, the `add`, the signature key identifier, the durable revocation record and step 3's verifier lever. ⚠️ **The first two landed 2026-08-28**; the rest are open `## TODO` rows above. The subsection maps clause to row, measured 2026-08-28 against the production paths, and says which six have not been read against the tree at all |

⛔ **Nothing MAPPED is untested.** Every clause the 2026-08-23 mapping walked has
something exercising it, and the single absence it found was refuted; for those,
the gap is the precision of assertions rather than the absence of tests.
⚠️ **That is no longer a statement about the whole catalogue.** Section 17's
clauses — count them, do not read a figure here; it said "seventeen" until
2026-08-28 when there were 53 — were added by
[decisions.md 119](detail/decisions.md#119-crypto-agility-each-advertisement-adds-and-the-signer-chooses-2026-08-27),
and several of them had nothing exercising them at all. ⚠️ **This said "the
nskey mint they describe is unbuilt", which stopped being true on 2026-08-28**;
what remains unbuilt is named by the subsection this paragraph points at. **What each one waits on is now enumerated**, in
[section 17's own subsection](detail/acceptance.md#section-17--the-crypto-agility-clauses-and-what-each-waits-on).
Re-derive rather than reading this paragraph as current.

⛔ **And a clause can be FALSE rather than imprecise, which no instrument here
reports as anything but a test gap.** A sweep of the 29 partials on 2026-08-27
classified **11 of them as specification defects** — the tree contradicts what
they say — against 18 ordinary gaps, a split an adversarial pass over all 12
original calls upheld but for one. **They were not 11 coincidences, and that is
the reusable part**: three shared one cause,
[the negative cache](#how-the-negative-cache-falsified-three-clauses), fixed the
same day; two were the signing-root privilege gate stated from both sides, which
the tree refuses deliberately while both clauses said it grants; two were the
retrofit cap, whose formula the clauses had right and whose *re-arming* they
missed; two were the self-copy, an AtCollection behaviour these rows do not
assert. **All eleven are discharged** — four in the code, seven in the
catalogue —
and the [remaining defects](detail/acceptance.md#the-partial-clauses--objective-1s-remaining-work)
are counted by the table that lists them rather than by a figure here. **Open the production path a clause describes before writing its
test** — a test written to a false clause fails confusingly, and the tempting fix
is to weaken the assertion until it passes, which enshrines the wrong behaviour
as the specification. The live proof of the fixed one is
`pq_cold_start_recovery_test.dart`, and the notify half of UC-A4.4 is
`pq_notify_fallback_test.dart` — ⛔ **a separate file on purpose.** `notify`
folds a key outside the client's app namespace into the key name and
substitutes the client's, and `AtClientManager` caches a client per
`(atSign, enrollmentId)` — so a second test in one file inherits the FIRST
test's namespace and every notify in it is silently redirected there. Measured
2026-08-27: the arm passed alone and failed in CI, resolving against a namespace
the recipient had been made to publish for by the file's own first test.

⛔ **Why the catalogue drifted, named by gkc 2026-08-27 — and the reason to
expect more of it.** The use cases were never updated after the agility decision
that **all advertisements must hold ARRAYS** — enrollment key packages, nskeys,
and `_apsk` at the pqActive posture. Every stale clause found on 2026-08-27 is a
pre-array single-key assumption, and they were found one at a time by tripping
over them:

| Clause | What it assumed |
| ------ | --------------- |
| UC-A3.5 c3 | a bare shape where an absent `alg` could only mean the one KEM that existed |
| UC-A2.4 c5 | that no client sends `enroll:update`, so a second key could never be advertised |
| UC-C1.6 c1 | every posture axis is individually overridable |

**So this is one uncorrected consequence, not three coincidences, and the
remaining partials have not been searched for it.** A clause written against the
single-key shape reads as a test gap rather than as a specification defect, which
is exactly how the mapping classified all three. ⚠️ **Sweep the catalogue for
clauses reasoning from "there is only one KEM", from a flat or bare
advertisement, or from an entry rather than a list — before writing a test for
any of them.** Writing a test for a superseded clause fails confusingly, and the
tempting fix is to weaken the assertion until it passes, which enshrines the
wrong behaviour as the specification.

**The instances, found by a cold read on 2026-08-27 and CORRECTED the same day.**
All were in `acceptance.md`; each was verified against the tree before editing,
and two of the cold read's rows did not survive that check. The corrections are
in `acceptance.md` itself, each stale sentence replaced in place with a dated
⚠️ note saying what it used to claim.

| Where | What it assumed | What the tree says |
| ----- | --------------- | ------------------ |
| **UC-A4.5**, "the KEM is configured, never negotiated" | "each atSign advertises **one** KEM per generation, and rotation is the only moment that can change" | **Both halves false**, and the clause was pinned. `KeyPackageMinting` mints a keypair for *every* configured algorithm; `reconcileKeyPackage` adds one at the next start after a preference edit, no rotation. The SP 800-227 conclusion survives on a different mechanism — the offer is APKAM-signed and the sender's order is fixed — so the clause was rewritten and re-pinned to four tests that establish *that* |
| **Section 1**, key objects | the nskey is "**one** X-Wing KEM keypair"; the key package is "the per-enrollment **X-Wing** recipient keypair" | The nskey's *cardinality* held when this was written — a mint wrote one key, under `keyEstablishmentAlgorithms.first` — but naming the algorithm was stale. ⚠️ **The cardinality has since moved too**: from 2026-08-28 a mint writes a key per configured algorithm. The key package's is false outright: it carries a key per configured algorithm, and `kpid` names whichever entry is active |
| **Section 1**, state table | "its **X-Wing** key package"; "the namespace's **one** nskey private" | Same algorithm staleness; and an enrollment holds every superseded generation's private too, filed per `nskeyKid` — `rotate` retains rather than replaces, which Section 1's own nskey bullet already said |
| **Section 1**, `appMetadata` | only `at/nskey/XWING/AES/GCM` | Both ids are in the tree (`nskey_records.dart`) and both are registered on every client |
| **UC-A3.2** mint step | mints "the **one** … X-Wing keypair" | The "one" was right when this was written and the algorithm was not. ⚠️ **Neither is right now**: from 2026-08-28 a mint writes a key per configured algorithm |
| **UC-A3.1** / **UC-A4.1** data paths | "**X-Wing-seal** the CK" | The seal follows the *destination's* advertised `alg` — which is UC-A4.5's own subject |
| **UC-A2.1** steps 1–2 | "**X-Wing** key package", "(X-Wing)" | Under UC-A2.4 a configured deployment produces an ML-KEM package here |
| **UC-A2.1** step 3 and Then | E2's `_apsk` is "the **bare** key value, exactly as today" | **False for UC-A2.1's own Given.** `bareApskValueOf` returns bare only for a single *active `rsa2048`* entry; a pq-native E2 advertises `mldsa65`, so it gets the array. The point the sentence was making — the value is not wrapped in an envelope, and the chain link rides the *metadata* — survives and now says so. ⚠️ The cold read guessed the condition was the posture and cited "section 15.7"; the condition is the entry's algorithm, and the table is in section 16 |
| **UC-A1.1** step 4, **UC-B1.1** step 2 | onboarding and retrofit mint an "**X-Wing** key package" | Both mint under `keyEstablishmentAlgorithms.first`; the rest arrive at the next start |
| ~~**UC-A1.1** Then, "no RSA-wrapped (`apkamSymmetricKey` rides X-Wing)"~~ | — | **Mis-cited.** The phrase occurs once in the document and it is in **UC-A2.1**'s Then, not UC-A1.1's. Corrected there |
| ~~**UC-C1.7**, the two signing-set axes "overridable per preference"~~ | — | **False alarm — the sentence is TRUE.** `AtClientPreference` resolves both `authenticationKeyAlgorithm` and `dataSigningKeyAlgorithms` as `?? posture.<axis>`, so an explicit argument beats the posture on each. UC-C1.6's exception was `disallowLegacyEncryption`, which has no constructor argument at all; the two are not the same sentence |

**What the corrections cost the burn-down: nothing** — the figure was
unchanged across that commit, in both columns. (Read the current one by running
the suite; it has moved since for unrelated reasons.) Every stale sentence but
two lived in a **Steps** block or in Section 1, and only **Then** clauses are
counted; the
two that were clauses kept their pins, UC-A4.5's by re-pointing them at four
tests and UC-A2.1's because its fragments were short enough to survive the edit.

⚠️ **The sweep also found a defect in the citation rail itself.** `provenIn`
matched a cited test name against the raw source with one spelling, so a test
whose name contains an apostrophe — 22 files in `at_client` alone — could never
be cited, and the failure read as "no test there starts with that name", which
sends a reader looking for a rename. It now tries both source spellings, and a
citation naming a genuinely absent test still goes red quoting the name.

⚠️ **Six live partials sit under use cases in that table**, so the
clause a test would be written to has just moved. (The one in-process partial
that did — `UC-A1.1` c3 — is closed.) Re-read the clause in `acceptance.md`
before writing its test — the
partial-clause table in [detail](detail/acceptance.md#the-partial-clauses--objective-1s-remaining-work)
quotes the wording as it stood on 2026-08-27, which for those six is no longer
what the catalogue says.

⚠️ **Check the production path before writing the test.** Of the six clauses
examined closely on 2026-08-27, **three were false rather than untested**. The
check is cheap — open the code the clause describes — and it is the only thing
that separates the two.

The five findings below are clause gaps under another name, and are counted
here rather than in a list of their own.

Five open findings, recorded in full in
[detail — the citation audit](detail/acceptance.md#the-citation-audit--cluster-a-2026-08-26)
and the cluster sections under it. **Tally them by the `F<n>` headings in that
file rather than from this list** — one finding recorded itself CLOSED in its
body while its heading was never struck, so a command keying on headings counted
it open and disagreed with the prose. Both were honest and one was wrong.

⚠️ **F11, F12 and F18 closed on 2026-08-26**, and what closing them turned up is
worth reading before writing any refusal test. F11 was that all seven refusals in
`enroll_update_live_test.dart` were `throwsA(isA<Object>())`, which cannot tell
the guard firing from a timeout. Probing first — rather than inferring from the
handler — showed all five come back as `AtLookUpException` with distinct
messages, so they are now asserted by name and each was mutated to prove it
discriminates.

⛔ **F18 came out of that probe and is the sharper defect.** UC-G1.12's arm sent
`enroll:update` naming `namespaces` **and nothing else**, so the atServer refused
it for naming no recognised field at all — an earlier well-formedness check,
which says nothing about namespaces. The escalation guard the row names was never
reached, and deleting it would have left the test green. Naming one valid field
alongside reaches it. **The shape generalises: a refusal arm must differ from the
accepted case in the forbidden thing and in nothing else**, and stripping a
request down to only the illegal field is the natural way to write the test and
the reliable way to miss the guard.

**F16 is now the one that matters, and it shares a measurement with
[the seeding failure mode](#a-client-that-exits-during-its-startup-tail-abandons-seeding).**
⚠️ That was a P0 row until 2026-08-28, when the row was retired as done; the
`###` section it named is still here and is what this points at. `neither key record is immutable; the lock that mints them is`
names `_rootlock@owner` and `_nskeylock.<ns>@owner`, and proves the live refusal
for the first only. The nskey lock is covered by a raw-literal pin of the
client's intent and by a mock that models the refusal on the key name — and a
mock cannot test a refusal it does not model, so the guard's presence and its
absence look the same.
[The seeding section](#a-client-that-exits-during-its-startup-tail-abandons-seeding)
recorded its self-perpetuating-interlock arm as reasoned from the code rather
than measured; ⚠️ **that stopped being true on 2026-08-28** —
`mint_lock_self_contention_test.dart` measures it in-process, and the live
half below is what remains. **It is the same measurement, and one live test
discharges both.**
`pq_signing_root_mint_lock_test.dart` already takes, releases and re-takes a lock
against a live atServer; a fourth test doing that with `nskeyMintLockKey` is the
same shape against a different key.

**The remaining four:**

- **F15** — UC-G1.2 promises the resolver returns the new enrollment id after a
  retrofit, and nothing calls it. Sharper than it looks: the flat `enrollmentId`
  stays at the legacy enrolment, so the keyfile answers the question two ways
  depending on which field a reader takes, and the row promises one of them.
- **F8** — every UC-B1 assertion is a restriction, so an enrolment that gained
  nothing and can do nothing satisfies the whole cluster. Partly answered by
  UC-B1.4 to UC-B1.7, which assert capabilities; the review question it
  generalises to is worth keeping: *does this row assert a capability, or only a
  restriction?*
- **F1** — the clause level was 9% adopted when this was written (2026-08-26; it is 59% at 2026-08-29, so re-derive rather than reading either), so the ledger could not show which part
  of a row an individual citation is for.
- **F3** — about 8 citations rest on tests they do not pin.

⚠️ **Also still open from cluster B**: UC-B1.3's `nskey`-subset clause is stated
in the catalogue and established by no citation, recorded at the row.

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

### A client that exits during its startup tail abandons seeding

⛔ **Confirmed live in both directions, 2026-08-26, by the at_talk demo
session.** The variable is the client's LIFETIME and nothing else — same
client, same keyfile, same posture, same environment, same minute, with stdin
held open for 35 s instead of piped and closed:

| | lock frame | advertisement |
| --- | --- | --- |
| stdin piped and closed | never reached the atServer | never |
| stdin held open 35 s | `19:48:12.191Z` | `19:48:12.243Z` — 52 ms later |

After the second run the atSign was reachable as a recipient for the first time
that day.

**The mechanism.** Seeding is unawaited work: `AtClientImpl._init` fires
`PqClientBootstrap.startup()` without awaiting it, deliberately, because
construction must not block on network round trips. A client that finishes its
job and exits takes the process down wherever the tail has got to. In the
failing run it got as far as forming the mint interlock write — the client
logged `update to remote: …_nskeylock.<ns>@<atSign>` — and the wire capture,
which ran another 26 seconds, carries no such frame from that atSign at all.
The bytes never left the process.

⚠️ **The retrofit is not the cause**, though that is where a day of
investigation went. Every route that retrofits publishes, because each keeps
its client alive:
[UC-B1.4](acceptance.md#84-uc-b14--a-retrofitted-scoped-enrollment-runs-an-authenticated-verb)'s
file carries arms for the in-process route, the cold-keyfile route and
`at_activate list`. The retrofit merely produced an atSign with nothing
published whose every later client was short-lived.

⛔ **Two failure modes, and the second is worse.**

1. **Silent abandonment.** Nothing tells the caller. The only symptom is at the
   FAR end, where a *different* atSign reports "@X has no published nskey" —
   naming the wrong party, which is what sent the investigation to the retrofit.
2. **A self-perpetuating interlock.** A client that dies *after* the lock lands
   rather than before leaves an immutable `_nskeylock.<ns>@<atSign>` with a
   120-second ttl that nothing deletes, and a successor that finds it held with
   nothing published throws rather than minting. ✅ **Both of those are measured
   as of 2026-08-27** — see `nskey_mint_lock_live_test.dart`. ✅ **And the LOOP
   is measured as of 2026-08-28** — `mint_lock_self_contention_test.dart`,
   three arms in which the only thing that varies is
   `ownLockIsNotContention`. ⛔ **The answer splits by path, and this
   paragraph's "could never get through" is FALSE for the nskey lock it
   names.** `mintAndPublish` passes the flag and `MintLock._holder` is the
   enrollment id — an identity, not an instance — so a relaunched client meets
   its own token and proceeds. It is the **signing root** that has no such
   escape, because its mint does not pass the flag; that is
   [ruling 124](detail/decisions.md#124-the-signing-roots-mint-lock-is-sized-against-starvation-not-contention-2026-08-28),
   which shortened `signingRootMintLockTtl` to 15 seconds rather than leaving
   the window at two minutes.

**And `startupComplete` cannot be the answer as it stands.** It is the only
signal a caller has, and `stop()` breaks the step loop and completes it anyway,
so it resolves identically whether the work ran or was skipped. A caller that
waits for it still cannot tell.

✅ **REPRODUCED IN-TREE 2026-08-27**, as a two-file differential against the
local virtualenv. Same atSign, same posture, same construction, same minute,
run-unique namespace each — the only variable is whether the tail was stopped:

| arm | file | advertisement | `startupComplete` |
| --- | --- | ---: | --- |
| left alive | `seeding_tail_runs_live_test.dart` | **published in ~1s** | — |
| stopped as the client was returned | `seeding_tail_abandoned_live_test.dart` | **nothing after 15s** | **resolved at 185 ms** |

⚠️ **Two files because `AtClientManager` is a per-isolate singleton** that
re-serves the client it already built — two arms in one file share one
bootstrap, and whichever ran second measures nothing. Break-it checked:
removing the `stop()` reddens the second arm, so it measures the stop and not
the environment.

⛔ **Why the earlier attempts failed, now that a control exists.** They were
lost on the rig, not on the hypothesis, and attempt 3's diagnosis was wrong:
it concluded "the rig could not seed for those namespaces at all" when a
living client at a **seeding posture** publishes in about a second. The trap
is that `seedNamespaceKeys` is **false** at `PqPosture.legacy`, so a client
built there correctly publishes nothing and the red says nothing about
stopping.

⚠️ **And `nskey_seeding_live_test.dart` is blind to this defect**, though its
own doc comment says it exists to catch "whether the path runs at all — a
client whose seeding silently never fired". It builds at `PqPosture.legacy`
and calls `NskeySeeding.seed()` by hand, so a client whose tail never fires
passes it. Nothing else covered it either: `pq_posture_grid_test.dart` builds
cells at seeding postures and depends on the tail having run, but only
indirectly — its writes would fail otherwise. That is the hole this shipped
through.

**Item 3 measured.** The abandonment is not silent, but it is not loud either:
`AtSignLogger`'s default `_root_level` is `info`, so the line *is* emitted in
production —

    INFO|…|PqClientBootstrap (@alice)|PQ startup stopped for @alice; the
    remaining steps will not run (the next start retries them)

— at `info`, among 31 other `info` lines in a 15-second run, naming neither
which steps were skipped nor the consequence (this atSign is now unreachable
as a recipient). ⚠️ **And "the next start retries them" is reassuring in a way
that is false for the shape that hits this**: a cron job or a piped-stdin CLI
does have a next start, and it abandons too.

⚠️ **The tree already contradicts itself about whether `startupComplete` is
for callers.** `at_client_impl.dart:308` says "tests do; production code must
not"; `:696` says "Awaitable via `pqBootstrap`'s `startupComplete` for callers
that need the tail to have run". That is request item 5 made concrete, and it
is a defect in the tree today.

✅ **FIXED 2026-08-27.** Both halves of the app author's stated minimum:

- **Item 3** — the abandonment logs at `warning`, naming each skipped step and
  saying that peers cannot seal here, and deliberately dropping "the next start
  retries them".
- **Item 1** — **`AtClient.ensureReachable(namespace)`**, on the **interface**
  rather than on `pqBootstrap`. ⛔ **Ruled by gkc 2026-08-27**, and the
  deciding argument was not cost: a perfectly typed outcome on the bootstrap
  still answers a question about *our* twelve internal steps, and the app's
  question is "can peers send to me". `pqBootstrap` is also `@experimental` and
  documented as not for app authors, so an outcome surfaced there does not
  reach the caller who reported this. Returns `AtReachabilityResult` —
  `alreadyReachable` / `published` / `postureDoesNotSeed` / `notAuthorised` /
  `timedOut` / `failed`. Item 2 is folded in: it *is* the "do not exit until I
  am reachable" call. Items 4 and 5 (the asymmetry, and pointing
  `startupComplete` at the alternative) are covered by the new dartdoc, which
  states the send/receive asymmetry where an app author meets it.

**Proven by a three-file live differential**, each file its own isolate because
`AtClientManager` is a per-isolate singleton: `seeding_tail_runs_live_test.dart`
(alive → publishes), `seeding_tail_abandoned_live_test.dart` (stopped →
nothing), `ensure_reachable_live_test.dart` (stopped, then rescued → published,
and a second call reports `alreadyReachable` rather than minting again).

⚠️ **What the live arm caught that a mock could not.** Extracting a
per-namespace `NskeySeeding.seedNamespace` initially let a **conveyance**
failure sink the whole seed, so `ensureReachable` reported `failed` for an
atSign whose advertisement had just been published. A legacy PKAM client has
no APKAM keypair, the conveyance enumerates members with `enroll:listns`, and
the atServer refuses that without APKAM authentication. Publishing is what
makes an atSign reachable; conveying is what gives its *other* enrollments the
private, and an enrollment that misses the push pulls at its next start — so
the two are now guarded separately. The original `seed()` counted the namespace
as minted *before* conveying, so this also restores behaviour the extraction
had changed.

✅ **Failure mode 2's two mechanisms are now MEASURED**, in
`nskey_mint_lock_live_test.dart` against a live atServer, each with its own
control and each mutation-proven:

- **The atServer refuses a second create of `_nskeylock.<ns>@<atSign>`**, on
  its own message — so the refusal is the interlock and not an unrelated write
  failure. Control: the same write is accepted once the lock is released.
  Mutation: skip the first take and the second write succeeds.
- **A client meeting a lock held by another enrollment, with nothing
  published, refuses to mint and publishes nothing.** Control: the same call
  succeeds once the lock is gone. Mutation: give the lock **this** client's own
  holder id and it mints instead of refusing — which is `ownLockIsNotContention`
  working as documented, and is what makes the sibling case the thing under
  test rather than "a lock exists".

⚠️ **What is still reasoned rather than measured is the LOOP**, and only that:
whether a short-lived client relaunched repeatedly could in principle never get
through. Both ingredients are now observed; the rate claim is not, and "could in
principle" is where it should stay until something counts it.
[The `batch` P2 row](#p2--should-be-done-if-there-is-time) would remove the
window structurally rather than shortening it.

⚠️ **The three earlier reproduction attempts**, recorded so they are not
repeated:

1. **Stop the client the enrolment handed back.** Vacuous green — that client
   was built seconds earlier inside the enrolment dance and its tail had long
   finished, so `stop()` had nothing to interrupt.
2. **Build a second client and stop it in the turn `create` returns.** Vacuous
   green for a different reason: the assertion was that `startupComplete` had
   resolved, and it resolves on a stopped startup by design.
3. **Assert the outcome instead — `startupComplete` resolved, so the
   advertisement must exist.** Went red, and then its own positive control went
   red too: an identical client left ALIVE on a second run-unique namespace
   also published nothing, so the rig could not seed for those namespaces at
   all and the red said nothing about stopping. Not committed.

✅ **That is what the successful attempt did**, and it is why it worked where
three others had not. The unexplained difference turned out to be the
**posture**: `seedNamespaceKeys` is false at `PqPosture.legacy`, so a client
built there correctly publishes nothing, and a red from that arm says nothing
about stopping. Establish a living client at a **seeding** posture first, and
the rest follows.

**What an app author says they need, written down at gkc's request
2026-08-26.** This is a request with a use case attached, not a ruling and not a
design — the shape is still owed. It comes from the session that hit the defect
while building a real chat client, and the case is ordinary: a client driven
from a script with piped stdin sends one message and exits, which is the same
shape as a CLI tool, a cron job or a one-shot notifier.

1. **An outcome, not a completion.** Whatever a caller awaits must resolve to
   *what happened* — published / already published / nothing to do and why /
   abandoned / failed with this error. ⛔ A future that resolves identically for
   "did the work" and "was stopped before doing it" is not something an
   application can branch on, and `startupComplete` is exactly that today.
2. **A supported way to say "do not exit until I am reachable."** The property
   an app cares about is not "startup finished" but "other atSigns can now send
   to me" — different sentences, and only the second is meaningful to an app
   author. Sketched as `await atClient.ensureReachable(namespace, timeout: …)`:
   idempotent, safe on every start, cheap when there is nothing to do. **Not
   asked for as a default.**
3. **Loud failure when the tail is abandoned or fails** — at warning, naming the
   atSign and what was not done. Same class as an event dropped on a delivery
   path, and for the same reason: the cost is paid by a different principal in a
   different process.
4. **The asymmetry written down where an app author will see it.** Sending works
   the moment the client is up; receiving does not, until the tail has run. That
   one sentence on `AtClient` would have saved the day this cost.
5. **If `startupComplete` stays as it is**, its dartdoc should name the supported
   alternative. `pqBootstrap` is `@experimental` and says "tests do; production
   code must not", so today the only thing that would have helped is explicitly
   not for app authors — which reads as "there is no way to do this".

**Stated minimum: 1 and 3.** If what a caller awaits tells the truth and an
abandoned publish is loud, an app author can build the rest.

⛔ **Explicitly NOT requested: making the tail awaited by default.** The reason
it is unawaited is good — construction must not block on the network — and
blocking it would trade this problem for a worse one in every app that never
needs to receive.

✅ **That live probe is built and green: `nskey_mint_lock_live_test.dart`**,
and it discharged both directions at once. It was owed because `_nskeylock` was
covered only by a raw-literal pin of the client's *intent* and by a mock that
models the refusal — and a mock cannot test a refusal it does not model, so the
interlock's presence and its absence were indistinguishable. It now takes,
releases and re-takes the lock live, exactly as
`pq_signing_root_mint_lock_test.dart` does for `_rootlock`.

⚠️ **And the interlock half is the sharper one**: if the lock cannot be made
self-healing, a client that takes it should release it on shutdown, and one that
finds it held with nothing published should say so at warning rather than
throwing something the caller cannot interpret. A cron-driven notifier is
precisely a short-lived client relaunched in a loop.

### An enrolment could race itself and publish two namespace keys

⛔ **FIXED 2026-08-27 (`9b51265a5`), and nothing is owed here.** Kept
because the shape recurs and because how it was caught matters more than
the fix. Out of `## TODO` deliberately: a row leaves that table when it is
done rather than gaining a ✅, and this one sat there with **Blocked on:
Nothing**, which is the exact signature of a pickable item.

✅ **FIXED 2026-08-27** (`9b51265a5`), recorded because the shape recurs. **Found by the at_talk demo session**, live: `@alpha` published two advertisements **7.5ms apart** with different key material, the second overwriting the first, both conveyed — a peer fetching in that window holds a generation whose private the owner may have replaced. **The cause:** the wire lock's value is the enrolment id, an *identity* rather than an *instance*, so a second concurrent mint by the same enrolment is refused the lock, reads it back, sees its own id, concludes it holds it, and mints. `ownLockIsNotContention` was built so an enrolment re-entering its own **cooldown** adopts; it also admitted this. ⛔ **Deliberately NOT fixed with a per-instance wire token** — the winner never releases the lock, the ttl does, so a client restarting inside the two-minute cooldown meets its own lock and must adopt; a per-instance token would make it refuse to mint for the rest of the ttl, and an ordinary restart falls inside that window. `MintLock` now keeps an **in-flight map keyed by lock record**: the second caller waits, then declines to its ordinary re-read-and-adopt path. ⚠️ **Two lessons worth more than the fix.** (1) The claim it falsified was in a shipped dartdoc and CHANGELOG — *"safe to call while the startup step is running… the loser adopts"* — corrected before the fix was written. (2) The test that should have caught it, `ensure_reachable_live_test.dart`, calls `stop()` **before** `ensureReachable`, so the two never race: **a probe that has to disable the very thing the claim is about in order to run at all** (at_talk's phrasing, and a better tell than the fan-out one).

**The app author's verdict on the API itself, 2026-08-27: "good enough, and
I'd ship it."** Recorded because the request came from them and a verdict is
what closes it. What they measured: the workaround block in their retrofit
script — a FIFO, a 60-iteration advertisement poll, a bounded shutdown and a
`pkill`, 3383 characters — collapsed to one call; **320ms** from connect to
advertisement on loopback; and a probe run **after the client process exited**
confirming the "you may exit the moment it returns" contract in the real
piped-stdin shape. `postureDoesNotSeed` answered in 35ms and reads as a fact
rather than a failure — they asked for the name to be kept. ⚠️ **Two arms of
their report are gaps rather than passes, and they said so**: `timedOut` never
fired, so it is untested; and nothing was abandoned in any of their runs, so
the `warning` this session added has never been seen to fire outside a unit
test.

✅ **Confirmed live by the reporting session, 2026-08-27, on the pinned fix**
(`9b51265a5`), and the confirmation is worth more than the count:

| | unfixed | fixed |
| --- | ---: | ---: |
| advertisement writes for one atSign | **2** (different kids, 7.5ms apart) | **1** |
| `_nskeylock` write attempts | **2** (second refused `AT0032`) | **1** |

The second lock attempt is gone entirely — the loser never reaches the wire,
which is a better outcome than one advertisement.

⚠️ **A 1 on its own would have been a claim about timing, not about the fix**,
so they proved the race *occurred*: the in-flight log line captured with a
negative control (50 INFO lines in that run) and a positive control (the line
itself). ⛔ **Their first attempt nearly reported "the race did not occur"** —
they grepped a log that carried **zero** INFO lines because `at_talk` pins
`AtSignLogger.root_level = 'SHOUT'`. A filtered stream, and the absence was a
fact about the log level. Re-run with `-v` on a second fresh environment.

**Scope, stated by them and kept here:** one observation per arm. It bounds no
rate, and "the race occurred in the run I have the log line for" is the whole
claim.

### A retrofitted enrolment cannot run an authenticated verb

⛔ **FIXED 2026-08-26, and nothing is owed here.** Kept because the mechanism is
counter-intuitive and the coverage gap that let it ship is a separate finding
that is still open. Reported by the at_talk demo session from a live ephemeral
environment, with shipped code: same `at_activate` binary, same atSign, same
environment, interleaved control then test on one keyfile, varying only whether
the retrofit had run.

| | |
| --- | --- |
| `at_activate list`, keyfile NOT retrofitted | exit 0, one enrolment listed |
| `at_activate list`, SAME keyfile, retrofitted | **exit 1** — `this PKAM key is 1218 bytes, and an ML-DSA-65 secret key is 4032` |

**The mechanism: three values, two sources.**
`AtOnboardingServiceImpl._initAtClient` adopts the client's own lookup on the
authentication path and stamps three things on it. The enrolment id and the
signing algorithm came from the client — deliberately, and with a comment
naming the retrofit as the reason. The signer came from the caller:
`authenticate()` passes `atAuth.atChops`, which at_auth built for the enrolment
the keyfile's flat fields name, *before* the client existed. A client that
retrofits during `AtClientImpl._init` comes up on a new enrolment holding an
ML-DSA-65 keypair, so the lookup then declared `mldsa65` over an RSA-2048 key.

⛔ **`authenticatorFor` cannot reconcile them, and that is what makes it
silent.** Given an injected signer it takes only the ALGORITHM from the keyfile
(at_auth's `_pkam`, the `injectedChops != null` branch) — so the two halves are
read from the same file, for the same enrolment id, and still disagree.
Measured with three arms over one keyfile, varying only the enrolment id:

| arm | outcome |
| --- | --- |
| injected RSA signer, the enrolment it belongs to | authenticates |
| injected RSA signer, the retrofitted enrolment | **at_chops refuses: an RSA-2048 key under the ML-DSA-65 routine** |
| no injected signer, the retrofitted enrolment | authenticates |

The third arm places the fault: the keyfile resolves this correctly on its own,
so it is the injection of another enrolment's signer that breaks it — not the
retrofit, and not the key material.

**Why authentication reported success.** at_auth authenticates on its own
connection, before the client is built. The verb runs over the client's rebuilt
connection, which authenticates lazily through the mismatched pair. So both runs
print "Connected" and only the second fails, **on every run** — the retrofit
deliberately leaves the keyfile's own `enrollmentId` at the capped legacy
enrolment, so it is due again at each start.

⛔ **The retention is CORRECT — do not "fix" it.**
[UC-G1.2](acceptance.md) specifies the legacy keypair staying in the flat fields
byte-identical and statusless, so the capped legacy enrolment keeps
authenticating until the atServer expires it.

**The fix**: `_initAtClient` resolves the signer beside the id and the
algorithm, from whichever source that flow trusts — the client on the
authentication path, the caller on the enrolment path, where the APKAM keypair
was minted moments ago and no keyfile holds it yet. `_atLookUp.atChops` stays
the caller's on both, deliberately: that field is what at_auth's
`EnrollmentApprover` reads for enrollment crypto, where what matters is the
encryption keypair and the APKAM symmetric key, and a retrofitted client's
AtChops carries no symmetric key.

**Proven at two layers.**
`packages/at_onboarding_cli/test/retrofitted_client_signs_with_its_own_key_test.dart`
drives `authenticate()` against a client already running as a retrofitted
enrolment and runs the installed authenticator, with two mutations red for
different reasons — restoring the caller's signer reddens on at_chops' refusal,
and "fixing" it by weakening the declaration to `rsa2048` instead reddens on the
algorithm assertion. And a third arm in
`tests/at_onboarding_cli_functional_tests/test/pq_native_enroll_test.dart` runs
the reported command, `at_activate list`, against a real atServer on a keyfile
a real retrofit has moved, with the keyfile read on both sides so that a green
from a run where no retrofit happened fails instead.

⛔ **The coverage gap that let it through was per-ROUTE, and closing it took
four new use cases.** The behaviour had been proven — for the *other* route.
`self_enrollment_retrofit_live_test.dart` has had a `selfRetrofit` client
running a verb, receiving over a monitor and signing envelopes on a scoped
enrolment since before this defect existed. So "is a retrofitted enrolment
proven to work?" answered yes, and the answer was true of `selfRetrofit` and
false of `AtClientImpl._settleEnrollmentIdentity` — the route `at_activate` and
every SDK consumer take.

[UC-B1.4](acceptance.md#84-uc-b14--a-retrofitted-scoped-enrollment-runs-an-authenticated-verb)
to
[UC-B1.7](acceptance.md#87-uc-b17--holds-the-parent-enrollments-grants-verbatim)
now state the property with the route named: a retrofitted scoped enrolment runs
an authenticated verb, reads and writes inside its namespace, is refused outside
it, and holds the parent's grants verbatim. The startup route is
`tests/at_functional_test/test/pq_retrofitted_scope_test.dart` — four arms, each
asserting the retrofit happened before asserting anything else, with two
mutations red: a `legacy` posture reddens every arm's precondition, and widening
the grant reddens exactly the two arms that measure the boundary.

⚠️ **Still open from the same audit**: B1.3 states that a restricted enrolment
receives only its authorised subset of `nskey` keys, and its citation
establishes three other things and not that one — recorded at the row. See the
B1 audit in
[detail — the citation audit](detail/acceptance.md#the-citation-audit--cluster-a-2026-08-26).

### 14.39 `PqPosture` and the rollout it drives

**Two things are owed here, and they sit in different priority bands.** The
rename, the three postures, the posture-only refusal flag, the sender-side
algorithm list, the CLI's `--posture`, the client-driven retrofit at start and
the `pqReady` default all shipped and are live-green; none of that is repeated
here.

**The key-exchange axis now reaches the CLI's enrolment**, landed 2026-08-26,
and it is recorded here because what it changed is a **default**, not because
anything is owed. `sendEnrollRequest` chooses between `AtEnrollmentRequest` and
`AtEnrollmentRequest.pq` from `preference.posture.keyExchangeMode`, and
`enroll` gained `--key-exchange legacy|pq` to override it. Guarded by
`packages/at_onboarding_cli/test/enroll_key_exchange_mode_test.dart` — 7 tests,
three mutations, one of which is the reason the file has a seventh.

⛔ **`PqPosture.pqReady.keyExchangeMode` is `pq` and pqReady is the SDK default,
so this moved what an `at_activate enroll` naming no `--posture` does.** A pq
request carries no RSA-wrapped key and relies on the approver sealing one to
the advertised key package; against an approver that predates conveyance the
enrolment is approved and then **cannot decrypt anything**, where before it
silently degraded to legacy. gkc ruled the trade on 2026-08-26: route it
faithfully, and add the escape hatch for the case the posture cannot see —
**which approver will pick the request up**. That is why `--key-exchange` is a
separate argument rather than another thing the posture implies, and why it
sits on `enroll` alone rather than on the shared parser.

⚠️ **The CLI is the FIRST production caller of `AtEnrollmentRequest.pq`.**
Before this, every `.pq(` in the workspace was a test. Nothing else in any
package's `lib/` routes the axis, and for at_client that is by design
(`pq_posture.dart`: *"at_client submits no app enrollment, so they take effect
when the app builds its `AtEnrollmentRequest` from the posture"*).

⚠️ **A mutation that should have failed came back green, and the seventh test
exists because of it.** Hardcoding `SigningAlgoType.rsa2048` into the
`enrollmentKeyPackageBuilder(...)` call left all six original cells passing:
`request.signingAlgo` is a *different field* from the one handed to the
builder, so asserting it says nothing about what the key package is signed
with. Running the builder against an ML-DSA APKAM keypair is the only way to
observe that algorithm, and the reddened failure now quotes
`RsaSigningAlgo.sign` parsing an ML-DSA private key — the mechanism itself.

⛔ **Two things that sound true and are NOT**, both measured:

1. *"Abstention falls out for free from `keyExchangeMode`."* No: a legacy-mode
   enrollment still registers a key package at runtime, because
   `conveyed_key_collection.dart` calls `register()` unconditionally at every
   client start. Measured — a legacy-mode cell enrolled without a key package
   and prepared one anyway.
2. *"The harness should derive the mode from `preference.posture`, as app
   authors are told to."* Tried and reverted: seven substrate tests went red,
   because a caller naming no posture used to get `legacy` silently. The
   functional harness now always builds pq, which is the opposite failure from
   the CLI's — the two real callers ignore the axis **in opposite directions**,
   and only the CLI half ships.

**(P3) Public-data signature verification — POST-D1, undesigned, and deliberately
NOT in the acceptance catalogue** (gkc, 2026-08-23): `dataSignature` appears 0
times in `acceptance.md`, so nothing asserts it. ⚠️ `pqActive` already
**signs** public data — `_signPublicData` in
`packages/at_client/lib/src/transformer/request_transformer/put_request_transformer.dart`
sets `metadata.dataSignature` — and **nothing anywhere verifies it**: not
at_client (no verifier symbol exists), and not the atServer, which only
stores, merges and forwards the field. So we knowingly emit a signature no one
checks, and this builds the first verifier rather than extending one. The
design: `pqActive` signs with the enrollment's data signing key in the `_apsk`
envelope form, and the verifier walks the signer's `_apsk` through the
approval chain to `pq_signing_root`
(`packages/at_client/lib/src/signing/apsk_composition.dart`). `pqReady`
changes nothing. Verification runs automatically on public reads, non-fatally,
with the outcome exposed to the caller; it needs the signer's `_apsk` cached
or every public read pays a remote lookup on another atSign. Both `_apsk`
forms are read, and the legacy form permanently, because every public record a
released at_client signed sits on a live atSign.

**[#2016](https://github.com/atsign-foundation/at_client_sdk/issues/2016)
(R-2) still reads as blocked.** Its title and body were rewritten for ruling
113, but the closing paragraph says *"State at 2026-08-18: not started, and
now blocked on 14.39. The default posture is `ReleasePosture.migration()`;
`ReleasePosture.postQuantum()` already exists"* — and `ReleasePosture` is gone
from the tree (`git grep -l ReleasePosture -- packages` hits at_client's
CHANGELOG only). Replace it: 14.39 shipped, so R-2 is unblocked; the default
is `PqPosture.legacy` (`at_client_preference.dart:138`) and the target
`PqPosture.pqActive` exists.

**`enrollmentlId` is misspelled in a PUBLISHED public API, not just in
at_lookup.** The field is declared at
`packages/at_commons/lib/src/verb/pkam_verb_builder.dart:5` and read at 11
sites — at_commons (`:29,:30` plus its tests), at_auth
(`at_authenticator.dart:118,189,257`), at_lookup (`at_lookup_impl.dart:700`)
and two functional tests. at_commons **5.16.0** is published, so the rename is
breaking and rides an at_commons major. Record the ruling either way; this has
been sitting as a passing note since 2026-08-19 with a location
(`at_lookup_impl.dart:563`) that has since moved.

⚠️ **Also owed, and nearly lost in the 2026-08-23 cut:** A rejected-design
record kept on purpose: the two objects that hold a stale `RemoteSecondary`
and so would break a live enrolment re-point, plus the reason rebuilding the
sync service is the wrong answer. The section states outright that it was
recorded because sequencing sidesteps the hazard rather than removing it —
i.e. it is being held for whoever builds the live re-point. It is in no commit
(the re-point was never built) and nowhere in decisions.md: ruling 113 records
only the monitor half of this audit.

⚠️ **Also owed, and nearly lost in the 2026-08-23 cut:** If the triage's three
promotes for 14.39 include the stream-audit result, it must NOT go to
decisions.md as a standing ruling: the audit is dated 2026-08-19 and the
at_lookup consolidation has since falsified it. Promoting it would ship a
false absence claim into the ledger, and a future live-re-point builder would
trust it and orphan subscribers.


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

**Carving a package PR from the spike.** One worktree per package, off
`origin/trunk`, so the PR carries that package alone. ⚠️ The branch name uses
HYPHENS where the package uses underscores (`at_lookup` →
`gkc-pq-d1-at-lookup`).

```bash
git worktree add /tmp/carve-<pkg> -b gkc-pq-d1-<pkg-hyphenated> origin/trunk
git -C /tmp/carve-<pkg> checkout gkc-pq-d1-spike -- packages/<pkg>
git -C /tmp/carve-<pkg> diff gkc-pq-d1-spike --stat -- packages/<pkg>   # the
gate
```

The diff is a **list to justify line by line**, not a failure: it was empty
for at_commons, at_chops and at_lookup and is deliberately non-empty for
at_auth. Every departure must be named, and carried back to the spike when
trunk merges in.

⚠️ **A MAJOR version is not package-only.** A pub workspace refuses to resolve
if any member's constraint excludes the new version, so every job dies at
`dart pub get` before a test runs and the failure looks nothing like a version
problem. Widen every member's constraint in the same commit: `git grep -n -P
'^\s+at_<pkg>:' -- '*pubspec.yaml'`.

Then analyze and test the package **and its consumers**, and raise with the
org template. **Ready** means that package's own work is done, its share of
14.11's bucket B included. Order, derived from the pubspecs — note `at_auth`
depends on `at_server_status`, which is easy to miss: at_commons → at_chops →
at_lookup → at_server_status → at_auth → at_client (stacked PRs) →
at_client_flutter → at_onboarding_cli. Live state is the release-train row in
[`## TODO`](#todo); the publish order is [detail — what still has to be published, in
order](detail/implementation-plan.md#what-still-has-to-be-published-in-order)
and is not restated here. The spike's test packs ride with at_client and need
a VE image that verifies ML-DSA PKAM — settled: CI runs
`atsigncompany/virtualenv:dev_env`, with `legacy_server_tests` left on
`vip-p3.15.0` as the control that proves the others moved.

⚠️ **at_auth's carve departs from the spike on purpose, and the departures owe
a trip back.** `origin/gkc-pq-d1-at-auth` differs from `gkc-pq-d1-spike` over
`packages/at_auth` in **10 files** as of 2026-08-23; only three were ever
written down (two dependency floors that were too low, a CHANGELOG sentence
justifying a breaking change by naming a consumer that does not do the thing
on trunk, and a test dartdoc citing a `docs/projects/` path). Re-derive the
real list and reconcile every line when #2179 merges: `git diff
gkc-pq-d1-spike origin/gkc-pq-d1-at-auth --stat -- packages/at_auth`.

⚠️ **Dispatch CI before carving.** Nothing fires on push on this branch — the
workflows are `workflow_dispatch` plus `push`/`pull_request` on `trunk` only —
so the newest run is only ever as new as the last manual dispatch. Dispatch
first, because CI's at_client job runs a **bare** `dart analyze` that reads
`benchmark/`, which the routine `dart analyze lib test` never opens; that hid
five errors for six days. The dispatch and comparison commands are on the **CI at
head** row in [`## TODO`](#todo).

Each carve merges to trunk on its own. ⛔ **The spike branch itself never
merges** — it is carved from, never landed.

Step 20's rotation arm is owed and is a **P1** row in [`## TODO`](#todo); do not
restate it here. ⚠️ 14.18's version of its blocker was stale — the
fleet-adoption wait is closed and the matrix now builds its own enrollments
through `enrolStage`, so "the matrix's demo atSigns hold no enrollment" is no
longer the reason it needs its own atSign.

Step 30's owed half is a **P1** row in [`## TODO`](#todo) and is detailed in
[14.11](#1411-deprecated_member_use-findings-across-the-workspace); do not
restate it here. (Its count is a moving figure: re-derive at_client's readers
with `git grep -n "atLookUp.enrollmentId" -- packages/at_client/lib`, which
gives **7** today against the "eight" this row recorded.)

⚠️ **Before cutting the step tables, repoint what cites them.** 44 links
resolve to `#1418-the-remaining-d1-initial-development-sequence`, nine of them
from `detail/decisions.md` into the *live* plan and citing step numbers (5,
16, 19, 20–22). A near-complete copy of 14.18 already sits at
`detail/implementation-plan.md:2737` — retarget those nine there. That copy is
itself **stale at Stage 6**: its step 32 still reads "Carve the spike into
stacked PRs", the shape superseded on 2026-08-20 by the per-package release
train. Fix it in the same edit or the cut leaves the only surviving copy
contradicting the live plan on the single most consequential row.

⚠️ **Also owed, and nearly lost in the 2026-08-23 cut:** A line naming four
work items as D1-parallel appears in the triage's owed list nowhere. It is
mostly superseded — B-3 and KF-1 have rows in `## PARKED`, step 29's
disposition rules IS-1 not-D1, and 14.29's TODO row rules S-3 not-D1 — but the
line is the only place in the live plan that asserts they are D1 work, and it
contradicts PARKED. It should be reconciled deliberately (deleted with the
contradiction noted), not dropped silently as part of a ~230-line archaeology
cut, because a silent drop leaves two documents that disagreed and no record
that anyone noticed.



### 14.19 Small items, raised 2026-08-12 and not yet acted on

⚠️ **The `14.19` open-item re-derivation command is wrong in all four of its
homes** — two in this file and two in `detail/implementation-plan.md`. ⚠️ This
named them by line number until the 2026-08-23 cut moved every one of them;
find them with `git grep -n 'grep -cE' -- docs/projects/pq` instead, which is
the shape they share. Each matches `^[0-9]+\.
\*\*`, which misses item 36 (its line opens `⛔ **`), so every one of them
returns **14** against an actual **15** — and the item they drop is the D1
gate. Replace with, and print the ids rather than only the count:

```bash
D=docs/projects/pq/detail/implementation-plan.md
awk '/^### 14.19 /,/^#### 14.19.1/' $D | grep -cP '^[0-9]+\. (?!~~)'   # open
-> 15
awk '/^### 14.19 /,/^#### 14.19.1/' $D | grep -cP '^[0-9]+\. '          #
total -> 36
awk '/^### 14.19 /,/^#### 14.19.1/' $D | grep -oP '^[0-9]+(?=\. (?!~~))' # ids
```

**Item 8 is ruled and closed (2026-08-23) but unstruck**, so it is still
counted as open by every re-derivation and the live plan still describes it as
the only item waiting on a ruling. Strike its heading in
`detail/implementation-plan.md` and drop that sentence here; the ruling itself
belongs in `decisions.md` (see the promoted claim).

The items are in
[`detail/implementation-plan.md`](detail/implementation-plan.md#1419-small-items-raised-2026-08-12-and-not-yet-acted-on).
✅ **Item 36 was a D1 gate and was closed on 2026-08-24** — the one known case of
the catalogue asserting clauses no live row proves. All three clauses are
live-proven in `key_package_amendment_live_test.dart` and pinned so the ledger
counts them, and two of the three corrected the catalogue's own wording. ⚠️ This
read "Item 36 IS a D1 gate" and pointed at a gate letter that no longer exists.
**Item 8 is now the only one here waiting on a ruling**, and it is a P2 row in
[`## TODO`](#todo).

⚠️ **Never read a count from this heading — re-derive it.** The number has had
six homes, two of them outside this repo, and has been stale in every one.
Command above.

Open at the last re-derivation: **2, 4, 8, 10, 11, 14, 20, 21, 26, 28, 29, 31,
34, 35, 36** (15 of 36). Of those, 20, 21 and 26 were examined and
deliberately left, so they are not work; 14 is not PQ; 35 lands in
`atGettingStarted`; 8 is ruled and awaiting only its strike. Item 10 is an
unexplained functional run with two disproven theories. **Item 11 — an APKAM
rotation that lands and is not persisted locks the enrollment out permanently
— is real owed work** and is the thing step 20's rotation arm waits on.



### 14.14 A client with no enrollment id is treated as fully privileged

⛔ **This section owes no work.** It is kept only for what the adversarial pass
below records; if that is empty, delete the section.



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

**14.11 Migrate the credential ladder off the deprecated `AtLookUp` members.**
**88** `deprecated_member_use` sites — `enrollmentId` **75**, `signingAlgoType`
**13**; **26 in `lib/`, 62 in tests**, across `at_client` (15 + 33),
`at_onboarding_cli` (8 + 19), `at_client_flutter` (0 + 10) and `at_auth`
(3 + 0) — move onto the `AtAuthenticator` seam. Measured with the analyzer at
`ef2c36187`, 2026-08-26.

⛔ **`at_client_flutter` is in scope and two earlier statements of this figure
left it out** — 10 sites in `keychain_io_impl_test.dart` (8),
`keychain_storage_test.dart` and `test/data/keychain_data.dart`. That is a whole
package missing from the stated scope, not a stale count. ⚠️ The figure has read
**71** (`enrollmentId` 59 / `signingAlgoType` 12, 24 lib + 47 test, three
packages) and then **85**; it moves with the tree, so re-derive rather than
quoting any of them.

**Use the ANALYZER, never a grep.** `enrollmentId` is a legitimate identifier in
hundreds of places; only the analyzer knows which uses are of the deprecated
member.

**Where the work concentrates**, which is what makes it a list rather than a
sweep: `at_onboarding_cli/lib/src/onboard/at_onboarding_service_impl.dart` holds
**all 8** of that package's library sites (verified 2026-08-26 — every one of
them is in that file);
`at_client/lib/src/client/remote_secondary.dart` holds 5 of at_client's 15; and
on the test side `at_client_flutter/test/keychain_io_impl_test.dart` (8) and
`at_client/test/signing_algo_threading_test.dart` (7) are the two largest.

**The replacement** is `authenticatorForChops()` (in
`packages/at_auth/lib/src/auth/at_authenticator.dart`, exported from
`at_auth`); the migration pattern is already in the tree at the
`authenticatorForChops(` call in
`packages/at_client/lib/src/client/remote_secondary.dart` and the one in
`packages/at_client/lib/src/service/notification_service_impl.dart`. It takes
`signingAlgo` and `hashingAlgo` as **required** arguments, so a migrated call
site cannot inherit an algorithm it did not choose.
Nothing else in the workspace's deprecation debt is D1 work: buckets A, C and
E get no `// ignore:` yet, and D waits for v5. Re-derive before starting
rather than quoting any figure — from each package directory run `dart analyze
lib test > /tmp/an.txt 2>&1` with nothing after it, then group with `grep
deprecated_member_use /tmp/an.txt | grep -oP "^\s*info - \S+ - '\K[^']+" |
sort | uniq -c | sort -rn`.

**Bucket D — the at_auth response family** (`atAuthKeys`, `AtAuthResponse`,
`AtOnboardingResponse`; 27 findings, 22 of them `atAuthKeys` in
at_onboarding_cli) is scheduled for **v5**. Not D1.

⚠️ **Also owed, and nearly lost in the 2026-08-23 cut:** Bucket E has no
disposition and the triage does not carry it. The ruling paragraph
dispositions A, B, C and D and is silent on E; the bucket table's own note for
E is "case by case", which is a decision still to be made about 8 findings.
The triage's owed list names bucket B and bucket D only, so cutting the bucket
table takes 8 undecided findings with it and nothing goes red.


### After D1

**After D1.** The release programme is **not** part of D1 initial development,
and it ends with **R-2**, the at_client 4.0.0 posture flip: the default
`PqPosture` becomes `pqActive` ([ruling
113](detail/decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18),
issue #2016). It is a pure default-flip carrying no code of its own —
`packages/at_client/lib/src/preference/at_client_preference.dart:138` still
reads `{this.posture = PqPosture.legacy, …}` — so **anything the posture needs
lands in D1 before it**.

**The ordered publish list lives in one place and is not restated here:**
[detail/implementation-plan.md — what still has to be published, in
order](detail/implementation-plan.md#what-still-has-to-be-published-in-order).
⚠️ **Re-derive it before acting — it was measured 2026-08-19 and every row has
moved.** It names at_auth `3.4.0` (in-tree **4.0.0-rc1**), at_client `3.14.1`
(in-tree **3.15.0-rc1**), at_chops 3.6.0 and at_commons 5.16.0 as unpublished
(both published 2026-08-21), and says at_lookup is "not on this list" while
in-tree it is **3.7.0-rc1** — as are at_server_status 1.1.2-rc1,
at_onboarding_cli 1.17.0-rc1 and at_client_flutter 1.1.5-rc1. Re-derive with
`git grep -n '^version' -- 'packages/*/pubspec.yaml'` against `curl -s
https://pub.dev/api/packages/<pkg> | python3 -c "import sys,json;print([v['version']
for v in json.load(sys.stdin)['versions']][-5:])"`. ⚠️ The versions LIST, not
`latest` — `latest` excludes prereleases, so every `-rc1` reads as unpublished.



### 14.42 Why enrollment setup takes four minutes


⛔ **Not a D1 gate (gkc, 2026-08-23), but owed to gkc personally** — he asked
for the cause on 2026-08-20, so this is not plan-generated hygiene and is not
to be quietly demoted.

`tests/at_end2end_test/test/enrollment_setup.dart` submits and approves one
enrollment for each of the four @ce2e atSigns. Measured 2026-08-20 in the
`end2end_test_14` job: **3:56** on one run and **4:59** on another. The budget
is now `@Timeout(Duration(minutes: 15))` (`enrollment_setup.dart:13`), which
stops the job failing and explains nothing.

⛔ **Do not spend a local loop on it, and do not re-derive the sync backlog.**
Both hypotheses are closed on measurement — see `decisions.md`.

**The first move is a CI round trip with instrumentation**, through
`.github/workflows/at_client_sdk.yaml`'s `end2end_test_14` job.

**Only one piece is missing locally, not two.**
`tests/at_end2end_test/config/config14.yaml` **is checked in** — it names
@ce2e1–4 against `root.atsign.wtf` — and CI does nothing more exotic than `mv
config/config14.yaml config/config.yaml`. What is missing is the
**`AT_CICD_CREDENTIALS`** repository secret, which CI writes over
`tests/at_end2end_test/lib/src/at_credentials.dart` (a 4-line stub in every
checkout) and from which every @ce2e keypair is built. Ask gkc for it, or
budget the CI round trip. ⚠️ Two traps if you try: `runLocal.sh` regenerates
`config/config.yaml` from `at_demo_data` (`runLocal.sh:28`) and would clobber
the config14 copy, so drive `dart test --concurrency=1
test/enrollment_setup.dart` directly; and `test_initializers.dart`'s
`_seedCredentialsForLocalRun` fills an empty credentials map from
`AtTestCredentials` (demo atSigns only), which covers no @ce2e atSign — so
with config14 in place and no secret you get a null check, not a silent demo
run.



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
| [14.14](#1414-a-client-with-no-enrollment-id-is-treated-as-fully-privileged) | A client with no enrollment id is fully privileged, and signs as `primary` | ✅ **CLOSED 2026-08-23 — both halves were already ruled, and nobody had closed the row.** Privilege: the resolver's own dartdoc says a client with no enrollment id authenticates with the atSign's own keys, *"which is full privilege by construction rather than by grant"*. Identity: [14.18](#1418-the-remaining-d1-initial-development-sequence) step 13 ruled that such a client publishes its `_apsk` under `primary` deliberately, as the only writer for an `_apsk` no `enroll:request` can carry. Kept so the question is not re-derived |
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
| R-2   | at_client 4.0.0 posture defaults                     | After D1. **The default `PqPosture` becomes `pqActive`** ([ruling 113](detail/decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18)) — one value, replacing the two coupled edits it used to be. Still a pure default-flip carrying no code of its own. Issue #2016.<br><br>⚠️ **R-2 is now a ONE-STAGE step, not two.** The shipped default moved `legacy` → **`pqReady`** on 2026-08-26, so R-2 is `pqReady` → `pqActive` — the two axes ruling 113 names as the only difference between them (the data signing key becomes ML-DSA, and post-quantum writes become the default). This row said "and now after 14.39" while 14.39's posture work was owed; it landed |
| D2-1  | Carve `at/pqmls` + D1-E shape fixes                  | D2, out of D1 |

---

## Re-deriving the state


Run these rather than trusting the table. Each answers one row.

**The clause burn-down first** — it is the measure of how close the acceptance
suite is to done, and it prints on every run of the suite:

```bash
cd packages/at_client && dart test test/acceptance --concurrency=1 \
  | grep BURN-DOWN
```

⛔ **The clause map behind the remaining-work tables was a one-off** and lives
in no file here. Do not try to re-derive the tables from it; re-derive the
*counts* with the command above and read the tables as the judgements they are.
Verify any row against its test before acting on it.

```bash
# the functional suite's convergence-race rate. It has been written five
# different ways from partial views; this is the only way to get it right.
for r in $(gh run list --branch gkc-pq-d1-spike --workflow at_client_sdk.yaml \
             --limit 20 --json databaseId --jq '.[].databaseId'); do
  gh run view "$r" --json jobs \
    --jq '.jobs[] | select(.name|startswith("functional_tests")) | [.name,.conclusion] | @tsv'
done | sort | uniq -c | sort -rn     # RUN IT. 2026-08-20: beta 3 fail/10, stable 1 fail/10

# 14.22: which of its rows have landed? The first landed when this file started
# composing apskAdvertisement; row 2 is unbuilt for as long as the prefix
# still names one algorithm.
git grep -n "keyIdPrefix =\|apskAdvertisement" -- packages/at_client/lib/src/crypto/nskey/

# 14.19: which items are still open? (~~struck~~ ones are done)
# ⚠️ Against detail/, NOT this file. The items moved there in the restructure
# and this copy was left pointing here, where it matches nothing: it printed
# ZERO and exited 1 while the answer was 17, so a reader working down this
# block concluded there was no open work. Fixed 2026-08-16.
awk '/^### 14.19 /,/^#### 14.19.1/' docs/projects/pq/detail/implementation-plan.md \
  | grep -cE "^[0-9]+\. \*\*"     # RUN IT. A number written here is a fifth home
awk '/^### 14.19 /,/^#### 14.19.1/' docs/projects/pq/detail/implementation-plan.md \
  | grep -cE "^[0-9]+\. ~~"       # likewise. NO NUMBER LIVES HERE: this comment
  #                                 itself said "an actual 9/16" while the answer
  #                                 was 10/16, so the warning about stale counts
  #                                 was the fifth home carrying a stale count.

# the stage-5 table, which owns steps 23-31
awk '/^\*\*Stage 5/,/^\*\*Stage 6/' docs/projects/pq/implementation-plan.md

# the citation audit's denominator. ⛔ `rm -f` FIRST — provenIn APPENDS, and a
# stale file reads as roughly twice the corpus (measured: 284 where the answer
# was 145, and the doubling looked like a real property of the suite).
cd packages/at_client && rm -f /tmp/cit.jsonl && \
  ACCEPTANCE_LEDGER=/tmp/cit.jsonl dart test test/acceptance --concurrency=1 >/dev/null
wc -l < /tmp/cit.jsonl            # RUN IT. A stamped figure here rots; 2026-08-26's 161 read as current until 2026-08-29, when it was 268
# the second derivation, which is what makes the first trustworthy: this sums
# to the same figure PLUS the 2 declarations in proven_elsewhere.dart.
git grep -c 'provenIn(' -- packages/at_client/test/acceptance | awk -F: '{s+=$2} END {print s}'

# acceptance: what is skipped, and on which blocker.
# Anchor on "}, skip:" — a bare "skip:" also matches catalogue_test.dart's and
# manifest.dart's prose ABOUT skips and reports 5 where the answer is 2.
grep -rn "}, skip:" packages/at_client/test/acceptance/*_test.dart
grep -n "blocked:\|owed:" packages/at_client/test/acceptance/blockers.dart

# ⛔ THERE IS NO COMMAND FOR "which atServer build is in at_virtual_env:local",
# and this block carried one that looked like there was. The
# `org.opencontainers.image.revision` label belongs to the PUBLISHED BASE image
# (atsigncompany/vebase) and describes the at_server revision that built THAT.
# The root/secondary binaries are compiled from whatever working tree ran the
# build, and nothing records which. Measured 2026-08-24: the label read
# `a0deee69` on an image whose binaries had been compiled minutes earlier from
# `af957440` — a different branch entirely. Reading the label to identify the
# code is wrong in a way that looks authoritative.
#
# The only sound answer is to build it yourself from a ref you name. at_server's
# own runner does the steps; the short form, from a detached worktree so a
# shared checkout is never mounted (the compile's in-container `dart pub get`
# rewrites its .dart_tool with /app paths):
#   git -C <at_server> worktree add --detach <dir> <ref>
#   docker run --rm -v "<dir>:/app" -w /app/packages/at_secondary_server \
# dart:3.11.2 sh -c 'dart pub get && dart compile exe bin/main.dart -o
# secondary'
#   ... same for at_root_server ... copy both into
#   tools/build_virtual_environment/ve/contents/atsign/{root,secondary}/ ...
# cd <dir>/tools/build_virtual_environment/ve && docker build -f ./Dockerfile
# -t <tag> .
# `shasum -a 256` the compiled `secondary` from each ref before believing two
# images differ.

# the external gates — the release train and step 20's rotation arm. The
# at_auth release is a pub.dev
# question; the atServer image gate is gkc's call and is NOT to be checked
# against atsigncompany/virtualenv:vip (ruled 2026-08-13).

# rails, all four packages. EACH FIGURE CARRIES THE COMMIT IT WAS MEASURED AT —
# a block with one date at the bottom invites reading every number as current,
# and three of these five were re-measured 15 commits after the other two.
# ⚠️ THREE live packs, not two. `find tests -name runLocal.sh` — the CLI one
# is the one that gets missed, and the block listed two until 2026-08-25, which
# is exactly how a full-rails run came back "all green" having skipped it.
#
# ⛔ PIN THE IMAGE ON EVERY LIVE RUN. All three default VIRTUALENV_IMAGE to
# `at_virtual_env:local`, and that tag is whatever tree last built it — on
# 2026-08-24 at_server's own runLocal.sh silently retagged it with an UNMERGED
# fix, so a bare run here tests a patched atServer and looks identical. Build
# from a named ref and say which (see the note above this block on why no image
# label can tell you). The figures below were taken against at_server
# `a37e3e3b` — which WAS trunk when they were measured, and which PREDATES the
# concurrent-relayed-lookup fix, merged to at_server trunk on 2026-08-25 as
# `8f4a985a`. So the three
# live packs below were last measured against an atServer that still answers
# concurrent cross-atSign lookups pairwise. Rebuild the image from a named ref
# before re-measuring, and record which ref.

cd packages/at_client         && dart analyze lib test                     # exit 0, 428 info
cd packages/at_client         && dart format . -o none --set-exit-if-changed  # exit 0 — a CI gate
cd packages/at_client         && dart test --concurrency=1                 # 1572
cd packages/at_client         && dart test test/acceptance --concurrency=1 # RUN IT
cd packages/at_auth           && dart analyze --fatal-warnings lib test    # exit 0, 158 info
cd packages/at_auth           && dart test --concurrency=1                 # 351
cd packages/at_lookup         && dart test --concurrency=1                 # 137
cd packages/at_commons        && dart test --concurrency=1                 # 518
cd packages/at_chops          && dart test --concurrency=1                 # 431
cd packages/at_onboarding_cli && dart test --concurrency=1                 # 56
cd packages/at_policy         && dart test --concurrency=1                 # 5 — AtRpc's only
                                                                          #     other consumer
cd packages/at_client_flutter && dart analyze lib test                     # exit 0, 72 info
cd packages/at_onboarding_cli && dart analyze lib test                     # exit 0, 216 info
cd tests/at_functional_test   && dart analyze test                         # exit 0, 246 info
cd tests/at_end2end_test      && dart analyze test                         # exit 0, 83 info
cd tests/at_onboarding_cli_functional_tests && dart analyze test           # exit 0, 15 info
# ✅ THE SIXTEEN ABOVE were all re-measured together on 2026-08-26 at
# `ef2c36187`. Four moved since the 2026-08-25 set and none is a regression:
# at_client 1559 → 1572, at_onboarding_cli 54 → 56, at_client analyze 422 → 428
# info, at_onboarding_cli analyze 207 → 216 info.
#
# ⛔ THE THREE LIVE PACKS BELOW WERE **NOT** RE-RUN AT `ef2c36187`. Each figure
# carries its own stamp for exactly this reason — a block with one date at the
# bottom promotes every number in it to head, and three of these were once
# re-measured 15 commits after the others.
VIRTUALENV_IMAGE=<a-ref-you-named> bash tests/at_functional_test/runLocal.sh              # 183 pass, 0 skipped — RE-RUN 2026-08-26 on at_virtual_env:g0fixed
# ⚠️ A SECOND instrument, and not a comparison with the line above: against an
# already-running at_virtual_env:local, `cd tests/at_functional_test && dart test
# test --concurrency=1` gave 189 pass, EXIT=0 on 2026-08-26. runLocal.sh recycles
# the container and this does not, so the two are different measurements of
# overlapping sets — do not read the difference as 6 tests appearing.
VIRTUALENV_IMAGE=<a-ref-you-named> bash tests/at_end2end_test/runLocal.sh                 # 63, EXIT=0 — RE-RUN 2026-08-26 on at_virtual_env:g0fixed
VIRTUALENV_IMAGE=<a-ref-you-named> bash tests/at_onboarding_cli_functional_tests/runLocal.sh  # 18, EXIT=0 — RE-RUN 2026-08-26 at the key-exchange fix
# ✅ The FUNCTIONAL pack was re-run on 2026-08-26 carrying the posture default
# flip and the key-exchange routing: 183 pass, 2 skipped, unchanged from the
# baseline.
# ⛔ THOSE TWO SKIPS ARE NOW GONE. `concurrent_relayed_lookup_test` and
# `pq_read_returns_another_record_test` reproduced the atServer's
# concurrent-relayed-lookup defect and were skipped because they are SUPPOSED
# to go red against an unfixed atServer. gkc deleted them on 2026-08-26: the
# atServer is fixed, so they reproduce nothing. Expect 0 skipped from here.
# ⚠️ What went with them is the fastest way to tell a FIXED atServer from an
# unfixed one — the relay probe answered that in seconds and nothing else in
# the tree does. If that question ever needs asking again, the harness and its
# measurements are in detail/implementation-plan.md under the discharged G0.
# ⚠️ The E2E COUNT MOVED: 63 tests, not the 54 this block recorded at
# `ecf1082de`. ✅ `bypasscache_test` was red 2 of 3 full-pack runs on 2026-08-26
# and is FIXED — the fault was its own push gate, not the product. Two wrong
# readings on the way there, both from too few observations: "it is the image"
# (one arm, varying two things), then "red 2 of 2, an ordering effect, not a
# flake" (called a kind on two observations, and the third run was green).
# ✅ The CLI pack WAS re-run on 2026-08-26, carrying the key-exchange routing,
# and is 18 EXIT=0. ⛔ It went 14/4 first: flipping the default to a posture
# whose key-exchange mode is `pq` broke four of its tests, and nothing in any
# unit suite could see it. Delete `*.enrollment.checkpoint` at that package's
# root before believing a red — `enroll()` RESUMES from one instead of sending
# a fresh request, so debris from a failed run makes the NEXT run fail at
# approve with "No pending enrollment requests found", which reads as a
# product defect. ⚠️ The block previously read "ALL SIXTEEN …
# at `bef991985`, against at_server `a37e3e3b`"; rows have been added since, so
# do not quote a count of rows either.
#
# ⚠️ THE FUNCTIONAL FIGURE ABOVE PREDATES THE FIX and is left as it was
# measured. This block has said, in turn, that the pack "failed once … that is
# 1 of 3", and then that "the rate is now 3 of 5 … the cause is DIAGNOSED
# rather than ruled out: the receiving client parks the notification for an
# nskey private that is conveyed to a sibling enrollment of the same atSign and
# never to the one that asked". The last clause was wrong about the mechanism —
# addressing was never the problem — and the defect is now FIXED: see the
# "late-arriving nskey private" row. Post-fix the pack is 0 red of 5 on the
# same image, all runs
# 308-312s. Re-run rather than quoting either number.
#
# The analyze counts are tallied by severity (`grep " - " | awk '{print $1}' |
# sort | uniq -c`) and are all `info`; the exit code is the verdict, never the
# count.
# ⚠️ Run the FUNCTIONAL pack twice before believing a red. The one recorded
# intermittent, self_enrollment_retrofit_live_test.dart, was DIAGNOSED AND FIXED
# on 2026-08-25 (14.34) — so a red there is now new information rather than a
# known rate. A single red is still a rate observation, not a regression.
# (2026-08-20 at 327cf4fa2 a first run was 173/174, the failure being 14.34.)
# ⚠️ The e2e default EXCLUDES the `legacy-server` arm (`-x legacy-server`, see
# that runner's own header), and that arm needs the PINNED PRE-PQ image or it
# stops testing the thing it exists for — the same image CI uses for it:
#   VIRTUALENV_IMAGE=atsigncompany/virtualenv:vip-p3.15.0 \
#     bash tests/at_end2end_test/runLocal.sh 26000 test/pq -t legacy-server
# ⚠️ There are no deliberate skips in this pack any more — the two
# reproduction harnesses were deleted on 2026-08-26 when the atServer fix
# landed. A skip appearing here again is new information.
# (The two reproduction harnesses that used to be skipped here were deleted on
# 2026-08-26 once the atServer fix landed; see the note above.)
# ⚠️ Figures move for reasons worth knowing rather than growth: functional
# 169 → 174 (the matrix's cells, once its driver stopped asking the arms for
# stage names that no longer exist) → 183 (the acceptance arms and the two
# relayed-lookup harnesses), and both packs were RED at `c9de7d997` while
# every unit suite was
# green — analyze cannot see a string argument, so nothing caught it until the
# pack ran.
# Every figure in this project has been wrong at least once by being carried
# forward — the COMMAND is the value here, not the number beside it.
```


### After D1 — re-deriving the release programme

The release programme is **not** part of D1 initial development, and it ends
with **R-2**, the 4.0.0 posture flip: the default `PqPosture` becomes
`pqActive` ([ruling 113](detail/decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18)).
Still a pure default-flip carrying no code of its own, so anything the posture
needs lands in D1 before it.

**The ordered publish list lives in one place:**
[detail/implementation-plan.md — what still has to be published, in order](detail/implementation-plan.md#what-still-has-to-be-published-in-order).
It is not restated here. This block used to carry its own copy, as did
[#1889](https://github.com/atsign-foundation/at_client_sdk/issues/1889), and
all three drifted: two of them were still naming an at_commons slot 3 releases
behind.

✅ **The first rung is settled: at_chops publishes as 3.6.0, a minor**
([decisions 109](detail/decisions.md#109-at_chops-360-stays-a-minor-no-major-bump-for-this-release-2026-08-18),
gkc 2026-08-18). This reverses the in-principle position of 2026-08-13, and the
4.0.0 bump built and reverted that day is not to be re-attempted. 3.6.0 does
carry two source-breaking changes, and the judgement is that no consumer exists
for either to break: trunk's at_client compiles and tests green against this
branch's at_chops, and every `AtKemAlgorithm` implementer sits inside at_chops.
So the 6 workspace constraints do **not** have to widen together, and at_lookup
does **not** need 3.6.2 opened.
