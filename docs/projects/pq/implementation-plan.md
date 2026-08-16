# implementation-plan.md — TODO / PARKED / DONE

Three sections, one per state. **TODO carries full detail**, because it is what
the next session works from. **PARKED and DONE are one row each**, with the
detail in [`detail/implementation-plan.md`](detail/implementation-plan.md).

**Item ids are permanent.** `14.13` and `14.19 item 11` are cited from
production dartdoc and from `blockers.dart`, so an item keeps its id when it
moves between these three sections. Nothing here is ever renumbered.

**To add an item:** put it in TODO with its detail. When it lands, replace it
with a DONE row and move the detail to the detail file. When it is set aside,
give it a PARKED row whose reason is enough to stop someone building it — that
is the row's whole job.

This file has a **line ceiling**, enforced by
`packages/at_client/test/acceptance/docs_structure_test.dart`. Breaching it
means something finished and has not been demoted yet, so the fix is to move a
DONE item's detail out — not to raise the ceiling reflexively.

⚠️ **Re-derive before acting on any row below.** Every "current state" table in
this project has been wrong at least once by being carried forward; the
commands that re-derive these are in
[Re-deriving the state](#re-deriving-the-state) at the end.

**D1 initial development ends at step 34** — the spike carved into stacked PRs
and merged. Publishing and R-2 follow it and are not D1.

---

## TODO

| Item                            | What is owed                                                        | Blocked on                                                                       |
|---------------------------------|---------------------------------------------------------------------|----------------------------------------------------------------------------------|
| [14.24](#1424-the-nskey-mint-elects-a-winner--decisions-105) | The nskey mint elects a winner — **all seven rows built** on unit rails; the live-atServer proof is owed | Nothing. Development and testing run against `at_virtual_env:local`, which carries the fix (gkc, 2026-08-16). What still waits on at_server [PR #2751](https://github.com/atsign-foundation/at_server/pull/2751) is **release**: ttl-only release is correct only against an atServer running it |
| [14.18](#1418-the-remaining-d1-initial-development-sequence) | Steps 32–34: carve into stacked PRs, merge to trunk | The published atServer image verifying ML-DSA PKAM. Touches step 32 only |
| [14.18](#1418-the-remaining-d1-initial-development-sequence) | Step 20's rotation arm — enrollment then an `enroll:update` APKAM rotation mid-run | An at_auth release carrying the tolerant reader, then the staged status value. Needs its own CRAM atSign |
| [14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) | 17 open small items — the items are in `detail/`, none of them blocking | Item 8 is the only one waiting on a ruling. Items 20–22 are examined-and-left, not work. Item 18 closed 2026-08-16 by ceasing to exist |
| [14.17](#1417-signature-agility--what-is-built-and-what-is-owed) | Signature agility — the owed half | — |
| [14.16](#1416-four-residuals-the-issue-tree-audit-surfaced-2026-08-09) | Four audit residuals | — |
| [14.15](#1415-pre-pr-rails-checklist) | Pre-PR rails checklist | — |
| [14.14](#1414-a-client-with-no-enrollment-id-is-treated-as-fully-privileged) | A client with no enrollment id is treated as fully privileged | Wants a ruling on whether an owner-keys client belongs in the enrollment trust model |
| [14.12](#1412-a-mintlegacymaterialfalse-atsign-cannot-write-a-public-record) | A `mintLegacyMaterial:false` atSign cannot write a public record | Gates the stop-release |
| [14.11](#1411-deprecated_member_use-findings-across-the-workspace) | `deprecated_member_use` across the workspace | A call-site migration, not a lint sweep |
| [14.7](#147-noports-carries-its-own-copy-of-the-envelope-shape) | NoPorts carries its own copy of the envelope shape | Separately owned — named here, not fixed here |
| [14.25](#1425-three-projects-state-partial-completion-and-six-state-none) | Reconcile nine project entries whose stated status and the burn-down disagree | — |
| [14.26](#1426-a-comment-in-at_server-is-now-false) | A comment in at_server says a branch never runs; the PR #2751 fix makes it run | **Lands in at_server**, not here. Rides PR #2751 while it is still open |

### 14.26 A comment in at_server is now false

⚠️ **This lands in at_server, not in this repo.** It is recorded here because
this is the list the work is driven from, and a correction owed in a sibling
repo dies if it is only written in the ruling that found it.

`packages/at_persistence_secondary_server/lib/src/spec/keystore/at_metadata_builder.dart:46`
carries, above the immutable-stickiness branch:

> *"Note: this condition never occurs right now but we will leave it here for
> safety's sake"*

It never occurred **because the update handler refused every such update**. The
fix on [at_server PR #2751](https://github.com/atsign-foundation/at_server/pull/2751)
makes an update delete an expired record and proceed, so the branch is now
reachable and the comment is false — see
[decisions 104.10](detail/decisions.md#10410-fixed-in-at_server-the-same-day-and-re-measured-on-the-wire).

Cheapest while the PR is still open: it rides that branch. Re-derive rather
than trusting this row — the comment may already be gone:

```bash
git -C ~/dev/atsign/repos/at_server grep -n "never occurs right now"
gh pr view 2751 --repo atsign-foundation/at_server --json state,mergedAt
```

### 14.25 Three projects state partial completion, and six state none

Raised 2026-08-16 by the restructure that produced this file, and **not yet
investigated** — this row records a discrepancy, not a diagnosis.

**Three project entries state that they are incomplete**, and none of them
appears in the D1 burn-down this section replaces:

- **S-3** — `PARTLY LANDED 2026-08-08`
- **SS-1c** — `PARSER + VERIFY LANDED on gkc-pq-d1-spike; live drive still owed`
- **SS-4** — `ABOUT HALF LANDED on gkc-pq-d1-spike`

**Six state no status at all** — P-3, SS-2, B-1, RF-1, RF-SRV, RF-2c. They sit
under DONE below because the burn-down does not list them as owed, which is an
inference from an absence rather than an observation of the tree.

So either the burn-down under-counted what D1 owes, or those residuals were
absorbed by later work and the headings are stale. Both are plausible and
neither has been checked. Read each entry in
[`detail/implementation-plan.md`](detail/implementation-plan.md) against the
tree, then either add a TODO row or correct the record. Do not assume the
burn-down was right because it is newer: it was maintained by hand, and this
project has been bitten by exactly that before.

### 14.24 The nskey mint elects a winner — decisions 105

⚠️ **THIS is the model being built.**
[14.23](detail/implementation-plan.md#1423-the-nskey-mint-stops-needing-a-winner--decisions-104) is HELD.
[decisions 105](detail/decisions.md#105-the-nskey-mint-elects-a-winner-and-an-atserver-defect-blocks-the-clean-shape-2026-08-16)
rules the design; this is the order. One nskey record, and a lock used as an
**election token with a cooldown** rather than a mutex.

**The requirement, which had never been written down:** *if enrollments A, B
and C all decide they need to mint, only one of them eventually does.* Every
earlier argument about the lock was about mechanisms with no agreed property to
hold them to, which is why "is 14.19 item 18 worth fixing" stayed unanswerable
for two sessions.

**All seven rows are built.** What is owed is the live-atServer proof: the
unit rails pin the behaviour against mocks, and nothing has yet run the
three-enrollment race against a real atServer.

**Rows 3 and 5 depend on an at_server change that is OPEN, NOT MERGED:
[at_server PR #2751](https://github.com/atsign-foundation/at_server/pull/2751)**,
branch `gkc-expired-immutable-blocks-create`. **gkc owns that PR.** That is a
**release** gate, not a development one — gkc ruled 2026-08-16 that the work
runs against the locally built `at_virtual_env:local`, which carries the fix.

⚠️ **Cite the PR, not a SHA.** This block named `b5654bfd`; gkc rewrote the
commits before pushing, so that SHA no longer exists anywhere. The branch now
carries the fix plus an at_secondary_server version bump. Re-derive rather than
trust this line:

```
gh pr view 2751 --repo atsign-foundation/at_server --json state,mergedAt
git -C ~/dev/atsign/repos/at_server log --oneline origin/trunk..origin/gkc-expired-immutable-blocks-create
```

⚠️ **A merge is not enough for rows 3 and 5** — they need an atServer that
*runs* the fix. The local `at_virtual_env:local` has been rebuilt and does; any
other deployment needs its own rebuild, and a client relying on ttl-only
release is incorrect against an atServer without it.

| # | What | The differential |
|---|---|---|
| 1 | ~~A **remote-only** read of the published advertisement for the mint path. ⚠️ **NOT by changing `currentPublic`** — that is also the sender path, reached from `CkManager.ensureCurrent` on *every* put, so making it remote puts a round trip on the write path and breaks offline writes. A separate read, always remote, skipping both caches — the shape `PqSigningRoot.publishedRoots` already has | a sibling enrollment publishes; this client's pre-check sees it without waiting for sync. ⚠️ **Scope: `published_nskey_key_ring.dart:450` is the read to change, but it is NOT the only optionless read in the subsystem** — `ck_manager.dart:248` and `symmetric_aes_gcm_provider.dart:250` are optionless too. Those two are **content-key conveyance** reads rather than advertisement reads and are plausibly correct as local-first, so they are out of scope *by argument, not by absence*. Re-derive before believing either way: `git grep -n -A3 "atClient\.get(" -- packages/at_client/lib/src/crypto/nskey/`~~ ✅ **BUILT.** `PublishedNskeyKeyRing.publishedAdvertisement` is the new read; `currentPublic` is untouched. Three mint-path call sites use it — `mintAndPublish`'s post-loss read, `rotate`'s precondition, and `NskeySeeding.seed`'s pre-check |
| 2 | ~~The **winner's re-check under the lock**, which the nskey path has never had. `_mintUnderLock` (root) re-reads; `_mint` (nskey) does not~~ ✅ **BUILT** as `_mintUnlessPublished`, which wraps `_mint` on the `mintAndPublish` path only — `rotate` still runs `_mint` directly, because a rotation that adopted what it found would have rotated nothing while reporting success | a winner that published between the pre-check and this client taking the lock is adopted, not overwritten |
| 3 | ~~`withLock` **stops releasing** — the ttl is the release~~ ✅ **BUILT.** `MintLock._release` is deleted, and `withLock` now **refuses a lock key with no ttl** — with nothing deleting the record, a missing ttl means it is never released at all rather than released late | a holder that finishes does not free the lock; a second enrollment is refused until the ttl elapses. This is what made [14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) item 18 disappear rather than be fixed |
| 4 | ~~The **loser**: re-read once, adopt a published generation, otherwise **fail** with a reason~~ ✅ **BUILT.** Both arms now have a test; the `StateError` says why the loser must not mint and that the retry is the next client start | lock held + a generation published → adopts. Lock held + nothing published → fails naming the contention, and a waiting `put` fails loudly rather than hanging on another device's crash |
| 5 | ~~The **lease self-abort**~~ ✅ **BUILT** as `MintLease`, which `withLock` hands to the mint. ⚠️ Its deadline is stamped **before** the take goes out, never after: the atServer starts the ttl at or after the send, so stamping from the reply would have the client believe it still held a lock the atServer had released. Checked immediately before each publish, so a keygen or a suspend cannot happen after the check | a mint that overruns the ttl publishes nothing. Without it the requirement fails with everything else correct, because the bounded window bounds when the three *attempt*, not how long the winner *takes* |
| 6 | ~~The "crash backstop" claim is **false as written**~~ ✅ **BUILT** — both sites in `nskey_records.dart` now say the ttl is what releases the lock, and `mintLockTtl` says it is also the winner's own budget | none — a doc correction |
| 7 | ~~Docs and acceptance sweep~~ ✅ **BUILT.** `acceptance.md` steps A3.2 and B6 said the holder "releases"; `design.md` §1.3 and the B5b sequence said the same. All now say the ttl releases it, and §1.3 states the winner's re-read | `catalogue_test.dart` and `docs_structure_test.dart` staying green is the check |

**Two things found while checking the protocol against the tree, which the rows
above assume.**

- **Exactly two production callers mint**: `nskey_seeding.dart:100`
  (`mintAndPublish`) and `nskey_rotation.dart:152` (`rotate`). Re-derive:
  `git grep -n "mintAndPublish\|\.rotate(" -- packages/at_client/lib packages/at_onboarding_cli/lib`
- ~~**`rotate`'s precondition read is asked twice.**
  `NskeyRotation.rotateNamespaceKey:145` calls `ring.currentPublic` to refuse a
  cold-start rotation, and `ring.rotate:320` calls it again. Both are
  local-first, so row 1 has to reach both — and they are the same question
  asked twice, which is worth collapsing rather than converting twice.~~
  ✅ **COLLAPSED** into `ring.rotate`, which now returns
  `({rotated, superseded})` so its caller names what it superseded from the read
  already made. The cold-start refusal and its message live in one place.
- **A third advertisement read is still local-first, and is out of scope by
  argument.** `NskeySeeding.requestMissingPrivates` (`nskey_seeding.dart:186`)
  reads `currentPublic` to decide which generation's private to ask for. It is
  the *pull* path, not the mint path, so nothing it does can overwrite a key —
  but a stale read there asks for a superseded generation, and the heal then
  waits for the next start. Worth deciding on rather than leaving undecided.

---


### 14.18 The remaining D1 initial-development sequence

Ruled 2026-08-11 by a walk through every open item
([`decisions.md` 93](detail/decisions.md#93-the-d1-remaining-work-sequence-and-the-rollout-axis-becomes-real-2026-08-11)).
This is the **order**, not the inventory — each row points at the entry that
holds the detail. **D1 initial development ends at step 34**, when the stacked
PRs are merged; publishing and R-2 follow it.

**Stage 0 — scaffolding.**

| # | Work | Where | State |
|---|------|-------|-------|
| 1 | Drop at_server's `at_commons` override; delete the `at_commons-apsk-1` tag | at_server | **DONE 2026-08-11.** Override gone from both files, `pubspec.lock` resolves hosted 5.14.0, tag deleted local+origin. **[at_server#2744](https://github.com/atsign-foundation/at_server/pull/2744) is MERGED** — corrected 2026-08-13; this row and step 2a both said "open" for a week while `5bc3618a` had become an ancestor of at_server's `origin/trunk`, and the tags `c3.16.0` and `c3.16.1` both contain it. ⚠️ **at_server's 210/210 is still stale** and must be re-earned. `origin/trunk` was `c16f32b0` when this row was written on 2026-08-13 and is `fdb78568` as of 2026-08-14 — re-derive it with `git -C ~/dev/atsign/repos/at_server log --oneline -1 origin/trunk` rather than citing either, since this row records a moving value and nothing here goes red when it moves |
| 2 | Run at_client_sdk's functional pack for the two never-run keyId-shape files | at_client_sdk | **DONE 2026-08-12.** Both pass: `pq_native_onboard_live_test.dart` (UC-A1.1) in the functional pack, and `pq_native_onboard_test.dart` in at_onboarding_cli's pack, both against `at_virtual_env:local`. The run also surfaced the `_apsk` seam break below — 16 of 19 failures, one cause |
| 2a | **The `_apsk` composer moves client-side** — at_server#2744 merged, so the atServer publishes only what a request sends and composes nothing. The client sent nothing, so no `_apsk` existed at approval and every advertised key package was rejected. `EnrollVerbBuilder`/`EnrollParams` gain `apsk` (the array) and `apskLegacy` (the bare RSA string); at_auth composes one or the other at all three submit sites; `parseApskValue` reads the array; the never-published tagged form is deleted | at_client_sdk | **BOTH HALVES DONE.** Client half 2026-08-12, functional pack 127/19 → 143/3. **The atServer half is MERGED too** — corrected 2026-08-13, having been listed as owed after it landed: at_server `6a86fbcc` "feat(at_secondary_server): honour apskLegacy, and bound the whole record" went in via [at_server#2746](https://github.com/atsign-foundation/at_server/pull/2746) (merge `b4ea7cf2`), is an ancestor of `origin/trunk`, and `at_secondary_server` is 3.16.1. ⚠️ **Do not rebuild it.** ✅ **The exercise this row still owed is discharged as of 2026-08-14**, on both arms and against the local image that carries the server code: the **request** arm by rollout-1 enrollments in the matrix, where UC-G1.14 has a released at_client 3.14.0 reader fetch that record and parse it with `RSAPublicKey.fromString` — which succeeds only on the bare form — and the **`enroll:update`** arm by B4's `apsk_server_side_test.dart` row "a healed enrollment advertises its signing key in the bare form", which is the only thing that has ever driven `apskLegacy` on an update — it had been sent solely on the enrolment request. That row is proven discriminating: with the client-side fix reverted it is the only failure of 164 |

**Stage 1 — one envelope shape, one key vocabulary, then the `_apsk` reader
half. Nothing blocks it; start here.** Steps 3–5 are ordered so each shrinks
the next: deleting v1 removes wrapper branches the vocabulary would otherwise
have to carry, and the vocabulary is where `status` is defined before step 5
builds on it.

| # | Work | Detail |
|---|------|--------|
| 3 | **DONE 2026-08-12 — one envelope shape, RFC 7515 general serialization**, `{payload, signatures:[{protected, signature}]}` with `{alg, kid, v}` in each `protected`. Deleted `signedEnvelopeVersion`, `jwsEnvelopeVersion`'s flattened form, `envelopeVersionOf`'s dispatch, the `wrapperFields` ternary in `ApkamSignedAdvertisedKeys.verify`, and `envelopeVersion` as a `ReleasePosture` axis. Also took `hashingAlgo` off `signEnvelope` — `alg` names the hash, so nothing unsigned selects a routine — and retired UC-C1.3, the rollout's envelope axis, which had nothing left to drive. The `.mjs` adjudicator moved `flattenedVerify` → `generalVerify`; vectors regenerated at `test/vectors/jws_envelope.json`. **Found en route:** `publishPendingLink`'s already-published check compared a top-level `['signature']` the envelope does not have, so `null == null` matched every time and a different link conveyed later was silently never published | [`decisions.md` 95](detail/decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12) ruling 1, **superseding [91](detail/decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11) ruling 12**'s bespoke container |
| 4 | **DONE 2026-08-13 — ruling 2 landed, so all of step 4 is complete and step 6 is unblocked.** Ruling 2 in three commits: `6462ae786` (the advertisement becomes `{v, createdAt, keys:[{use, alg, pub, kid}], suites}` with one `toPayload`/`fromPayload` codec replacing a map literal in `_mint` and a hand parser in `verify` 250 lines apart), `d28ef48a9` (a key that is not its algorithm's length is refused — a kid is the digest of whatever bytes are carried, so it matched a forged key as readily as a real one), `69449603e` (the reader skips entries it has no KEM for and picks the strongest it can use, which has to ship before any writer emits a second key). **Three things the ruling got wrong**, all corrected in `decisions.md` 94: `_apsk` entries never carried `status`; `status` and `KeyEntryStatus` are deferred **entirely to step 5** so no dead field ships (gkc, 2026-08-13); and at_auth cannot reach `PackageKey` because at_client depends on at_auth, so one vocabulary means one **wire spelling** across two Dart types. `createdAt` was added for symmetry with `KeyPackage`; `v` stays 1. Rails: at_client 1188/1188, functional 146/146. One key-entry vocabulary across all three advertising records — `{use, alg, pub, kid, status?}` inside `{v, keys:[…], suites}`. **Landed 2026-08-12:** ruling 3 (one kid function, at_auth's `publicKeyKid`, over the key's raw BYTES — `apskKid` hashed the base64 text and `nskeyKidOf` the material, and every kpid changes value); ruling 4 (`v`, `alg`, `suites` required, both `legacy*Suites` deleted); ruling 5 (one `SecretSharingAlgos.bestSuiteBetween`); **ruling 6** — `pq_envelope.dart`'s `pqSealToBase64`/`pqOpenFromBase64`, both taking `info` and `version` as **required** arguments and constructing neither, so there is nothing inside the shared code for the two substrates to converge onto. at_chops' `pqSeal`/`pqOpen` now require `info` too, which makes a shared binding a **compile error** rather than a convention — it was reachable before, because `info` was optional and `info ?? Uint8List(0)` made omission and empty the same binding. **Found en route:** the pairwise substrate had NO test that could fail on a converged binding — dropping the label from all three pairwise/enrollment call sites left the suite green at 1180/1180 — so the production-fed differential in `pairwise_secret_sharing_test.dart` was built first and proven by that same symmetric mutation, which now turns exactly one test red. **Still owed: ruling 2** — the nskey advertisement gains a `keys` list and adopts the shared spelling | [`decisions.md` 94](detail/decisions.md#94-three-records-advertise-keys-and-only-one-of-them-speaks-the-vocabulary-2026-08-11) — ⚠️ **before step 6**, or that parser becomes the third hand-rolled codec for one shape |
| 5 | **DONE 2026-08-13 — the `retired` key path, in three commits.** `6a5eac838`: `PackageKey` gains `status`, a `KeyEntryStatus` of `active` or `retired`, and `bestKeyFor` on both a key package and an nskey advertisement passes a retired key over, so `kpid` is the *active* enc key's kid. Emitted only when retired — absent already reads as active — and an unrecognised value reads as retired, the one reading that cannot make a build use a key its owner withdrew. `f956b2146`: `PersistedApkamKeys` becomes `{encKeys: [PersistedEncKey]}` and `KeyPackageRegistration` expands, advertises and answers for every held key, with `encKeyFor(kid)` replacing `encSecretKey` and `heldKpids` listing every address. `f6fc3796e`: the sweep, the wake-up subscription and the sync listener cover every held address (`EnvelopeAddressing.regexForAny`/`sweepRegexForAny`), and `_consume` opens with the key the envelope names. **Three things ruling 9 got wrong or omitted**, all recorded in `decisions.md` 95: the sweep filter is a **fifth** consequence and the one that makes the other four reachable; the keyfile already records the status (`AtKeysMaterial.KeyPartStatus`, `AtKeys.retireKey`, and an `AtKeysAssurance` rule enforcing one active `publicEncapsulation` per enrollment and algorithm), so deriving it from `createdAt` was wrong; and `dead` material is not adopted at all. Rails: at_client 1210/1210, functional 146/146. **Nothing rotates yet** — the writer is step 16. ⚠️ app-facing: `PersistedApkamKeys` is what apps build in `loadApkamKeys`/`saveApkamKeys` | [`decisions.md` 95](detail/decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12) rulings 6–9 — without the plural holding the field is decorative. The **name collision** was settled 2026-08-12 (gkc) and landed as ruled: the per-entry wire value is a Dart `KeyEntryStatus`, and `KeyPackageStatus` — the reader's verdict on a whole package (`present`/`absent`/`rejected`/`unsupported`) — keeps its name. Nothing renamed |
| 6 | **DONE — mostly with step 2a, completed 2026-08-13.** `parseApskValue` reads the array **and** the released bare string, refuses a structured value advertising nothing it understands rather than guessing, and skips entries whose `use` or `alg` it does not know; `apsk_formats_test.dart` covers all of that plus "the array form is unmistakable to a bare-RSA consumer". Finished on 2026-08-13 by giving `ApskSigningKey` a `status` and having `apskSigningKeys` read it — **keeping** a retired entry, because this list is what verifies stored envelopes and a retired key is precisely what signed the older ones. `KeyEntryStatus` moved from at_client to **at_auth** in the same change so all three advertising records name one type, narrowing [94](detail/decisions.md#94-three-records-advertise-keys-and-only-one-of-them-speaks-the-vocabulary-2026-08-11)'s "one vocabulary cannot mean one Dart type" — that was true of a type living in at_client, and at_auth is the lower package. **Found by the re-verify:** `design.md` 9.3's JSON example omitted `kid`, which the reader requires, so the document the design showed is one every reader treats as empty and then refuses; corrected, and pinned. `advertised.first` and the singular `ParsedApsk` are steps 7–9's business, not a gap here | [`design.md` 9.3](design.md#9-subsystem-g--signature-agility-the-authsigning-key-split) |
| 7 | **DONE 2026-08-13.** `SigningAlgoType.strongestFirst` + `strongestOf` in at_chops — purely additive (two statics on the existing enum; no member added, moved or renamed, so it does not touch the unresolved 3.6.0-versus-major question). Deliberately **not** declaration order: members are declared in the order they were added and reordering them is a wire change, so preference is a second statement. `mldsa65` first, categorically — the only member Shor does not break — then RSA-4096, `ed25519`, `ecc_secp256r1`, RSA-2048 by classical security level. Total on purpose: a partial order leaves the choice undefined for exactly the pair nobody thought about. **The tripwire is completeness, not just the literals**: a new `SigningAlgoType` left out of the order turns `test/signing_strength_test.dart` red, which is what stops it becoming silently unrankable. Wired straight into `parseApskValue`, which took `advertised.first` — the order entries arrive in is the *signer's* choice, so an enrollment advertising ML-DSA-65 beside RSA-2048 was verified against whichever it listed first | [14.17](#1417-signature-agility--what-is-built-and-what-is-owed) |
| 8 | **DONE 2026-08-13.** `requireAlg` is gone rather than rewritten: the algorithm is now *resolved* — from what the envelope's `signatures` and the signer's `_apsk` have in common, taking the strongest by `SigningAlgoType.strongestFirst` — and then its key is fetched, where before one advertised key was taken and the envelope was required to match it. Its refusal survives in a different form: no algorithm in common is refused naming both lists. `ParsedApsk` went plural (`keys`, `keyFor(algo)`; `signingAlgo`/`publicKey` survive as strongest-of getters), and the bare RSA form parses to a one-entry list so both published forms are one shape to the caller. The two JOSE `alg` switches — one on the sign side, one on the verify side — became one `_joseAlgFor`, since two would be two chances to disagree | ⚠️ an inversion, not an addition |
| 9 | **DONE 2026-08-13, with step 8** — the two do not separate: resolving the strongest shared algorithm *is* walking the entries. `verifyEnvelope` selects its entry by algorithm rather than taking `signatures.first`, verifies only that one, and refuses on failure with no fallback. **Found en route and fixed:** `signerEnrollmentId` reads `signatures.first.kid` while the verified entry is now chosen by algorithm, so the two could be different entries — append a signature under a stronger algorithm carrying another kid and a caller acts on a signer whose signature was never checked. `SignedEnvelope.fromJson` now refuses an envelope whose entries name more than one signer, which is a structural claim about this shape rather than a verify-time check. UC-G1.7 is covered for the first time, four rows | [`design.md` 9.4](design.md#9-subsystem-g--signature-agility-the-authsigning-key-split) |

**A reader understanding no entry refuses outright** — no downgrade, no fallback
to a derivable legacy key ([`decisions.md` 93](detail/decisions.md#93-the-d1-remaining-work-sequence-and-the-rollout-axis-becomes-real-2026-08-11) ruling 2).

**Stage 2 — the unblocker. The writer half cannot start before this.**

| # | Work |
|---|------|
| 10 | **DONE 2026-08-13 — one resolver, not a materialised projection.** `AtKeys.authenticationFor(enrollmentId)` returns the AtChops and the PKAM algorithm, with typed material winning wherever the keyfile holds it for that enrollment and the flat fields answering only where it holds none; `authenticationAlgorithmFor` is the algorithm half, so a caller holding an injected AtChops does not build one `toAtChops` would throw on. `AtAuthImpl.authenticate` and `AtClientImpl._createAtChops` both move onto it. **Ruling 7 as written could not be built** and is amended in place ([`decisions.md` 91.3](detail/decisions.md#913-the-rulings)): filing a projected material makes `toJson` emit `version`/`atsign`/`keys` — the guard is `keys.isEmpty` and both stores stamp `atsign` first — which breaks the byte-identical legacy round-trip [91.4](detail/decisions.md#914-what-is-released-and-therefore-what-must-still-be-read) promises, and on a retrofitted keyfile the one-active-`privateAuthentication`-per-document rule refuses the add outright. Four shipping shapes hold nothing to project from: a pre-typed `.atKeys`, an `rsa2048` first onboard, an OTP enrollment, and an onboard handed its keys by the caller. **Found en route and fixed:** `_createAtChops` picked its keypair off the algorithm `_resolveSigningAlgoFromKeyMaterial` had recorded, and that records nothing when its own read throws — so a transient keyfile failure made a retrofitted client PKAM with the *flat* enrollment's key while its typed material sat in the same file. Its comment claimed it mirrored `AtAuthImpl`; it did not. Rails: at_auth 257/257, at_client 1218/1218 |
| 11 | **PARTLY DONE 2026-08-13 — the wiring half.** ⚠️ **The nullability was never the problem, and the blocking claim was measured rather than inherited.** `apkam_signing.dart`'s dartdoc says sourcing from `AtKeys` "cannot land until every client has an `AtKeysIo` — today it is nullable and most apps supply none". Measured over the 22 repos on disk that depend on at_client: **0 of 22** supply one to a client and **0 of 22** use `fromAuthSession`, so the claim is TRUE — but the dominant cause is one SDK line, not app behaviour. `AtOnboardingServiceImpl.authenticate()` built a `FileAtKeysIo` for `AtAuth` and then created the client without it, so every `at_cli_commons` consumer (at_talk, sshnoports, noports-tools, at_demos, ogentic) inherited a source-less client. **Fixed:** `_initAtClient` takes the source and threads it to `setCurrentAtSign`. The injected AtChops still authenticates — this only gives the client the source for what AtChops cannot answer. ⚠️ **Deliberately NOT done: an `atKeysIo ??=` default on at_client_flutter's `AuthService.authenticate()`.** `AtAuthRequest`'s constructor already refuses a request with neither `atKeysIo` nor `atAuthKeys`, so the default could only ever fire when the caller supplied `atAuthKeys` — an app that loaded its own key material — and pointing it at a keychain that may hold another atSign's keys, or none, is a guess. The asymmetry with `onboard()`'s `??=` is correct: onboarding mints keys and needs somewhere to write them. ⚠️ **The null case is a tested, deliberate property**, not an oversight — `no_atkeysio_inertness_test.dart` pins that a source-less client performs zero PQ writes at startup, which is what protects the long-lived cicd atServers, and the e2e pack builds its clients through `setCurrentAtSign` directly so this change does not reach them. ✅ **DONE 2026-08-13, with step 12:** the signing half — `signingKeys` sources from `AtKeys` rather than reading the APKAM auth keypair out of `atChops`. Built once, as step 12's per-algorithm accessor |
| 12 | ✅ **DONE 2026-08-13.** `AtKeys.signingKeysFor(enrollmentId)` (at_auth) returns every active signing keypair the enrollment holds, one per algorithm, strongest first; `ApkamSigning.signingKeys` (at_client) is a `Future<List<ApkamSigningKeys>>` reading it through `AtClient.atKeysIo`. `ApkamSigningKeys` now carries its `algorithm` and `signEnvelope` takes it from there rather than a separate `signingAlgo` argument — a key and an algorithm arriving separately can disagree, and the resulting signature verifies against nothing. ⚠️ **Selection is by the keyId shape `sign:<enrollmentId>:<algo>:<n>`, NOT by the `privateSigning` role**: `PqSigningRoot` files the atSign-wide signing root under that same role with no enrollment id, so a role filter hands an enrollment a key that was never its own — the same defect shape as 14.19 item 6. Proven by mutation: selecting on the role turns two tests red. **The empty case answers with the APKAM authentication keypair**, which is what ruling 10 keeps in the `_apsk` array permanently, so the accessor is live from this commit rather than waiting on a writer, and `now`-posture envelopes stay byte-identical (the stored JWS vector re-signs to the same bytes). That also covers the source-less client, which is a deliberate tested property. Read per call, not cached: a cached copy goes stale the moment a rotation retires what it held. **The minting/filing half is NOT here** — `fileSigningMaterial` still has no production writer, and which algorithms to mint is the in-use set's decision, so it stays step 18. Rails: at_client **1228/1228** (2 skipped), at_auth **266/266** |

**Stage 3 — the `_apsk` writer half (rollout 2).**

| # | Work |
|---|------|
| 13 | ✅ **DONE 2026-08-13.** `apskAdvertisement` composes from a **list** of keys rather than one `(apkamPublicKey, signingAlgo)` pair, so a second algorithm's key can be advertised beside the first; `ApskSigningKey.forPublicKey` builds an entry and derives its `kid`, which is never a caller's to supply. `status` is emitted **only when retired**, so an advertisement that has never rotated is byte-identical to what the single-key composer wrote. The enrollment-request site still sends one key — at request time the enrollment holds nothing but its freshly minted APKAM keypair, and a second arrives by `enroll:update` (step 16) once step 18 mints one. **`publishPublicSigningKey`'s fate, settled:** it stays the only writer for an `_apsk` no `enroll:request` can carry (a client with no enrollment publishes under `primary`, which has no enrollment record). It now publishes `publicSigningKeyValue` — the **bare** key when the client holds exactly one `rsa2048` key, the array otherwise — which is the same rule `_apskFor` uses for `apsk`-versus-`apskLegacy`; the two must agree because they describe one record. It also **republishes on a change**, closing [decisions.md 91.1](detail/decisions.md#911-what-is-wrong-today) cost 2: it used to read the record, log "have already published" and return, so a rotated key never reached the atServer and every envelope signed with the new one was verified against the old. Proven by mutation: restoring the absent-only condition turns exactly the republish test red. Rails: at_client **1234/1234** (2 skipped), at_auth **269/269** |
| 14 | *(done in step 2a)* `EnrollParams.apsk`/`apskLegacy` are populated at all three submit sites. ⚠️ **This read "Only the atServer half of `apskLegacy` remains" until the 2026-08-14 wrap-up, and that half had merged two days earlier** — at_server `6a86fbcc`, an ancestor of `origin/trunk`, re-verified with `git -C ~/dev/atsign/repos/at_server branch -r --contains 6a86fbcc`. Step 2a was corrected on 2026-08-13 and this row was not, which is how a reader working top-down would have rebuilt merged work |
| 15 | ✅ **DONE 2026-08-13.** `signEnvelope` takes a **list** of keys and emits one signature entry per key, in the order given — which is what the RFC 7515 general serialization the envelope already used is for. `wrapAndSign` passes every key `signingKeys` returns rather than its strongest: the **verifier** chooses, taking the strongest algorithm the envelope and the published `_apsk` share, so signing only under this build's strongest would be unverifiable to any peer that has not implemented it — an envelope carrying both is readable by the upgraded peer and the un-upgraded one, which is the rollout problem in one sentence. The payload is encoded **once** and every entry signs its own protected header joined to that same text, so the entries are alternatives rather than a chain. `SignedEnvelope.fromJson` already refused an empty signatures array and a multi-**signer** document, so the writer builds through it and inherits both refusals. ⚠️ **UC-G1.7's two-signature fixture was hand-assembled** from two single-signature envelopes, so that whole group was a test of the fixture and would have passed against a writer that could not emit two signatures at all; it now drives the real writer. Proven by mutation: signing with `[keys.first]` turns the multi-signature test red. Nothing files per-algorithm signing material yet, so every envelope still carries exactly one signature today, and the stored JWS vector re-signs byte-identically. Rails: at_client **1237/1237** (2 skipped), at_auth **269/269** |
| 16 | ✅ **DONE 2026-08-13, in five commits `e04040ac1`…`d467ed3b5`** — two code, three docs (this row said "in two commits", written before the doc sweep and the wrap-up corrections landed). `AtEnrollment.update` takes an `EnrollmentUpdateRequest` and an `EnrollmentUpdater` sends it, beside `EnrollmentApprover` and deliberately not on it: the approver's verbs need a connection holding `__manage` and act on somebody else's enrollment, while this one needs no privilege and can only act on the enrollment the connection *is* — the atServer refuses an owner connection here rather than waving it through. The request refuses at construction to be built naming nothing to change, with a public key and no private half, with a key and no algorithm or an algorithm and no key, with both `_apsk` shapes, or with an advertisement of no keys. **Found en route: the wire vocabulary was one field short, so this row's "only the caller is owed" was wrong.** `EnrollParams.apkamPublicKeySignature` existed with its own round-trip test, but `EnrollVerbBuilder.buildCommand` never copied it into the params it builds — and a `toJson`/`fromJson` round trip is equally true of a field nothing can send, so the test could not see it. **Two rulings this took:** `signingAlgo` is **always** sent, so the effective algorithm the atServer interpolates is the one signed here and the literal `"null"` can never come from this emitter (pinned regardless — a second implementation has to know the server accepts it); and the public API takes two key-material **strings**, not an `AtPkamKeyPair`, because at_chops deprecates that type and a new signature carrying it hands every caller a deprecation. `ecc_secp256r1` is refused rather than signed: at_chops' pkam-mode signer selects an RSA implementation for everything that is not `mldsa65`, so an ECC key would be signed as though it were RSA — and an ECC APKAM key lives in a secure element whose private half is not a string anyone can pass. **Proven by two mutations**, against tests that re-run the atServer's own `ApkamSignatureVerifier` branches rather than asserting through the signer: signing everything as `rsa2048` turns exactly the mldsa65 arm red (that arm is the only one that can see an algorithm mix-up), and dropping the algorithm from the signable turns all three signature tests red (both arms verify real bytes). ⚠️ **Nothing persists a rotated keypair** — [14.19 item 11](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on). Rails: at_commons **517/517**, at_auth **288/288**, at_client **1237/1237** (2 skipped), at_onboarding_cli **39/39**. **THE PoP CONTRACT, read from at_server `6a86fbcc` `enroll_verb_handler.dart` `_verifyApkamPublicKeyPossession` and `apkam_signature_verifier.dart` — do not re-derive it:** signable is `utf8.encode('<enrollmentId>|<apkamPublicKey>|<signingAlgo>')`, signature travels **base64**, signed by the **NEW** private key. Three things a guess gets wrong: (a) `signingAlgo` is the **effective** one, `request.signingAlgo ?? record.signingAlgo`, string-interpolated — so a null becomes the literal `"null"` in the signed bytes, and a client that omits it must know the record's current value; (b) **mldsa65 signs the message DIRECTLY with no hash** (`MlDsa65PureDartAlgo.verifyBytes`), while rsa2048/ecc go through `AtChopsImpl.verify` with `HashingAlgoType.sha256` — a client that hashes for both fails only on the PQ path; (c) `AtSigningMode.pkam`, never `data`, which signs with the *encryption* keypair. The server also refuses `signingAlgo` without `apkamPublicKey`, and `enroll:update` is **self-only** and **approved-only**. ⚠️ **Adding a member to `AtEnrollment` touched 7 `Mock implements` in three packages** (at_auth 2, at_client 4, at_onboarding_cli 1), plus `AtEnrollmentImpl`, which is the **production** class and got a real implementation rather than a stub — not an eighth mock, as an earlier draft of this row said. All three suites re-run; the mocks are safe because no production path calls the new member, and they would have broken at RUNTIME, not analyze |
| 17 | ✅ **DONE 2026-08-13.** `AtClientPreference.inUseSigningAlgorithms` — a `Set<SigningAlgoType>`, final at construction and stored unmodifiable, defaulted from a new fifth `ReleasePosture` axis and overridable per preference. **The four things ruling 16 left open were ruled by gkc and are recorded in [`decisions.md` 91.3](detail/decisions.md#913-the-rulings) ruling 16 with their reasoning:** defaults `{}` in 3.x and `{mldsa65}` in 4.0; a `Set`; final at construction; and an algorithm this build cannot sign an envelope under is refused at construction with an `ArgumentError` rather than skipped. ⚠️ **The doc sweep this owed was bigger than the row** — three documents enumerated the posture's axes and all three still listed the **signed-envelope version**, deleted at step 3: [`decisions.md` 56.4](detail/decisions.md#564-from-the-pq-projects-view-40-is-final-3x-with-different-flag-defaults)'s table, its capstone entry [`decisions.md` 70](detail/decisions.md#70-workstream-a-capstone-releaseposture-the-five-flags-as-one-value-2026-08-10), and `roadmap.md`'s axis list. The count stayed five across the swap, which is precisely how a stale enumeration survives review. Acceptance gained UC-C1.7 and UC-C1.6's "UC-C1.1–C1.5 prove the arms" was corrected — C1.3 is withdrawn. `design.md` 9.6's strength order still showed the three-member ruling rather than the five-member total order step 7 shipped. **Nothing reads the set yet — step 18 is its only consumer**, so this commit is a preference and its refusal, not a behaviour change. **Proven by four mutations**: each posture default flipped reddens its literal pin, disabling the signable check reddens the refusal test, and returning the caller's own set rather than an unmodifiable copy reddens the containment test. ⚠️ **The 1240/1240 in this commit's message was measured before the doc edits and does not hold for the commit as landed** — adding UC-C1.7 to `acceptance.md` without a scenario in `test/acceptance/` turns `catalogue_test.dart` red, which is that guard doing its job. Fixed in step 18's first commit, which adds the scenario and the README row count. Rails for 17+18a together: at_client **1245/1245** (2 skipped), acceptance **57** (2 skipped) |
| 18 | **PART 1 DONE 2026-08-13 — the reader and the advertisement; the minter is part 2.** Splitting it was forced by a defect the minter would have shipped: `ParsedApsk.keyFor` took **one key per algorithm** (`where(alg).firstOrNull`) and `verifyEnvelope` checked that one, so ruling 10's retained authentication key works only where its algorithm differs from the minted key's. A post-quantum-native enrollment's auth key is ML-DSA and so is what it mints, which puts two `mldsa65` entries in `_apsk`, and every envelope signed before the split stops verifying — the ordinary 4.0 case. `keysFor(algo)` is now plural and the verifier tries each, refusing only when none verifies; ruling 10 is amended in place with why. **The reader ships before the writer**, which is also why this is two commits rather than one. Also here: `apskEntries`/`apskValueOf` (`apsk_composition.dart`) are the one composition of the `_apsk` record for both its publishers, and they append the authentication key as `retired` once the enrollment holds signing keys — deduped, because one key described as both current and withdrawn is a document a verifier has nothing to choose on. An enrollment holding no signing material advertises exactly what it did before. ⚠️ **The retention half was reversed 2026-08-14 by row B2** under [`decisions.md` 98](detail/decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14) ruling 2: the auth key is advertised only while it *is* the signer and is never retained, and what `apskEntries` carries beside the active signers is the enrollment's **retired signing keys**. The dedup survives, between an active signer and a retired entry naming the same public half. **Proven by mutation**: restoring the single-key selection reddens the retained-key test. Rails: at_client **1245/1245** (2 skipped), acceptance **57** (2 skipped). **Part 2 owes** the minter itself: mint at start, publish, then file. ⚠️ **In that order** — filing first makes the client sign with a key its advertisement does not name, and every envelope written in that window is permanently unverifiable, while an advertised key that was never filed costs a verifier nothing and disappears at the next publish. The nskey path's rule is the opposite (`NskeyPrivateFiling.store` files before publishing) because an unopenable *encapsulation* key loses data; the asymmetry is real and worth stating where both are read |
| 18b | ✅ **DONE 2026-08-13.** `SigningKeyMinting` (at_client) mints a keypair for every algorithm the in-use set names and the enrollment does not hold, advertises it, and **then** files it through `WrittenAtKeysIo.update` — the store's atomic verb, because a client's start files conveyed key material through the same keyfile and a hand-rolled read → mutate → write would drop whichever addition flushed first. Wired as the **ninth** `PqClientBootstrap` step, `mintInUseSigningKeys`, gated by `PqStartupGates` and placed **before every step that signs** (seeding, both link publications and the sweep all emit signed envelopes), so a key minted on a start is advertised before anything signs with it. Which writer depends on whether there is an enrollment record: `enroll:update` where there is one — the atServer is the only writer of an enrollment's `_apsk` — and a direct publish under `primary` where there is not. Inert with an empty in-use set (the 3.x default) and inert for a client with no key source, which is the tested no-`AtKeysIo` property. `RsaKeyPair.generate()` rather than `AtChopsUtil.generateAtPkamKeyPair()`, which returns a type at_chops deprecates. **Proven by three mutations**: swapping to file-then-publish reddens the ordering test, dropping the retained authentication key reddens the advertisement tests, and minting an already-held algorithm reddens both idempotence tests. ⚠️ **The second of those mutations no longer discriminates** — row B2 removed the retention it was probing. Its replacement is B2's own pair: gutting `retiredSigningKeysFor` reddens the two retained-signing-key tests, and removing the dedup reddens the third. Rails: at_client **1257/1257** (2 skipped), acceptance **57** (2 skipped) |
| — | *(the original row, kept for its spec pointers)* Mint-on-demand when the in-use set names an algorithm the enrollment lacks. **Spec: ruling 16** (mint locally at start, file it, publish it — a *signing* keypair may, because unlike the auth key it needs no server approval) and **[`decisions.md` 91.3](detail/decisions.md#913-the-rulings) ruling 9** (the array is append-mostly: an algorithm leaving the set stops signing, but its key and its published entry are **retained**, because they are what verify the envelopes it already signed). This is the step that gives `signingKeysFor` something to read — `fileSigningMaterial` has no production writer until it lands |
| 19 | ✅ **DONE 2026-08-13.** The axis is **`SigningRollout`** — `now` / `rollout1` / `rollout2` — on `ReleasePosture.signingRollout`, overridable per `AtClientPreference`, with the in-use signing set **derived** from it rather than stored beside it. **The step opened with a finding that nearly closed it:** the three rollout-2 writer behaviours are inseparable *by construction*, not by three flags agreeing — only minting is a decision, while the array form (`apskValueOf` emits the bare string only for a single active `rsa2048` entry) and the multi-signature envelope (`wrapAndSign` signs with every key the keyfile holds) are consequences of the enrollment holding a second key. Folding the axis away like step 23 was put to gkc and **declined**: the axis earns its place by naming the position, and steps 20–22's driver needs those names. So it names a position and supplies one default, and cannot contradict the behaviour — two stored fields would be two controls over one thing. `rollout1` writes exactly what `now` writes (the reader half needs no gate) and carries the *fleet's* position instead; it is reachable only through the preference, since there are two postures and no general constructor, and an unreachable value would be a rollout position nothing could ever be in. **Proven by three mutations**: giving `rollout1` a non-empty set, ignoring an explicit stage, and letting the stage beat an explicit set each redden their own arm. Rails: at_client **1261/1261** (2 skipped), functional **146/146** at `88ab87b4e` |

⚠️ **The rollout stages were REDEFINED 2026-08-14, and the at-rest keyfile
shape with them. NONE of it is built.** Read
[`decisions.md` 98](detail/decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14)
and [99](detail/decisions.md#99-the-keyfile-groups-by-enrollment-and-the-atsigns-own-keys-move-out-2026-08-14)
for what and why, and **[14.20](detail/implementation-plan.md#1420-building-rulings-98-and-99--the-sequence)
for the order to build them in** — several of those orderings are the difference
between a working rollout and a broken fleet. Read all three before acting on
any row below that names a stage. Rollout 1 now moves the
**authentication** key to ML-DSA-65 and mints a fresh **RSA-2048 signing key**
to advertise in its place: only the atServer verifies the auth key, while every
peer verifies the signing key, so the forgeable-later credential can move first
while the verification surface stays classical. Consequences that touch rows
already marked done:

- ✅ **DONE 2026-08-14 (row B1).** `SigningRollout`'s in-use sets became `{}` /
  `{rsa2048}` / `{mldsa65}`, and it gained
  `defaultRetrofitAuthenticationAlgo`; `retrofitSigningAlgo` is renamed
  `retrofitAuthenticationAlgo` and is now a derived getter (step 17/19's
  landed work, extended).
- `_apskFor` must advertise the **signing** key, not `apkamPublicKey`, and the
  retrofit must mint that key **before** submitting — otherwise a rollout-1
  enrollment publishes an ML-DSA array at creation and breaks every deployed
  reader (step 2a/13's composer, changed).
- `apskEntries` stops appending the authentication key unconditionally;
  [`decisions.md` 91.3](detail/decisions.md#913-the-rulings) ruling 10 is superseded
  and ruling 9 preserved (step 18a's composer, changed).
- **Rollout 1 needs no APKAM rotation**, so it depends on neither step 20's
  rotation arm nor the at_auth release — it is buildable today.

**Stage 4 — the programme pair. This is the validation gate before any PR is carved.**

| # | Work |
|---|------|
| 20 | **MOSTLY DONE 2026-08-14 — the pair runs; the rotation arm is not built.** `tests/pq_matrix/` holds `scenario/`, `current/` and `published/`, three standalone packages. What is built and driven: the stage parameterisation, a real notification, multiple puts and gets with each put read back at the write. **Still owed: enrollment followed by an `enroll:update` APKAM rotation mid-run.** ⚠️ **Its blocker is now an at_auth RELEASE, not a ruling** — [14.19 item 11](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) was ruled two-phase on 2026-08-14 and its reader half has landed, so what remains is: publish at_auth carrying the tolerant reader, then add the staged status value, then build the arm. It also needs a dedicated CRAM atSign, since the matrix's demo atSigns hold no enrollment. Do not re-open the persist-before-versus-after question |
| 21 | ✅ **DONE 2026-08-14.** `tests/at_functional_test/test/pq_rollout_matrix_test.dart` runs all sixteen cells, sender and receiver as separate **processes** — they are separate builds, and no one process can hold two versions of at_client. The receiver is spawned first and the sender waits on its `READY` line, because notification streams are broadcast and do not replay. Every cell passes; the failing cells the row used to describe were measured out of existence (see the warning below). **Proven by mutation**: a sender writing `putCount - 1` records reddens the cell, and the error names the missing record, so the receiver genuinely reads from the atServer rather than passing on an empty comparison |
| 22 | ⚠️ **DONE 2026-08-14, then SUPERSEDED the same day.** The row it proves was rewritten by [`decisions.md` 98](detail/decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14) ruling 12: rollout 1 publishes a *different key* from `now`, so byte-identity is false by design and the test as landed asserts something that will stop being true the moment the stages are rebuilt. Its replacement asserts the **form** instead, measured by the published arm — a released at_client 3.14.0 reader fetching a rollout-1 sender's `_apsk` and base64-decoding it as an RSA key. **The positive control is the part to keep**: whatever the row asserts, a rollout-2 cell must differ, or it passes for a harness where no stage does anything. *What landed, for the record:* UC-G1.14 runs its own now/now and rollout1/rollout1 cells rather than reading what the matrix loop left behind — a test that depends on another test having run first passes on declaration order, which is not a property of the code. It asserts the published `_apsk` byte-identical and the sender's keyfile byte-identical across the two stages. **It carries its own positive control**, and that is the part worth keeping: a third cell at rollout2 must *differ* on both counts. Without it the row passes just as well for a harness where no stage does anything — which is exactly how a rollout-2 arm attached with no key source reads. Measured: `now` and `rollout1` leave the keyfile at its 5605-byte baseline, `rollout2` leaves 14016 |

Scope of the pair, ruled: the signed-envelope exchange; a real notification and
data path; **multiple puts and gets**; and enrollment followed by an
`enroll:update` APKAM rotation mid-run. The **published** arm runs the last
released at_client and is what makes "`now` is faithful to legacy" a
measurement rather than a claim — see [`acceptance.md` 16.1](acceptance.md#161-the-harness).

**Where it lives, ruled 2026-08-14** ([`decisions.md` 96](detail/decisions.md#96-the-programme-pair-gets-a-home-outside-the-workspace-2026-08-14)):
`tests/pq_matrix/` holding `scenario/`, `current/` and `published/` as three
**standalone** packages — none listed in the root `workspace:`, because
`packages/at_client` is a workspace member and a member cannot depend on the
hosted 3.14.0. `published/` pins `at_client: 3.14.0` exactly with its lockfile
committed; `scenario/` holds the exchange once and each arm supplies only its
own preference construction, so a published-versus-`now` divergence is
attributable to at_client rather than to two hand-written programs. The driver
is a test file in `tests/at_functional_test`, so `runLocal.sh` stays the entry
point.

⚠️ **The matrix is a data-path matrix, and the two failing cells are gone.**
Measured 2026-08-14: at_client 3.14.0 and this tree cannot exchange an envelope
in **either** direction under **any** stage — this tree → 3.14.0 is a
`_TypeError` null cast, 3.14.0 → this tree refuses with "an envelope must carry
its payload as a string". Step 3 deleted the envelope as a posture axis, so no
stage emits the released shape. gkc ruled the break accepted rather than fixed,
on reachability: the released reader is same-atSign only, hangs off an
`@experimental` entry point nothing in 3.14.0 constructs, and that entry point's
dartdoc opens "not yet suitable for production secrets". Both errors are pinned
as raw literals. The rollout-2 cells previously shown as failing with
`IllegalStateException` were wrong on both the cells and the error —
[`acceptance.md` 16.5](acceptance.md#165-the-rollout-matrix) records what it
used to say, and [`decisions.md` 95](detail/decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
rulings 2 and 3 are amended in place.

**Stage 5 — the rest of D1. All in scope; none deferred.**

| # | Work | Entry |
|---|------|-------|
| 23 | *(folded away)* passive-by-default **is** the axis's `now` position | [14.13](detail/implementation-plan.md#1413-a-passive-by-default-flag-surveyed-not-built) |
| 24 | A client with no enrollment id is treated as fully privileged | [14.14](#1414-a-client-with-no-enrollment-id-is-treated-as-fully-privileged) |
| 25 | A `mintLegacyMaterial:false` atSign cannot write a public record | [14.12](#1412-a-mintlegacymaterialfalse-atsign-cannot-write-a-public-record) |
| 26 | *(closed)* revocation visibility — an `EnrollmentManager` cache race, fixed in at_server `16dd457f`. ⚠️ This cell said "a proven test-instrument failure" until 2026-08-15; that was the 2026-08-11 ruling the root-cause overturned | [14.9](detail/implementation-plan.md#149-a-revoked-enrollment-can-still-authenticate-briefly) |
| 27 | ✅ **DONE 2026-08-15** — domain separation on the signed envelope, per-use `typ` plus a root-link prefix ([`decisions.md` 103](detail/decisions.md#103-an-envelope-says-what-it-is-for-and-a-verifier-says-what-it-wants-2026-08-15)) | [14.8](detail/implementation-plan.md#148-domain-separation-on-the-signed-envelope) |
| 28 | NoPorts' own copy of the envelope shape | [14.7](#147-noports-carries-its-own-copy-of-the-envelope-shape) |
| 29 | The four audit residuals — perf ceiling on a real low-end device, UC-A3.4 live self-direction, SS-4 interrupted-mint resume, IS-1 record-name drift | [14.16](#1416-four-residuals-the-issue-tree-audit-surfaced-2026-08-09) |
| 30 | `deprecated_member_use` findings across the workspace (340 at_client, 183 at_onboarding_cli, 110 at_auth, 28 at_lookup) | [14.11](#1411-deprecated_member_use-findings-across-the-workspace) |
| 31 | Pre-PR rails checklist | [14.15](#1415-pre-pr-rails-checklist) |

Also in D1, runnable in parallel: **S-3**'s completion, **B-3** ([#2128](https://github.com/atsign-foundation/at_client_sdk/issues/2128),
open), **KF-1** ([#2129](https://github.com/atsign-foundation/at_client_sdk/issues/2129),
open), and **IS-1**. ~~merging at_lookup 3.6.1 (#2127)~~ — dropped 2026-08-13:
that PR merged 2026-08-08 and 3.6.1 is on pub.dev, so it had been listed as
parallel work for five days after it was finished. Issue states verified with
`gh` on 2026-08-13; re-derive rather than trusting this line.

**Stage 6 — the carve-up, which is where D1 initial development ends.**

| # | Work |
|---|------|
| 32 | Carve the spike into stacked PRs |
| 33 | Merge them to trunk. **The spike branch itself never merges** |
| 34 | ← D1 initial development complete here |

Then, as the release programme rather than development: publish at_chops 3.6.0
→ at_commons **5.16.0** → at_auth 3.4.0 → at_client's GA minor, and finally
**R-2**, the 4.0.0 posture flip. (⚠️ this said at_commons **5.15.0** until
2026-08-13, a version already on pub.dev; the in-tree in-progress heading is
5.16.0. Check pub.dev against every touched pubspec before acting on this
ladder — a same-value version bump merges silently.)


### 14.19 Small items, raised 2026-08-12 and not yet acted on

**17 open, 5 struck.** Each is real and verified at the time of writing, and
each is too small to be a step of its own. **None blocks anything** — which is
why the items themselves live in
[`detail/implementation-plan.md`](detail/implementation-plan.md#1419-small-items-raised-2026-08-12-and-not-yet-acted-on)
rather than here: they are work to pick up, not work to hold in mind.

**Item 8 is the only one waiting on a ruling** — typed key material is not
self-encrypted at rest while the flat fields are. Item 10 is an unexplained
functional run with two disproven theories. Item 14 is not PQ at all. Items
20–22 were examined and deliberately left, so they are not work.

Re-derive the open count rather than trusting the number above:

```bash
awk '/^### 14.19 /,/^#### 14.19.1/' docs/projects/pq/detail/implementation-plan.md \
  | grep -cE "^[0-9]+\. \*\*"
```

[14.19.1](#14191-things-that-look-like-defects-and-are-not) stays below,
deliberately: it records proposals that were made and **rejected on evidence**,
and it only works if it is read where the temptation arises.

#### 14.19.1 Things that LOOK like defects and are not

Recorded because each was proposed as a fix and **rejected on evidence**.
Without this note the next reader re-derives the proposal, "fixes" it, and ships
a false claim — one of them was already drafted into a CHANGELOG line before an
adversarial pass killed it. Items 1–3 came from ruling 6; the rest were raised
later, so do not read this list as scoped to one ruling. **Add to it rather
than re-litigating an entry**, and if an entry is genuinely wrong, amend it in
place with what it used to say.

0. **Do NOT add a "refuse a document carrying a top-level `atSignKeys` by
   name" guard.** Proposed 2026-08-15 while renaming that field to
   `atsignKeys`, on the precedent of A1's refusal of a stale top-level `keys`
   (which is a real guard and stays). ⚠️ **The two cases are not alike, and
   the difference is who holds the stale document.** A1's `keys` guard protects
   against a shape *this tree itself wrote and shipped through several of its
   own commits*, so a stale file could plausibly be sitting on a machine that
   matters. `atSignKeys` existed only between A1 and this rename, was never
   released — zero matches across all ten at_auth versions in the pub cache,
   with `class AtKeys` as the positive control — and the only files carrying it
   are ones our own functional runs generate and regenerate. gkc ruled it out
   the same day. A guard here would be code no reachable file can trigger,
   which reads as a supported migration path that does not exist.
1. **A corrupt-base64 pairwise envelope is NOT misclassified as transient.**
   It is tempting to read `sweepOnce`'s broad `catch` arm as the "retry
   forever" path and the `received == null` arm as the "deterministic skip"
   path, and to claim routing the decode through `pqOpenFromBase64` changes the
   outcome. It does not: both arms run the same two statements — release the
   claim, log a warning — and neither deletes, so the envelope waits for ttl
   expiry either way. Only the log line and the classification differ. Do not
   describe this as a behaviour or at-rest change.
2. **An `on PqSealException` arm at the nskey seal site would be dead code.**
   `pqSeal` throws it in exactly one place, the unsupported-version refusal,
   and `NskeyProvider.encrypt`'s own version guard makes that unreachable — the
   version always comes from `sealVersionFor`. The wrong-length-key case that
   arm looks like it catches arrives from `encapsulate`, which at_chops now
   maps itself.
3. **Do NOT tighten `_openIfSymmetricKey`'s `catch (e)` to a typed catch.**
   `enrollment_symmetric_key.dart` documents "every rejection is a skip rather
   than a throw", its caller's poll loop has no `try` at all, and a throw there
   fails the whole enrollment — recoverable only by re-requesting, since the
   conveyed `apkamSymmetricKey` is written once. The breadth is the contract.
   [Section 47.6](detail/decisions.md#476-two-defects-in-the-enrollment-path-both-from-the-same-shape)
   records the two defects that breadth was introduced to fix.
4. **A suite-versus-key-algorithm guard in `_consume` would change no
   outcome.** Once a client can hold keys under more than one KEM
   ([14.18](#1418-the-remaining-d1-initial-development-sequence) step 5), an
   envelope can name an ML-KEM suite and an X-Wing key, and it looks like
   something to refuse before the open. It is not: at_chops maps the
   wrong-length secret key to a `PqOpenException`, which the open already
   catches and skips, and its message names the mismatch outright
   ("ML-KEM-1024 secret key must be 3168 bytes: 32"). The guard was written,
   removing it turned nothing red, and it comes out — a check that changes no
   outcome and reads like a security check it is not. What *does* matter is
   pinned instead: the envelope is skipped rather than crashing the sweep, so
   the good envelopes behind it in the batch still arrive.
5. **Do NOT add `atKeysIo ??= KeychainAtKeysIo()` to at_client_flutter's
   `AuthService.authenticate()`.** `onboard()` has exactly that line
   (`auth_service.dart:40`) and `authenticate()` does not, which reads as an
   oversight and is not. `AtAuthRequest`'s constructor already refuses a
   request carrying neither `atKeysIo` nor `atAuthKeys`
   (`at_auth_requests.dart:119`), so on the authenticate path the `??=` could
   only ever fire when the caller supplied **`atAuthKeys`** — an app that
   loaded its own key material and is telling you so. Defaulting a keychain
   source there points the client at a store that may hold another atSign's
   keys, or none. The asymmetry is correct: onboarding *mints* keys and needs
   somewhere to write them, while authenticating does not. Proposed and
   rejected 2026-08-13 while wiring [14.18](#1418-the-remaining-d1-initial-development-sequence)
   step 11; the same reasoning is now a comment above the method, because the
   invitation is in the file rather than in this document.
6. **Do NOT add `update` to at_client's `EnrollmentService`.** The invitation is
   strong and will recur: `AtEnrollment.update` landed with no at_client-side
   entry point, `EnrollmentServiceImpl` already wraps an `AtEnrollment`, and it
   already forwards `approve`/`deny`/`revoke` — so exposing `update` beside them
   looks like finishing the job. It is not. That facade is the **approver** side:
   every verb on it needs a connection holding `__manage` and acts on *somebody
   else's* enrollment. `enroll:update` is the opposite — no privilege at all, and
   only ever on the enrollment the connection *is*, with the atServer refusing an
   owner connection rather than waving it through. Putting both behind one
   interface makes the two authorities look interchangeable to every caller and
   every reviewer, which is the distinction the whole self-only security argument
   rests on. Note also that the facade does **not** mirror `AtEnrollment` today —
   it carries no `submit`, no `list`, no otp verbs — so "it forwards the others"
   was never the rule. Proposed and rejected 2026-08-13 while landing
   [14.18](#1418-the-remaining-d1-initial-development-sequence) step 16. When
   steps 17–18 need to reach `update` from at_client, give it a seam of its own
   on the signing path rather than widening this one.


### 14.17 Signature agility — what is built, and what is owed

The design landed 2026-08-11 as [`decisions.md` 91](detail/decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11),
[`design.md` 9](design.md#9-subsystem-g--signature-agility-the-authsigning-key-split)
and [`acceptance.md` 16](acceptance.md#16-g1--signature-agility-and-the-rollout-matrix).
This entry is the owed half; the rulings are the contract.

**Owed, in dependency order.**

1. ~~**Drop at_server's at_commons override.**~~ **DONE 2026-08-11.** The
   override is out of both `pubspec.yaml` and `pubspec_overrides.yaml`,
   `pubspec.lock` resolves at_commons from hosted 5.14.0, the
   `at_commons-apsk-1` tag is deleted local and origin (its commit `54ccffdd0`
   is an ancestor of trunk, so nothing was orphaned), and
   [at_server#2744](https://github.com/atsign-foundation/at_server/pull/2744)
   **MERGED 2026-08-11** — ⚠️ *this line read "is open for review" until the
   2026-08-14 wrap-up; verified with `gh pr view 2744 --repo
   atsign-foundation/at_server`.* ⚠️ **And the `5bc3618a` this paragraph named
   as at_server's head is long superseded** — it is an ancestor of
   `origin/trunk` now, i.e. landed. ⚠️ **Do not read a SHA here as "at_server's
   head" at all:** `6a86fbcc`, cited elsewhere in this plan for the PoP
   contract, is the tip of the local `gkc-add-apskLegacy-field` branch and is
   *also* an ancestor of trunk; `origin/trunk` itself was at `fdb78568` on
   2026-08-14 and moves independently of anything here. Re-derive with
   `git -C ~/dev/atsign/repos/at_server rev-parse --short origin/trunk`; none
   of this is visible from inside at_client_sdk, which is how both errors
   survived.

   **What this still leaves owed:** at_server's own **210/210** was measured at
   `ab38b884`, several commits back and against a different at_commons source.
   **That number is stale twice over and has to be re-earned before it is cited
   again** — it is at_server's pack, not at_client_sdk's, so none of this
   project's runs discharge it.
2. ~~**Ruling 7's remaining half: flat → typed.**~~ **DONE 2026-08-13**, and
   narrowed on evidence — see [14.18](#1418-the-remaining-d1-initial-development-sequence)
   step 10 and the amendment in [`decisions.md` 91.3](detail/decisions.md#913-the-rulings)
   ruling 7. The projection cannot be **materialised**, so "nothing reads them"
   became "one place reads them": `AtKeys.authenticationFor` /
   `authenticationAlgorithmFor`. ⚠️ **The reader list above was wrong on two of
   its four entries.** `file_io.dart` touches no `AtKeys` flat field at all —
   its only `atKeys.*` uses are `atsign` and `toJson` — and `onboarding_mint.dart`
   *writes* them at mint time, which is the projection working as intended
   rather than a read to move. The two that did move are `AtKeys.toAtChops()`'s
   callers in `at_auth_impl.dart` and, not on the list, `at_client_impl.dart`.
3. ~~**The wire half, client side — none of it exists.**~~ ⚠️ **STOP — this
   whole item is a 2026-08-11 SNAPSHOT and four of its five sub-bullets are now
   FALSE.** Corrected 2026-08-13 after a context-free read of the handoff
   reported that a reader sent here for the step-17 spec would conclude the
   multi-signature writer and the strength order were still owed, and rebuild
   them. **What actually landed** ([14.18](#1418-the-remaining-d1-initial-development-sequence)
   is authoritative, not this list):

   - the `_apsk` **array composer and reader** — steps 6 and 13;
   - the **multi-signature envelope** — step 15. `signEnvelope` takes
     `required List<ApkamSigningKeys> keys` and emits one entry per key;
   - **`requireAlg` no longer exists in any source file** (step 8 replaced the
     refusal with algorithm *resolution*; the only surviving mention is
     `packages/at_client/CHANGELOG.md`). Any line below citing it, or citing
     `envelope_signature.dart:577`, is describing deleted code;
   - the **strength order** — step 7. `SigningAlgoType.strongestFirst` is at
     `packages/at_chops/lib/src/algorithm/algo_type.dart:37`, with
     `packages/at_chops/test/signing_strength_test.dart` as its tripwire, so
     UC-G1.7 has had something to run against since 2026-08-13;
   - the **`enroll:update` caller** — step 16.

   ⚠️ **The line numbers below are also stale** — `ApkamSigningKeys` is no
   longer at `envelope_signature.dart:197`, and `signingKeys` is at
   `apkam_signing.dart:124` returning `Future<List<ApkamSigningKeys>>`, not at
   `:56`. **Nothing is owed from this item any more** — the in-use signing set
   landed 2026-08-13 as step 17, mint-on-demand as step 18, and row B3 moved
   the mint ahead of the enrollment submission on 2026-08-14. (This line read
   "only mint-on-demand is genuinely still owed" until that sweep.) The original text is kept below
   because its *reasoning* about why each piece is an inversion rather than an
   addition is still worth reading — but read it as history, and verify every
   claim against the source before acting on it.

   - **The `_apsk` array composer and reader.** Today `publishPublicSigningKey`
     (`apkam_signing.dart:38`) `put`s a **single bare key**, and does so only
     when the record is absent — a get-then-put-if-missing. Nothing composes
     `{v:1, keys:[{use, alg, pub, status}]}` and nothing reads it. The
     `use`/`alg`/`pub` vocabulary exists in the tree, but in `key_package.dart`
     (the **KEM** package, a different record) and as `[{alg, pub}]` in
     `pq_signing_root.dart` (the signing root, no `use`, no `status`). ⚠️ ~~**Open
     question when the composer lands:** does `publishPublicSigningKey` retire,
     or does it stay and become a second writer to a record the approval path
     also writes? Its skip-if-present means an enrollment that already published
     a bare string never rewrites it.~~ **ANSWERED by [14.18](#1418-the-remaining-d1-initial-development-sequence)
     step 13 — it stays**, as the only writer for an `_apsk` no `enroll:request`
     can carry (a client with no enrollment publishes under `primary`, which has
     no enrollment record). And the skip-if-present is gone: it **republishes on
     a change**, which was a real defect — a rotated key never reached the
     atServer and every envelope signed with the new one verified against the
     old.
   - **The multi-signature envelope. This is an inversion, not an addition.**
     `signEnvelope` emits exactly one `signature` and one `signingAlgo` from a
     `switch` on a single `SigningAlgoType`, on both the v1 and JWS paths. The
     verifier does not merely lack multi-signature support — it **actively
     refuses** a mismatch, via `requireAlg` at `envelope_signature.dart:577`,
     whose message reads *"the published `_apsk` is a `<algo>` key"*. The
     singular is baked into the behaviour and the diagnostic, so this work
     changes an existing refusal rather than extending a permissive path.
   - **The strength order** beside `SigningAlgoType` in at_chops, with its
     raw-literal tripwire. No ordering exists anywhere in at_chops or at_client
     today, so [UC-G1.7](acceptance.md#16-g1--signature-agility-and-the-rollout-matrix)
     ("the verifier takes the strongest and does not fall back") has nothing to
     run against.
   - ~~**The `enroll:update` caller** and its PoP signature~~ — ✅ **BUILT
     2026-08-13** as [14.18 step 16](#1418-the-remaining-d1-initial-development-sequence):
     `AtEnrollment.update`, `EnrollmentUpdateRequest`, `EnrollmentUpdater` and
     `apkamPossessionSignature` (`AtSigningMode.pkam`, SHA-256 — ruling 14, and
     `AtSigningMode.data` cannot work). ⚠️ A rotation is not persisted anywhere,
     [14.19 item 11](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on).
   - ~~**The in-use signing set** on `AtClientPreference`~~ — ✅ **BUILT
     2026-08-13** as [14.18 step 17](#1418-the-remaining-d1-initial-development-sequence):
     `inUseSigningAlgorithms`, defaulted from `ReleasePosture`. The deprecated
     `signingAlgoType` stays where it is — it is the *authentication* key's
     algorithm, a different thing.
   - **Mint-on-demand** when the in-use set names an algorithm the enrollment
     lacks.

   ⚠️ **Neither side of rollout 1 exists yet.** The staging in
   [`design.md` 9](design.md#9-subsystem-g--signature-agility-the-authsigning-key-split)
   has rollout 1 ship *reader* capability ungated, before any writer emits the
   array — but the client has neither reader nor writer, so the first
   deliverable here is the reader, not the composer, however tempting it is to
   build the thing that produces output you can look at.

   ⚠️ **The writer half is blocked on owed item 2, and the reader half is not.**
   Found 2026-08-11 by reading the source, and it changes the order this entry
   should be worked in:

   - A **reader** needs the published `_apsk` array and the envelope, both
     fetched over the wire. It touches no local key material, so nothing gates
     it. Start here.
   - A **writer** emitting multi-signature envelopes needs one signing keypair
     **per algorithm**, and nothing can supply that today.
     `ApkamSigningKeys` (`envelope_signature.dart:197`) holds exactly one pair
     of `String`s; `signingKeys` (`apkam_signing.dart:56`) reads it out of
     `atChops`, which carries only the APKAM *authentication* keypair; and
     `AtKeys.toAtChopsForEnrollment` (`at_keys.dart:498`) builds that same
     single authentication pair. **Nothing anywhere enumerates an enrollment's
     signing keys per algorithm** — the accessor that would front the array
     does not exist. Sourcing per-algorithm material
     means sourcing from `AtKeys`, and `apkam_signing.dart`'s own dartdoc
     records why that cannot land yet: *"it cannot land until every client has
     an `AtKeysIo` — today it is nullable and most apps supply none, so reading
     through it would break them."* `_atKeysIo` is indeed `AtKeysIo?`
     (`at_client_impl.dart:80`) and honoured only on first construction.
     ⚠️ **Amended 2026-08-13: that quoted dartdoc is now half wrong, and it is
     still in the file.** The claim was measured — 0 of 22 repos on disk
     supplied one — but the cause was one SDK line, and
     [14.18](#1418-the-remaining-d1-initial-development-sequence) step 11 fixed
     it, so an `at_onboarding_cli` client has a source now. What survives is
     that an app building its own client still supplies none *and is entitled
     to*: a source-less client is a deliberate, tested property protecting the
     cicd atServers. So the accessor needs a defined answer for "no source"
     rather than a precondition that there always is one. Rewriting the dartdoc
     is part of step 12.

     ✅ **Resolved 2026-08-13 by step 12.** `AtKeys.signingKeysFor` enumerates
     an enrollment's signing keys per algorithm, and `ApkamSigning.signingKeys`
     is a `Future<List<ApkamSigningKeys>>` sourced from the keyfile. The "no
     source" answer is the APKAM authentication keypair, which is also the
     answer while nothing files signing material — so the accessor is live
     rather than waiting on a writer, and `now`-posture envelopes are
     unchanged. The stale dartdoc is rewritten.

   So **owed item 2 is not merely the largest remaining piece, it is the gate on
   this one** — which is the argument for doing it before the composer, and the
   reason a session that starts with "compose the array" will not finish it.
4. **The rollout axis.** One `ReleasePosture` flag switching all three writer
   behaviours together (mint signing keys, publish the array, emit
   multi-signature envelopes). **The axis has no name yet** — see
   [`design.md` 9.7](design.md#9-subsystem-g--signature-agility-the-authsigning-key-split).
5. **The rollout harness.** Two stage-parameterised executables plus the 3×3
   matrix in [`acceptance.md` 16.5](acceptance.md#16-g1--signature-agility-and-the-rollout-matrix),
   with the failing cell asserted by its specific error.
6. **`enroll:update` parity for every other atServer implementation** — needs
   its own tracking issue so it cannot silently diverge.

**Still owed: an `mldsa65` arm on the rotation tests** — the algorithm the
feature exists for is the one arm nothing covers, and picking `rsa2048` for a
fixture is exactly the choice that makes a wrong answer invisible.

### 14.16 Four residuals the issue-tree audit surfaced, 2026-08-09

Updating the #1889 tree to the current state meant auditing every open issue's
own deliverables against the code rather than against the plan. Four things were
owed that no ledger recorded — and two plan claims were wrong, now corrected in
place (the layer-3 AAD literal, and UC-A3.4 below).

1. **The performance ceiling is not pinned.** [acceptance.md](acceptance.md)
   asks for the deltas measured on *one reference low-end device*, with the
   ceiling pinned when the harness lands. The harness exists and has been run —
   but only on a 16-core arm64 Mac, which is the opposite of the device the
   criterion names. Until it is re-run, "performance is measured, not assumed"
   is not yet true. B-1's own unmet acceptance requirement (#2010).
2. **UC-A3.4's self direction is unit-only.** Both live notify tests are
   alice→bob; the alice1→alice2 case is asserted against a `MockAtClient`. The
   plan claimed both A3.4 and A4.4 were live-covered — corrected. It is now
   *owed rather than blocked*: the harness limitation the issue cites
   (`AtClientManager` being a singleton) was removed by `ConcurrentClients` and
   `EnrolledClient`, so the assertion is writable today (#2093).
3. **SS-4: an interrupted mint does not resume.** The acceptance bullet asks
   that it resume rather than re-generate; there is no persisted in-progress
   marker, so it starts over. Worth deciding whether that is still required —
   the mint lock and the immutable create may already make re-generation safe,
   and the acceptance text predates both (#2087).
4. **IS-1's record name drifted from its issue.** Deliverables 1 and 3 name
   `pq_signing_publickey@<atSign>`; that string appears nowhere in the
   implementation. The issue needs correcting against the code before anyone
   builds on it, and its PR needs a re-review after the pare-back (#2049).

**The general lesson, which is why this is a numbered entry rather than four
comments.** A project's issue and the plan's project entry drift *independently*,
and both drift away from the code. Three of the four above were invisible from
the plan alone, because the plan records what a project set out to do and the
issue records what someone thought it had done. Reading a project's own
deliverable list against the code is a different check from reading the plan,
and it found things the plan's own owed-tables had lost.


### 14.15 Pre-PR rails checklist

No PR opens against this branch until the published atServer image verifies
ML-DSA PKAM (owner's call, 2026-08-08). One thing must still be true by then:

> ~~The functional pack's compose hardcodes a local image, so CI's
> `docker compose pull` kills the job~~ — **done, verified 2026-08-10.** All
> three packs now commit `image: ${VIRTUALENV_IMAGE:-atsigncompany/virtualenv:vip}`
> (functional `docker-compose.yaml:13`, e2e `:14`), and each `runLocal.sh`
> exports `VIRTUALENV_IMAGE="${VIRTUALENV_IMAGE:-at_virtual_env:local}"` and
> skips `docker compose pull` for a name containing no `/`. A clean checkout
> and CI therefore resolve the published image with no environment set, while
> our runs opt into the local build. **Nothing needs reverting before a PR.**

1. **The `pqe2e_tests` CI job is written but UNVERIFIED.** Nothing has run it
   end to end, because no published image supports the tests it runs. Run it
   once the image lands, before trusting it. An image without PQ support fails
   at authentication with a server-side
   `AT0010-Exception: RangeError (length): Invalid value: Not in inclusive range 0..47: 48`
   from `AtLookupImpl.pkamAuthenticate` — that signature means the image, not
   the client.


### 14.14 A client with no enrollment id is treated as fully privileged

`AtClientImpl._resolveFullPrivilege()` returns **true unconditionally when
`enrollmentId == null`**, and `ApkamSigning.enrollmentId` substitutes the
sentinel `'primary'` when there is none. So a legacy PKAM client that happens to
hold an `AtKeysIo` publishes `public:_apsk.primary.a.__e@<atSign>` and signs
approval-chain links as `"primary"`.

Found while surveying for [14.13](detail/implementation-plan.md#1413-a-passive-by-default-flag-surveyed-not-built),
and worth separating from it: a flag would *hide* this rather than resolve it.
The question is whether an owner-keys client should be in the enrollment trust
chain at all, and if so under what identity — `'primary'` is a name no
enrollment record carries.


### 14.12 A `mintLegacyMaterial:false` atSign cannot write a public record

Found 2026-08-08 by UC-B4.2's opt-out arm, the first thing ever to activate an
atSign that way and then use it. The opt-out works exactly as designed at
activation — no RSA keypair is minted, no `public:publickey` is published, and
`completeActivation` says so — but the resulting atSign cannot then publish
anything, because **every public write is signed with the legacy encryption
private key**
(`put_request_transformer.dart` `_signPublicData` throws
`AtPrivateKeyNotFoundException('Failed to sign the public data')` when it is
absent). Two things the post-quantum path itself needs are public writes: the
enrollment's `_apsk` anchor to the signing root, and the nskey advertisement.
Both fail, live and logged, on an opt-out atSign. Sync fails alongside them —
"Self encryption key is not set for current atSign" — because there is no
`selfEncryptionKey` either.

So `mintLegacyMaterial: false` is a switch that exists and is honoured but is
**not yet a usable configuration**, which matters because
[decisions 42](detail/decisions.md#42-the-to-define-list-ruled-2026-08-05) item 10 has
the release default resolving null→false in the major after R-2. Closing it means public-record signing moves onto the
ML-DSA signing root rather than the RSA encryption keypair — the same swap
IS-1 made for inter-server auth — and self data moves off `selfEncryptionKey`
onto the nskey path (B-3 phase 1). Neither is scheduled here; the point of this
entry is that the stop-release cannot ship before both are, and that the
`mintLegacyMaterial` flag must not be recommended to anyone until then.

Asserted, rather than merely noted, in the opt-out arm of
`tests/at_functional_test/test/pq_legacy_interop_live_test.dart`: it expects the
public write to fail with that exact reason, so whichever project fixes this
gets a red test naming the row that was waiting for it.


### 14.11 `deprecated_member_use` findings across the workspace

Everything else `dart analyze` reported is cleared (`3e3ac1075`); at_chops and
at_commons are clean outright. What remains is live use of
deprecated-but-still-required APIs — the `AtChops` compatibility shim,
`AtSigningInput`, `apkamPublicKey` — so clearing them means migrating call
sites, which is a code change rather than a lint sweep and wants its own pass.

**Re-measured 2026-08-13** (the heading said 299 and named only at_client). Per
package, `dart analyze lib test` from each package directory, counted with
`grep -c deprecated_member_use`:

| package | findings |
|---|---|
| `at_client` | 340 |
| `at_onboarding_cli` | 183 |
| `at_auth` | 110 |
| `at_lookup` | 28 |
| `at_chops`, `at_commons` | 0 |

⚠️ **Scope this before starting it — a straight "migrate off the deprecated
member" sweep is not available for the PKAM signing path.** `PkamSigningAlgo`
and `PkamMlDsa65SigningAlgo` are both deprecated *classes*, and so are
`AtChopsImpl`, `AtChopsKeys`, `AtSigningInput`, `AtSigningMode` and
`AtPkamKeyPair`. Non-deprecated key material *does* exist —
`RsaSignatureAlgo`, and `MlDsa65PureDartAlgo.signBytesSync`/`verifyBytes` with
explicit keys — so what is missing is not a replacement but the **dispatcher**:
nothing non-deprecated selects an algorithm from a `SigningAlgoType` the way
`AtChopsImpl.sign` does in pkam mode. A caller wanting both algorithms writes
the two-way branch itself.

And the RSA arm is not a free swap: the atServer's `ApkamSignatureVerifier`
records that **`RsaSignatureAlgo` refuses any modulus that is not exactly 2048
bits, which `PkamSigningAlgo` does not**, so adopting it would stop an
enrollment holding an off-size RSA key from authenticating. That is a change to
what verifies on the authentication path, not a refactor. Any sweep that
touches signing has to decide this deliberately; the rest of the findings
(models, `apkamPublicKey`, collection APIs) are ordinary migrations.


### 14.7 NoPorts carries its own copy of the envelope shape

`sshnoports/packages/dart/noports_core/lib/src/common/validation_utils.dart`
produces the same `{payload, signature, hashingAlgo, signingAlgo}` shape with
the same re-encoding behaviour. It does not import at_client's functions — it
signs with the encryption keypair and fetches `getRemotePK` rather than
`_apsk` — so a migration here does not break it. But "nobody has this shape
deployed" is wrong, and if the pitch becomes "our envelopes are RFC 7515" then
NoPorts is a separately-owned second migration to name rather than discover.


---

## PARKED

Set aside deliberately. A row here exists to stop someone building it, so
the reason is the point of the row.

| Item  | What it is                                      | Why it is parked                                                                                    |
|-------|-------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| 14.1  | The signing root's `keys[]` shape               | SUPERSEDED by decisions 101 and 14.22. Kept for the reasoning; two of its conclusions are now false |
| 14.13 | A passive-by-default flag                       | FOLDED AWAY 2026-08-11 into the rollout axis (14.18 step 19). Kept for its survey                   |
| 14.21 | The signing root cannot be rotated              | RULED the same day by decisions 101. Kept so 14.22 is legible against it                            |
| 14.23 | The nskey mint stops needing a winner           | ⛔ HELD — do NOT build. decisions 105 supersedes it; 104 states what would revive it                 |
| KE-2  | `enroll:update` + a multi-kpid receiver         | Blocks the two skipped acceptance rows. Issue #2133                                                 |
| B-3   | `selfEncryptionKey` + `shared_key.*` retirement | Ecosystem-gated by decisions 37. Issue #2128                                                        |
| KF-1  | `.atKeys`-at-rest protection + backup/restore   | Off the GA critical path. Issue #2129                                                               |
| S-5   | at_auth 4.0.0 WASM barrel split                 | Off the GA critical path                                                                            |
| S-6   | Consumer constraint bumps onto at_auth ^4.0.0   | Follows S-5                                                                                         |
| R-2   | at_client 4.0.0 posture defaults                | After D1. A pure default-flip: 4.0 is identical to final-3.x code                                   |
| D2-1  | Carve `at/pqmls` + D1-E shape fixes             | D2, out of D1                                                                                       |

---

## DONE

One row each; the detail is in
[`detail/implementation-plan.md`](detail/implementation-plan.md). The third
column reports what the plan **records**, which is not always what was
measured — see [14.25](#1425-three-projects-state-partial-completion-and-six-state-none).

| Item   | What it delivered                                       | State as the plan records it                                                                                         |
|--------|---------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------|
| P-1    | at_chops stateless core + HPKE                          | SATISFIED — at_chops 3.3.0 published 2026-06-23                                                                      |
| P-2    | `mldsa65` wired into the verification branch            | SATISFIED — published 2026-07-17                                                                                     |
| P-3    | `public:pqpublickey` + X-Wing-preferred enrollment wrap | No status stated — see [14.25](#1425-three-projects-state-partial-completion-and-six-state-none)                     |
| S-1    | at_auth `AtKeys`/`AtKeysIo` extended in place           | SATISFIED — at_auth 3.3.0 published                                                                                  |
| S-2    | `CryptoContext.keys` additive field                     | SATISFIED on trunk 2026-07-17; residual is the at_client publish                                                     |
| S-3    | Updatable `.atKeys` / keychain via injected `AtKeysIo`  | States PARTLY LANDED — see [14.25](#1425-three-projects-state-partial-completion-and-six-state-none)                 |
| SS-0   | WP-SS substrate baseline                                | SATISFIED — merged 2026-07-17                                                                                        |
| SS-1a  | at_commons enroll grammar + flattened `listns`          | SATISFIED — at_commons 5.12.0 published 2026-07-04                                                                   |
| SS-1b  | atServer stores/returns `EnrollParams.metadata`         | SATISFIED — merged 2026-07-07                                                                                        |
| SS-1c  | Client wired to the live verbs + flattened parser       | States live drive owed — see [14.25](#1425-three-projects-state-partial-completion-and-six-state-none)               |
| SS-2   | Substrate wired into AtClient + server wake-up          | No status stated — see [14.25](#1425-three-projects-state-partial-completion-and-six-state-none)                     |
| SS-3   | Substrate hardening + `signingAlgo` verify              | LANDED — at_server#2739 merged 2026-08-10                                                                            |
| SS-4   | nskey minting + signing-root lifecycle                  | States ABOUT HALF LANDED — see [14.25](#1425-three-projects-state-partial-completion-and-six-state-none)             |
| B-1    | The nskey data path — providers + cold start            | No status stated; the D1 centrepiece — see [14.25](#1425-three-projects-state-partial-completion-and-six-state-none) |
| RF-1   | `requestSecret(name)` confirm                           | No status stated — see [14.25](#1425-three-projects-state-partial-completion-and-six-state-none)                     |
| RF-SRV | atServer authenticated self-retrofit enroll             | No status stated — see [14.25](#1425-three-projects-state-partial-completion-and-six-state-none)                     |
| RF-2b  | PQ ML-DSA APKAM mint + self-retrofit                    | LANDED 2026-08-05 (decisions 43)                                                                                     |
| RF-2c  | Retrofit orchestration + full e2e                       | LANDED 2026-08-05 (decisions 44)                                                                                     |
| R-1    | `disallowLegacyEncryption`                              | DELIVERED 2026-08-05; scope shrunk by decisions 36                                                                   |
| SH-1   | Key-material self-heal                                  | LANDED 2026-08-05                                                                                                    |
| B-2    | nskey rotation + revocation                             | LANDED 2026-08-06                                                                                                    |
| KE-1   | Selectable KEM + negotiated construction                | LANDED 2026-08-07                                                                                                    |
| ON-1   | PQ-native greenfield onboarding + opt-out               | ACCEPTANCE COMPLETE 2026-08-08 (decisions 52)                                                                        |
| IS-1   | Inter-server FROM/POL signature swap RSA → ML-DSA-65    | PR #2683                                                                                                             |
| 14.2   | A version on the two signed payloads                    | DONE — `3c2eddbe6`                                                                                                   |
| 14.3   | JWS for the signed envelope, one shape, no flag         | DONE 2026-08-09 (decisions 60)                                                                                       |
| 14.4   | A `suites` list on the key package                      | DONE — `1688ed69d`, corrected `c9f8580da`                                                                            |
| 14.5   | Write-side envelope version selector in at_chops        | DONE — `1688ed69d`                                                                                                   |
| 14.6   | `metadata.keyPackage` stops being a one-way door        | Client caller landed 2026-08-13                                                                                      |
| 14.8   | Domain separation on the signed envelope                | DONE 2026-08-15 (decisions 103)                                                                                      |
| 14.9   | A revoked enrollment could still authenticate           | ROOT-CAUSED 2026-08-12; fixed in at_server `16dd457f`                                                                |
| 14.10  | UC-B0.1 needed a legacy atServer image                  | RESOLVED 2026-08-08 via the `vip-p3.15.0` pin                                                                        |
| 14.20  | Building rulings 98 and 99                              | DONE — every row built; owes nothing                                                                                 |
| 14.22  | Making the signing root rotatable                       | DONE 2026-08-15 — all seven rows                                                                                     |

---

## Re-deriving the state


Run these rather than trusting the table. Each answers one row.

```bash
# row 1: which 14.22 rows have landed? Row 1 landed when this file started
# composing apskAdvertisement; row 2 is unbuilt for as long as the prefix
# still names one algorithm.
git grep -n "keyIdPrefix =\|apskAdvertisement" -- packages/at_client/lib/src/crypto/nskey/

# row 11: which 14.19 items are still open? (~~struck~~ ones are done)
awk '/^### 14.19 /,/^#### 14.19.1/' docs/projects/pq/implementation-plan.md \
  | grep -E "^[0-9]+\. \*\*"

# rows 3-9: the stage-5 table, which owns steps 23-31
awk '/^\*\*Stage 5/,/^\*\*Stage 6/' docs/projects/pq/implementation-plan.md

# acceptance: what is skipped, and on which blocker.
# Anchor on "}, skip:" — a bare "skip:" also matches catalogue_test.dart's and
# manifest.dart's prose ABOUT skips and reports 5 where the answer is 2.
grep -rn "}, skip:" packages/at_client/test/acceptance/*_test.dart
grep -n "blocked:\|owed:" packages/at_client/test/acceptance/blockers.dart

# row 2 and row 12: the external gates. The at_auth release is a pub.dev
# question; the atServer image gate is gkc's call and is NOT to be checked
# against atsigncompany/virtualenv:vip (ruled 2026-08-13).

# rails, all four packages. EACH FIGURE CARRIES THE COMMIT IT WAS MEASURED AT —
# a block with one date at the bottom invites reading every number as current,
# and three of these five were re-measured 15 commits after the other two.
cd packages/at_client         && dart analyze lib test       # exit 0, 351 info  @92e859e52
cd packages/at_client         && dart test --concurrency=1   # 1344 (2 skipped)  @92e859e52
cd packages/at_client         && dart test test/acceptance --concurrency=1  # 66 (2)  @92e859e52
cd packages/at_auth           && dart test --concurrency=1   # 312              @7c6b3e7f2
cd packages/at_onboarding_cli && dart test --concurrency=1   # 39               @7c6b3e7f2
cd tests/at_functional_test   && ./runLocal.sh               # 165/165          @7c6b3e7f2
# ⚠️ The functional 165/165 was measured against the virtualenv image as it
# was BEFORE `at_virtual_env:local` was rebuilt, so it is not a claim about the
# image on this machine now. Rebuild-and-re-run before treating it as current.
# Every figure in this project has been wrong at least once by being carried
# forward — the COMMAND is the value here, not the number beside it.
```


### After D1

The release programme, in order, and **not** part of D1 initial development:
publish **at_chops 3.6.0** → **at_commons 5.16.0** → **at_auth 3.4.0** →
**at_client's GA minor** → **R-2**, the 4.0.0 posture flip (a pure
default-flip: 4.0 is identical to final-3.x *code*).

⚠️ Check pub.dev against every touched pubspec before acting on that ladder —
a same-value version bump merges silently.

⚠️ **The first rung is contested and this line is not the ruling.** gkc has
ruled *in principle* that at_chops' next release should be a **major**, not
3.6.0: 3.6.0 carries two source-breaking changes. The 4.0.0 bump was built and
**reverted** on 2026-08-13, so the decision exists in principle and not in the
tree, and nothing in TODO owns it. Settle it before publishing at_chops, and
note that six constraints must widen together or `pub get` fails, and at_lookup
needs at_chops 3.6.2.
