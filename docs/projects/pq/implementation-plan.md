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

When an item finishes, move its detail to `detail/implementation-plan.md` and
leave the row here. That is a judgement about *state*, not about length — this
file carried a line ceiling until 2026-08-17, and it made size the trigger for
a demotion that should follow completion.

⚠️ **Re-derive before acting on any row below.** Every "current state" table in
this project has been wrong at least once by being carried forward; the
commands that re-derive these are in
[Re-deriving the state](#re-deriving-the-state) at the end.

**D1 initial development ends at step 34** — the spike carved into stacked PRs
and merged. Publishing and R-2 follow it and are not D1.

---

## THE NEXT MOVE

⛔ **This is the one ranked list, and it lives here.** Memory holds a single line
pointing at it and no detail. `## TODO` below is *what is owed*, unordered; this
is *what to do first*. Re-read this section against `git log --oneline -10`
before acting — it has led with finished work before.

Last re-ranked **2026-08-20** against the tree at `31fb4a241`.

⚠️ **A second workstream is now open and is NOT in this table** — the knowledge
base, agreed with gkc 2026-08-20. Its plan, format, rail design and ordered
method are in [`docs/knowledge/README.md`](../../knowledge/README.md), which is
a scaffold with no nuggets written yet. If that is what you are here for, open
that file instead; the list below is the PQ release work.

1. **[RECOMMENDED] Publish at_chops 3.6.0 to pub.dev.** #2169 **merged**
   2026-08-20 as `c4c581834` — approved by Xlin123, CI 47/47, and an
   adversarial re-review confirmed every fix and every argued reply before the
   merge (its one finding, an unrecorded promise, is delivered in ruling 110's
   addendum). Merged is not published, and the train's gate is the publish:
   nothing after at_chops can declare `at_chops: ^3.6.0` until it is on
   pub.dev. No workflow in this repo publishes to pub.dev (checked
   `.github/workflows/` 2026-08-20), so the publish is a maintainer step —
   gkc's.
2. **Carve at_lookup** — train position 3. Recipe is in
   [14.18](#1418-the-remaining-d1-initial-development-sequence); the carve gate
   is `git -C /tmp/carve-<pkg> diff gkc-pq-d1-spike --stat -- packages/<pkg>`
   returning empty. It can be **carved** now but **not published**: at_lookup
   declares `at_commons: ^5.16.0` and pub.dev's at_commons is still 5.15.0.
   Re-derive that before assuming, with the command in
   [Re-deriving the state](#re-deriving-the-state).
3. **Diagnose [14.43](#1443-the-functional-suites-convergence-race) from the
   two reds captured 2026-08-20.** The missing evidence exists: a local pack
   log (`untracked/pq-1443-packs/run_4_20260820_223443.log`, this machine
   only) red in `atclient_sync_conflict_test` with `conflictInfo` null where
   the pull reported success, and CI run `32418455392`'s beta functional red
   in UC-G1.15 — an rsa2048 envelope signature that does not verify against
   the one key the published `_apsk` advertises. Both signatures and the
   provenance are recorded in the section. Read the disproven-hypotheses lists
   there before forming a new one.
4. ~~Decide `executeVerb`'s inert `sync` parameter~~ **Done 2026-08-20**
   ([14.46](#1446-executeverbs-sync-parameter-is-inert-on-both-secondaries)):
   `@Deprecated` for 3.x on all six declarations (at_client and at_lookup),
   removal owed at 4.0.

**Blocked, and what lifts it:** publishing anything past at_chops waits on
at_chops 3.6.0 reaching pub.dev — #2169 is merged, so only the publish itself
remains. at_lookup's publish additionally waits on at_commons 5.16.0.

⚠️ **CI on this branch is behind HEAD, and cannot catch up by itself.** Nothing
fires on push here — the workflow is `workflow_dispatch` only on this branch —
so the newest run is as new as the last manual dispatch and no newer. The
2026-08-20 dispatch on `cfd511663` (run `32418455392`) **failed three jobs**:
both `unit_at_client` channels on the `dart format` gate — three files, fixed
in `be1fb9172` — and `functional_tests (beta)` on UC-G1.15, which is a 14.43
instance and is captured as evidence there, not a new defect. A fresh dispatch
on `31fb4a241` (run `32421422064`) was queued the same evening; read its
conclusion rather than this sentence. Dispatch before treating the branch as
green, and compare the two SHAs rather than reading a conclusion:

```bash
gh workflow run at_client_sdk.yaml --ref gkc-pq-d1-spike
gh run list --branch gkc-pq-d1-spike --workflow at_client_sdk.yaml --limit 1 \
  --json headSha,conclusion --jq '.[] | [.headSha[0:9], .conclusion] | @tsv'
git log --oneline -1
```

⚠️ **Three `## TODO` rows below are finished and still render as owed** —
**14.41** (all four red CI rows fixed; its remainder moved to 14.42 and 14.43,
which have their own rows), **14.45** (both halves fixed; only an out-of-repo
residual remains) and most of **14.39**. You learn that only by reading to the
end of each cell. They want demoting to `## DONE` with their detail moved to
`detail/implementation-plan.md`, per this file's own convention — not done here
because a wrap-up is the wrong place to move anchors the acceptance rail parses.

---

## TODO

| Item                            | What is owed                                                        | Blocked on                                                                       |
|---------------------------------|---------------------------------------------------------------------|----------------------------------------------------------------------------------|
| [14.18](#1418-the-remaining-d1-initial-development-sequence) | Steps 32–34: the per-package release train. ✅ **at_commons PR #2168 is MERGED to trunk** (2026-08-20) and the spike's at_commons is now byte-identical to trunk. at_chops **PR #2169** is raised and green. Next: at_lookup, at_server_status, at_auth, at_client (stacked), at_client_flutter, at_onboarding_cli | ⚠️ **MERGED IS NOT PUBLISHED, and at_lookup is gated on the difference.** at_lookup declares `at_commons: ^5.16.0` because it reads `AtNetworkTimeouts.defaultResponseBudget`, and pub.dev's latest at_commons is still **5.15.0** — re-derive, never quote: `curl -s https://pub.dev/api/packages/at_commons | python3 -c "import sys,json;print(json.load(sys.stdin)['latest']['version'])"`. So at_lookup can be CARVED now and cannot be PUBLISHED until at_commons 5.16.0 is on pub.dev |
| [14.18](#1418-the-remaining-d1-initial-development-sequence) | Step 20's rotation arm — enrollment then an `enroll:update` APKAM rotation mid-run | An at_auth release carrying the tolerant reader, then the staged status value. Needs its own CRAM atSign |
| [14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) | **17** open small items of 36 — the items are in `detail/`, none of them blocking. Re-derive rather than quoting: this row said 17 while the count was 10, then 15 while the count was 18, and the comment beside the command said 17 for two days after the row was fixed | Item 8 is the only one waiting on a ruling. Items 20 and 21 are examined-and-left, not work. Item 35 lands in `atGettingStarted`, not here |
| [14.16](detail/implementation-plan.md#1416-four-residuals-the-issue-tree-audit-surfaced-2026-08-09) | Three audit residuals — UC-A3.4's live self-direction was the fourth and is done | — |
| [14.14](#1414-a-client-with-no-enrollment-id-is-treated-as-fully-privileged) | A client with no enrollment id is treated as fully privileged | Wants a ruling on whether an owner-keys client belongs in the enrollment trust model |
| [14.12](#1412-a-mintlegacymaterialfalse-atsign-cannot-write-a-public-record) | A `mintLegacyMaterial:false` atSign cannot write a public record | Two moves its body names, neither scheduled: public-record signing onto the ML-DSA signing root, and self data off `selfEncryptionKey` onto the nskey path (B-3 phase 1). ⚠️ This cell read "Gates the stop-release" until 2026-08-18 — which is what 14.12 *blocks*, so anyone scanning this column for what is ready to start misread the row as ready |
| [14.41](#1441-what-the-first-ci-runs-on-the-spike-branch-found) | **ALL FOUR red rows are fixed and CI is fully green** (run 32392240064, 11 of 11, on `f24ee3ab6` — the head with **origin/trunk merged in**, so it covers at_commons #2168 and the 15 commits trunk brought). Only ONE of the four was a product defect; two were harness assumptions holding by luck and one was a CI step running the wrong image. What remains from this section is the convergence RACE and the two items below it | Nothing |
| [14.42](#1442-why-enrollment-setup-takes-four-minutes) | **Why `enrollment_setup.dart` takes ~4 minutes.** Measured at 3:56 and 4:59 against the @ce2e atSigns; 30 seconds is nowhere near enough and the budget is now 15 minutes, which hides rather than explains it. gkc asked for the cause, 2026-08-20. ⚠️ My sync-backlog reading is NOT established — `end2end_tests` runs the same four atSigns and the same suite in ~3 minutes | ⛔ **@ce2e-only — it does NOT reproduce locally, and this cell said it did.** `runLocal.sh` regenerates `config/config.yaml` from at_demo_data, and against demo atSigns the same four enrollments take about ONE SECOND — a local run reproduces the symptom's ABSENCE. The ~3-minute local repro belonged to a DIFFERENT and already-fixed defect (14.41 row 3's cache key). Reaching this one needs `config14.yaml` and the @ce2e keyfiles, i.e. a CI round trip, and nothing here records how to get those locally |
| [14.43](#1443-the-functional-suites-convergence-race) | **The functional suite's convergence race** — 1 red in 4 local runs, ~1 in 6 in CI, four distinct tests, all update/notify/sync convergence. Six hypotheses disproven and listed. Also here: `FunctionalTestSyncService.syncData()` calls `syncOutcome.complete()` on `SyncStatus.failure`, so a FAILED sync returns to its caller as success — a separate defect that did not cause this race but will hide something | Nothing. Reproduces locally: `cd tests/at_functional_test && ./runLocal.sh` |
| [14.47](#1447-the-at_client-unit-tree-has-a-cross-file-isolation-flake) | **A unit-tree isolation flake**: `local_secondary_sync_queue_test.dart` failed 1-in-4 when run after the nskey/pq files in one non-alphabetical invocation — a same-file test's queue entry leaked into a later test, so the per-test store isn't always fresh. Green alone, green in the full suite | Reproduce at rate (~10 runs of the four-file order), then read the file's setUp for what makes the store per-test fresh |
| [14.46](#1446-executeverbs-sync-parameter-is-inert-on-both-secondaries) | **`executeVerb`'s `sync` parameter does nothing** — declared, never read, on at_client's both secondaries AND at_lookup. **Decided and phase 1 shipped 2026-08-20**: `@Deprecated` on all six declarations for 3.x, removal in 4.0; every cross-package and every prose-reasoned call site cleaned. Still in the section: a stale at_server comment #2169 will falsify, and the untracked `post-quantum-cryptography.md` | **Removal at 4.0** — delete the parameter from all six declarations and let the compiler enumerate the ~76 remaining same-package sites |
| [14.45](#1445-an-expired-key-the-client-cannot-delete-pins-it-in-a-hot-loop) | ✅ **The spin is FIXED** — a sweep that removed nothing now backs off 30s instead of re-arming at zero. Was: **225,721 failed sweeps across three `_nskeylock` records** in one local pack, **47.4%** of its log lines. Designed-in — `MintLock` releases by ttl alone (`mint_lock.dart:80`), so every mint and rotation makes another one. Pre-existing on trunk. ✅ **The refusal is fixed too** — it was a namespace check, not immutability, and the sweep now bypasses it. **Owed elsewhere:** the keystore's `get()` does not filter expired records (at_persistence_secondary_server, another repo) | Nothing. ⛔ **NOT the cause of [14.43](#1443-the-functional-suites-convergence-race)** — the run carrying all three loops was **green, 177/177**. A rate effect is not excluded; presence is. ⛔ Why the lock is synced to local storage at all is **parked** (gkc, 2026-08-20) |
| [14.44](#1444-residuals-from-the-at_chops-pr-review) | Residuals from the at_chops PR review, none fixable there: the passphrase envelope persists the salt and three costs but **not `hashLength`**; `XWingCore.combine` writes at hardcoded 32-byte offsets while sizing its buffer from actual lengths; and at_chops 3.6.0's CHANGELOG owes the resolution-skew sentence whose durable record is ruling 110's addendum | Nothing. The first belongs in the **at_auth carve** (train position 5), where that file is already being edited; the other two go whenever at_chops is next open |
| [14.11](#1411-deprecated_member_use-findings-across-the-workspace) | `deprecated_member_use` across the workspace | A call-site migration, not a lint sweep |
| [14.7](detail/implementation-plan.md#147-noports-carries-its-own-copy-of-the-envelope-shape) | NoPorts carries its own copy of the envelope shape | Separately owned — named here, not fixed here |
| [14.34](#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart) | `self_enrollment_retrofit_live_test.dart` failed once in five pack runs | Unexplained. Not a flake and not fixed — a rate, not a kind |
| [14.29](#1429-the-residuals-1425-surfaced) | SS-2's `__ssenv` and two small S-3 items — none blocking. Re-read 2026-08-18: B-1's residuals had shipped and S-3's migration test existed, so this row said **three B-1 residuals, three small S-3 items** against an actual none and two | — |
| [14.39](#1439-pqposture-and-the-rollout-it-drives) | `PqPosture` — **mostly DONE 2026-08-19**: the rename, the 3 postures, the posture-only refusal flag, the sender-side algorithm list and the CLI's `--posture` all shipped, live-green. **Client-driven retrofit at start is BUILT 2026-08-19**, sequenced into `_init` rather than re-pointing a live client; unit-green and **live-green** — functional 174/174 (after one 173/174 whose single failure was [14.34](#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart)), e2e pq 54/54, and the `legacy-server` arm 2/2 against the pinned `atsigncompany/virtualenv:vip-p3.15.0`. **Owed: public-data signature verification** (undesigned) | Nothing |

### 14.39 `PqPosture` and the rollout it drives

Design settled with gkc on 2026-08-18 and recorded as
[ruling 113](detail/decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18),
which carries the posture matrix, the 8 rulings and the reasoning. This row is
the work, which is large and touches at_client, at_auth and at_onboarding_cli.

**The class.** `ReleasePosture` becomes `PqPosture` with 3 pre-built constants
— `legacy` (default), `pqReady`, `pqActive` — and a program may build and
inject its own. `SigningRollout` is deleted, replaced by `authenticationKeyAlgorithm`
and `dataSigningKeyAlgorithms`. `mintLegacyMaterial` becomes an axis pinned true
in all three. Construction rejects `disallowLegacyEncryption` true where
`writesPqByDefault` is false, since such a posture refuses its own writes.

**The behaviour.** A posture is a floor and never downgrades: key material wins
for authenticating and reading. Nothing is needed for capping; the atServer's
720-hour grace already re-arms per sibling and exempts the first enrollment.

✅ **Client-driven retrofit at start is BUILT, 2026-08-19 — and it is SEQUENCED,
not a live re-point.** Asked whether there was a sequencing issue, gkc ruled the
retrofit is awaited inside `AtClientImpl._init`, before anything that derives
from the identity exists. The monitor, the sync service's own `RemoteSecondary`
and the encryption service are all built from the client's enrollment id *after*
`_init` returns, so settling it first makes them correct by construction. That
retires the live re-point, the atomic cache re-file, the bounded in-run retry
and the second startup pass. `AtClientImpl.retrofitIsDue` carries the
derivation; `retrofitIdentity` (split out of `selfRetrofit`, which could not be
called from `_init` without building a second client) carries the submission.
⚠️ **The success path has no UNIT coverage** — it needs a live atServer. What is
unit-pinned is the derivation (`retrofitIsDue`, across the posture matrix
including the downgrade arm) and the failure containment. Its live proof is the
packs, and they were run on 2026-08-19: e2e `retrofit_e2e_test.dart` and
`retrofit_retirement_e2e_test.dart` cover UC-B1.1/B1.2/B1.3 and UC-B2.1/B2.2,
and the `legacy-server` arm covers UC-B0.1's refusal against a pinned pre-PQ
atServer — the one path a refactor could silently turn from a refusal into a
success.

⚠️ **Two stale-reference hazards a live re-point would have to solve, found by
the same audit and recorded because sequencing sidesteps rather than removes
them.** `EncryptionService.remoteSecondary` is a stored, mutable field assigned
once at init; and `SyncServiceImpl` builds and holds `final` its **own**
`RemoteSecondary`, a second connection constructed from the enrollment id at
create time. Everything else reaches the remote through
`atClient.getRemoteSecondary()` at call time and is re-point-safe already.
Rebuilding the sync service instead of re-pointing it is contraindicated by an
incident recorded in `at_client_manager.dart` — two `SyncService` instances
against one Hive queue lost writes and surfaced as `bypasscache_test` timing out
in CI.

The original design, now superseded in part, was ruled with gkc
2026-08-19 and folded into
[ruling 113](detail/decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18)
ruling 2, which carries the mechanics. In short: the **same** `AtClient`
instance survives and its connections move; the instance cache is re-filed
under the new id; the internals are rebuilt and the old connections torn down
explicitly; a partial re-point is retried in-run with bounded backoff; a
connection records what it last authenticated as, on `AtConnectionMetaData`
beside `isAuthenticated`, with the time; a successful retrofit re-runs the
whole startup; "partial from `pqReady`" means no retrofit at all; the trigger
is derived from key material rather than stored; and the new enrollment reuses
the old one's `appName`, `deviceName` and grants verbatim.

⛔ **The monitor's move was built and then REVERTED** (gkc 2026-08-19), and the
reason is worth keeping. `Monitor.enrollmentId`, `Monitor.atChops` and
`Monitor.signingAlgoType` are all `final`, so "rebuild rather than mutate"
means the monitor object is *replaced* — and `currentListenerStateStream` hands
out that object's own controller, so every subscriber alive at the swap is left
on a stream nothing writes to again. noports' `sshnpd` holds exactly such a
subscription for the life of the daemon. A relay in `NotificationServiceImpl`
fixes it, and **a live re-point cannot be built without one**. Sequencing
removed every monitor replacement from the tree, so the relay guarded something
that can no longer happen and came out with `repointMonitor()`.

✅ **The stream audit was done, 2026-08-19, and is clean.** No
`StreamController` exists in `RemoteSecondary`, `AtLookupImpl`,
`OutboundMessageListener` or anywhere in at_chops, so the monitor was the only
object whose replacement orphaned a subscriber. What the audit *did* turn up is
below.

⚠️ **Two of the three blockers first recorded here were wrong**, and both for
the same reason — read off `AtClientPreference` and a function signature rather
than the layer that already stores the data. `appName`, `deviceName` and the
grants are all on the enrollment record via
`LocalSecondary.getEnrollmentDetails()`, which `PqClientBootstrap` already
calls; `AtClientImpl.atKeysIo` is a public getter and the bootstrap already
holds `_keysIo`. The blocker that was real — `selfRetrofit` returning a
different client — is what ruling 2 now answers.

⚠️ **This paragraph used to read "Nothing is half-built for this — `selfRetrofit`
has no production caller at all today; every call site in the tree is a test."**
It was true when written and survived the build as a literal truth with the
wrong effect, ~65 lines above this section's own row saying the retrofit is
BUILT. `selfRetrofit` itself still has no production caller — every call site
is an e2e or functional test — but `retrofitIdentity`, split out of it, is
called by `AtClientImpl._settleEnrollmentIdentity` on every client start.

✅ **The at_lookup half is DONE**, released as **3.7.0** (gkc's call
2026-08-19; in-tree 3.6.1 equalled published 3.6.1, so there was no in-progress
heading to fold under). `AtConnectionMetaData` gained
`authenticatedAsEnrollmentId` and `authenticatedAt`, set by every path in
`AtLookupImpl` that authenticates, and `Monitor._authenticateConnection` sets
the same fields on its own socket. Noted in passing: the builder field at
`at_lookup_impl.dart:563` is spelled `enrollmentlId`.

**The narrowing.** `disallowLegacyEncryption` becomes posture-only and its
`AtClientPreference` override goes, which overturns ruling 70's
individual-flags-win for that flag and **redefines R-2**
([#2016](https://github.com/atsign-foundation/at_client_sdk/issues/2016)) as
"the default posture becomes `pqActive`". That issue needs rewriting when this
lands.

**The lists.** Posture supplies defaults, `AtClientPreference` holds the values.

✅ **The sender-side list is DONE** — `PqPosture.sealsToKeyAlgorithms` and
`AtClientPreference.sealsToKeyAlgorithms`, identical in all three stages
because which KEM is acceptable is a deployment decision rather than a rollout
position ([ruling 50.3](detail/decisions.md#503-the-kem-is-configured-the-construction-is-negotiated)).
It is **ordering first**: a sender picks the first entry a recipient
advertises. Narrowing it is the deployment choosing to refuse, and the refusal
names both sides so a FIPS-only operator does not read their own configuration
as the recipient having published nothing. `NskeyResolver` refuses rather than
walking up to a broader namespace's key, since walking on would change the
content-key scope silently. Consulted at both sender-choice sites:
`NskeyResolver.resolve` (through `CkManager` and the era `CryptoConfig`) and
`PairwiseSecretSharing.sendEnvelope`.

⛔ **The receiver-side list is NOT part of this row** — ruled with gkc
2026-08-19. ⚠️ **This paragraph read "`AtClientPreference.keyEstablishmentAlgo`
stays singular" until later the same day, and that is no longer true: it was a
statement about THIS row's scope, not a permanent one.** The list landed in
KE-2 as `keyEstablishmentAlgorithms`, together with the writer that gives it
meaning — which is exactly why it was held out of this row. The
multi-key *reader* shipped 2026-08-13, so what widening it needed was the
**writer**: mint a second key, retire the first, republish. That is KE-2's
remaining half ([#2133](https://github.com/atsign-foundation/at_client_sdk/issues/2133),
effort L), with [#2135](https://github.com/atsign-foundation/at_client_sdk/issues/2135)
tracking the singularity. A list here before that writer exists would have
entries nothing acts on. Verification and decryption stay maximal and are never
posture-settable, so *reads are universal* holds by construction.

**The rename.** Every parameter, variable and class says whether it means the
PKAM authentication signing key or the data signing key. Scope is at_client and
at_onboarding_cli. at_chops' `AtSigningInput.signingAlgoType` is deliberately
left alone — 165 hits across 48 files, unambiguous in context, and it would open
an at_chops version ruling 109 avoided. Measured blast radius for the rest:
`PqPosture` 112 hits in 23 files, `SigningRollout` 77 in 20, `signingRollout`
77 in 19, `dataSigningKeyAlgorithms` 95 in 22, `retrofitAuthenticationAlgo` 13 in 6.
⚠️ The acceptance rows `UC-C1.x` and ruling 70 move in the same commit.

**The CLI.** ✅ **DONE.** `--posture legacy|pqReady|pqActive` on every command,
with **no default** — an unnamed posture leaves at_client's own, so the binary
is not pinned to the stage current when it was compiled. `--signingAlgoType` is
removed, and activation reads the posture's `authenticationKeyAlgorithm`
instead. There is no `--disallowLegacyEncryption` anywhere.
`at_onboarding_cli` majors when it takes at_client 4.x.

⚠️ **`pq_native_onboard_test.dart` set `preference.signingAlgoType` itself**, so
it asserted the value it had just written and passed whether or not the
resolution mechanism worked — the shape [14.38](detail/implementation-plan.md#1438-activate_cli-cannot-administer-a-pq-native-atsign)
recorded. It now names `PqPosture.pqReady` and nothing else.

✅ **The sibling-repo dependency is merged, and still unreleased.**
Client-driven retrofit rests on the atServer exempting the atSign's FIRST
enrollment from the retrofit cap. That merged as at_server **PR #2755** on
2026-08-18 (`c2260e640`) and is on at_server `trunk`, so the design gate is
lifted. It is in **no release** — at_server's newest tag is `c3.16.1` of
2026-08-13 — so **test against a freshly built `at_virtual_env:local`**;
`atsigncompany/virtualenv:vip` cannot contain it and a green there proves
nothing about capping. Re-derive both halves:
`git -C ~/dev/atsign/repos/at_server grep -c preserveFirstEnrollmentOnRetrofit origin/trunk -- packages/at_secondary_server/lib`
and `gh release list -R atsign-foundation/at_server --limit 3`

**Public-data signatures.** ⚠️ **Nothing verifies `metadata.dataSignature`
today** — not at_client, not the atServer — so this builds the first verifier
rather than extending one. `pqActive` signs with the enrollment's data signing
key in the `_apsk` envelope form, and the verifier walks the signer's `_apsk`
through the approval chain to `pq_signing_root`. `pqReady` changes nothing.
Verification runs automatically on public reads, non-fatally, with the outcome
exposed; it wants the signer's `_apsk` cached or every public read pays a remote
lookup on another atSign. Both forms are read, and the legacy form permanently,
because every public record a released at_client signed sits on a live atSign.

### 14.40 at_client publishes as a minor, and the heading now says so

✅ **RESOLVED 2026-08-20. The tree already moved and this body did not say so
for two days.** `packages/at_client/pubspec.yaml` is `version: 3.15.0` and its
`CHANGELOG.md` opens `## 3.15.0` — a minor, which is what a source-breaking
entry needs. Verify rather than trusting this line:
`grep -m1 '^version:' packages/at_client/pubspec.yaml && head -1 packages/at_client/CHANGELOG.md`

What it was: raised 2026-08-18 by the `0x01` removal, which added a **BREAKING**
entry under an in-progress `## 3.14.1` heading. A patch version carrying a
source-breaking change was the conflict; the entry itself was correct and
stayed. ⚠️ The heading above read "at_client's in-progress heading is a patch"
until today, which a reader would take as the current state.

⚠️ **The question got bigger on 2026-08-19, not smaller.** 14.39 added four more
**BREAKING** entries under the same `## 3.14.1` heading — `PqPosture` replacing
`ReleasePosture`, `SigningRollout` deleted, `disallowLegacyEncryption` losing
its constructor argument, and `inUseSigningAlgorithms` renamed — plus a
**BREAKING** `--posture` entry under at_onboarding_cli's in-progress `## 1.17.0`.
So this is now two version questions, not one. The blast-radius argument is
unchanged and still bounded: none of that surface is published (at_client 3.14.0
on pub.dev carries no `ReleasePosture`, no `SigningRollout` and no
`disallowLegacyEncryption`), so no released consumer breaks — it remains a
numbering question.

The break is real: `SecretSharingAlgos.xWingHpke` is gone, `suites` and
`openableSuitesFor` no longer name it, and the `suites` list emitted on
`enroll:request` narrows. What it costs is bounded by the same argument
[decisions 109](detail/decisions.md#109-at_chops-360-stays-a-minor-no-major-bump-for-this-release-2026-08-18)
makes for at_chops — the substrate is `@experimental` and its only consumer is
this repository — so this is a numbering question, not a blast-radius one.

⛔ **Not acted on deliberately.** Version bumps are gkc's call and the standing
rule is to fold entries under the in-progress heading rather than open a new
one. Recorded here so the conflict is not discovered at publish time.

### 14.30 A content notification can outrun the key that opens it

Found 2026-08-16 writing UC-A3.4's self direction live
([decisions 106](detail/decisions.md#106-a-notification-that-outruns-its-key-is-dropped-not-parked-2026-08-16)).
A notification whose decryption needs an nskey private the receiver has not yet
**filed** is **dropped and never retried**, while the private is filed a
fraction of a second later and the envelope stays on the atServer for
`envelopeTtl`.

**Cause, measured 2026-08-17.** The push is built and on time: approval conveys
the private (`EnvelopeEnrollmentConveyance`), and the receiver reads and deletes
both of its `__ssenv` envelopes. What is missing is the **wait** — `AtClientImpl`
fires `unawaited(_pqBootstrap!.startup())`, and
`PqClientBootstrap._collectConveyedKeys` (*"the only route by which a conveyed
nskey private reaches the keyfile"*) is that startup's second step. A client is
handed to its caller before its conveyed privates are filed. Drop at `12.703`
with `no nskey private held`; the ring's read-miss self-heal fired at `12.819`,
**116 ms too late**.

✅ **RULED 2026-08-17 (gkc), and BUILT** — see
[106.5](detail/decisions.md#1065-ruled-park-and-re-drive-not-readiness-at-the-hand-back-2026-08-17).
Direction 2 was not taken on its own: awaiting `startupComplete` closes only the
startup window, and a private conveyed while the client is already running still
races.

**What shipped.** `NskeyPrivateUnavailableException` carries
`(owner, namespace, nskeyKid)` so the park has a key that is not a message
string; `SignalsPrivateFiling` — implemented by `PublishedNskeyKeyRing`,
emitting from `NskeyPrivateFiling` **after** the material is readable — is what
releases it; `CryptoConfig` now carries the `keyRing` so the notification
service can reach the signal without depending on which providers are
registered. The park is bounded by `maxParked` and `parkTtl`, and every
eviction logs at `warning` naming the notification, because a held message
nothing re-drives is the same data loss with a longer fuse.

Unit cover: `notification_park_test.dart` — five rows, including the two
controls that keep it honest (a failure no filing can fix is dropped rather
than parked, and a filing for a *different* generation releases nothing).
Removing the park reddens three of them, each quoting its own reason.

**Four vacuous live attempts preceded the proof below, and they are kept because
each one is a trap worth not re-entering.** ⚠️ This paragraph used to end "Not
proven live, and a live proof needs something that does not exist yet" — that
was true when written and is now false; the whole chain is proven live, further
down. What the attempts establish:

1. **Minting the nskey *after* the enrollments** — intended to leave the
   receiver without the private. It leaves the *sender* without a published
   nskey too, so the send falls back to `legacy`, the receiver opens it
   trivially, and the run is green with the park never entered.
2. **Minting before, and not awaiting the receiver's `startupComplete`** — the
   originally measured shape. Still green with `parkedTotal == 0`: the test's
   own positive control (waiting for the monitor's stats notification to prove
   the monitor is live) takes seconds, and the receiver's startup finishes
   inside it. **The setup closes the very gap the test exists to open.**

The window is ~116 ms and sits between an `unawaited` startup's second step and
a notification, so no arrangement of ordinary test setup reliably lands inside
it. ⚠️ **Both runs would have been recorded as live proof but for
`NotificationServiceImpl.parkedTotal`**, a cumulative counter added precisely so
that "it arrived" cannot be mistaken for "it was parked and released".

3. **A `holdBeforeStore` seam on `NskeyPrivateFiling`**, so the window is held
   open rather than raced. ⚠️ This entry used to end "reverted unexercised …
   committing it would have added a test affordance to production crypto that no
   test uses". It **was** reverted at the time, for that reason — and once the
   `legacy` cause below was found it went back in and is now exercised by the
   live row (`nskey_private_filing.dart`, used at the live test's hold). The
   seam is in the tree; only the attempt that could not use it was discarded.
4. **Reordering so the receiver enrols before the second namespace is minted
   and the sender after** — on the hypothesis that `currentPublic` being
   local-first hid the new namespace from the sender. Also still legacy.

✅ **THE PARK IS PROVEN LIVE**, in
`tests/at_functional_test/test/nskey_park_and_redrive_live_test.dart`. A real
notification, sealed `at/nskey/XWING/AES/GCM` to a generation the receiver
genuinely does not hold, is **held rather than dropped**:

```
Parked notification @alice🛠:parked….nskeyparkb…
```

The window is made deterministic by `NskeyPrivateFiling.holdBeforeStore`, a
test-only hook: the race is ~116 ms wide and four earlier attempts to catch it
by timing all passed while never entering the park.

⛔ **What made those four vacuous, so nobody repeats them.** The era default is
`readsNskeyWritesLegacy` — it reads the nskey path and **writes legacy** — so a
`notify` that does not pass `cryptoProviderId: symmetricAesGcmCryptoProviderId`
goes out legacy and the park is never reached. UC-A3.4's test passes it on one
line. Four live runs were spent not reading that line; one grep would have
answered it. The other dead ends: minting the nskey after the enrollments
(starves the sender too), and installing the hold after the second namespace is
minted (the receiver has already filed by then).

**Two real defects fell out of the live work, both invisible to unit tests:**

1. **The filing signal resolved the wrong config.** `_listenForFilings` read
   `getPreferences().crypto.keyRing` — the *raw* preference. An app that names
   no config gets the era default, whose ring the PQ bootstrap supplies, so the
   read found null and the service silently subscribed to nothing. Now via
   `CryptoConfig.forClient`, re-attempted at park time because the bootstrap
   wires the ring asynchronously. Unit tests set `crypto` explicitly, which is
   the one case where the raw read happens to work.
2. **Every client held TWO `NskeyPrivateFiling` objects.**
   `collectConveyedKeyMaterial` built its own unconditionally, so the object
   that actually files conveyed privates was not the one the ring exposes.
   Harmless while filing was write-only — both wrote the same keyfile — but the
   moment a filing gained an observable event, the emitter was unreachable.
   Measured: `hasListener=false` on the announcing object while three clients
   had each subscribed successfully to a different one. The bootstrap now passes
   `ring:` through and the sweep files through the ring's filing.

✅ **THE WHOLE CHAIN IS PROVEN LIVE.** The run shows it end to end:

```
Parked notification @alice🛠:parked…
handleRequest kind=request          (the holder sees and answers the ask)
Filed the nskey private nskeyparkb…:__nskey.b195…
re-driving 1 parked notification(s)
```

and the notification is delivered **decrypted**. Getting there took three more
defects, none of which a unit test could reach:

1. **`PairwiseSecretSharing.startListening()` had no production caller**, and
   `_handleRequestPayload` — which answers another enrollment's request — is
   reachable **only** from `sweepOnce`. So a client's only sweep was the one at
   its own start, a request arriving later was seen by nobody, and **no
   read-miss self-heal could complete for anyone**. `PqClientBootstrap` now
   starts the listener and `stop()` tears it down.
2. **A declined request returned silently.** A holder that refused logged
   nothing, so "nobody answered" was indistinguishable from "everybody
   declined". Now `warning`, naming both sides. Fixing the instrument first is
   what made the next step findable.
3. **The read-miss heal asked and never filed the answer.** This is the one that
   mattered. `_askForMissingPrivate`'s dartdoc claimed *"the answer is filed by
   the arrival path so a later read finds it"* — and **there is no such arrival
   path mid-session**: nothing subscribes to `receivedSecrets` to file an nskey
   private, and `NskeyPrivateFiling.filePending` says so itself (*"a private
   that arrives after this runs is filed at the next start"*). Two dartdocs in
   one subsystem contradicted each other and the ring's was wrong. The heal now
   waits for the answer and files it, exactly as the startup path already did.

⛔ **What made four earlier live attempts vacuous, so nobody repeats them.** The
era default is `readsNskeyWritesLegacy` — it reads the nskey path and **writes
legacy** — so a `notify` without
`cryptoProviderId: symmetricAesGcmCryptoProviderId` goes out legacy and the park
is never reached. UC-A3.4's test passes it on one line. Also dead: minting the
nskey after the enrollments (starves the sender too), and installing the filing
hold after the second namespace is minted (the receiver has already filed).

The window is made deterministic by `NskeyPrivateFiling.holdBeforeStore`; it is
~116 ms wide and every attempt to catch it by timing passed while never entering
the park. `parkedTotal` is asserted so a run that wins the race cannot pass
quietly.

### 14.31 A refused watermark write permanently disables the monitor

`Monitor.stayConnected` calls `getLastNotificationTime()` **before** issuing
`monitor:`, and its first-call branch **writes** a seed record
(`local:lastreceivednotification.<ns>@<atSign>`). Under
`disallowLegacyEncryption` that put throws `LegacyEncryptionRefusedException`,
the exception escapes to the connect handler, and the monitor closes and
retries with backoff — **forever**. The client is silently deaf. The same
refusal hits `lastreceivedservercommitid`, the sync watermark.

That these writes are refused is **already known and owed to R-2** —
`PqPosture.pqActive`'s own dartdoc names "the sync and notification
watermarks" among them. What is new is the blast radius: one refused internal
write does not fail one write, it takes the notification listener out
altogether.

**Measured** on `nskey_self_notify_live_test.dart` at `56f69577a`, three arms,
same rig:

| arm | `refusing to encrypt` | test |
|-----|----------------------|------|
| both enrollments `migration` | 0 | pass |
| receiver `postQuantum` | 10 | pass |
| both `postQuantum` | 18 | fail |

⚠️ The receiver-only pass is timing luck — ten refusals happened in it too. It
is not evidence that one PQ client is safe.

⛔ **Not PKAM**, which is where three earlier guesses went. Every enrollment
authenticates `rsa2048` under both postures, with no signing-algorithm
resolution warnings: `signingAlgoOf` prefers the key-material resolution, and
the posture moves the *signing* key, never the authentication key.

✅ **DONE 2026-08-17.** It was six related defects, not one, and the diagnosis
above named the symptom rather than the cause. Ruling
[107](detail/decisions.md#107-a-local-record-is-not-encrypted-and-the-legacy-refusal-exempts-it-2026-08-17)
carries the measurements; what shipped:

1. **A `local:` record no longer goes through the shared-data crypto path.**
   `_putInternal` and `PutRequestTransformer` skip it on `atKey.isLocal`. Such a
   record is never synced and the keystore encrypts it at rest, so value-level
   encryption protected nothing — while every post-quantum provider declines a
   local key, making *every* local write a legacy write by construction.
2. **`disallowLegacyEncryption` exempts `isLocal`.** It was refusing a provider
   **id**, not an exposure: for these keys "legacy" is `SelfKeyEncryption`,
   AES-256-CTR under a key that never leaves the device. A *synced* self key
   reaches the same class and is deliberately still refused.
3. **The SDK's own watermark writes pass `shouldEncrypt = false`** — the third
   layer, matching how the refusal is already checked at both selection and
   encryption time.
4. **`Monitor` no longer dies from it.** The watermark read has its own guard
   rather than sitting inside the connect `try` alongside four other
   operations, and a connect failure that is not a `SocketException` logs at
   `warning`, not `info`.
5. **The sync watermarks are guarded, and no longer mask.** The pull cursor is
   written in a `finally`, where a throw *replaces* the in-flight exception —
   so a failed cursor write was reported instead of whatever broke the sync.
   Extracted as `persistPullCursor`, whose contract is that it never throws.
6. **The notification watermark drops the payload and the metadata blob.** All
   twelve fields were stored and one is read. Older records still read back
   unchanged, so nothing migrates.

**Rails at the fix:** at_client unit **1386 (2 skipped)**, `dart analyze lib
test` exit 0 / 351 info, `dart analyze test` in `at_functional_test` exit 0 /
193 info. Twelve new tests, each with its break-it mutation run and confirmed
red *for its own stated reason*.

⚠️ One of those mutations found a defect in the tests rather than the product:
guarding `setAndGetSkipDeletesUntil` made a **stub-arity mismatch invisible** —
`sync_service_test.dart` stubbed `put(any(), any())` while production had begun
passing `putRequestOptions:`, so mocktail returned null, the write failed, the
new guard swallowed it, and the test reported success while persisting nothing.
It now verifies the call and its arguments.

⚠️ **This section used to claim a second half was still owed** — "namespace-less
keys that are not local, a legacy recipient's `shared_key.*` most obviously, are
still refused under the posture". That was wrong: nothing routes a
`shared_key.*` through the refusal, so it can never be refused. Closed as
[14.33](detail/implementation-plan.md#1433-closed-the-shared_key-refusal-was-never-reachable).
The one namespace-less write that genuinely is refused is
[14.35](#1435-notificationservicesend-throws-away-the-namespace-it-was-given).

### 14.32 A `primary` client's ML-DSA signing key is not visible to its verifiers

An approver built `pqActive` (so `dataSigningKeyAlgorithms = {mldsa65}`)
conveys correctly — both `__ssenv` envelopes are written — and the
receiving enrollment refuses every one of them:

```
the envelope is signed under "ML-DSA-65" and the published _apsk advertises
"rsa2048" — no algorithm in common, so there is no signature here this key
can check
```

`waitForApproval` then times out at 30s with *"No conveyed apkamSymmetricKey
arrived … the approver is running a client that does not convey"*, which names
the wrong side: it conveys, and what it wrote cannot be verified.

The approver is the atSign's own client, so it has **no enrollment id** and
mints under the `primary` pseudo-enrollment. It does mint and does try to
publish — `Minted mldsa65 signing key(s) for primary; publishing before
filing`, then `publishPublicSigningKey: what is published is not what this
client holds - republishing` — and `enroll:update` is sent **zero** times,
correctly, because there is no enrollment record to update. Yet a verifier
reading `public:_apsk.primary.a.__e@alice🛠` still saw `rsa2048` throughout the
30s.

⛔ **The transport question is ANSWERED, and the answer is no — do not
re-derive it.** This entry used to say the one open question was "by what
transport does the `primary` republish reach the atServer? A local-first put
reaches it only when sync gets round to it … a race by construction." Read
2026-08-17: **every leg of this path is remote-first.**

| leg | where | routing |
|-----|-------|---------|
| the writer's pre-read | `apkam_signing.dart:56` | `useRemoteAtServer = true` |
| the republish itself | `apkam_signing.dart:73` | `useRemoteAtServer = true` |
| all five verifier reads | `pq_signing_chain.dart` 224, 272, 403, 465, 637 | `useRemoteAtServer = true` |

So there is no value-and-pointer-on-different-transports race here, and no fix
should be designed around one.

**Also ruled out by reading, not by measurement:** signing and advertising
cannot drift on this path. `EnvelopeSigning.wrapAndSign` resolves
`await signingKeys` (`envelope_signing.dart:56`) and the advertisement is
composed from the same getter, which is what `signingKeys`' own dartdoc claims
("what signs and what is advertised are one rule and cannot drift apart").

**The cause, measured 2026-08-17 — it is a CLOBBER, in order, both writes
remote.** The arm was re-run with the approver built `postQuantum`, and the
atServer's own log for `@alice🛠` was read rather than the client's account of
it. The record starts absent (`AT0015 … does not exist in keystore`) and then
takes **four** updates:

| # | what the update wrote |
|---|-----------------------|
| 1 | a bare RSA public key (`MIIBIjANBgkqhkiG9w0B…`) |
| 2 | a bare RSA public key |
| 3 | **`{"v":1,"keys":[{…,"alg":"mldsa65",…}]}`** — the mint's republish |
| 4 | **a bare RSA public key** — overwrites 3 |

So the ML-DSA advertisement *is* published, and is then overwritten by a later
writer with the RSA fallback. A remote read taken **after** both republishes
returned the bare RSA key, which is what the verifier then refuses against for
the whole 30s. Nothing here is a transport problem; the final state is simply
the wrong value.

**The mechanism, confirmed by instrumenting `publishPublicSigningKey` and
re-running.** Every call logged what it held and what it was about to write:

| # | caller | `heldSigningKeys` | `value` passed in? | writes |
|---|--------|-------------------|--------------------|--------|
| 1 | `AtClientSecretSharing` | `[]` | no | bare RSA |
| 2 | `AtClientSecretSharing` | `[]` | no | bare RSA |
| 3 | `SigningKeyMinting` | `[]` | **yes** | **`mldsa65` JSON** |
| 4 | `AtClientEnvelopeSigner` | `[]` | no | bare RSA |

**`heldSigningKeys` is empty at all four**, so the minted signing key never
reaches the keyfile for `primary` at all. `signing_key_minting.dart:287` — the
only call that passes `value:`, and guarded by `atLookUp?.enrollmentId == null`
— advertises the minted key by handing the value in directly, which is what
"publishing before filing" means. Every other caller composes from
`publicSigningKeyValue`, reads an empty keyfile, falls back to the APKAM
authentication key (RSA), and publishes that over the mint's advertisement.

⛔ **STOP — this is [ruling 102](detail/decisions.md#102-an-_apsk-fallback-value-never-replaces-a-real-advertisement-2026-08-15),
already measured and already ACCEPTED.** `_publish`'s own dartdoc
(`signing_key_minting.dart` ~252) describes this exact sequence — "a concurrent
`publishPublicSigningKey` … sees no signing key, falls back to the APKAM
**authentication** key, and overwrites: measured, a PQ-native enrollment's
ML-DSA array replaced by a bare RSA string" — and records that **three guards
against it were built and all three broke the live enrollment path.** It warns
anyone tempted to try a fourth that "never drop an advertised key" cannot be
stated over `public:_apsk.primary.a.__e`, which no single client owns.

**So the record-level guard is a re-derivation. Do not build it without
re-opening 102.**

⚠️ **What is NOT yet established, and what an earlier version of this entry
wrongly asserted.** It claimed "it is not a timing window … the keyfile is empty
for the whole run". The evidence does not support that: `_file` **is** called,
at `signing_key_minting.dart:167`, immediately after `_publish`, so the empty
keyfile at all four calls is equally consistent with all four falling *inside*
the publish-before-file window — which is exactly what 102 describes. The
timeline is 20 ms wide:

```
07.117  Minted mldsa65 … publishing before filing
07.119  SigningKeyMinting   held=[]  -> writes mldsa65 (value: override)
07.155  … republishing
07.175  AtClientEnvelopeSigner held=[]  -> writes bare RSA
07.200  … republishing
```

**Ruling 102 has been re-opened on this evidence** — see
[102.1](detail/decisions.md#1021-the-race-is-measured-and-the-price-it-was-accepted-at-was-wrong-2026-08-17).
Two of its sentences were false and are corrected there: the race **is**
measured, and reaching it needs **no** application call racing `startup()` —
the ordinary approver flow does it every run. More importantly the *price* was
wrong: 102 accepted "one process lifetime of refused envelopes", where the
measured cost is that **a `postQuantum` approver cannot approve an enrollment
at all**.

⛔ **That does not revive the three guards.** Guard 3's finding stands: the
demotion rule cannot be stated over `primary`, a record no single client owns.

✅ **The filing works, so this is 102's window and nothing else.** Logging
`heldSigningKeys` immediately after `_file` returns gives `[mldsa65]`, with the
mint's `io` and `atClient.atKeysIo` the same instance. The keyfile does hold the
post-mint state; `AtClientEnvelopeSigner` simply read before the filing
completed.

✅ **DONE 2026-08-17 — fixed by serialising this process's `_apsk` writes**,
ruled and built as [102.2](detail/decisions.md#1022-the-in-process-window-is-closed-by-serialising-the-writers-2026-08-17).
`serialiseApskWrite` chains every `_apsk` write one client makes, and the mint
holds it across publish, file and retire together, so a writer arriving mid-mint
composes after the filing and finds nothing to change. It states in-process-only
and nothing more — a second client in another process is still 102's accepted
window. Re-entrancy is handled by splitting `publishPublicSigningKey` (acquires)
from `publishPublicSigningKeyLocked` (does not).

**Proven live on the arm that had never passed:** updates to
`_apsk.primary` go 4 → 2, the final value goes bare RSA → the `mldsa65` array,
`no algorithm in common` goes 2 → 0, and the test goes fail → pass. Unit cover
in `apsk_write_serialisation_test.dart`, whose ordering test reddens on the
exact interleave when the lock is removed.

⚠️ This is **not** [14.31](#1431-a-refused-watermark-write-permanently-disables-the-monitor).
That one is a refused internal write killing the monitor; this one is an
advertisement a verifier cannot see. Both surfaced from the same posture and
they have nothing else in common.

### 14.35 `NotificationService.send()` throws away the namespace it was given

`send()` takes a namespace as a parameter, builds a key string from it, and then
recovers the namespace by re-parsing that string
(`notification_service_impl.dart:578`):

```dart
final String key = '$to:$namespace$atSign';
final AtKey atKey = AtKey.fromString(key);
atKey.metadata.namespaceAware = false;
```

`AtKey.fromString` splits at the last dot, so the round trip is lossy in two
different ways. Measured, both arms, against a client under the postQuantum
posture:

```
send(namespace:"wavi")       => THREW LegacyEncryptionRefusedException
send(namespace:"buzz.wavi")  => selected at/symmetric/AES/GCM
```

A **single-segment** namespace parses to `namespace = null`, so every
post-quantum provider declines it (`canHandle` is `!isLocal && namespace != null
&& namespace.isNotEmpty`), the fallback is legacy, and the flag refuses it. A
**dotted** namespace parses to `key = "buzz", namespace = "wavi"` — it seals,
but to an nskey scoped to `wavi` rather than to the `buzz.wavi` the caller
named.

`send()` is the only write path that can reach this, because it is the only one
that bypasses the namespace defaulting every other path applies before
encrypting — `at_client_impl.dart:981` and `:1252`
(`atKey.namespace ??= preference?.namespace`) and
`notify_request_transformer.dart:122` (`ak.namespace ??= atClientPreference.namespace`).
`send()` encrypts inline and hand-builds its own `notify:` command string, so it
touches none of them. `AtRpc` sets `..namespace = baseNameSpace` explicitly and
goes through `notify()`, so it is unaffected.

**The fix, ruled by gkc 2026-08-17: the parameter is `<id>.<namespace>` and is
poorly named — that is the root of it.** The id is the first segment and the
namespace is the remainder, so `send()` splits at the **first** dot and sets
both `AtKey` fields itself instead of letting `fromString` do it. `namespace` is
deprecated in favour of `idAndNamespace`; a name with no interior dot, or with
either half empty, throws `ArgumentError` at the call site.

⚠️ **An earlier draft of this row recorded a one-line fix — "set
`atKey.namespace = namespace`" — and that was WRONG.** It would have broken
every `send()` that works today. The ciphertext binding is computed over
`'${atKey.key}.${atKey.namespace}'`, deliberately split-invariant so writer and
reader agree, and setting only the namespace changes the joined name. Measured:

```
                     sender          receiver (parses the wire)
today                "buzz.wavi"     "buzz.wavi"        match
+ namespace only     "buzz.buzz.wavi"  "buzz.wavi"      MISMATCH — nothing decrypts
+ namespace, key=""  ".buzz.wavi"    "buzz.wavi"        MISMATCH
first-dot split      "a.b.c"         "a.b.c"            match
```

The first-dot split holds for every case tried (`wavi`, `buzz.wavi`, `a.b.c`,
`id.foo.bar.my_app`) precisely because the join is split-invariant: the sender
cutting at the first dot and the receiver at the last produce the same name.
The wire key is unchanged, so this is not a cross-version break; what changes is
that the content key is conveyed at the level the caller named, and a receiver
that has not yet got it parks and re-drives
([14.30](#1430-a-content-notification-can-outrun-the-key-that-opens-it)).

`send()` is public, documented and not deprecated, and two example programs use
it (`example/bin/notifications.dart`, `example/bin/dockerstats_publish.dart`) —
both with dotted namespaces, so both take the wrong-scope arm rather than the
refusal.

### 14.36 `send()`'s command is hand-rolled where a tested builder exists

`send()` writes its own `notify:` command into a `StringBuffer` rather than
using `NotifyVerbBuilder`, which is what every other notification path goes
through. It is the duplication that let
[14.35](#1435-notificationservicesend-throws-away-the-namespace-it-was-given)
happen: the builder path resolves a namespace before encrypting, and `send()`
never reached it.

The swap is nearly free, but not free. Measured, same inputs:

```
hand-built today   notify:id:X:ttln:900000:isEncrypted:false:@bob:a.b.c@alice:payload
NotifyVerbBuilder  notify:id:X:notifier:SYSTEM:ttln:900000:isEncrypted:false:@bob:a.b.c@alice:payload
```

Byte-identical **except** `:notifier:SYSTEM`, which `buildCommand` writes
unconditionally. So this is a wire change, not a refactor, and it does not ride
along with a behaviour fix — it gets its own commit and its own functional-pack
run. The argument that it is safe (every `notify()` call already sends that
token, so the atServer sees it constantly) is an argument, not evidence.

⚠️ **`useAtKeyToString = true` is required.** With it false the builder writes
`:${atKey.key}`, and since 14.35 the name is split across `key` and `namespace`,
so the wire key would become `@bob:a@alice` — measured. `atKey.toString()`
yields `@bob:a.b.c@alice` under either `namespaceAware` setting.

**Built 2026-08-17.** The command is pinned as a raw literal rather than by
`contains` fragments — a wire shape is frozen, and an intended change has to
edit the pin, which is the review. A `contains` check would not have noticed
`:notifier:SYSTEM` arriving.

⚠️ **`send()` had NO live coverage at all, in either direction** — the pack's
168 tests never called it, so the first pack run after this change proved only
that nothing else regressed. `:notifier:SYSTEM` being safe rested on every
`notify()` already sending it, which is an inference, not an exercise of this
path. `atclient_notify_test.dart` now drives `send()` live: it asserts the
stored notification's key is the *whole* name (the wire half, which a builder
writing only `atKey.key` would truncate) and that the body arrives decrypted at
the recipient.

⚠️ **The architecture guard had to move with it, and the direction matters.**
`architecture_guard_test.dart` required `notification_service_impl.dart` to
mention `toAtProtocolFragment`, which the file no longer does — the builder
calls it. Keeping that assertion would have forced the hand-rolled command back,
so the guard now asserts the file does **not** contain `'notify:id:`. That is
what the guard was always for: not the presence of a name, but the absence of a
rival serializer. Verified against the previous commit, where the pattern
appears once.

### 14.34 An unexplained intermittent in `self_enrollment_retrofit_live_test.dart`

One full-pack run on 2026-08-17 came back **166/167**: the test timed out after
40 s at `await firstNotification`. **Five pack runs were made that day and only
that one failed** — the others were 167/167 and 168/168 ×3 — and the file passes
alone.

⚠️ **Very probably the same phenomenon as
[14.43](#1443-the-functional-suites-convergence-race), and the two rows were
written months apart without noticing each other** (linked 2026-08-20). Both are
intermittents in the FUNCTIONAL pack; both are waits on convergence — this one
times out at `await firstNotification`; both pass when the file runs alone. If
14.43 is worked, work this row with it: five files, one family, is a different
problem from five unrelated flakes. **Not asserted as identical** — nobody has
shown one cause covers both.

⛔ **Not a flake, and not fixed.** Nothing explains it. Five observations bound a
rate, not a kind, and "it was green before" is weak in the other direction too:
the 167/167 baseline it is measured against was itself a single run. Record any
further occurrence with its numerator and denominator rather than re-classifying
it.

**Recurred 2026-08-19 at `327cf4fa2`, in 1 of 2 pack runs** (173/174, then
174/174 on a re-run). Same file, same symptom, same 40 s timeout at
`await firstNotification`. The tree state is not the one the 2026-08-17
observations were made on — the retrofit sequencing landed in between — so the
two rates describe different trees and must not be pooled.

**The 2026-08-19 run produced evidence the earlier ones did not: the
notification WAS delivered.** The client log carries
`Received @alice🛠:rf2cmon-57335863.buzz@alice🛠`, and exactly **one** such
line, on a monitor whose PKAM went out as `signingAlgo:rsa2048`. Two clients
were live with monitors listening — the legacy owner and the retrofitted ML-DSA
one — and the test awaits the latter. So the question narrows from "was it
delivered" to **which monitor the atServer considered a subscriber**, which is a
fact with no near-side representation at all.

⚠️ **`runLocal.sh` ends with `docker compose down`, so the atServer log for that
occurrence was destroyed before it could be read.** A run chasing this must copy
the logs out first — `docker cp test-virtualenv-1:/apps/logs <dir>` — before the
teardown. The re-run did capture them, and passed, so they say nothing.

**If it recurs,** the bisect point is `0668cf91d` — code there is 14.31's
local-key fix without the `_apsk` write serialisation, so green at that commit
would pin it on the serialisation.

### 14.29 The residuals 14.25 surfaced

**Two** project entries owe work the D1 burn-down never listed — it was three
until 2026-08-18, when B-1's pair turned out to have shipped. Found 2026-08-16
by reading all nine against the tree ([14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none)).
They are collected here because a residual left inside a project entry is
invisible to anyone working the TODO table.

- **SS-2 — the atServer's `__ssenv` behaviour.** It does not exist server-side
  at all, so DEP4's update-put auto-notify is unbuilt — but it is **deferred,
  not owed**: [the 2026-08-03 ruling](detail/implementation-plan.md#ss-2--substrate-wired-into-atclient--server-wake-up-key-package-in-request-new-device-conveyance-only--at_secondary_server-at_client-at_auth-at_commons--l--2085)
  took DEP4 off SS-2 once the correctness argument behind it was withdrawn, so
  what is left here is a pure optimisation and `sendWakeUpNotification` stays
  `true` until it lands. ⚠️ Needs parity across every atServer implementation
  in the same sweep, which is a clean starting state rather than unfinished
  homework: `__ssenv` is a zero in all three implementations, so none has a
  divergent version to reconcile. ⚠️ **Re-derive against all three, not just
  the first** — this named only `at_server` until 2026-08-18, which answers a
  question about one repo:
  `git -C ~/dev/atsign/repos/<repo> grep -c "__ssenv"` across every atServer
  implementation's repo. Zero in each as of 2026-08-18, each run
  beside a control that matched, since an unvalidated grep and a true absence
  print the same nothing.
- **B-1 — none left of the two.** ✅ Both closed since, and re-verified
  2026-08-18. This bullet used to read *"two left: everything beyond envelope
  delivery (`pushSecretToNames…`); and UC-A3.4's self direction, owed rather
  than blocked since `ConcurrentClients` landed"*
  ([#2093](https://github.com/atsign-foundation/at_client_sdk/issues/2093)).
  UC-A3.4's self direction is built and **live-green** —
  `nskey_self_notify_live_test.dart`, "a self notification reaches a second
  enrollment and decrypts", passing in the functional pack. The substrate's
  pull flow is driven live by `nskey_park_and_redrive_live_test.dart` and
  `signing_root_pull_two_enrollments_test.dart`, and **eight** functional
  files now run two real enrollments — so the "waits on SS-2" clause on the
  live-coverage row was wrong as well as the count: two enrollments never
  needed `__ssenv`.
  ✅ **The fixture blind spot is closed** (2026-08-16):
  `buildRemoteBackedMockClient` takes an optional `localData`, and with it a
  local-first read of a key only the atServer holds misses instead of
  succeeding. Opt-in, because the nine callers that predate it specify the
  single-store default.
- **S-3 — two, both small.** This said **three**; the migration test exists.
  `at_keys_test.dart` covers the only N-1 there is — `AtKeys.supportedVersion`
  is still `1`, so the predecessor is the unversioned legacy document, and it
  is pinned three ways: legacy fallback on a versionless file, no version
  stamped onto a file that gained only an atsign, and a field-for-field
  round trip. What remains: a keychain round-trip on a real device,
  **blocked** because this repo has no `integration_test` harness and
  at_client_flutter's tests mock the platform channel; and
  `LocalKeystoreAtKeysIo`, still "not needed at this time" — named in four
  docs and in no source file.

⚠️ **None of these blocks D1's remaining sequence**, which is why they were
survivable as residuals. The B-1 fixture item was the one with teeth — a fake
that cannot distinguish local from remote is exactly the shape that let the
nskey mint read local storage — and it is now closed.

**Re-read against the tree 2026-08-18**, two days after they were written, and
**three of the six had shipped without anything striking them.** Only SS-2
survives intact: `git -C ~/dev/atsign/repos/at_server grep -c "__ssenv"` still
matches nothing, with a positive control run to prove the grep reaches the
repo. That ratio is the finding — a residual parked inside a project entry
falsifies quietly, because the work that closes it is filed somewhere else.

### 14.18 The remaining D1 initial-development sequence

**The per-package carve recipe, which worked three times.** It lived only in a
memory file until 2026-08-20, where a fresh clone could not see it:

```bash
# one worktree per package, off origin/trunk so the PR carries that package alone
# ⚠️ HYPHENS in the branch name where the package has underscores:
#    at_lookup -> gkc-pq-d1-at-lookup  (matching gkc-pq-d1-at-commons/-at-chops)
git worktree add /tmp/carve-<pkg> -b gkc-pq-d1-<pkg-hyphenated> origin/trunk
git -C /tmp/carve-<pkg> checkout gkc-pq-d1-spike -- packages/<pkg>
# the gate: the carved tree must be byte-identical to the spike over that package
git -C /tmp/carve-<pkg> diff gkc-pq-d1-spike --stat -- packages/<pkg>   # must be EMPTY
```

Then analyze and test the package **and its consumers**, and raise with the org
template. Order: **at_commons → at_chops → at_lookup → at_server_status →
at_auth → at_client (stacked) → at_client_flutter → at_onboarding_cli**.

⚠️ **at_lookup does NOT wait on at_chops publishing.** Established by a compile
differential 2026-08-20: at_lookup builds and passes 130/130 against the
published at_chops 3.5.0, and uses no symbol newer than it. It waits only on
**at_commons 5.16.0**, because it reads `AtNetworkTimeouts.defaultResponseBudget`
which 5.15.0 does not have — its floor is already raised to `^5.16.0`.

Ruled 2026-08-11 by a walk through every open item
([`decisions.md` 93](detail/decisions.md#93-the-d1-remaining-work-sequence-and-the-rollout-axis-becomes-real-2026-08-11)).
This is the **order**, not the inventory — each row points at the entry that
holds the detail. **D1 initial development ends at step 34**, when the stacked
PRs are merged; publishing and R-2 follow it.

⛔ **What actually gates D1 (established 2026-08-20, after two misdiagnoses).**
D1 is done when the spike is in trunk **and the eight packages are released**
(gkc). The blocker is **not** an at_server release: `preserveFirstEnrollmentOnRetrofit`
is on at_server `trunk` (8 hits). It is **CI pulling the production VE image**.

- ⚠️ **`canary` is NOT the trunk image.** It shares a digest with
  `canary-c3.16.1` (`sha256:7d8a01…`, 2026-08-13), so it *is* the c3.16.1
  release build and predates #2755. The trunk-tracking pair is **`dev_env` /
  `trunk-gha6542`** (`sha256:5318d0…`, 2026-08-19). Re-derive from
  `https://hub.docker.com/v2/repositories/atsigncompany/virtualenv/tags/`.
- ⛔ **DONE 2026-08-20 — and the enumeration this bullet used to carry was
  wrong.** It read "all four VE jobs — `functional_tests`, `end2end_tests`,
  `end2end_test_14`, `pqe2e_tests`". **Two of those four start no virtualenv
  at all**: `end2end_tests` and `end2end_test_14` run against the long-lived
  `@ce2e1..@ce2e4` atServers on the CICD VMs, and
  `tools/cicd1x64/update_ce2e_images.sh` already rolls those to
  `atsigncompany/secondary:dev_env` (ce2e1/2) and `:canary` (ce2e3/4) — so
  they were on the trunk build before this was ruled, and the tree's own use
  of `dev_env` there is independent corroboration of the tag choice. **Two VE
  jobs live in a second workflow the bullet never named**: `at_libraries.yaml`'s
  `functional_tests_at_onboarding_cli`, a matrix of two packs, one of which
  gained `pq_native_onboard_test.dart` on this branch and needs an atServer
  that verifies ML-DSA PKAM. Enumerate the real set by what starts a
  container, not by what anyone remembers:
  `grep -rn 'docker compose up' .github/workflows/`.
- **What landed**: `VIRTUALENV_IMAGE: atsigncompany/virtualenv:dev_env` on
  `functional_tests` and `pqe2e_tests` in `at_client_sdk.yaml`, and on
  `functional_tests_at_onboarding_cli` in `at_libraries.yaml`;
  `tests/at_onboarding_cli_functional_tests_proxy/docker-compose.yaml` gained
  the `${VIRTUALENV_IMAGE:-…}` override it never had. `legacy_server_tests`
  stays pinned at `vip-p3.15.0`, because testing an old server is its whole
  purpose — it is the control that proves the others actually moved.
- ⚠️ **The gate does not block the first carves, only the last ones.** Trunk
  carries no `tests/at_end2end_test/test/pq/` files (0 against 8 on the spike)
  and no `pqe2e_tests` job; both arrive with the spike's test packs, which ride
  with at_client. So `at_commons` and `at_chops` carve against CI as it stands.
- ⚠️ The tests needing #2755 span **two** packs — 3 files under
  `at_end2end_test/test/pq/` and 4 under `at_functional_test/test/` including
  `self_enrollment_retrofit_live_test.dart`. Moving only the PQ e2e job would
  leave the gate standing.
- ⚠️ **CI does not run on this branch automatically — it has to be dispatched.**
  The workflow triggers are `push: [trunk]` and `pull_request: [trunk]`, so
  nothing fires on a push here. **`workflow_dispatch:` IS enabled** and has been
  used: `gh run list --branch gkc-pq-d1-spike --workflow at_client_sdk.yaml`
  returns **12** runs as of 2026-08-20. ⚠️ This bullet read "CI has never run on
  this branch and structurally cannot" until 2026-08-20, which was true when
  written and stopped being true the first time anyone dispatched it.

  **The consequence to watch:** because nothing fires on push, the newest CI run
  is only ever as new as the last manual dispatch. Compare them before believing
  any "CI is green" claim —

  ```bash
  gh run list --branch gkc-pq-d1-spike --workflow at_client_sdk.yaml --limit 1 \
    --json headSha,conclusion --jq '.[] | [.headSha[0:9], .conclusion] | @tsv'
  git log --oneline -1
  ```

  Dispatching is worth doing before any PR is carved, because CI's at_client job
  runs a **bare** `dart analyze` that reads `benchmark/`, which the routine
  `dart analyze lib test` never opens. That already hid five errors for six days.

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
| 3 | **DONE 2026-08-12 — one envelope shape, RFC 7515 general serialization**, `{payload, signatures:[{protected, signature}]}` with `{alg, kid, v}` in each `protected`. Deleted `signedEnvelopeVersion`, `jwsEnvelopeVersion`'s flattened form, `envelopeVersionOf`'s dispatch, the `wrapperFields` ternary in `ApkamSignedAdvertisedKeys.verify`, and `envelopeVersion` as a `PqPosture` axis. Also took `hashingAlgo` off `signEnvelope` — `alg` names the hash, so nothing unsigned selects a routine — and retired UC-C1.3, the rollout's envelope axis, which had nothing left to drive. The `.mjs` adjudicator moved `flattenedVerify` → `generalVerify`; vectors regenerated at `test/vectors/jws_envelope.json`. **Found en route:** `publishPendingLink`'s already-published check compared a top-level `['signature']` the envelope does not have, so `null == null` matched every time and a different link conveyed later was silently never published | [`decisions.md` 95](detail/decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12) ruling 1, **superseding [91](detail/decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11) ruling 12**'s bespoke container |
| 4 | **DONE 2026-08-13 — ruling 2 landed, so all of step 4 is complete and step 6 is unblocked.** Ruling 2 in three commits: `6462ae786` (the advertisement becomes `{v, createdAt, keys:[{use, alg, pub, kid}], suites}` with one `toPayload`/`fromPayload` codec replacing a map literal in `_mint` and a hand parser in `verify` 250 lines apart), `d28ef48a9` (a key that is not its algorithm's length is refused — a kid is the digest of whatever bytes are carried, so it matched a forged key as readily as a real one), `69449603e` (the reader skips entries it has no KEM for and picks the strongest it can use, which has to ship before any writer emits a second key). **Three things the ruling got wrong**, all corrected in `decisions.md` 94: `_apsk` entries never carried `status`; `status` and `KeyEntryStatus` are deferred **entirely to step 5** so no dead field ships (gkc, 2026-08-13); and at_auth cannot reach `PackageKey` because at_client depends on at_auth, so one vocabulary means one **wire spelling** across two Dart types. `createdAt` was added for symmetry with `KeyPackage`; `v` stays 1. Rails: at_client 1188/1188, functional 146/146. One key-entry vocabulary across all three advertising records — `{use, alg, pub, kid, status?}` inside `{v, keys:[…], suites}`. **Landed 2026-08-12:** ruling 3 (one kid function, at_auth's `publicKeyKid`, over the key's raw BYTES — `apskKid` hashed the base64 text and `nskeyKidOf` the material, and every kpid changes value); ruling 4 (`v`, `alg`, `suites` required, both `legacy*Suites` deleted); ruling 5 (one `SecretSharingAlgos.bestSuiteBetween`); **ruling 6** — `pq_envelope.dart`'s `pqSealToBase64`/`pqOpenFromBase64`, both taking `info` and `version` as **required** arguments and constructing neither, so there is nothing inside the shared code for the two substrates to converge onto. at_chops' `pqSeal`/`pqOpen` now require `info` too, which makes a shared binding a **compile error** rather than a convention — it was reachable before, because `info` was optional and `info ?? Uint8List(0)` made omission and empty the same binding. **Found en route:** the pairwise substrate had NO test that could fail on a converged binding — dropping the label from all three pairwise/enrollment call sites left the suite green at 1180/1180 — so the production-fed differential in `pairwise_secret_sharing_test.dart` was built first and proven by that same symmetric mutation, which now turns exactly one test red. **Still owed: ruling 2** — the nskey advertisement gains a `keys` list and adopts the shared spelling | [`decisions.md` 94](detail/decisions.md#94-three-records-advertise-keys-and-only-one-of-them-speaks-the-vocabulary-2026-08-11) — ⚠️ **before step 6**, or that parser becomes the third hand-rolled codec for one shape |
| 5 | **DONE 2026-08-13 — the `retired` key path, in three commits.** `6a5eac838`: `PackageKey` gains `status`, a `KeyEntryStatus` of `active` or `retired`, and `bestKeyFor` on both a key package and an nskey advertisement passes a retired key over, so `kpid` is the *active* enc key's kid. Emitted only when retired — absent already reads as active — and an unrecognised value reads as retired, the one reading that cannot make a build use a key its owner withdrew. `f956b2146`: `PersistedApkamKeys` becomes `{encKeys: [PersistedEncKey]}` and `KeyPackageRegistration` expands, advertises and answers for every held key, with `encKeyFor(kid)` replacing `encSecretKey` and `heldKpids` listing every address. `f6fc3796e`: the sweep, the wake-up subscription and the sync listener cover every held address (`EnvelopeAddressing.regexForAny`/`sweepRegexForAny`), and `_consume` opens with the key the envelope names. **Three things ruling 9 got wrong or omitted**, all recorded in `decisions.md` 95: the sweep filter is a **fifth** consequence and the one that makes the other four reachable; the keyfile already records the status (`AtKeysMaterial.KeyPartStatus`, `AtKeys.retireKey`, and an `AtKeysAssurance` rule enforcing one active `publicEncapsulation` per enrollment and algorithm), so deriving it from `createdAt` was wrong; and `dead` material is not adopted at all. Rails: at_client 1210/1210, functional 146/146. **Nothing rotates yet** — the writer is step 16. ⚠️ app-facing: `PersistedApkamKeys` is what apps build in `loadApkamKeys`/`saveApkamKeys` | [`decisions.md` 95](detail/decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12) rulings 6–9 — without the plural holding the field is decorative. The **name collision** was settled 2026-08-12 (gkc) and landed as ruled: the per-entry wire value is a Dart `KeyEntryStatus`, and `KeyPackageStatus` — the reader's verdict on a whole package (`present`/`absent`/`rejected`/`unsupported`) — keeps its name. Nothing renamed |
| 6 | **DONE — mostly with step 2a, completed 2026-08-13.** `parseApskValue` reads the array **and** the released bare string, refuses a structured value advertising nothing it understands rather than guessing, and skips entries whose `use` or `alg` it does not know; `apsk_formats_test.dart` covers all of that plus "the array form is unmistakable to a bare-RSA consumer". Finished on 2026-08-13 by giving `ApskSigningKey` a `status` and having `apskSigningKeys` read it — **keeping** a retired entry, because this list is what verifies stored envelopes and a retired key is precisely what signed the older ones. `KeyEntryStatus` moved from at_client to **at_auth** in the same change so all three advertising records name one type, narrowing [94](detail/decisions.md#94-three-records-advertise-keys-and-only-one-of-them-speaks-the-vocabulary-2026-08-11)'s "one vocabulary cannot mean one Dart type" — that was true of a type living in at_client, and at_auth is the lower package. **Found by the re-verify:** `design.md` 9.3's JSON example omitted `kid`, which the reader requires, so the document the design showed is one every reader treats as empty and then refuses; corrected, and pinned. `advertised.first` and the singular `ParsedApsk` are steps 7–9's business, not a gap here | [`design.md` 9.3](design.md#9-subsystem-g--signature-agility-the-authsigning-key-split) |
| 7 | **DONE 2026-08-13.** `SigningAlgoType.strongestFirst` + `strongestOf` in at_chops — purely additive (two statics on the existing enum; no member added, moved or renamed, so it does not touch the unresolved 3.6.0-versus-major question). Deliberately **not** declaration order: members are declared in the order they were added and reordering them is a wire change, so preference is a second statement. `mldsa65` first, categorically — the only member Shor does not break — then RSA-4096, `ed25519`, `ecc_secp256r1`, RSA-2048 by classical security level. Total on purpose: a partial order leaves the choice undefined for exactly the pair nobody thought about. **The tripwire is completeness, not just the literals**: a new `SigningAlgoType` left out of the order turns `test/signing_strength_test.dart` red, which is what stops it becoming silently unrankable. Wired straight into `parseApskValue`, which took `advertised.first` — the order entries arrive in is the *signer's* choice, so an enrollment advertising ML-DSA-65 beside RSA-2048 was verified against whichever it listed first | [14.17](#1417-signature-agility--complete) |
| 8 | **DONE 2026-08-13.** `requireAlg` is gone rather than rewritten: the algorithm is now *resolved* — from what the envelope's `signatures` and the signer's `_apsk` have in common, taking the strongest by `SigningAlgoType.strongestFirst` — and then its key is fetched, where before one advertised key was taken and the envelope was required to match it. Its refusal survives in a different form: no algorithm in common is refused naming both lists. `ParsedApsk` went plural (`keys`, `keyFor(algo)`; `signingAlgo`/`publicKey` survive as strongest-of getters), and the bare RSA form parses to a one-entry list so both published forms are one shape to the caller. The two JOSE `alg` switches — one on the sign side, one on the verify side — became one `_joseAlgFor`, since two would be two chances to disagree | ⚠️ an inversion, not an addition |
| 9 | **DONE 2026-08-13, with step 8** — the two do not separate: resolving the strongest shared algorithm *is* walking the entries. `verifyEnvelope` selects its entry by algorithm rather than taking `signatures.first`, verifies only that one, and refuses on failure with no fallback. **Found en route and fixed:** `signerEnrollmentId` reads `signatures.first.kid` while the verified entry is now chosen by algorithm, so the two could be different entries — append a signature under a stronger algorithm carrying another kid and a caller acts on a signer whose signature was never checked. `SignedEnvelope.fromJson` now refuses an envelope whose entries name more than one signer, which is a structural claim about this shape rather than a verify-time check. UC-G1.7 is covered for the first time, four rows | [`design.md` 9.4](design.md#9-subsystem-g--signature-agility-the-authsigning-key-split) |

**A reader understanding no entry refuses outright** — no downgrade, no fallback
to a derivable legacy key ([`decisions.md` 93](detail/decisions.md#93-the-d1-remaining-work-sequence-and-the-rollout-axis-becomes-real-2026-08-11) ruling 2).

**Stage 2 — the unblocker. The writer half cannot start before this.**

| # | Work |
|---|------|
| 10 | **DONE 2026-08-13 — one resolver, not a materialised projection.** `AtKeys.authenticationFor(enrollmentId)` returns the AtChops and the PKAM algorithm, with typed material winning wherever the keyfile holds it for that enrollment and the flat fields answering only where it holds none; `authenticationAlgorithmFor` is the algorithm half, so a caller holding an injected AtChops does not build one `toAtChops` would throw on. `AtAuthImpl.authenticate` and `AtClientImpl._createAtChops` both move onto it. **Ruling 7 as written could not be built** and is amended in place ([`decisions.md` 91.3](detail/decisions.md#913-the-rulings)): filing a projected material makes `toJson` emit `version`/`atsign`/`keys` — the guard is `keys.isEmpty` and both stores stamp `atsign` first — which breaks the byte-identical legacy round-trip [91.4](detail/decisions.md#914-what-is-released-and-therefore-what-must-still-be-read) promises, and on a retrofitted keyfile the one-active-`privateAuthentication`-per-document rule refuses the add outright. Four shipping shapes hold nothing to project from: a pre-typed `.atKeys`, an `rsa2048` first onboard, an OTP enrollment, and an onboard handed its keys by the caller. **Found en route and fixed:** `_createAtChops` picked its keypair off the algorithm `_resolveSigningAlgoFromKeyMaterial` had recorded, and that records nothing when its own read throws — so a transient keyfile failure made a retrofitted client PKAM with the *flat* enrollment's key while its typed material sat in the same file. Its comment claimed it mirrored `AtAuthImpl`; it did not. Rails: at_auth 257/257, at_client 1218/1218 |
| 11 | ✅ **DONE 2026-08-13 — both halves.** ⚠️ This cell was labelled `PARTLY DONE` until 2026-08-18, five days after its own closing clause recorded the second half as done, and 15.2 said so in prose the whole time — a diagnosis is not a correction. **The wiring half.** ⚠️ **The nullability was never the problem, and the blocking claim was measured rather than inherited.** `apkam_signing.dart`'s dartdoc says sourcing from `AtKeys` "cannot land until every client has an `AtKeysIo` — today it is nullable and most apps supply none". Measured over the 22 repos on disk that depend on at_client: **0 of 22** supply one to a client and **0 of 22** use `fromAuthSession`, so the claim is TRUE — but the dominant cause is one SDK line, not app behaviour. `AtOnboardingServiceImpl.authenticate()` built a `FileAtKeysIo` for `AtAuth` and then created the client without it, so every `at_cli_commons` consumer (at_talk, sshnoports, noports-tools, at_demos, ogentic) inherited a source-less client. **Fixed:** `_initAtClient` takes the source and threads it to `setCurrentAtSign`. The injected AtChops still authenticates — this only gives the client the source for what AtChops cannot answer. ⚠️ **Deliberately NOT done: an `atKeysIo ??=` default on at_client_flutter's `AuthService.authenticate()`.** `AtAuthRequest`'s constructor already refuses a request with neither `atKeysIo` nor `atAuthKeys`, so the default could only ever fire when the caller supplied `atAuthKeys` — an app that loaded its own key material — and pointing it at a keychain that may hold another atSign's keys, or none, is a guess. The asymmetry with `onboard()`'s `??=` is correct: onboarding mints keys and needs somewhere to write them. ⚠️ **The null case is a tested, deliberate property**, not an oversight — `no_atkeysio_inertness_test.dart` pins that a source-less client performs zero PQ writes at startup, which is what protects the long-lived cicd atServers, and the e2e pack builds its clients through `setCurrentAtSign` directly so this change does not reach them. ✅ **DONE 2026-08-13, with step 12:** the signing half — `signingKeys` sources from `AtKeys` rather than reading the APKAM auth keypair out of `atChops`. Built once, as step 12's per-algorithm accessor |
| 12 | ✅ **DONE 2026-08-13.** `AtKeys.signingKeysFor(enrollmentId)` (at_auth) returns every active signing keypair the enrollment holds, one per algorithm, strongest first; `ApkamSigning.signingKeys` (at_client) is a `Future<List<ApkamSigningKeys>>` reading it through `AtClient.atKeysIo`. `ApkamSigningKeys` now carries its `algorithm` and `signEnvelope` takes it from there rather than a separate `signingAlgo` argument — a key and an algorithm arriving separately can disagree, and the resulting signature verifies against nothing. ⚠️ **Selection is by the keyId shape `sign:<enrollmentId>:<algo>:<n>`, NOT by the `privateSigning` role**: `PqSigningRoot` files the atSign-wide signing root under that same role with no enrollment id, so a role filter hands an enrollment a key that was never its own — the same defect shape as 14.19 item 6. Proven by mutation: selecting on the role turns two tests red. **The empty case answers with the APKAM authentication keypair**, which is what ruling 10 keeps in the `_apsk` array permanently, so the accessor is live from this commit rather than waiting on a writer, and `now`-posture envelopes stay byte-identical (the stored JWS vector re-signs to the same bytes). That also covers the source-less client, which is a deliberate tested property. Read per call, not cached: a cached copy goes stale the moment a rotation retires what it held. **The minting/filing half is NOT here** — `fileSigningMaterial` still has no production writer, and which algorithms to mint is the in-use set's decision, so it stays step 18. Rails: at_client **1228/1228** (2 skipped), at_auth **266/266** |

**Stage 3 — the `_apsk` writer half (rollout 2).**

| # | Work |
|---|------|
| 13 | ✅ **DONE 2026-08-13.** `apskAdvertisement` composes from a **list** of keys rather than one `(apkamPublicKey, signingAlgo)` pair, so a second algorithm's key can be advertised beside the first; `ApskSigningKey.forPublicKey` builds an entry and derives its `kid`, which is never a caller's to supply. `status` is emitted **only when retired**, so an advertisement that has never rotated is byte-identical to what the single-key composer wrote. The enrollment-request site still sends one key — at request time the enrollment holds nothing but its freshly minted APKAM keypair, and a second arrives by `enroll:update` (step 16) once step 18 mints one. **`publishPublicSigningKey`'s fate, settled:** it stays the only writer for an `_apsk` no `enroll:request` can carry (a client with no enrollment publishes under `primary`, which has no enrollment record). It now publishes `publicSigningKeyValue` — the **bare** key when the client holds exactly one `rsa2048` key, the array otherwise — which is the same rule `_apskFor` uses for `apsk`-versus-`apskLegacy`; the two must agree because they describe one record. It also **republishes on a change**, closing [decisions.md 91.1](detail/decisions.md#911-what-is-wrong-today) cost 2: it used to read the record, log "have already published" and return, so a rotated key never reached the atServer and every envelope signed with the new one was verified against the old. Proven by mutation: restoring the absent-only condition turns exactly the republish test red. Rails: at_client **1234/1234** (2 skipped), at_auth **269/269** |
| 14 | *(done in step 2a)* `EnrollParams.apsk`/`apskLegacy` are populated at all three submit sites. ⚠️ **This read "Only the atServer half of `apskLegacy` remains" until the 2026-08-14 wrap-up, and that half had merged two days earlier** — at_server `6a86fbcc`, an ancestor of `origin/trunk`, re-verified with `git -C ~/dev/atsign/repos/at_server branch -r --contains 6a86fbcc`. Step 2a was corrected on 2026-08-13 and this row was not, which is how a reader working top-down would have rebuilt merged work |
| 15 | ✅ **DONE 2026-08-13.** `signEnvelope` takes a **list** of keys and emits one signature entry per key, in the order given — which is what the RFC 7515 general serialization the envelope already used is for. `wrapAndSign` passes every key `signingKeys` returns rather than its strongest: the **verifier** chooses, taking the strongest algorithm the envelope and the published `_apsk` share, so signing only under this build's strongest would be unverifiable to any peer that has not implemented it — an envelope carrying both is readable by the upgraded peer and the un-upgraded one, which is the rollout problem in one sentence. The payload is encoded **once** and every entry signs its own protected header joined to that same text, so the entries are alternatives rather than a chain. `SignedEnvelope.fromJson` already refused an empty signatures array and a multi-**signer** document, so the writer builds through it and inherits both refusals. ⚠️ **UC-G1.7's two-signature fixture was hand-assembled** from two single-signature envelopes, so that whole group was a test of the fixture and would have passed against a writer that could not emit two signatures at all; it now drives the real writer. Proven by mutation: signing with `[keys.first]` turns the multi-signature test red. Nothing files per-algorithm signing material yet, so every envelope still carries exactly one signature today, and the stored JWS vector re-signs byte-identically. Rails: at_client **1237/1237** (2 skipped), at_auth **269/269** |
| 16 | ✅ **DONE 2026-08-13, in five commits `e04040ac1`…`d467ed3b5`** — two code, three docs (this row said "in two commits", written before the doc sweep and the wrap-up corrections landed). `AtEnrollment.update` takes an `EnrollmentUpdateRequest` and an `EnrollmentUpdater` sends it, beside `EnrollmentApprover` and deliberately not on it: the approver's verbs need a connection holding `__manage` and act on somebody else's enrollment, while this one needs no privilege and can only act on the enrollment the connection *is* — the atServer refuses an owner connection here rather than waving it through. The request refuses at construction to be built naming nothing to change, with a public key and no private half, with a key and no algorithm or an algorithm and no key, with both `_apsk` shapes, or with an advertisement of no keys. **Found en route: the wire vocabulary was one field short, so this row's "only the caller is owed" was wrong.** `EnrollParams.apkamPublicKeySignature` existed with its own round-trip test, but `EnrollVerbBuilder.buildCommand` never copied it into the params it builds — and a `toJson`/`fromJson` round trip is equally true of a field nothing can send, so the test could not see it. **Two rulings this took:** `signingAlgo` is **always** sent, so the effective algorithm the atServer interpolates is the one signed here and the literal `"null"` can never come from this emitter (pinned regardless — a second implementation has to know the server accepts it); and the public API takes two key-material **strings**, not an `AtPkamKeyPair`, because at_chops deprecates that type and a new signature carrying it hands every caller a deprecation. `ecc_secp256r1` is refused rather than signed: at_chops' pkam-mode signer selects an RSA implementation for everything that is not `mldsa65`, so an ECC key would be signed as though it were RSA — and an ECC APKAM key lives in a secure element whose private half is not a string anyone can pass. **Proven by two mutations**, against tests that re-run the atServer's own `ApkamSignatureVerifier` branches rather than asserting through the signer: signing everything as `rsa2048` turns exactly the mldsa65 arm red (that arm is the only one that can see an algorithm mix-up), and dropping the algorithm from the signable turns all three signature tests red (both arms verify real bytes). ⚠️ **Nothing persists a rotated keypair** — [14.19 item 11](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on). Rails: at_commons **517/517**, at_auth **288/288**, at_client **1237/1237** (2 skipped), at_onboarding_cli **39/39**. **THE PoP CONTRACT, read from at_server `6a86fbcc` `enroll_verb_handler.dart` `_verifyApkamPublicKeyPossession` and `apkam_signature_verifier.dart` — do not re-derive it:** signable is `utf8.encode('<enrollmentId>|<apkamPublicKey>|<signingAlgo>')`, signature travels **base64**, signed by the **NEW** private key. Three things a guess gets wrong: (a) `signingAlgo` is the **effective** one, `request.signingAlgo ?? record.signingAlgo`, string-interpolated — so a null becomes the literal `"null"` in the signed bytes, and a client that omits it must know the record's current value; (b) **mldsa65 signs the message DIRECTLY with no hash** (`MlDsa65PureDartAlgo.verifyBytes`), while rsa2048/ecc go through `AtChopsImpl.verify` with `HashingAlgoType.sha256` — a client that hashes for both fails only on the PQ path; (c) `AtSigningMode.pkam`, never `data`, which signs with the *encryption* keypair. The server also refuses `signingAlgo` without `apkamPublicKey`, and `enroll:update` is **self-only** and **approved-only**. ⚠️ **Adding a member to `AtEnrollment` touched 7 `Mock implements` in three packages** (at_auth 2, at_client 4, at_onboarding_cli 1), plus `AtEnrollmentImpl`, which is the **production** class and got a real implementation rather than a stub — not an eighth mock, as an earlier draft of this row said. All three suites re-run; the mocks are safe because no production path calls the new member, and they would have broken at RUNTIME, not analyze |
| 17 | ✅ **DONE 2026-08-13.** `AtClientPreference.dataSigningKeyAlgorithms` — a `Set<SigningAlgoType>`, final at construction and stored unmodifiable, defaulted from a new fifth `PqPosture` axis and overridable per preference. **The four things ruling 16 left open were ruled by gkc and are recorded in [`decisions.md` 91.3](detail/decisions.md#913-the-rulings) ruling 16 with their reasoning:** defaults `{}` in 3.x and `{mldsa65}` in 4.0; a `Set`; final at construction; and an algorithm this build cannot sign an envelope under is refused at construction with an `ArgumentError` rather than skipped. ⚠️ **The doc sweep this owed was bigger than the row** — three documents enumerated the posture's axes and all three still listed the **signed-envelope version**, deleted at step 3: [`decisions.md` 56.4](detail/decisions.md#564-from-the-pq-projects-view-40-is-final-3x-with-different-flag-defaults)'s table, its capstone entry [`decisions.md` 70](detail/decisions.md#70-workstream-a-capstone-pqposture-the-five-flags-as-one-value-2026-08-10), and `roadmap.md`'s axis list. The count stayed five across the swap, which is precisely how a stale enumeration survives review. Acceptance gained UC-C1.7 and UC-C1.6's "UC-C1.1–C1.5 prove the arms" was corrected — C1.3 is withdrawn. `design.md` 9.6's strength order still showed the three-member ruling rather than the five-member total order step 7 shipped. **Nothing reads the set yet — step 18 is its only consumer**, so this commit is a preference and its refusal, not a behaviour change. **Proven by four mutations**: each posture default flipped reddens its literal pin, disabling the signable check reddens the refusal test, and returning the caller's own set rather than an unmodifiable copy reddens the containment test. ⚠️ **The 1240/1240 in this commit's message was measured before the doc edits and does not hold for the commit as landed** — adding UC-C1.7 to `acceptance.md` without a scenario in `test/acceptance/` turns `catalogue_test.dart` red, which is that guard doing its job. Fixed in step 18's first commit, which adds the scenario and the README row count. Rails for 17+18a together: at_client **1245/1245** (2 skipped), acceptance **57** (2 skipped) |
| 18 | **PART 1 DONE 2026-08-13 — the reader and the advertisement; the minter is part 2.** Splitting it was forced by a defect the minter would have shipped: `ParsedApsk.keyFor` took **one key per algorithm** (`where(alg).firstOrNull`) and `verifyEnvelope` checked that one, so ruling 10's retained authentication key works only where its algorithm differs from the minted key's. A post-quantum-native enrollment's auth key is ML-DSA and so is what it mints, which puts two `mldsa65` entries in `_apsk`, and every envelope signed before the split stops verifying — the ordinary 4.0 case. `keysFor(algo)` is now plural and the verifier tries each, refusing only when none verifies; ruling 10 is amended in place with why. **The reader ships before the writer**, which is also why this is two commits rather than one. Also here: `apskEntries`/`apskValueOf` (`apsk_composition.dart`) are the one composition of the `_apsk` record for both its publishers, and they append the authentication key as `retired` once the enrollment holds signing keys — deduped, because one key described as both current and withdrawn is a document a verifier has nothing to choose on. An enrollment holding no signing material advertises exactly what it did before. ⚠️ **The retention half was reversed 2026-08-14 by row B2** under [`decisions.md` 98](detail/decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14) ruling 2: the auth key is advertised only while it *is* the signer and is never retained, and what `apskEntries` carries beside the active signers is the enrollment's **retired signing keys**. The dedup survives, between an active signer and a retired entry naming the same public half. **Proven by mutation**: restoring the single-key selection reddens the retained-key test. Rails: at_client **1245/1245** (2 skipped), acceptance **57** (2 skipped). ~~**Part 2 owes** the minter itself: mint at start, publish, then file.~~ ✅ **PART 2 DONE 2026-08-13** (`90730a130`, "an enrollment mints its own signing keys, advertising before filing"), and this sentence stayed here reading as owed until 2026-08-18. `SigningKeyMinting` (`signing/signing_key_minting.dart`) mints one keypair per algorithm the in-use set names and the enrollment lacks, retires every held one the set no longer names, and is wired as step 3 of `PqClientBootstrap` (`pq_client_bootstrap.dart:203`); `test/signing_key_minting_test.dart` covers it and `tests/at_functional_test/test/apsk_server_side_test.dart:215` drives it live. The order it owed is the order it shipped in. ⚠️ **That order matters** — filing first makes the client sign with a key its advertisement does not name, and every envelope written in that window is permanently unverifiable, while an advertised key that was never filed costs a verifier nothing and disappears at the next publish. The nskey path's rule is the opposite (`NskeyPrivateFiling.store` files before publishing) because an unopenable *encapsulation* key loses data; the asymmetry is real and worth stating where both are read |
| 18b | ✅ **DONE 2026-08-13.** `SigningKeyMinting` (at_client) mints a keypair for every algorithm the in-use set names and the enrollment does not hold, advertises it, and **then** files it through `WrittenAtKeysIo.update` — the store's atomic verb, because a client's start files conveyed key material through the same keyfile and a hand-rolled read → mutate → write would drop whichever addition flushed first. Wired as the **ninth** `PqClientBootstrap` step, `mintInUseSigningKeys`, gated by `PqStartupGates` and placed **before every step that signs** (seeding, both link publications and the sweep all emit signed envelopes), so a key minted on a start is advertised before anything signs with it. Which writer depends on whether there is an enrollment record: `enroll:update` where there is one — the atServer is the only writer of an enrollment's `_apsk` — and a direct publish under `primary` where there is not. Inert with an empty in-use set (the 3.x default) and inert for a client with no key source, which is the tested no-`AtKeysIo` property. `RsaKeyPair.generate()` rather than `AtChopsUtil.generateAtPkamKeyPair()`, which returns a type at_chops deprecates. **Proven by three mutations**: swapping to file-then-publish reddens the ordering test, dropping the retained authentication key reddens the advertisement tests, and minting an already-held algorithm reddens both idempotence tests. ⚠️ **The second of those mutations no longer discriminates** — row B2 removed the retention it was probing. Its replacement is B2's own pair: gutting `retiredSigningKeysFor` reddens the two retained-signing-key tests, and removing the dedup reddens the third. Rails: at_client **1257/1257** (2 skipped), acceptance **57** (2 skipped) |
| — | *(the original row, kept for its spec pointers)* Mint-on-demand when the in-use set names an algorithm the enrollment lacks. **Spec: ruling 16** (mint locally at start, file it, publish it — a *signing* keypair may, because unlike the auth key it needs no server approval) and **[`decisions.md` 91.3](detail/decisions.md#913-the-rulings) ruling 9** (the array is append-mostly: an algorithm leaving the set stops signing, but its key and its published entry are **retained**, because they are what verify the envelopes it already signed). This is the step that gives `signingKeysFor` something to read — `fileSigningMaterial` has no production writer until it lands |
| 19 | ✅ **DONE 2026-08-13.** The axis is **`SigningRollout`** — `now` / `rollout1` / `rollout2` — on `PqPosture.signingRollout`, overridable per `AtClientPreference`, with the in-use signing set **derived** from it rather than stored beside it. **The step opened with a finding that nearly closed it:** the three rollout-2 writer behaviours are inseparable *by construction*, not by three flags agreeing — only minting is a decision, while the array form (`apskValueOf` emits the bare string only for a single active `rsa2048` entry) and the multi-signature envelope (`wrapAndSign` signs with every key the keyfile holds) are consequences of the enrollment holding a second key. Folding the axis away like step 23 was put to gkc and **declined**: the axis earns its place by naming the position, and steps 20–22's driver needs those names. So it names a position and supplies one default, and cannot contradict the behaviour — two stored fields would be two controls over one thing. `rollout1` writes exactly what `now` writes (the reader half needs no gate) and carries the *fleet's* position instead; it is reachable only through the preference, since there are two postures and no general constructor, and an unreachable value would be a rollout position nothing could ever be in. **Proven by three mutations**: giving `rollout1` a non-empty set, ignoring an explicit stage, and letting the stage beat an explicit set each redden their own arm. Rails: at_client **1261/1261** (2 skipped), functional **146/146** at `88ab87b4e` |

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
| 24 | ✅ **DONE — RULED 2026-08-20: leave it, the warning is the answer.** `isFullyPrivileged()` keeps returning true for a null enrollment id — a client authenticating with the atSign's own keys holds full privilege by construction, which the resolver's own dartdoc already argues. `ApkamSigning.enrollmentId` keeps substituting `'primary'`, so such a client keeps publishing `public:_apsk.primary.a.__e@<atSign>` under a name no enrollment record carries, and `apkam_signing.dart:68` keeps logging a warning when it happens. ⚠️ Accepted knowingly: a verifier walking an owner-key signature through the approval chain dead-ends, and surfaces that as a verification error rather than as this decision. Do not re-open. | [14.14](#1414-a-client-with-no-enrollment-id-is-treated-as-fully-privileged) |
| 25 | ⛔ **STRUCK FROM D1 2026-08-20 — it belongs to the STOP-RELEASE.** 14.12's own body says so: "the point of this entry is that the stop-release cannot ship before both are", where *both* are public-record signing moving onto the ML-DSA signing root and self data moving off `selfEncryptionKey` onto the nskey path (B-3 phase 1). Neither is scheduled, and this row sitting in the D1 sequence made D1 depend on two undesigned moves. The assertion in `pq_legacy_interop_live_test.dart`'s opt-out arm stays exactly where it is — it already fails with the reason naming this row, so whichever project fixes it gets a red test pointing here. | [14.12](#1412-a-mintlegacymaterialfalse-atsign-cannot-write-a-public-record) |
| 26 | *(closed)* revocation visibility — an `EnrollmentManager` cache race, fixed in at_server `16dd457f`. ⚠️ This cell said "a proven test-instrument failure" until 2026-08-15; that was the 2026-08-11 ruling the root-cause overturned | [14.9](detail/implementation-plan.md#149-a-revoked-enrollment-can-still-authenticate-briefly) |
| 27 | ✅ **DONE 2026-08-15** — domain separation on the signed envelope, per-use `typ` plus a root-link prefix ([`decisions.md` 103](detail/decisions.md#103-an-envelope-says-what-it-is-for-and-a-verifier-says-what-it-wants-2026-08-15)) | [14.8](detail/implementation-plan.md#148-domain-separation-on-the-signed-envelope) |
| 28 | ✅ **DONE AS NOTED 2026-08-20 — the naming WAS the deliverable.** 14.7 establishes that a migration here does not break NoPorts: it imports none of at_client's functions, signs with the encryption keypair and fetches `getRemotePK` rather than `_apsk`. There is nothing to build. It becomes a separately-owned second migration only if the envelope pitch becomes RFC 7515, and that conditional is what this row records. | [14.7](detail/implementation-plan.md#147-noports-carries-its-own-copy-of-the-envelope-shape) |
| 29 | **Three** audit residuals — perf ceiling on a real low-end device, SS-4 interrupted-mint resume, IS-1 record-name drift. ⚠️ This read **four**, including UC-A3.4's live self-direction, until 2026-08-18 — 14.16's own body has marked that ✅ DONE since 2026-08-17 | [14.16](detail/implementation-plan.md#1416-four-residuals-the-issue-tree-audit-surfaced-2026-08-09) |
| 30 | `deprecated_member_use` across the workspace. ⚠️ **RE-DERIVED 2026-08-20 at `26644e779`: 780, not the 666 this row used to record** — at_client **396**, at_onboarding_cli **205**, at_auth **153**, at_lookup **26**, at_chops 0, at_commons 0 (`dart analyze lib test` per package, `grep -c deprecated_member_use`). ⛔ **RULED 2026-08-20: all 780 are in D1's bar.** ⚠️ **76 of them are this project's own**, added deliberately by the at_lookup consolidation's six credential deprecations and the `AtLookupImpl` constructor deprecation; the other 704 are the at_chops compatibility shim, `AtSigningInput` and `apkamPublicKey`. Clearing the 76 means moving at_client's eight readers of `atLookUp.enrollmentId` and the `atChops` readers off those members — the work filed as **BLOCKS THE MAJOR** in `docs/projects/at-lookup-consolidation/plan.md` section 6. That is non-breaking: the members stay, their callers leave. | [14.11](#1411-deprecated_member_use-findings-across-the-workspace) |
| 31 | ✅ **DONE — nothing owed since 2026-08-10.** The one item (the functional pack's compose hardcoding a local image) is struck in the body; the external gate it names is step 32's blocker, not a checklist entry. This row carried no state until 2026-08-18, which in this table reads as open | [14.15](#1415-pre-pr-rails-checklist) |

Also in D1, runnable in parallel: **S-3**'s completion, **B-3** ([#2128](https://github.com/atsign-foundation/at_client_sdk/issues/2128),
open), **KF-1** ([#2129](https://github.com/atsign-foundation/at_client_sdk/issues/2129),
open), and **IS-1**. ~~merging at_lookup 3.6.1 (#2127)~~ — dropped 2026-08-13:
that PR merged 2026-08-08 and 3.6.1 is on pub.dev, so it had been listed as
parallel work for five days after it was finished. Issue states verified with
`gh` on 2026-08-13; re-derive rather than trusting this line.

**Stage 6 — the carve-up, which is where D1 initial development ends.**

| # | Work |
|---|------|
| 32 | ⛔ **RESHAPED 2026-08-20 — NOT one stack. A per-package release train.** Carve a PR **per package**, from the spike branch, each raised when that package has no work pending but publishing. **Single PRs for all except at_client, which lands as a series of stacked PRs.** Dependency order, derived from the pubspecs rather than assumed — note `at_auth` depends on `at_server_status`, which is easy to miss: **at_commons → at_chops → at_lookup → at_server_status → at_auth → at_client (stacked) → at_client_flutter → at_onboarding_cli**. ✅ **Ready now: at_commons and at_chops** — 0 deprecations each, no D1 row touches them. **Ready means that package's own work is done, its share of step 30 included.** ⚠️ This also dissolves step 20's circularity: at_auth publishes at position 5, so the rotation arm becomes buildable long before at_client's stack lands. |
| 33 | Merge them to trunk. **The spike branch itself never merges** |
| 34 | ← D1 initial development complete here |

Then, as the release programme rather than development: publish at_chops 3.6.0
→ at_commons **5.16.0** → at_auth 3.4.0 → at_client's GA minor, and finally
**R-2**, the 4.0.0 posture flip. (⚠️ this said at_commons **5.15.0** until
2026-08-13, a version already on pub.dev; the in-tree in-progress heading is
5.16.0. Check pub.dev against every touched pubspec before acting on this
ladder — a same-value version bump merges silently.)


### 14.19 Small items, raised 2026-08-12 and not yet acted on

**17 open, 19 struck** (36 items) — ⚠️ **re-derive all three, never read them
here.** This header said `11 open, 12 struck` until 2026-08-18, `15 open, 16
struck` until 2026-08-19 and `17 open, 17 struck` until items 32 and 33 were
done, and the TODO row three paragraphs up said 9 the whole time: the count
turned out to have **four** homes, not the two a correction had been updating.
⚠️ **It has SIX** — the two memory files a fresh session reads first state it
too, and they are not in this repo, so nothing here can go red for them. A cold
read on 2026-08-19 found this header stale for a second time, by a correction
that had updated the other three. (Was 17 open on 2026-08-17, before items 1,
3, 16, 17 and
19 were fixed, 22 was struck as a false positive, and 15 was struck as the
closure it had already recorded in its own body since 2026-08-15. Then 32 and
33 were done on 2026-08-19, which also **added** item 35 — deleting dead code
found a consumer of it in another repo, so the open count fell by one, not
two.) **Check the total as well as the open count**: the two disagree whenever
an item is added rather than closed, and only the total catches a duplicated or
skipped number. Each is real
and verified at the time of writing, and each is too small to be a step of its
own. **None blocks anything** — which is why the items themselves live in
[`detail/implementation-plan.md`](detail/implementation-plan.md#1419-small-items-raised-2026-08-12-and-not-yet-acted-on)
rather than here: they are work to pick up, not work to hold in mind.

**Item 8 is the only one waiting on a ruling** — typed key material is not
self-encrypted at rest while the flat fields are. Item 10 is an unexplained
functional run with two disproven theories. Item 14 is not PQ at all. Items 20
and 21 were examined and deliberately left, so they are not work.

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

7. **Do NOT make the mint lock release itself while its lease is unspent.**
   Proposed 2026-08-16 — by me, and *recommended* — when the first live run of
   [14.24](detail/implementation-plan.md#1424-the-nskey-mint-elects-a-winner--decisions-105) showed a
   rotation refused for the two minutes after a mint. The argument was that it
   is sound by construction: `MintLease.expiresAt` is stamped *before* the take
   goes out, so "unspent by my clock" implies the atServer has not expired it
   either, so the lock cannot be a successor's — closing the stolen-release
   window properly while keeping rotation responsive.
   **gkc rejected it.** Step 6 of the election protocol
   ([decisions 105.2](detail/decisions.md#1052-the-protocol-gkc-specified)) is
   that the winner does not delete the lock, and it binds rotation as well as
   the mint election. The cooldown is the design, not a cost to engineer away.
   ⚠️ **It will look like an obvious improvement again**, because the refusal
   is visible in a test failure and the change is six lines. What is not
   visible from the code is that a lock nobody deletes has **no**
   stolen-release window to close, and adding a delete back reintroduces the
   whole class — which is what
   [14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) item 18
   was, and it took two sessions to kill. If this is re-opened, the thing to
   change is the *protocol*, in a ruling — not `MintLock`. See
   [decisions 105.6](detail/decisions.md#1056-built-the-cooldown-binds-rotation-too).

8. **`revokeEnrollmentAndRotate` does NOT retry a rotation the cooldown
   refused, and that was decided rather than overlooked.** It revokes first, so
   a refusal leaves the enrollment cut off from the atServer while still
   holding the live generation. Retrying in-process would mean sleeping for the
   ttl inside a call that already did the destructive half, and swallowing the
   partial state rather than surfacing it. It instead catches per namespace,
   logs `severe` naming the cooldown as the likely cause, and carries on to the
   other namespaces. If this is revisited, the question is whether the CALLER
   can see which namespaces failed — `outcomes` lists only the successes today,
   so a caller counting them cannot tell a refusal from a namespace that had
   nothing to rotate.


### 14.17 Signature agility — complete

✅ **COMPLETE 2026-08-18.** Steps 1–5 are done and step 6 is out of scope by
gkc's ruling. The last piece to land was step 5's signed-envelope 3×3
(UC-G1.15), which is what makes
[`decisions.md` 108](detail/decisions.md#108-the-signing-rollout-swaps-algorithms-it-never-overlaps-them-2026-08-18)
a measurement rather than a ruling.

⚠️ **This entry spent five days claiming steps 4 and 5 were owed after they had
shipped**, because it was written 2026-08-11 and never re-read against the tree
while [14.18](#1418-the-remaining-d1-initial-development-sequence) built the
work. The individual strikes below say what each row used to claim. The reason
nothing caught it is worth more than the corrections: the `UC-G1.x` rows this
entry is accepted against are the one cluster of the catalogue no rail checks —
`manifest.dart`'s regexes hard-code `UC-[ABC]`.

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
   - ~~**The strength order** beside `SigningAlgoType` in at_chops, with its
     raw-literal tripwire~~ — ✅ **BUILT 2026-08-13** as [14.18 step 7](#1418-the-remaining-d1-initial-development-sequence):
     `SigningAlgoType.strongestFirst` and `strongestOf` at
     `packages/at_chops/lib/src/algorithm/algo_type.dart:37`, with
     `packages/at_chops/test/signing_strength_test.dart` as the tripwire, and
     [UC-G1.7](acceptance.md#16-g1--signature-agility-and-the-rollout-matrix)
     ("the verifier takes the strongest and does not fall back") reads PROVEN in
     the catalogue. This bullet said "no ordering exists anywhere in at_chops or
     at_client today" for 5 days after it shipped, which left the plan claiming
     an at_chops obligation it did not have.
   - ~~**The `enroll:update` caller** and its PoP signature~~ — ✅ **BUILT
     2026-08-13** as [14.18 step 16](#1418-the-remaining-d1-initial-development-sequence):
     `AtEnrollment.update`, `EnrollmentUpdateRequest`, `EnrollmentUpdater` and
     `apkamPossessionSignature` (`AtSigningMode.pkam`, SHA-256 — ruling 14, and
     `AtSigningMode.data` cannot work). ⚠️ A rotation is not persisted anywhere,
     [14.19 item 11](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on).
   - ~~**The in-use signing set** on `AtClientPreference`~~ — ✅ **BUILT
     2026-08-13** as [14.18 step 17](#1418-the-remaining-d1-initial-development-sequence):
     `dataSigningKeyAlgorithms`, defaulted from `PqPosture`. The deprecated
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
4. ~~**The rollout axis.**~~ **DONE 2026-08-13** as
   [14.18](#1418-the-remaining-d1-initial-development-sequence) step 19, and
   built out further by rows B1 and B3 on 2026-08-14. ⚠️ **This item read "the
   axis has no name yet" until 2026-08-18, and had been false for five days.**
   The axes are `PqPosture.authenticationKeyAlgorithm` and
   `PqPosture.dataSigningKeyAlgorithms`, each overridable on
   `AtClientPreference`, and read in production by `self_retrofit.dart`,
   `signing_key_minting.dart` and the `_apsk` composer. They were one enum,
   `SigningRollout` (`now`/`rollout1`/`rollout2`), until
   [ruling 113](detail/decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18)
   split them. Its premise was wrong as well as its status: the stage does
   **not** switch three flags. Only minting is a decision; the array form and
   the second signature are consequences of how many keys the keyfile holds,
   and the posture supplies one default,
   `AtClientPreference.dataSigningKeyAlgorithms`.
   [`design.md` 9.7](design.md#9-subsystem-g--signature-agility-the-authsigning-key-split)
   has said so since it was written, which is where this row should have been
   checked against.
5. **The rollout harness — the data path is built; the envelope grid is owed.**
   ⚠️ **This item read as wholly owed, and named a 3×3, until 2026-08-18.**
   Built as [14.18](#1418-the-remaining-d1-initial-development-sequence) steps
   20–22: the two stage-parameterised executables are `tests/pq_matrix/`
   (`scenario/`, `current/`, `published/`), driven by
   `tests/at_functional_test/test/pq_rollout_matrix_test.dart` as a **4×4**
   matrix over `published`/`legacy`/`pqReady`/`pqActive`. All sixteen cells pass,
   and the "failing cell asserted by its specific error" this row asks for no
   longer exists — both cells were measured out of existence on 2026-08-14 and
   [`acceptance.md` 16.5](acceptance.md#165-the-rollout-matrix) records what it
   used to say.

   ✅ **The signed-envelope grid closed it the same day.** It was the one piece
   of this row genuinely owed — the 4×4 does not touch the envelope path at all
   (`git grep 'wrapAndSign\|signEnvelope\|verifyEnvelope' -- tests/pq_matrix`
   returned nothing, against `EnvelopeSigning` as a positive control), so the
   sixteen green cells were not evidence about envelope verification. Built as
   UC-G1.15: nine cells over `legacy`/`pqReady`/`pqActive`, each signing at the
   sender's stage and verifying at the receiver's through a real `_apsk` fetch.
   It is a 3×3 rather than a fourth row and column because a released client and
   this tree cannot exchange an envelope in either direction under any stage.

   **`pqActive → pqReady` passes**, which is what turns
   [`decisions.md` 108](detail/decisions.md#108-the-signing-rollout-swaps-algorithms-it-never-overlaps-them-2026-08-18)
   from a ruling into a measurement: strongest signer, weakest verifier, and no
   overlap needed because verification is ungated.

   ⚠️ **The nine cells are not what proves the stages differ, and this is
   measured rather than argued.** Mutating `pqActive` to resolve as `pqReady`
   leaves **all nine passing** — a sender signing RSA-2048 verifies everywhere
   too. What catches it is the algorithm assertion: `pqActive → pqActive` must
   be exactly `['ML-DSA-65']`, `legacy → legacy` must not contain it. Both arms
   in one
   session: the mutation reddens naming `['RS256']`, the revert is green.
   The envelope half lives in `current/lib/envelope_exchange.dart`, not the
   shared scenario, because 3.14.0's `wrapAndSign` returns a `Map` where this
   tree's returns a `SignedEnvelope` and 3.14.0 ships no `lib/src/signing/` —
   a shared file would not compile on the published arm.
6. ~~**`enroll:update` parity across atServer implementations.**~~
   ⛔ **OUT OF SCOPE — gkc, 2026-08-18.** Do not re-raise it, and do not file a
   tracking issue for it. Recorded here rather than deleted because it was
   raised three times in one session, each time from re-reading this row as
   owed.

⚠️ **"Still owed: an `mldsa65` arm on the rotation tests" was struck 2026-08-18.**
The sentence dated from 2026-08-11 and the arm has since been written:
`packages/at_auth/test/enrollment_update_test.dart` carries both algorithms (15
`rsa2048` mentions, 10 `mldsa65`), and `signing_key_minting_test.dart` covers
the mint-and-retire path under `mldsa65`. The reasoning it recorded is still
right — picking `rsa2048` for a fixture is the choice that makes a wrong answer
invisible — which is why it is struck here rather than deleted.

### 14.15 Pre-PR rails checklist

✅ **NOTHING OWED, since 2026-08-10.** The single item is struck below. What
remains is the external gate — the published atServer image verifying ML-DSA
PKAM — and that is **step 32's blocker**, not a checklist entry. ⚠️ This section
sat in the TODO table until 2026-08-18 because its opening read as a condition
rather than a status, which also put the done marker outside the window the new
TODO-row guard reads.

No PR opens against this branch until the published atServer image verifies
ML-DSA PKAM (owner's call, 2026-08-08). The one thing that had to be true by
then:

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

`EnrollmentRecordPrivilegeResolver.isFullyPrivileged()`
(`service/enrollment_privilege_resolver.dart`) returns **true unconditionally
when `enrollmentId == null`**, ⚠️ **and its own dartdoc now argues the case this
item still frames as an open question** — *"a client with no enrollment id is
authenticating with the atSign's own keys, which is full privilege by
construction rather than by grant."* The behaviour is unchanged. This item cited
`AtClientImpl._resolveFullPrivilege()` until 2026-08-18, a name that had been
moved verbatim on 2026-08-10 (`289bbe453`) and exists in no source file —
`git grep` finds it only in these docs. Also, and `ApkamSigning.enrollmentId` substitutes the
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

**Re-measured 2026-08-18** (⚠️ **re-run it rather than quoting the table** —
`at_client` read 340 here from 2026-08-13 until this measurement, and the
heading said 299 and named only at_client before that). Per package,
`dart analyze lib test` from each package directory, exit code printed
separately, counted with `grep -c deprecated_member_use`. Every package exited
0, and only `at_client` moved:

| package | findings |
|---|---|
| `at_client` | 345 |
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


### After D1

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

### 14.41 What the first CI runs on the spike branch found

CI had never run on `gkc-pq-d1-spike` and structurally could not: both
workflows trigger only on `trunk`. Dispatched manually 2026-08-20 through
`workflow_dispatch`, on both `at_client_sdk.yaml` and `at_libraries.yaml`.
Everything below is from those runs plus the re-runs after each fix.

**Three CI-only defects were found and fixed**, none of them in library code:

| Fixed | What it was | How it is known to be fixed |
|-------|-------------|------------------------------|
| The VE image | Three jobs took the compose default `vip`; the post-quantum tests need a trunk-tracking atServer | `functional_tests` green on both channels against `dev_env` |
| The format gate | 95 files did not satisfy `dart format . -o none --set-exit-if-changed` in at_client and at_client_flutter | `unit_at_client` and `unit_at_client_flutter` went red to green on both channels |
| The e2e readiness step | `supervisorctl status` exits non-zero whenever ANY program is not RUNNING, and `pkamLoad` is deliberately `STOPPED`. As the last command of the step it failed a container that was in fact healthy | `legacy_server_tests` green for the first time; `pqe2e_tests` reaches its tests and runs 16 of 17 |

⚠️ **The same readiness bug is still in `tests/at_end2end_test/runLocal.sh`**,
where the loop cannot succeed either — so every local e2e run silently waits
the full 60 seconds before doing anything. Harmless, and worth removing.

**All four are fixed.** ⚠️ **"CI is green" is a claim about ONE workflow at ONE
commit, so say which:** `at_client_sdk.yaml` run **32392240064**, 11 of 11, on
`f24ee3ab6` — the head with `origin/trunk` merged in, covering at_commons #2168.
`at_libraries.yaml` last went green on a **different** commit, and docs commits
have landed since, so **no run covers the current head**. Re-derive before
repeating the claim; the command is in the re-derivation block.
wrong image. A convergence race remains, recorded below as a rate and owed in
[14.43](#1443-the-functional-suites-convergence-race). This section said "three" until
2026-08-20, when a fourth was found in `at_libraries`' matrix that had never
been recorded here at all — and that fourth turned out to be the cheapest of
the lot, a CI step running the wrong image.

⚠️ **Only ONE of the four was a product defect.** Rows 2 and 4 were harness
assumptions that had been holding by luck — an environment variable that
happened to survive, a file order that happened to be favourable — and both
failed deterministically the moment the luck changed. Row 1 was the real bug. None was the image, and none was a
flake: gkc ruled out infrastructure on 2026-08-20.

1. **`notify_test.dart` — FIXED 2026-08-20. A closed connection held the
   request mutex for 30 seconds.** `end2end_tests` was 36 of 37.

   Nothing to do with notifications, and nothing to do with the monitor. The
   monitor start and the teardown 62 ms later — which this row used to lead
   with — are ordinary atSign-switch behaviour and were a red herring; so is
   the test's name, which promises listening it never does (it reads back with
   `notifyList`). What actually happened, from the local log:

   ```
   12:44:59.882  @bob's PqClientBootstrap sends a verb, and waits for the reply
   12:44:59.885  the test switches atSign, so AtClientImpl.stop() destroys
                 @bob's socket 3 ms into that wait
   12:45:00.468  the test switches back to @bob and calls notifyList
   12:45:29.885  the test times out, 30 s after it started
   12:45:29.886  the abandoned read gives up and releases the mutex, one
                 millisecond too late
   ```

   `OutboundMessageListener.read` had no way to notice that its connection was
   gone: it woke only on a queued response or a deadline, so it sat out the
   full transient budget. `AtLookupImpl._process` holds `requestResponseMutex`
   across that read, and `AtClientImpl.create` memoises one client per atSign —
   so switching back to @bob handed the test the same AtLookupImpl, and its
   first verb queued behind a response that could never arrive.

   **Why it was a regression rather than a long-standing bug:** the defect is on
   trunk too, but the transient budget there is the parameter default of
   **10 s**, where this branch takes `AtNetworkTimeouts.effectiveDefault` —
   **30 s**. Ten seconds fits inside `dart test`'s 30-second per-test timeout;
   thirty does not. ⚠️ `AtNetworkTimeouts`' own dartdoc records that
   `defaultResponseBudget`'s 90 s "preserves the long-standing default … so
   adopting this changes no behaviour" — true of the whole-response budget, and
   silent about the transient one, which tripled in the same change.

   Fixed in at_lookup: every close routes through one place that fails the
   pending read first, and the caller gets a `ConnectionInvalidException`
   naming the closed connection instead of an `AtTimeoutException` pointing at
   the atServer. Pinned by four arms in
   `packages/at_lookup/test/socket_delivery_test.dart` — measured at **3003 ms
   against a 3000 ms budget before, immediate after** — the fourth holding the
   line that a response already parsed is still returned.

   Re-run it rather than trusting this row:

   ```bash
   cd tests/at_end2end_test && ./runLocal.sh 26000 test/notify_test.dart
   ```

   Green twice locally on 2026-08-20, and the second run carries the proof that
   the fix is what did it: `Connection closed with a request in flight` at
   13:01:25.009403, 211 microseconds after `AtClientImpl (@bob) stop()`, where
   the same request previously took 30.003 seconds. **`end2end_tests` is then
   green in CI** on run 32369016084 — so this is confirmed against the @ce2e
   atSigns too, not only the virtualenv.

2. **`nskey_recipient_not_ready_test.dart` UC-A4.2 — FIXED 2026-08-20. The
   control borrowed another file's side effect.** `pqe2e_tests` was 16 of 17,
   red on `control: readiness must be able to say yes, or its "no" carries no
   information` — the test correctly refusing to certify its own "no".

   The control asked whether `@bob` was ready for the **shared** `e2e_test`
   namespace. Nothing in that file made him ready: the e2e preferences set no
   crypto config and no posture, so an e2e client is legacy by construction and
   never mints an nskey on its own. It answered "yes" only when one of
   `era_default_read`, `nskey_notify` or `nskey_cross_atsign` had already
   minted @bob's `e2e_test` key.

   ⚠️ **`dart test` does not order files alphabetically, and the order is not
   stable between runs.** CI ran this file **first** of five; a later local run
   of the same directory ordered them
   `nskey_multi_enrollment, era_default_read, nskey_cross_atsign, nskey_notify,
   nskey_recipient_not_ready`. So the row was deterministic in CI and invisible
   in a directory run that happened to schedule it late — do not read a green
   directory run as evidence about this class of defect.

   Fixed by making the file establish every fact it asserts: it moves onto
   `ConcurrentClients` (so @bob can be brought up without the singleton tearing
   alice's client down) and @bob mints a **run-unique** warm namespace as the
   control's yes-case. The control still exercises the same query; it no longer
   adds a writer to the shared namespace.

   Measured, file run ALONE, both arms in one session — which is the arm that
   discriminates, since a directory run may schedule it late and pass either
   way:

   | arm | result |
   |-----|--------|
   | before the fix | control fails |
   | after the fix  | passes |

   Whole directory as CI invokes it (`test/pq -x legacy-server`): **17 of 17**.

3. **`end2end_test_14` — the setup is FIXED; a second layer is now visible.**

   **The setup step was SLOW, not stuck, and its budget was the framework
   default.** Measured 2026-08-20: given five minutes, all four approvals pass
   in **4:59**. Given thirty seconds they all time out. Two defects fixed:
   the step ran with `dart run`, which exits 0 even when its tests fail — so it
   went green with four timed-out approvals and the failure surfaced three
   minutes later as eight missing-keyfile errors in a different step — and the
   budget is now fifteen minutes, because 4:59 against 5:00 is a coin toss.

   ⚠️ **Sync volume is NOT a sufficient cause, and this row said it was.**
   `end2end_tests` runs the SAME four @ce2e atSigns (config23 lists the same
   set config14 does, reordered) and the SAME suite, and it is green. The
   differentiator is that `end2end_test_14` runs `enrollment_setup.dart` first.

   **The second layer, and the strongest lead on it.** With the setup passing,
   the suite reaches 34 tests instead of 12 and 18 fail, on
   `PKAM Keypair required for signing`. `AtClientImpl` has exactly **one**
   `_atKeysIo` field and it serves two jobs: the nskey private store handed to
   `PqClientBootstrap` (`at_client_impl.dart:610`) **and** the authentication
   key source in `_createAtChops` (`at_client_impl.dart:1651`), which prefers
   it over the local secondary. This branch's `test_initializers.dart` points
   that field at `<hiveStoragePath>/<atSign>.nskey.atKeys` and seeds it with an
   **empty `AtKeys()`**. A client that is not handed an `atChops` therefore
   authenticates from an empty keyfile.

   ⭐ **ROOT-CAUSED 2026-08-20, and it is the client cache key.** The
   `_atKeysIo` reading above was a wrong turn — the failing client's
   `_atKeysIo` is **null**; it takes `_createAtChops`' local-secondary branch.
   The actual chain, every link observed, and it **reproduces locally in about
   three minutes** (`enrollment_setup.dart` then `notify_test.dart` against the
   virtualenv, no @ce2e atSigns and no CI round trip):

   1. `enrollment_setup.dart` enrols an app per atSign and writes an
      **`enrollmentId` into the keyfile** — confirmed by reading
      `atKeys/@alice🛠_key.atKeys` after a local run.
   2. `testInitializer`'s apkam auth then passes that id, so the client is
      filed under `(atSign, enrollmentId)`.
   3. Tests like `notify_test.dart` call
      `setCurrentAtSign(atSign, namespace, preference)` with **no** enrollment
      id, which looks up `(atSign, null)`, **misses**, and builds a fresh client
      with no `atChops` and no `atKeysIo`.
   4. That client's `_createAtChops` falls through to the local secondary, which
      holds no PKAM key, and every verb fails
      **`PKAM Keypair required for signing`**.

   **Why it is a spike regression, mechanically.** Trunk keys the cache on the
   **atSign alone** (`atClientInstanceMap[currentAtSign]`); this branch keys it
   on **`(atSign, enrollmentId)`** via `AtClientImpl.instanceKey`. On trunk the
   bare call hits the very entry `testInitializer` created and gets the
   credentialed client. That is also why only `end2end_test_14` fails: it is the
   only job that runs `enrollment_setup` first, so the only one whose keyfile
   carries an enrollment id at all.

   ⚠️ **The change itself is right** — keying a client cache on the owner alone
   hands a caller another principal's object, and the code says so. What is
   unsettled is what `enrollmentId: null` should MEAN once an enrolled client
   exists for that atSign: return it, refuse loudly, or build the
   uncredentialed one it currently builds. **RULED by gkc 2026-08-20 and shipped in `0c79164fa`:** an
   unnamed enrollment falls back to the atSign's client when there is exactly
   ONE, and refuses naming the available ids when there are several. This
   paragraph asked for a ruling that now exists; do not go and ask for it
   again.
   It is a standalone setup step (`dart run test/enrollment_setup.dart`), not a
   test on `dart_test.yaml`'s allowlist, so its failure cascades: the 8 later
   failures all read `provided keys file does not exist`, for the keyfile the
   timed-out step never wrote. The throw is `OutboundMessageListener.read`'s
   *transient* branch, meaning `_lastReceivedTime` never moved — no bytes at
   all, not a partial response. ⚠️ **Row 1's fix does NOT close it — measured,
   not assumed.** `end2end_test_14` is still red on run 32369016084, the first
   CI run carrying the connection fix, so the shared fingerprint was a
   coincidence of symptom and the cause is a different one. ⚠️ This row used to end "It cannot be
   reproduced locally … so iterating on it costs a CI round trip", which was
   never true of the script: the blocker was `AtCredentials.credentialsMap`
   being a stub in every checkout, and the harness now seeds it from
   `AtTestCredentials`.

4. **`functional_tests_at_onboarding_cli` — a fourth red row, and it was never
   recorded here.** The non-proxy leg of `at_libraries`' matrix runs 16 of 17;
   the red is `pq_native_onboard_test.dart`'s "a CLI activation under the
   pqReady posture is PQ-native", failing PKAM for `@denise` with a
   **server-side** `AT0010-Exception: RangeError: Value not in range:
   -2881644029407446706`. Red on run 32360105692 as well, so it predates the
   connection fix. That test is new on this branch, so there is no trunk arm to
   compare against.

   **ROOT-CAUSED and fixed 2026-08-20: the job was running the published
   image.** ⚠️ This row first said "It is NOT the image, the env is set at job
   level and both matrix legs inherit it" — that was wrong, and wrong in an
   instructive way. The variable *is* set on the job, and the step ran
   `sudo docker compose up -d`; **`sudo` resets the environment**, so compose
   never saw `VIRTUALENV_IMAGE` and fell back to the `atsigncompany/virtualenv:vip`
   default in `docker-compose.yaml`. The published atServer cannot verify an
   ML-DSA PKAM signature, and its symptom is exactly this `RangeError`.

   It is the only container job in either workflow that used `sudo`; every one
   in `at_client_sdk.yaml` runs plain `docker compose` and gets its image. The
   fix drops the `sudo` and adds a step that inspects the **running**
   container and fails loudly when it is not the image the job asked for —
   because a wrong image otherwise presents as a client-side bug.

   Measured, both arms in one session, one variable changed:

   | image | result |
   |-------|--------|
   | `atsigncompany/virtualenv:dev_env` | 2 of 2 pass |
   | `atsigncompany/virtualenv:vip`     | `Pkam auth failed … AT0010-Exception: RangeError` |

   ⚠️ The earlier claim came from parsing the YAML and printing the resolved
   image per job. That measures what the *job* declares, not what *compose*
   receives — a validation of the wrong thing, and it read as thorough.

⚠️ **A fifth row, on the BETA Dart channel only, and it is a rate rather than
a kind.** `functional_tests (beta)` has failed **3 of 5** runs on 2026-08-20 —
`sync_multiple_client_test.dart` once and `pq_rollout_matrix_test.dart`'s
UC-G1.15 **twice, consecutively**. `functional_tests (stable)` is 0 of 5, and a
local full pack on stable was 177/177.

⭐ **This is a RACE, not a channel defect** (gkc, 2026-08-20). The rates say
so: **beta 3 red in 6, stable 1 red in 6**, and a race is what produces that
shape — the beta SDK's different timing widens the window rather than
introducing a bug. Reading it as "beta-only" was wrong twice over: stable has
now hit it too, and the framing pointed the search at the Dart channel instead
of at the window.

**Where the search has got to, and what is NOT established.** The harness's
`FunctionalTestSyncService.syncData()` waits on a LEVEL — it loops until
`localCommitId == serverCommitId` and nothing is pending — rather than on
*this test's writes having been pushed*. The only thing between a test's writes
and that check is a blind `await Future.delayed(Duration(milliseconds: 100))`.
In the local failure of 2026-08-20 it returned in **7 ms** reporting
`pending push count: 0` with the ids already equal, immediately after the test
had done three writes. ⚠️ **That is a characterisation, not a discriminator:**
a PASSING run shows a first `syncData` completing just as fast with
`pending push count: 0` too, so the pattern alone does not separate pass from
fail. Do not report it as the cause without an arm that does.

⛔ **Disproven, so nobody re-walks them.** The progress events are NOT dropped
by attaching the listener late — `MySyncProgressListener.streamController` is a
plain single-subscription `StreamController` and BUFFERS. And `syncData()`'s
`syncOutcome.complete()` on `SyncStatus.failure` — which does treat a failed
sync as done, and is a real defect worth fixing on its own — is NOT what fired
here: `SyncStatus.failure` appears **zero** times in the failing log.

Corroborating: **three of the four observed failures are notify/sync
convergence** — `sync_multiple_client_test` ("keys synced from multiple clients
converge"), `atclient_sync_conflict_test` ("notify updating of a key to
sharedWith atSign"), and UC-G1.15's cross-stage envelope verification. One
commit ran UC-G1.15 green on stable and red on beta in run 32381845256, which
is what a timing window looks like rather than a code difference. ⚠️ This row
first read "a different test each time", then "beta-only"; both were
falsified.

What the UC-G1.15 instance showed, recorded because it is the useful part:

- The failing cell was `pqActive → pqReady`, on
  `AtSigningVerificationException` — the receiver read `@alice`'s `_apsk`
  holding **exactly one key**, `kid f10e7bd62684126f`, `alg mldsa65`, and could
  not verify the envelope with it. So it is not a stale advertisement holding
  the pre-PQ key; it is an advertisement holding a key that did not sign.
- ⭐ **The same stage pair PASSES as its own test minutes earlier** (`✅
  pqActive sender to pqReady receiver`, 14:24:16) and fails inside UC-G1.15's
  nine-cell loop (14:25:53). Both go through the same `runCell`. **The variable
  is back-to-back-ness**, not the pair — the standalone tests are separated by
  framework overhead and the nine cells are not.
- Every cell overwrites `@alice`'s single `_apsk` record, and sender and
  receiver are separate processes. So a receiver can fetch an advertisement
  that a neighbouring cell published, or fetch before its own sender's publish
  has landed — the shape where a value and a pointer to it travel by different
  transports and race.
- ⚠️ The verifier's kid appears **once** in the whole 465k-line job log while
  other kids appear 4–9 times. Suggestive, NOT decisive: kids are only logged
  when a key package is, so that is a claim about the log.

**Four hypotheses are disproven, recorded so nobody re-walks them:** the
advertisement is NOT written local-first (`publishPublicSigningKey` passes
`useRemoteAtServer = true`); it is NOT the documented mint/publish race, whose
signature is an ML-DSA array replaced by a bare RSA string; there is NO mutex
contention with sync, because `SyncServiceImpl.create(atClient)` builds its own
`RemoteSecondary` and so its own connection; and the
`does not verify against its _apsk` SEVEREs are not the differentiator — they
appear **19 times in the PASSING stable log** against 17 in the failing beta
one. That last one is worth its own look some day: every functional run on both
channels logs 17–19 key-package verification failures and nothing fails.

⚠️ **A sixth row, seen once and recorded as a rate rather than a kind.**
`functional_tests (beta)` failed `sync_multiple_client_test.dart` ("keys synced
from multiple clients converge to the same value") at 176 of 177 on the
2026-08-20 16b00787c run, having passed on the 8295cea5b run an hour earlier.
`functional_tests (stable)` passed both, and both channels passed again on run
32369016084. So: **1 red in 3 beta runs, 0 in 3 stable runs** — not enough to
call it anything. Do not describe it as a flake or as a regression without
more runs.

**Four mechanisms were read and disproven** for rows 1 and 3, recorded so
nobody re-walks them: the monitor and verb sockets are *not* collapsed
(`NotificationServiceImpl` builds a deliberate fresh `AtLookUp.withSecureSocket`
and says why); `messageListener` cannot drift from `_connection` (both are
rebuilt together inside `createConnection`); a non-notification lookup *does*
notice a dead socket (`onSocketDone`/`onSocketError` call `closeConnection`
unconditionally, and the `onDisconnect` seam is additive); and Monitor's
`_notificationSubscription ??=` cannot hold a closed controller, because
`_stop()` nulls both subscriptions.

⚠️ **A measurement trap this cost an hour to.** Probing
`atsigncompany/virtualenv:dev_env` from `docker images` reads whatever was
cached locally, which can be months old — the copy on this machine was from
3 July and lacked both `mldsa65` and #2755, which produced a confident and
entirely wrong conclusion that the image ruling had been a mistake. **Pull
before probing.** The freshly pulled image is the Aug 19 build and carries
both. The contradiction that caught it was
`self_enrollment_retrofit_live_test.dart` passing "ML-DSA PKAM succeeds" on an
image just measured as lacking ML-DSA.

### 14.42 Why enrollment setup takes four minutes

`enrollment_setup.dart` submits and approves one enrollment for each of the
four @ce2e atSigns. Measured 2026-08-20 in `end2end_test_14`: **3:56** on one
run and **4:59** on another. Under the framework's 30-second default every
approval timed out; the budget is now `@Timeout(Duration(minutes: 15))`, which
stops the job failing but explains nothing. **gkc asked for the cause.**

⚠️ **My sync-backlog reading is NOT established, and is recorded here so it is
not inherited as fact.** The atSigns' commit logs do reach 836853 entries and a
fresh runner replays from `-1` — both measured — but `end2end_tests` runs **the
same four atSigns** (config23 names the same set config14 does, reordered) and
**the same suite** in about three minutes. So the backlog cannot be the whole
answer; the enrollment step is what differs.

⛔ **This does NOT reproduce locally, and an earlier draft of this section said
it did.** `runLocal.sh` regenerates `config/config.yaml` from `at_demo_data`
(`runLocal.sh:28`), so a local run drives DEMO atSigns — and against those the
same four enrollments finish in about **one second**. Running it locally
reproduces the symptom's *absence*.

That one-second figure is still the most useful measurement here: the same code
is four orders of magnitude apart on demo atSigns versus @ce2e, so whatever
costs the four minutes is a property of the **@ce2e side**, not of the script.

Reaching the symptom needs `config/config14.yaml` (which names @ce2e1–4 against
`root.atsign.wtf`) and the @ce2e credentials that CI injects from a secret —
**and nothing here records how to obtain those on a developer machine.** So the
realistic first move is a CI round trip with instrumentation added, via
`.github/workflows/at_client_sdk.yaml`'s `end2end_test_14` job. Budget for that
rather than expecting a local loop.

### 14.43 The functional suite's convergence race

**CI: beta 3 failures in 10 runs, stable 1 in 10** — measured 2026-08-20 by the
command in the re-derivation block at the end of this file, not transcribed.
Locally, **1 red in 5** packs the same day. ⛔ **Those two figures are the ONLY
rates to quote for this row. Every other one written on this page came from a
partial view and is superseded** — the page has carried six mutually
incompatible versions, which is why the command exists.

The observed failures — four in the functional pack, plus
[14.34](#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart)'s,
very probably the same thing — are all waits on update/notify/sync convergence:
`atclient_sync_callback_test` (local pack 2026-08-20: "latest commit entry is
updated when same key is updated and deleted", expected `-` got `*`),
`atclient_sync_conflict_test`, `sync_multiple_client_test`, and
`pq_rollout_matrix_test`'s UC-G1.15. ⚠️ Not a Dart-channel defect — beta is
redder because its timing widens the window, and one commit ran UC-G1.15 green
on stable and red on beta
**Reproduces locally**: `cd tests/at_functional_test && ./runLocal.sh`.

⛔ **Disproven hypotheses are listed and must not be re-walked** — they are listed in
[14.41](#1441-what-the-first-ci-runs-on-the-spike-branch-found), and the two
most attractive are that the progress events are dropped by attaching a
listener late (they are not: the controller is single-subscription and buffers)
and that `syncData()` completing on a failed sync is what fires (it is not:
`SyncStatus.failure` appears zero times in the failing log).

⛔ **Three more disproven, 2026-08-20, so nobody re-walks them.** The expiry hot
loop of [14.45](#1445-an-expired-key-the-client-cannot-delete-pins-it-in-a-hot-loop)
is **not** the cause — the run carrying all three of its loops was green at
177/177, so presence does not produce the failures (a *rate* effect is not
excluded and would need the pack run N times either side of that fix).
`SyncServiceWaitUntilCaughtUp.waitUntilCaughtUp` does **not** guard the null-id
"server and local are in sync" event that `FunctionalTestSyncService` completes
on — `sync_service.dart:90-95` deliberately completes on it too, so the two
waiters do not differ there. And an awaited `put()` **has** reached the sync
queue by the time it returns: `local_secondary.dart` awaits `_enqueueForSync`
before `_update` returns, so "the writes were not queued yet" is not available
as an explanation.

✅ **Two failing runs captured, 2026-08-20 evening, on different instruments.**
(This paragraph said "still no captured failing run" until that evening.)

- **Local**: 4 packs at `cfd511663` — 3 green, 1 red. The red's full log (at
  the pack's own log level) is `untracked/pq-1443-packs/run_4_20260820_223443.log`,
  **on this machine only** — `untracked/` is gitignored. Failing test:
  `atclient_sync_conflict_test.dart` "notify updating of a key to sharedWith
  atSign - using await", asserting at line 76 that the pulled
  `phone_0.wavi@alice🛠` keyInfo carries `conflictInfo` — it was **null**. The
  surrounding log shows the sync pull completing `SyncStatus.success` and the
  key arriving `remoteToLocal`; what did not happen is the conflict
  computation populating `conflictInfo`.
- **CI beta**: run `32418455392` on the same `cfd511663`,
  `functional_tests (beta)`, `pq_rollout_matrix_test.dart` UC-G1.15, cell
  `pqReady → pqActive`: `AtSigningVerificationException` — the envelope's
  rsa2048 signature does not verify against **the one rsa2048 key the
  published `_apsk` advertises**. Fetch with
  `gh run view 32418455392 --log-failed`. The smell is a stale or overwritten
  advertisement: whether the verifier read the signer's `_apsk` or a
  later-published one is a race on record convergence between the matrix's
  stage clients.

Two different failure signatures in one family — do not assume one cause
covers both.

⚠️ **Start by reading [14.34](#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart),
which is very probably the same thing.** It records an unexplained intermittent
in the same pack, timing out at `await firstNotification`, passing when its file
runs alone — recorded 2026-08-17 and recurring 2026-08-19, well before the four
below. That makes **five** files in one family, not four. ⚠️ Do NOT pool the
rates: 14.34's observations (1 of 5 runs, then 1 of 2) were taken on tree states
this branch has since moved past — 14.34 says so itself — and on a different
file. Two figures from different instruments are not a comparison, however
carefully each was taken. **Not asserted as identical**; nobody has shown one
cause covers both.

⭐ **The pattern to look for first: a test that passes only because of what
ran before it.** Three independent instances on this branch now, two of them
found by different people:

1. **UC-A4.2's control** asked whether @bob was ready for the shared namespace
   while nothing in its own file made him ready — green only when one of three
   other files had minted first. Fixed `454bedbbd`.
2. **`encryption_test.dart`'s monitor replay** — fixed on trunk by
   `6b91035b4` and arriving here with the 2026-08-20 merge. Its commit message
   is the clearest statement of the shape: "*without it this test only passes
   when some other test file happened to start atSign_2's monitor first, which
   is what made it flake*".
3. The four convergence failures above — **unproven**, but this is where to
   look before anything subtler.

⚠️ Instance 2 rests on **deliberate** product behaviour, not a defect, and the
distinction matters: `NotificationServiceImpl.getLastNotificationTime()`
returns null on its FIRST call for a keystore and seeds the record — confirmed
at `notification_service_impl.dart:439-444`, "*return null for THIS call to
keep first-run semantics ('don't replay history I never saw')*" — and a monitor
started with null asks the atServer for no replay. So a first-run subscriber
correctly misses what preceded it, and a test wanting replay must burn that
call itself. Do not "fix" the product here.

**A separate defect found in the same place, worth fixing on its own merits.**
`FunctionalTestSyncService.syncData()` calls `syncOutcome.complete()` on
`SyncStatus.failure`, so a **failed** sync returns to its caller as success. It
did not cause this race, but a harness that reports a failed sync as done will
eventually hide something that matters.

### 14.47 The at_client unit tree has a cross-file isolation flake

Found 2026-08-20 while regression-testing 14.46's edits. Running
`dart test --concurrency=1 test/pq_signing_root_test.dart
test/nskey_minting_test.dart test/nskey_rotation_test.dart
test/local_secondary_sync_queue_test.dart` — that order, which the
alphabetical full suite never produces — failed
`local_secondary_sync_queue_test.dart`'s "public key write enqueues with
op=updateAll" **1 time in 4 runs** (3 green re-runs of the identical
invocation; the file alone is green; the full suite is green). The failure
shape: the asserted queue read `['@bob:phone.wavi@alice',
'public:email@alice']` where only the second entry was expected — an entry
from an *earlier test in the same file* survived into a later test's queue,
which only happens when the file's per-test setup fails to give each test a
fresh store. One baseline run of the same order at the parent commit was
green, so the 14.46 edits are not excluded as a factor — but nothing in them
touches enqueue behaviour, and 1-in-4 vs 0-in-1 distinguishes nothing.

Not pooled with [14.43](#1443-the-functional-suites-convergence-race): that is
the functional pack against a live atServer; this is the unit tree and Hive
state on disk. What it wants: run the four-file order ~10 times either side of
any suspect change, and read `local_secondary_sync_queue_test.dart`'s setup
for what makes its store per-test fresh — the leak says sometimes it isn't.

### 14.46 `executeVerb`'s `sync` parameter is inert, on both secondaries

Found 2026-08-20 while tracing why a `_nskeylock` record reaches local storage.
`MintLock._take` passes `sync: false` and the surrounding dartdoc reasons about
it, so it reads as suppressing the sync of a record that must not be synced. It
suppresses nothing.

`Secondary.executeVerb` declares `{bool? sync, bool cameFromServer = false}`,
and **neither implementation reads `sync` in its body** —
`local_secondary.dart:300` and `remote_secondary.dart:211`; in each the word
appears once, on the signature line (positive control: `builder` appears 10
times in `LocalSecondary.executeVerb`'s body). **52 call sites pass a value into
it**, 39 `false` and 13 `true`, counted with

```bash
perl -0777 -ne 'while(/executeVerb\((?:[^()]|\([^()]*\))*?\bsync:\s*(\w+)/gs){print "$1\n"}' \
  $(git ls-files 'packages/**/*.dart') | sort | uniq -c
```

What actually decides whether a write is enqueued for client→server sync is
`cameFromServer` and `localOnly` in `LocalSecondary._update`/`_delete`. So the
control exists, under different names, and `sync:` is a third name that looks
like it and is not.

**Decided by gkc 2026-08-20: delete it, in two phases.** The parameter is
`@Deprecated` for the remaining 3.x releases and comes out in 4.0 with the rest
of the deprecated detritus, the compiler enumerating the call sites at removal.
Shipped on this branch:

- `@Deprecated` on all six declarations — at_client's `Secondary`,
  `LocalSecondary`, `RemoteSecondary.executeVerb` **and** `executeAndParse`
  (found in the sweep, same defect), plus **at_lookup's** `AtLookUp` /
  `AtLookupImpl`, which 14.46 as filed missed. Deprecating one interface and
  leaving the identical parameter on the layer below would have kept the trap
  in the package about to be carved.
- Every call site whose surrounding prose *reasoned about* the flag no longer
  passes it: `MintLock._take`, `SyncServiceImpl._pullToLocal` (whose dartdoc
  claimed `sync: false` "expresses the same intent" — it expressed nothing),
  the two remote-first publishes in `pq_signing_root.dart` /
  `published_nskey_key_ring.dart`, and at_lookup's example + README, whose
  comment "Set sync attribute to true sync the value to secondary server" was
  the document licensing the wrong pattern.
- Every **cross-package** site (6 in `tests/at_functional_test`, 1 in
  `tests/at_end2end_test`) — those are the only ones the deprecation warns on
  (`deprecated_member_use` is silent within the declaring package), verified
  by injecting one back as a positive control and reading the warning it
  produced.

**Remaining, deliberately:** 7 lib and 69 test sites inside at_client still
pass the argument. They are silent, harmless, and enumerated by the compiler
the day the parameter is removed — cleaning the test stubs by hand now would
churn ~15 files for nothing the 4.0 build won't force anyway. The mocktail
stubs matching `sync: any(named: 'sync')` were proven to still bind when the
caller omits the argument (the nskey/pq unit tests assert on what the stub
recorded, and stayed green).

**Also noticed, neither filed elsewhere:**

- `at_server`'s `apkam_signature_verifier.dart` carries a comment describing
  what `AtChopsImpl` does for `mldsa65` — *"it selects MlDsa65PureDartAlgo, then
  calls the deprecated verify()"*. at_chops #2169 changes that dispatch to
  `PkamMlDsa65SigningAlgo`, whose verify is synchronous, so the comment goes
  stale in the sibling repo when 3.6.0 publishes. Lands in **at_server**, not
  here.
- `docs/projects/pq/post-quantum-cryptography.md` is **untracked** — 271 lines,
  an explainer of the PQ choices, referenced by nothing in the doc set. Either
  finish and track it or delete it; as it stands only this machine has it.

### 14.45 An expired key the client cannot delete pins it in a hot loop

⛔ **Pre-existing on `origin/trunk`, not introduced by this branch** —
`_armExpiryTimer` has 5 hits and `deleteExpiredKeys` 2 there. Found 2026-08-20
while running the pack for [14.43](#1443-the-functional-suites-convergence-race).

**The loop, read from source.** `AtClientImpl._armExpiryTimer`
(`at_client_impl.dart:769`) arms `Timer(Duration.zero, _onExpiryFire)` whenever
the earliest expiry is already in the past — its own dartdoc says so.
`_onExpiryFire` runs `LocalSecondary.deleteExpiredKeys`, whose per-key `catch`
(`local_secondary.dart:585`) logs the failure at `warning` and moves on **without
removing the key**. `_onExpiryFire`'s `finally` then re-arms. The earliest expiry
is still in the past, so the timer is `Duration.zero` again. Nothing removes the
key, nothing backs off, nothing gives up: the client spins for the remainder of
its own lifetime, one `warning` line per turn of the event loop.

**Measured, one local pack run — THREE keys, three loops, all `_nskeylock`:**

| Key | Iterations |
|---------------------------------------------------|-----------:|
| `_nskeylock.cooldown1787252300302993.buzz@bob🛠`   | 186,994 |
| `_nskeylock.ns1787252329248768.wavi@alice🛠`       | 19,965 |
| `_nskeylock.rot1787252358178828.wavi@alice🛠`      | 18,762 |

225,721 in total, **47.4% of the run's 394,523 log lines**. Each is refused with
`Cannot perform delete … due to insufficient privilege`. Intervals tighten from
1259 µs to about 120 µs. The first began during `nskey_rotation_live_test.dart`
and ended only when that test file ended and the next one loaded — *not* by
resolving.

**This is designed-in, not incidental.** `MintLock` releases by ttl and by
nothing else — `mint_lock.dart:80`, "**The winner does not release the lock; the
ttl does**" — so every mint and every rotation creates a record whose only exit
is expiry, and the client cannot delete it when it expires. Every lock is
therefore a future hot loop, and the three above are one run's worth of
ordinary minting.

**Where it comes from, read in the dependency.** `nextExpiresAt()` reports the
earliest expiry in the store **including ones already past**, on both backends
of at_persistence_secondary_server 5.2.1 — Hive takes a bare minimum over every
record with an `expiresAt`, SQLite runs
`SELECT MIN(expires_at) … WHERE expires_at IS NOT NULL`. Its sibling
`nextAvailableAt()` filters (`available_at > ?`; Hive comments *"Strictly after
the cutoff: already-born keys are excluded"*). The asymmetry is fine on its own
— a past expiry means "sweep now" — and at_client's `_armExpiryTimer` is what
adds the assumption that the sweep will then clear it.

✅ **FIXED — the spin, not the refusal.** `AtClientImpl._onExpiryFire` now reads
`deleteExpiredKeys`'s return count and passes `afterFruitlessSweep: removed == 0`
to `_armExpiryTimer`, which floors the delay at 30s instead of arming zero when
the expiry is past and the sweep achieved nothing. The retry survives, so a
refusal that turns out to be transient still heals and a later expiry is still
collected. `AtClientImpl.expiryTimerDelay` is `@visibleForTesting` and its four
branches are pinned in `test/at_client_expiry_timer_test.dart`; reverting the
fix reddens the backoff test, quoting its own reason. ⚠️ **What that test does
NOT cover** is the single line feeding it — a change that always passed `false`
would leave the suite green and restore the spin. Observing it needs a built
`AtClientImpl` with an injected `LocalSecondary`, which was judged not worth the
scaffolding; the test file says so at the top.

✅ **The refusal is FIXED too, and it was not about immutability.** Traced
2026-08-20: the sweep's delete is refused by `isEnrollmentAuthorizedForOperation`
in `LocalSecondary._delete` — a **namespace** check — before any keystore or
server interaction. The lock key parses as `KeyType.selfKey` with namespace
`buzz`/`wavi`, so it is not in the skip list (`reservedKey`, `cachedSharedKey`,
`cachedPublicKey`, `localKey`). The sweep passes `localOnly: true` and so never
builds a `delete:` command at all, which is the only place `force:` appears —
and the client keystore has no immutability guard on remove (`immutable` occurs
20 times in at_persistence_secondary_server 5.1.0, in metadata serialization and
in `AtMetadataBuilder` preserving it across *updates*, never in a remove path;
control: `expiresAt` occurs 68 times). Immutability is the atServer's
enforcement, on the `delete` verb.

`deleteExpiredKeys` now passes `isExpiry: true`, which skips that check.
Reclaiming an expired record is storage internals, not an operation an
enrollment performs, and the scoping is unaffected because an expiry deletion is
local-only and never enqueued for sync. `test/expiry_sweep_authorization_test.dart`
pins both arms — an enrollment-initiated delete outside its namespace is still
refused, and the sweep reclaims the same record — and reverting the bypass
reddens it.

⛔ **Parked by gkc 2026-08-20: why the lock is in local storage at all.** It is
created remote-only (`MintLock._take` → `getRemoteSecondary().executeVerb`, and
`_isOwnLock` → `getRemoteSecondary().executeCommand`), and arrives locally by
the sync pull — the never-synced rule covers `public:_`, not self keys, and
`syncRegex` defaults to null so the pull is unfiltered. Two things stop a client
suppressing it today: the client API has no working suppression control —
`RemoteSecondary.executeVerb`'s `sync` parameter was inert and is now
`@Deprecated` (14.46; `_take` no longer passes it) —
and `:nc`/`noCommit` — which would stop the atServer logging the commit — exists
in at_commons (published 5.15.0, syntax groups for `update`, `update:meta` and
`delete`) but appears in **zero** files of at_server `origin/trunk`.

⚠️ **Owed against `at_persistence_secondary_server` (5.1.0), not fixable here.**
`HiveAtKeyValueStore.get()` does not filter expired records, and carries three
comment lines describing the filter that was never written — *"load metadata for
hive_key / compare availableAt with time.now() / return only between ttl and
ttb"*. It throws `KeyNotFoundException` only when the value is **absent**. So
expiry filtering lives in one caller: of **14** direct `keyStore.get`/`getMeta`
reads in at_client's `lib`, only `LocalSecondary._llookup` applies
`_isActiveKey`. Most of the rest are benign — the private-key getters have no
ttl, and `prevMeta` wants the pre-write value deliberately — but the filter
belongs in the store. ⛔ Do **not** "fix" `_llookup` to throw for an expired key:
returning `'data:null'` is the documented contract, stated at
`collections.dart:1366` as *"data:null (availableAt in future, or post-expiry)"*
and tested for at 16 call sites across 5 files.

⛔ **It is NOT what fires [14.43](#1443-the-functional-suites-convergence-race),
and this is a measurement rather than a guess.** The run these figures come from
was **fully green — 177/177, exit 0** — with all three loops running in it. So
the loop's *presence* does not produce the convergence failures, and a future
session should not adopt it as the cause on the strength of how alarming it
looks. What one green run cannot exclude is a *rate* effect: more event-loop
saturation widening an existing window. Settling that needs the pack's failure
rate over N runs with and without a fix, which is expensive and should wait
until the loop is fixed anyway.

### 14.44 Residuals from the at_chops PR review

The first two were raised by Xlin123 on [PR #2169](https://github.com/atsign-foundation/at_client_sdk/pull/2169)
(2026-08-20) and answered there; neither belongs in that PR — the first is an
at_auth file and the carve is at_chops-only, the second predates the branch.
The third is a promise a reply on that PR made, delivered elsewhere with a
consumer-facing half still owed. All are recorded here rather than left in a
review thread.

**at_chops 3.6.0's CHANGELOG owes the resolution-skew sentence.** A reply on
#2169 promised a record of the skew consequence: two installs of released
at_client 3.14.0, resolved either side of at_chops 3.6.0 publishing, cannot
read each other's pairwise envelopes in either direction for the envelopes'
7-day ttl. The durable record is
[ruling 110's addendum](detail/decisions.md#110-the-0x01-seal-version-is-retired-stop-emitting-before-removing-2026-08-18).
The consumer-facing sentence in the at_chops CHANGELOG's 3.6.0 entry could not
ride #2169 — the PR was approved, pushes dismiss stale approvals, and the
carve gate keeps at_chops byte-identical — so it goes in the next at_chops
touch, amending the 3.6.0 section in place.

**The passphrase envelope does not persist `hashLength`.** `6aa43b772` salts
the `.atKeys` passphrase derivation and spans two packages; the at_chops half
(`ArgonHashParams.salt`, `ArgonHashParams.owaspMinimum`) shipped in #2169, and
the at_auth half — writing the salt and the costs into the envelope and reading
them back — lands with the at_auth carve, position 5 in the train. What that
half persists is `salt`, `memory`, `iterations` and `parallelism`; it does
**not** persist `hashLength`. A caller that changed the key length would write
a file whose own decode path re-derives at 32 bytes and fails, and because the
cipher is unauthenticated the failure arrives as
`AtDecryptionException('passphrase may be incorrect')` — pointing at the
passphrase rather than at the parameter that actually differed.

Two ways to close it, and the second is probably right: persist `hashLength`
alongside the other three, or have `encode` refuse an `ArgonHashParams` whose
`hashLength` is not the default, since nothing in-tree varies it and a stored
parameter nobody sets is a format that cannot be tested. Do it in the at_auth
carve, where that file is already being touched.

**`XWingCore.combine` writes at hardcoded offsets.** It sizes its buffer from
the four inputs' actual lengths and then writes at literal 0/32/64/96/128, so
the two disagree for any component that is not 32 bytes. Measured rather than
reasoned: a **short** input throws `StateError: Too few elements` from
`setRange`, so only an **over-long** one is silently wrong — it truncates to 32
and leaves the tail of the buffer as zeros, yielding a shared secret neither
party can detect is wrong.

Not introduced by the branch. `origin/trunk` carries the same shape in both
`x_wing_pure_dart.dart` and `x_wing_ffi.dart`; extracting them into
`x_wing_core.dart` preserved the risk rather than creating it, though it did
widen the reach — the trunk copies were library-private and the shared one is
package-visible. Unreachable today: every caller passes components whose
lengths the underlying primitives fix at 32. The fix is to reject any
wrong-length input up front against `sharedSecretLength` rather than to track
offsets with a cursor, so that the guard states the contract instead of
silently accommodating a violation of it.

## PARKED

Set aside deliberately. A row here exists to stop someone building it, so
the reason is the point of the row.

| Item  | What it is                                           | Why it is parked |
|-------|------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| 14.26 | A false comment in at_server's `at_metadata_builder` | ⛔ **NOT PART OF D1** (gkc, 2026-08-16). It lands in at_server, off `trunk`, and nothing in D1 waits on it. Detail: [14.26](detail/implementation-plan.md#1426-a-comment-in-at_server-is-now-false) |
| 14.1  | The signing root's `keys[]` shape                    | SUPERSEDED by decisions 101 and 14.22. Kept for the reasoning; two of its conclusions are now false |
| 14.13 | A passive-by-default flag                            | FOLDED AWAY 2026-08-11 into the rollout axis (14.18 step 19). Kept for its survey |
| 14.21 | The signing root cannot be rotated                   | RULED the same day by decisions 101. Kept so 14.22 is legible against it |
| 14.23 | Per-generation nskey records                         | ⛔ REJECTED — do NOT build. 14.24 shipped instead; the body is kept so it is not re-derived |
| KE-2  | The `enroll:update` **writer**                       | **Writer built and live-proven 2026-08-19.** `KeyPackageMinting` is a startup step reconciling the advertised key package against `AtClientPreference.keyEstablishmentAlgorithms` (which replaced the singular `keyEstablishmentAlgo` in the same pass); it mints, files, retires and republishes, unit-tested and isolated by mutation. Verb merged to at_server `trunk`; the client receiver answers at every held kpid. ⚠️ This cell said "nothing mints a second KEM key and re-advertises, so a package cannot gain one" — false since that landed. UC-A2.5 and UC-A2.6 are `PROVEN`, cited to `tests/at_functional_test/test/key_package_amendment_live_test.dart` — the acceptance burn-down is back to **0 skipped**, and the `ke2` blocker constant is deleted. ⚠️ **Three clauses of those rows are NOT proven and deliberately not claimed** (a superseded kpid's envelope still opening, peer negotiation, and the revoked-enrollment gate) — plan 14.19 item 36. Issue #2133 |
| B-3   | Stop **conveying** the legacy `selfEncryptionKey`    | Narrower than it reads: the key's *use* is retired by the release cadence (R-2 flips `disallowLegacyEncryption`), so this is only relaxing `enroll:approve` to accept an approval that omits `encryptedDefaultSelfEncryptionKey` — every atServer implementation, one sweep — then ceasing to mint and convey it. Ecosystem-gated by decisions 37. Issue #2128 |
| KF-1  | `.atKeys`-at-rest protection + backup/restore        | Off the GA critical path. Issue #2129 |
| S-5   | at_auth 4.0.0 WASM barrel split                      | Off the GA critical path |
| S-6   | Consumer constraint bumps onto at_auth ^4.0.0        | Follows S-5 |
| R-2   | at_client 4.0.0 posture defaults                     | After D1, and now after 14.39. **The default `PqPosture` becomes `pqActive`** ([ruling 113](detail/decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18)) — one value, replacing the two coupled edits it used to be. Still a pure default-flip carrying no code of its own. Issue #2016 |
| D2-1  | Carve `at/pqmls` + D1-E shape fixes                  | D2, out of D1 |

---

## DONE

One row each; the detail is in
[`detail/implementation-plan.md`](detail/implementation-plan.md). The third
column reports what the plan **records**, which is not always what was
measured — see [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none).

⚠️ **So not every row here says "done", and the heading names this section's
place in the TODO / DONE / PARKED triad rather than every row's state.** Six
project rows record *no status* or a partial one and point at 14.25; **IS-1
records an OPEN PR** (`at_server#2683`, verified against GitHub 2026-08-18).
That is deliberate and the column header says so — but do not read a row's
presence here as delivery. What is actually left for D1 is
[14.18](#1418-the-remaining-d1-initial-development-sequence)'s steps, not the
absence of a row from this table.

| Item   | What it delivered                                       | State as the plan records it                                                                                         |
|--------|---------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------|
| [14.40](#1440-at_client-publishes-as-a-minor-and-the-heading-now-says-so) | ✅ **DONE — RULED 2026-08-20: at_client publishes as `3.15.0`, a MINOR.** Heading and pubspec both moved; the three `**BREAKING**` labels were rewritten because nothing published was removed — verified against the published 3.14.0 archive, where `disallowLegacyEncryption`, `keyEstablishmentAlgorithms`, `PqPosture` and `ReleasePosture` appear in **zero** files against a control of `AtClientPreference` in 20 | — |
| 14.38  | `at_activate` can administer a PQ-native atSign             | DONE 2026-08-19, live-green (CLI functional pack 17/17 against a locally built `at_virtual_env:local`). All three agreed changes landed, and two of them had been recorded as done when they were not: the `_initAtClient` overwrite survived a change to *which* preference field it read, and the file-stream site was named as methods that do not exist. The row also claimed `--posture` reached every command — it reached every *parser* while twelve commands ignored the value. Detail: [14.38](detail/implementation-plan.md#1438-activate_cli-cannot-administer-a-pq-native-atsign) |
| 14.37  | `pqSeal` version `0x01` removed outright, and the last homegrown key schedule with it | DONE 2026-08-18 — **one commit, not the two this row prescribed.** gkc reframed it from *retire safely* to *is there any value in `0x01` over `0x02`* — there is none: same KEM, so no diversity; self-generated vectors against the working group's; and its only distinctive feature, AES-256-GCM, is immaterial on a 32-byte content key. `_SealVersion.custom` had no other user, so `atPQv1-base` left the tree entirely. ⚠️ The two-commit plan's first step was also **mis-specified** — it named `SecretSharingAlgos.suites`, which neither seal site reads. Ruling [110](detail/decisions.md#110-the-0x01-seal-version-is-retired-stop-emitting-before-removing-2026-08-18) amended in place. Detail: [14.37](detail/implementation-plan.md#1437-the-0x01-seal-version-removed-outright) |
| 14.15  | Pre-PR rails checklist                                  | DONE 2026-08-10 — the compose-image item is struck in the body and nothing needs reverting before a PR. It stayed in TODO until 2026-08-18 because the section opened with a condition instead of a status. The external gate it names is step 32's blocker |
| 14.17  | Signature agility, and the G1 cluster joins the catalogue | DONE 2026-08-18 — steps 1–5 done, step 6 out of scope by gkc's ruling; the last piece was the signed-envelope 3×3. ⚠️ **This row sat in TODO reading "the owed half" for the rest of that day**, while the section's own body said COMPLETE — the shape the plan's own re-derivation warning names, where a body says closed and the heading nothing keys on says open. A cold read caught it. The section heading moved with this row. Body: [14.17](#1417-signature-agility--complete) |
| 14.36  | `send()` composes its command with `NotifyVerbBuilder`, and finally has live coverage | DONE 2026-08-17 — the hand-rolled `notify:` string is gone; `useAtKeyToString = true` is required, since the name is split across `key` and `namespace`. One wire delta, `:notifier:SYSTEM`. **`send()` had no live test at all before this**, so the wire delta was landed with one added rather than on the inference that `notify()` already sends the token. The architecture guard moved with it: requiring `toAtProtocolFragment` in this file would now force the hand-rolled command back, so it asserts the absence of one instead. Body: [14.36](#1436-sends-command-is-hand-rolled-where-a-tested-builder-exists) |
| 14.35  | `send()` splits its name at the first dot, and says what the parameter is | DONE 2026-08-17 — gkc ruled the parameter is `<id>.<namespace>` and poorly named; `namespace` deprecated for `idAndNamespace`, a dot-free name now throws at the call site. Unit **1401 (2)**, analyze exit 0. The one-line fix this row first proposed was measured WRONG — it would have changed the ciphertext binding. Body: [14.35](#1435-notificationservicesend-throws-away-the-namespace-it-was-given) |
| 14.33  | Closed as mis-stated: the refusal it named is unreachable | CLOSED 2026-08-17 — `shared_key.*` is written by a raw `UpdateVerbBuilder` at a `Secondary`, downstream of a refusal that fires before `provider.encrypt`, so it can never reach it. No client-side blocker remains for R-2. The real gap it was standing in front of is [14.35](#1435-notificationservicesend-throws-away-the-namespace-it-was-given). Ruling [107](detail/decisions.md#107-a-local-record-is-not-encrypted-and-the-legacy-refusal-exempts-it-2026-08-17) amended in place. Detail: [14.33](detail/implementation-plan.md#1433-closed-the-shared_key-refusal-was-never-reachable) |
| 14.30  | A notification that outruns its key is parked and re-driven | DONE 2026-08-17 — ruling [106.5](detail/decisions.md#1065-ruled-park-and-re-drive-not-readiness-at-the-hand-back-2026-08-17); proven live end to end (parked → asked → answered → filed → re-driven → decrypted). Three further defects fixed on the way, all invisible to unit tests. Body: [14.30](#1430-a-content-notification-can-outrun-the-key-that-opens-it) |
| 14.32  | An in-process `_apsk` write no longer clobbers a just-minted advertisement | DONE 2026-08-17 — ruling [102.2](detail/decisions.md#1022-the-in-process-window-is-closed-by-serialising-the-writers-2026-08-17); proven live, `_apsk.primary` ends on the mldsa65 array where it ended on bare RSA. Body: [14.32](#1432-a-primary-clients-ml-dsa-signing-key-is-not-visible-to-its-verifiers) |
| 14.31  | A `local:` record is not encrypted, and the legacy refusal exempts it | DONE 2026-08-17 — six related defects, not one; the listener no longer dies from a refused watermark. Ruling [107](detail/decisions.md#107-a-local-record-is-not-encrypted-and-the-legacy-refusal-exempts-it-2026-08-17). Body: [14.31](#1431-a-refused-watermark-write-permanently-disables-the-monitor) |
| 14.25  | Nine project entries reconciled against the tree | DONE 2026-08-16 — burn-down right about 4, headings stale for SS-1c and SS-4, real residuals in SS-2/B-1/S-3 (now [14.29](#1429-the-residuals-1425-surfaced)). ⚠️ Re-read 2026-08-18: **B-1's are gone** and S-3 is down to two, so what this row surfaced was two-thirds transient. Detail: [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none) |
| 14.28  | Live PQ proofs that no use case names | DONE 2026-08-16 — 9 uncited PQ live files ruled on: 5 became UC-B5.8–B5.12, 4 were already covered. Detail: [14.28](detail/implementation-plan.md#1428-live-pq-proofs-that-no-use-case-names) |
| 14.27  | The ledger's append-only rot, corrected | DONE 2026-08-16 — 11 rulings amended in the body and LIVE in the index, both citation debts discharged, and a test now asserts each. Detail: [14.27](detail/implementation-plan.md#1427-the-ledgers-remaining-append-only-rot) |
| 14.24  | The nskey mint elects a winner; the lock became an election token with a cooldown | DONE 2026-08-16 — seven rows, proven live at functional **166/166 `EXIT=0`**. Detail: [14.24](detail/implementation-plan.md#1424-the-nskey-mint-elects-a-winner--decisions-105) |
| P-1    | at_chops stateless core + HPKE                          | SATISFIED — at_chops 3.3.0 published 2026-06-23                                                                      |
| P-2    | `mldsa65` wired into the verification branch            | SATISFIED — published 2026-07-17                                                                                     |
| P-3    | `public:pqpublickey` + X-Wing-preferred enrollment wrap | No status stated — see [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none)                     |
| S-1    | at_auth `AtKeys`/`AtKeysIo` extended in place           | SATISFIED — at_auth 3.3.0 published                                                                                  |
| S-2    | `CryptoContext.keys` additive field                     | SATISFIED on trunk 2026-07-17; residual is the at_client publish                                                     |
| S-3    | Updatable `.atKeys` / keychain via injected `AtKeysIo`  | States PARTLY LANDED — see [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none)                 |
| SS-0   | WP-SS substrate baseline                                | SATISFIED — merged 2026-07-17                                                                                        |
| SS-1a  | at_commons enroll grammar + flattened `listns`          | SATISFIED — at_commons 5.12.0 published 2026-07-04                                                                   |
| SS-1b  | atServer stores/returns `EnrollParams.metadata`         | SATISFIED — merged 2026-07-07                                                                                        |
| SS-1c  | Client wired to the live verbs + flattened parser       | States live drive owed — see [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none)               |
| SS-2   | Substrate wired into AtClient + server wake-up          | No status stated — see [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none)                     |
| SS-3   | Substrate hardening + `signingAlgo` verify              | LANDED — at_server#2739 merged 2026-08-10                                                                            |
| SS-4   | nskey minting + signing-root lifecycle                  | States ABOUT HALF LANDED — see [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none)             |
| B-1    | The nskey data path — providers + cold start            | No status stated; the D1 centrepiece — see [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none) |
| RF-1   | `requestSecret(name)` confirm                           | No status stated — see [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none)                     |
| RF-SRV | atServer authenticated self-retrofit enroll             | No status stated — see [14.25](detail/implementation-plan.md#1425-three-projects-state-partial-completion-and-six-state-none)                     |
| RF-2b  | PQ ML-DSA APKAM mint + self-retrofit                    | LANDED 2026-08-05 (decisions 43)                                                                                     |
| RF-2c  | Retrofit orchestration + full e2e                       | LANDED 2026-08-05 (decisions 44)                                                                                     |
| R-1    | `disallowLegacyEncryption`                              | DELIVERED 2026-08-05; scope shrunk by decisions 36                                                                   |
| SH-1   | Key-material self-heal                                  | LANDED 2026-08-05                                                                                                    |
| B-2    | nskey rotation + revocation                             | LANDED 2026-08-06                                                                                                    |
| KE-1   | Selectable KEM + negotiated construction                | LANDED 2026-08-07                                                                                                    |
| ON-1   | PQ-native greenfield onboarding + opt-out               | ACCEPTANCE COMPLETE 2026-08-08 (decisions 52)                                                                        |
| IS-1   | Inter-server FROM/POL signature swap RSA → ML-DSA-65    | ⏳ **PR [#2683](https://github.com/atsign-foundation/at_server/pull/2683) is OPEN** — verified against GitHub 2026-08-18, not merged. This cell said only `PR #2683`, which reads as delivery and asserted no state at all |
| 14.2   | A version on the two signed payloads                    | DONE — `3c2eddbe6`                                                                                                   |
| 14.3   | JWS for the signed envelope, one shape, no flag         | DONE 2026-08-09 (decisions 60)                                                                                       |
| 14.4   | A `suites` list on the key package                      | DONE — `1688ed69d`, corrected `c9f8580da`                                                                            |
| 14.5   | Write-side envelope version selector in at_chops        | DONE — `1688ed69d`                                                                                                   |
| 14.6   | `metadata.keyPackage` stops being a one-way door        | DONE 2026-08-13 — the verb reaches `metadata` and `EnrollmentUpdateRequest.metadata` merges per-key, so the remedy for an unparseable key package is no longer delete-and-re-enrol. ⚠️ A **consumer** is still owed — nothing re-advertises a key package — and that is **KE-2**'s scope in PARKED, not this row's. This cell said only "Client caller landed" until 2026-08-18, which asserted no status at all |
| 14.8   | Domain separation on the signed envelope                | DONE 2026-08-15 (decisions 103)                                                                                      |
| 14.9   | A revoked enrollment could still authenticate           | ROOT-CAUSED 2026-08-12; fixed in at_server `16dd457f`                                                                |
| 14.10  | UC-B0.1 needed a legacy atServer image                  | RESOLVED 2026-08-08 via the `vip-p3.15.0` pin                                                                        |
| 14.20  | Building rulings 98 and 99                              | DONE — every row built; owes nothing                                                                                 |
| 14.22  | Making the signing root rotatable                       | DONE 2026-08-15 — all seven rows                                                                                     |

---

## Re-deriving the state


Run these rather than trusting the table. Each answers one row.

```bash
# the functional suite's convergence-race rate. It has been written five
# different ways from partial views; this is the only way to get it right.
for r in $(gh run list --branch gkc-pq-d1-spike --workflow at_client_sdk.yaml \
             --limit 20 --json databaseId --jq '.[].databaseId'); do
  gh run view "$r" --json jobs \
    --jq '.jobs[] | select(.name|startswith("functional_tests")) | [.name,.conclusion] | @tsv'
done | sort | uniq -c | sort -rn     # RUN IT. 2026-08-20: beta 3 fail/10, stable 1 fail/10

# row 1: which 14.22 rows have landed? Row 1 landed when this file started
# composing apskAdvertisement; row 2 is unbuilt for as long as the prefix
# still names one algorithm.
git grep -n "keyIdPrefix =\|apskAdvertisement" -- packages/at_client/lib/src/crypto/nskey/

# row 11: which 14.19 items are still open? (~~struck~~ ones are done)
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
cd packages/at_client         && dart analyze lib test       # exit 0, 360 info  @642a5899f
cd packages/at_client         && dart test --concurrency=1   # 1455 (2 skipped)  @642a5899f
cd packages/at_client         && dart test test/acceptance --concurrency=1  # 106 (2) @642a5899f
cd packages/at_auth           && dart test --concurrency=1   # 315              @642a5899f
cd packages/at_onboarding_cli && dart test --concurrency=1   # 49               @642a5899f
cd tests/at_functional_test   && bash runLocal.sh            # 174/174 EXIT=0   @642a5899f
cd tests/at_end2end_test      && bash runLocal.sh            # 54/54  EXIT=0    @642a5899f
# ✅ ALL SEVEN were re-measured together on 2026-08-19 at `642a5899f`, which is
# the first commit where both live packs are green after the PqPosture rename.
# Both runLocal.sh default VIRTUALENV_IMAGE to `at_virtual_env:local`, so a bare
# run is the PQ-capable arm — the var only has to be set by hand when driving
# `dart test` directly.
# ⚠️ The two live figures moved for reasons worth knowing rather than growth:
# functional 169 → 174 (the matrix's cells, once its driver stopped asking the
# arms for stage names that no longer exist), and both packs were RED at
# `c9de7d997` while every unit suite was green — analyze cannot see a string
# argument, so nothing caught it until the pack ran.
# Every figure in this project has been wrong at least once by being carried
# forward — the COMMAND is the value here, not the number beside it.
```


### After D1

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
