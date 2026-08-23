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

**D1 ends when every acceptance test passes and every rail is green, the
posture matrix included** — ruled by gkc 2026-08-23. What D1 requires is that
the acceptance set is **complete, implemented and verified**. Everything else
is a judgement call.

⚠️ **This definition moved twice on 2026-08-23 and both earlier forms are
wrong.** It read "ends at step 34 — the spike carved into stacked PRs and
merged. Publishing and R-2 follow it and are not D1", and then briefly "ends
when at_auth 4.0.0 is published, the staged status value is added and step 20's
rotation arm is green". The carve, the publishes and the rotation arm are all
still owed and still sequenced — they are simply not what *defines* the
boundary. R-2 still follows D1.

⚠️ **Read that together with G6 and G7 below, which say the train and the
rotation arm are D1 work, because the two are easy to read as contradicting.**
They are not: the acceptance criterion is what *ends* D1, and the carves,
publishes and rotation arm are work that has to happen before it can be met.
"In D1" means "owed before D1 closes"; it does not mean "defines when D1
closes". Nothing outside the acceptance set can move the boundary.

⛔ **"All acceptance tests pass" is true today and does not yet mean what this
definition needs.** All 69 catalogue rows read `PROVEN` (68 live, UC-C1.3
withdrawn) and all 68 live ones have a scenario — but the rail checks
**structure only**: that a scenario exists, that ids resolve, that counts
match. Nothing checks that a scenario proves what its row *claims*, and
`proves:` prose is matched against nothing. The one known overclaim, three
clauses of UC-A2.5/UC-A2.6, was found by hand. The clause-by-clause audit is a
D1 gate and is in [`## TODO`](#todo).

---

⛔ **A STANDING PROJECT PREMISE, and it settles more arguments than it looks
like it should.** **No production `.atKeys` file or keychain entry holds any PQ
key material** (gkc, 2026-08-23).

The consequence is the one worth carrying: **any argument of the form "X already
exists in the world, so we must tolerate it" is void here until somebody names
the holder.** As of 2026-08-23 this fact has closed three separate questions
that each looked like a real compatibility constraint — [14.19 item
11](detail/implementation-plan.md#1419-small-items-raised-2026-08-12-and-not-yet-acted-on)'s
"wait for the fleet" gate before emitting a staged status, item 23's "who holds
a `version: 1` keyfile with an empty `keys` array", and both questions left open
beneath [ruling 114](detail/decisions.md#114-a-signer-waits-for-its-own-mint-the-mint-alone-does-not-2026-08-21)
(durable pre-mint auth-fallback envelopes, and the verifier's pre-mint cache
asymmetry). Each needed a PQ-material holder to exist, and none does.

⚠️ **It is a statement about today, not a licence.** The moment a released build
starts writing PQ material, every one of those questions becomes reachable and
has to be re-asked rather than re-cited from here.

---

## THE NEXT MOVE

⛔ **This is the one ranked list, and it lives here.** Memory holds a single line
pointing at it and no detail. `## TODO` below is *what is owed*, unordered; this
is *what to do first*. Re-read this section against `git log --oneline -10`
before acting — it has led with finished work before.

Re-ranked **2026-08-23**, after gkc walked every open item and ruled each one
in or out of D1. ⛔ **The definition of D1 changed in that pass and this list is
ordered by it**: D1 ends when every acceptance test passes and every rail is
green, the posture matrix included, with the acceptance set complete,
implemented and verified. Everything else is a judgement call. ⚠️ **The
D1 gates are `G2`–`G7` and begin at "THE D1 GATES, in order" further
down; the numbered entries 1–8 above them are struck history, and `G1` is
below the gates under **POST-D1 CLEAN-UP** — it was a gate until 2026-08-23
and keeps its letter so the citations to these letters do not all shift.** This sentence
said "entries 1–5 below", which points at the wrong list — a file that has
already been bitten once by duplicate ordinals.

The pass before it, **2026-08-22 evening**, struck entry 4 when the at_auth
carve landed as [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179),
and recorded two claims that entry had been making which turned out false the
moment the carve was actually run.

The pass before it, **2026-08-22** against the tree at `64480808d`, went entry
by entry with the publish gate and CI both re-derived live rather than carried
forward. What that pass found, because a re-rank that reports only successes is one
whose checks were too weak to fail: the CI paragraph below was reporting a
**success on a superseded run while the newest was a failure**, the *Blocked*
note said the train was unblocked when 14.49.2 had re-gated it on an
unpublished candidate, and the list's own ordinals ran 1, 2, 3, 4, 3, 4, 5 —
two entries numbered 3 and two numbered 4, so "item 3" meant different things
in the source and on the rendered page. All three are corrected here.

gkc published **at_chops 3.6.0 and at_commons 5.16.0** to pub.dev on
2026-08-21, so the train's first two positions are released; **at_lookup
3.7.0-rc1 is not**, and that is the live gate.

⚠️ **A second workstream is now open and is NOT in this table** — the knowledge
base, agreed with gkc 2026-08-20. Its plan, format, rail design and ordered
method are in [`docs/knowledge/README.md`](../../knowledge/README.md), which is
a scaffold with no nuggets written yet. If that is what you are here for, open
that file instead; the list below is the PQ release work.

1. ~~Publish at_chops 3.6.0 to pub.dev~~ **Done by gkc 2026-08-21, and
   at_commons 5.16.0 with it.** Verified live the same day:
   `curl -s https://pub.dev/api/packages/<pkg> | jq -r .latest.version`
   returns **at_chops 3.6.0** and **at_commons 5.16.0**, both published
   2026-08-21. #2169 merged 2026-08-20 as `c4c581834` (approved by Xlin123,
   CI 47/47, adversarial re-review clean — its one finding, an unrecorded
   promise, is delivered in ruling 110's addendum). **The train's first two
   positions are now released, which lifts the gate on everything after
   them.** No workflow in this repo publishes to pub.dev (checked
   `.github/workflows/` 2026-08-20), so each publish stays gkc's step.
2. ~~Make `KeyEntryStatus` a typed String wrapper~~ **Done 2026-08-22** —
   [14.49.1](detail/implementation-plan.md#14491-keyentrystatus-becomes-a-typed-string-wrapper--done-2026-08-22)
   records what landed as well as the ruling. Both collapsing seams fixed (the
   section named one), the verify half wired at two call sites rather than
   merely offered, the `_apsk` selector widened with it, eleven
   mutation-proven tests, at_auth 335/335, at_client 1509/1509 and the
   functional pack 178/178. ⛔ `EnrollmentKeyExchangeMode` stays an enum — 14.49.1 says why,
   and that has not changed.
3. ~~Diagnose the red CI run~~ **Done 2026-08-22, and it was never this
   branch's code** — [14.50](#1450-the-e2e-teardown-revokes-enrollments-belonging-to-other-runs). A concurrent CI run on `gkc-pq-d1-at-lookup`
   tore down this run's enrollments: `enrollment_teardown.dart` revokes every
   approved enrollment on the shared `@ce2e1`-`@ce2e4` atSigns with
   `force: true`, not only its own. Diagnosed from the *other* run's log, as
   the entry said it had to be. **The harness defect is still open** and is in
   `## TODO`; CI is 24/24 green on `64480808d` but both green windows had no
   other run in flight, so that is a rate, not a fix.
4. ~~Carve at_auth~~ **Done 2026-08-22 — [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179)
   is open against trunk, CI green.** 89 files, +11130/−1008: 70 in at_auth
   and 19 outside it totalling **29 lines** — eight pubspecs flooring at_auth
   at `4.0.0-rc1` and eleven files importing `at_auth_io.dart`. Those had to
   ride the same commit: `tests/at_functional_test` alone pinning
   `at_auth: ^3.0.0` makes the workspace fail to resolve, so every job dies at
   `dart pub get`.
   - ⛔ **Two claims this entry made are DISPROVEN, so nobody re-derives
     them.** It said "buildable now, **not mergeable** now … the PR can be
     raised and its CI will fail to resolve until gkc publishes at_lookup
     3.7.0-rc1". False: at_lookup 3.7.0-rc1 is **on trunk**, and a Dart pub
     workspace resolves its siblings by path, not from pub.dev. `dart pub get`
     returned 0 and CI ran **47/47 green**. The publish gate is on *publishing
     at_auth to pub.dev*, which still waits on at_lookup — it was never a gate
     on raising or merging the PR. And the entry's gate recipe — the carved
     tree "byte-identical to the spike over that package" — is **not** what
     this carve satisfies; see the amended recipe in
     [14.18](#1418-the-remaining-d1-initial-development-sequence).
   - What the carve corrected beyond a copy, each measured: at_auth's floors
     `at_commons: ^5.15.0` and `at_chops: ^3.4.2` were **too low** — it uses
     `EnrollVerbBuilder.apkamPublicKeySignature` (first in at_commons 5.16.0)
     and `SigningAlgoType.strongestFirst` (first in at_chops 3.6.0), and
     `at_chops 3.4.2` was never published at all. They compiled only because
     the workspace resolves by path. Raised to `^5.16.0` and `^3.6.0`.
   - The "remove in v4" deprecations are settled, since this **is** v4. Ten
     annotation sites promised it; three members are removed
     (`AtOnboardingRequest.atKeys`, `AtAuthRequest.encryptedKeysMap`, the
     ignored `atSign` on `AtKeysIo.generateKeyPairs`) and the rest say
     **v5** — `AuthResponse` and its two subclasses and
     `AtAuthRequest.atAuthKeys` are the return types of `onboard`/
     `authenticate` and how a caller supplies enrollment-derived keys, with
     201 references outside at_auth, so retiring them is an API change of its
     own and is in `## TODO`.
   - ⭐ `AtOnboardingRequest.atKeys` **never worked**: `onboard()` overwrote
     whatever a caller set with the result of reading `atKeysIo` before
     anything read it, then threw "already onboarded" if that read returned
     keys — so the branch consuming it was unreachable. The analyzer confirmed
     it independently once the field was gone.
   - [14.44](#1444-residuals-from-the-at_chops-pr-review)'s first residual
     landed here as its second commit, taking that section's preferred option:
     `encode` refuses an `ArgonHashParams` whose `hashLength` is not the value
     `decode` will use. Two tests, mutation-proven separately.
   - Rails: at_auth 344/344, at_client 651 (+39 skipped), at_onboarding_cli
     33/33, at_client_flutter 17/17, both format gates clean, every other
     workspace package analyze exit 0, and **five live functional packs, four
     green**. ⚠️ The one red is `atclient_sync_conflict_test`'s `conflictInfo`
     case — [14.43](detail/implementation-plan.md#1443-the-functional-suites-convergence-race)'s shape A,
     whose fix (`_throwIfStopped`, the `stop()` done-completer,
     `sync_stop_race_test.dart`) is on this branch and **not on trunk**, so
     the carve necessarily runs the unfixed sync service. Re-derive rather
     than believe: `git grep -c _throwIfStopped origin/trunk -- packages/at_client/lib/src/service/sync_service_impl.dart`.
4a. ~~The at_auth 4.0 major~~ **Done 2026-08-22, and this list carried no
   trace of it until the wrap-up that day** — 14 commits, all pushed, CI 24/24
   green on `64480808d`. Recorded here because a reader working top-down would
   otherwise not learn that at_auth became a major at all. What landed: the
   keyfile's field names (`keyParts`/`keyPartType`/`keyAlgorithmType` →
   `material`/`role`/`algorithm`); `CryptographicMaterialRole`,
   `...Algorithm`, `...Status` and `KeyEntryStatus` as `extension type`s over
   String, erased at runtime so nothing moves at rest; the version to
   `4.0.0-rc1` with 10 dependent constraint sites; the `AtKeysMaterial` alias
   removed; and **S-5/S-6**, the WASM barrel split — `at_auth.dart` reaches no
   `dart:io` in at_auth's own sources, guarded by
   `packages/at_auth/test/wasm_barrel_test.dart`.

4b. ~~Test the registrar's certificate validation~~ **Now POST-D1 CLEAN-UP
   (gkc, 2026-08-23), as `G1` below the gates.** ⚠️ This entry read "Promoted
   to a D1 gate 2026-08-23" earlier the same day; it was demoted again, so
   the harness shape and the one missing import are there for whoever picks it
   up after D1. Do not work this entry.

4c. ~~Stop the e2e teardown revoking other runs' enrollments~~ ⛔ **NOT a D1
   gate, ruled 2026-08-23** — gkc: e2e runs isolate locally and are serialized
   by structure on GitHub. Recorded alongside that, because it is the part a
   future reader will re-derive: there is no top-level `concurrency:` key in any
   workflow, so `needs:` serializes the e2e jobs *within* a run and not across
   runs, and the incident that produced [14.50](#1450-the-e2e-teardown-revokes-enrollments-belonging-to-other-runs)
   was cross-run. The row stays in `## TODO` as unblocked hygiene.

5. ~~Carve at_lookup~~ **Done — merged as #2174** — train position 3, and **now
   unblocked for publish as well as carve**: its `at_commons: ^5.16.0` floor
   is satisfiable on pub.dev as of 2026-08-21, and 14.18's compile
   differential already established it needs nothing newer than the
   at_chops it was tested against. ⚠️ **The carve recipe that used to sit here
   has been removed: this entry is DONE, and ten lines of imperative
   instructions under a struck heading read as work to do.** The recipe lives
   in [14.18](#1418-the-remaining-d1-initial-development-sequence), amended
   there with what the at_auth carve taught — byte-identical to the spike is a
   default rather than a rule, and a MAJOR cannot be carved package-only.
6. ~~Close out [14.43](detail/implementation-plan.md#1443-the-functional-suites-convergence-race)'s
   remainder~~ **Done 2026-08-21, all of it.** All four original shapes have
   diagnosed, mutation-proven fixes; the last open members closed today:
   `sync_multiple_client_test`'s one examined red is classified — shape C's
   own signature on the diverged key (the section has the discriminators
   for any future red) — and the rotated-advertisement member was a
   test-side stale read, fixed in `ccf4987a4` (`publishedAdvertisement` at
   four assertions across three files). The matrix driver dumps child
   output on cell failure (`fce13ca52`).
   [14.48](detail/implementation-plan.md#1448-a-primary-client-can-sign-with-a-key-its-own-advertisement-just-withdrew)'s
   ruling landed as decisions.md 114 — sign awaits mint, built and proven
   (`09f9a974c`). UC-G1.14 is qualified in place. The pack-rate soak
   measured **0 family reds in 10 valid packs at `112e1f740`** (an eleventh
   run excluded, gkc-confirmed machine suspend; the rate paragraph in the
   section has the evidence). What remains: watch the rate hold; 14.48's
   residue is under ruling 114; the pull-side sync question and the parked
   driver gap are in 14.43's TODO row.
7. ~~Decide `executeVerb`'s inert `sync` parameter~~ **Done 2026-08-20**
   ([14.46](#1446-executeverbs-sync-parameter-is-inert-on-both-secondaries)):
   `@Deprecated` for 3.x on all six declarations (at_client and at_lookup),
   removal owed at 4.0.
8. ~~Demote the finished `## TODO` rows to `## DONE`~~ **Done 2026-08-22.**
   Twelve closed sections moved into `detail/implementation-plan.md`, each
   leaving a `## DONE` row; the live plan went 3,545 → ~1,700 lines and all
   45 inbound pointers were repointed. 14.17's two diverged copies were merged
   at the same time, the original kept whole.

---

**THE D1 GATES, in order. Everything above this line is history.**

**G2. [RECOMMENDED] Build the acceptance suite out per [ruling 115](detail/decisions.md#115-the-acceptance-suite-is-4-arms-and-a-ledger-not-one-grid-2026-08-23).**
The gate that D1's own definition rests on, and the largest. gkc's framing:
hundreds of functional and e2e tests cover the acceptance set between them, and
there is no definitive place to see the whole of it being proven; the posture
matrix is the logical place to build that out. **The gap is now established and
the design is ruled** — the first two of this entry's three owed steps are
discharged, and what remains is the build. **Of that build, the ledger, its
local driver, its wiring rail and arm 1 have all landed (2026-08-23); arms 2–4
and the ledger's clause level have not.** ⚠️ The entry stays `[RECOMMENDED]`
because arms 3 and 4 are the largest thing left in D1, not because nothing has
been done — read the ✅ markers below before starting anything here.

✅ **Arm 1 is BUILT (2026-08-23) — do not build it again.** This paragraph
opened "Start here, and it is startable now: build **arm 1**, the 3-cell stage
arm, in `tests/at_functional_test`", and that is done:
`test/pq_stage_arm_test.dart`, **186/186** in the full pack, with
**UC-C1.2 executed for the first time** — `disallowLegacyEncryption` has no
setter and no constructor argument, so a posture is the only way to reach it,
and it had 0 hits under `tests/`. Three things a reader should not re-derive.
**The arm is 3 enrollments, not 3 clients**: `AtClientImpl` keys its cache by
`(atSign, enrollmentId)` and `refuseChangedRolloutAxes` throws when a second
client asks for the same key under different rollout axes, so three postures
need three cache keys. **The refusal is at `crypto_runtime.dart:156`**, not at
`at_client_impl.dart:753` as this section said — that line is
`_announceLegacyEncryptionPosture`, which logs. And **the arm covers the rows
both derivations agree on**, not the contested 21
([which](acceptance.md#which-rows-arm-1-owes)); it does not measure UC-C1.4,
because `enrolAndAuthenticate` builds pq-mode enrollments only and every cell
therefore holds `keyExchangeMode` constant.
✅ **Its one real prerequisite is now built**
(2026-08-23): this entry read that the pack "has no `dart_test.yaml` and no
`pq` tag", and it now declares the tag with **29** of its 49 test files carrying it,
guarded by `test/pq_tag_test.dart` — a rail that re-derives the set from the
mechanisms a file drives, so a new PQ test cannot sit outside it unnoticed.
⛔ No `paths:` allowlist, deliberately: this pack's virtualenv is thrown away
per run, so allowlisting would carry the e2e pack's silent-omission risk with
none of its benefit. ✅ The prerequisite that read "`PqPosture.pqActive` breaks the monitor"
is **measured away** — see the correction below and in
[14.34](#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart).
✅ **The ledger, this entry's second piece, is BUILT** (2026-08-23), so do not
build it again. This paragraph said it "needs `manifest.dart` moved from
`packages/at_client/test/` to `lib/` before any pack can import it" — it did
not, and the move was never made: the test runner's own
`--file-reporter json:` output plus the citations `provenIn` records are
sufficient, so nothing was moved into at_client's shipped surface and none of
the 194 live tests changed. `packages/at_client/tool/acceptance_ledger.dart`
renders it, `test/acceptance_ledger_test.dart` guards the join, and four CI
jobs upload the inputs. Over all four report sources it reads **62 PROVEN · 1
NOT-EXERCISED · 6 NO-LIVE-CITATION** across 69 rows. The full description is in
[acceptance.md section 14](acceptance.md#14-test-harness--implverify-mapping).
⚠️ `manifest.dart` is still where it was, and that still blocks the *in-pack
rails* idea — a different thing, wanting each pack to assert its own citations
— so the prerequisite stands for that reason and not for this one.

**So what remains of this entry is arms 2–4**, plus the clause level of the
ledger. ⚠️ This read "what remains of this entry is arm 1" until arm 1 landed
on 2026-08-23. Arm 2 exists as the 4×4 and is not posture-faithful; arms 3 and
4 need the EE at a named `at_server` ref.

The measurement, 2026-08-23: 59 of 68 rows have live proof and 9 have none, so
coverage was never the gap; 135 `provenIn` citations split **68 live / 67
unit**; and of the 68 rows only **3** are shaped like a grid cell while **38**
do not vary by posture at all. Ruling 115 carries the full table, the design
(**4 arms and a generated ledger**, not a bigger grid) and the 4 verified
prerequisites.

⚠️ **This entry read "Measured 2026-08-23: 180 live test declarations across 65
files … a looser one gives 225", and both figures were scoped to 2 of the 4
live packs.** `tests/at_onboarding_cli_functional_tests` and
`tests/at_onboarding_cli_functional_tests_proxy` are live packs too, no
citation reaches either, and the CLI one builds clients from a `PqPosture` in
two arms. Across all 4 the strict matcher gives **194** and a multi-line-aware
one **247** — and that gap is entirely declarations whose name sits on the next
line, since an any-position same-line matcher also gives 194:

```bash
grep -rhoE "^[[:space:]]*test\([[:space:]]*'" tests/ --include='*.dart' | wc -l   # 194
perl -0777 -ne 'while (/(?<![A-Za-z0-9_])test\(\s*[\x27"]/gs){$n++} END{print "$n\n"}' \
  $(find tests -name '*.dart')                                                    # 247
```

The "29 of the 69 ids nameable" figure stands, and is a citation count rather
than a coverage count. The matrix is still 3 `test()` calls proving 2 use
cases.

**G3. Diagnose [14.34](#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart).**
A live-pack failure at once in five, unexplained. A gate only because D1 now
ends when every rail is green, and at that rate "green" is a rate rather than a
state.

**G4. Migrate 14.11's bucket B** — the 71 credential-ladder uses
(`enrollmentId` 59, `signingAlgoType` 12) onto the `AtAuthenticator` seam that
at_lookup 3.7.0-rc1 ships **on trunk** — pub.dev is still 3.6.1, and in this
file that distinction is the whole gate. 24 sites in `lib/`, 47 in tests, across
at_client, at_onboarding_cli and at_auth. The only one of the five
`deprecated_member_use` buckets with a replacement that exists today.

**G5. Close 14.19 item 36** — three clauses of UC-A2.5/UC-A2.6 that the
catalogue asserts and no live row proves. It is the one known instance of the
overclaim G2 exists to find, and it was found by hand.

**G6. The train.** Merge #2179 → **gkc publishes at_lookup 3.7.0-rc1** → **gkc
publishes at_auth 4.0.0-rc1** → carve at_client → at_client_flutter →
at_onboarding_cli. ⚠️ **Before carving at_client, raise its `at_commons` floor**:
it declares `^5.15.0` and `notify_request_transformer.dart:154` calls
`metadata.copy()`, which first exists in **5.16.0**. The identical defect was
found and fixed in at_auth during its carve.

**G7. Step 20's rotation arm** — publish at_auth, add the `pending` status
value, build the arm against its own dedicated CRAM atSign. ⛔ There is **no**
fleet-adoption wait: see the standing premise above.

---

**POST-D1 CLEAN-UP. Not gates, and not to be worked before D1 closes.**

⛔ **G1 was a D1 gate until 2026-08-23 and is now post-D1 clean-up** (gkc).
It keeps its letter rather than being renumbered, because prose above and
below cites these letters and a shift would silently repoint every one of
them. So the D1 gates are **G2–G7**, and G1 sits here.

**G1. Test the registrar's certificate validation, on
[PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179) while
it is still open.** The last S-5 behaviour change that exercises nothing, and
the only one with a security consequence: the default client used to accept any
TLS certificate on calls carrying the registrar API key. Neither arm has a test
and CI is blind — `RegistrarIoClient` appears in zero job logs. The harness is
settled and written up in its `## TODO` row: mint a self-signed cert in
`setUpAll` with `openssl` (**do not commit a PEM** — push protection blocks
private keys), serve it with `HttpServer.bindSecure`, point `RegistrarService`
at `localhost:<port>`, and run three arms — default refuses, io client with the
flag off refuses, io client with the flag on succeeds. The third is the
positive control without which a refusal is indistinguishable from a server
that never started. ⚠️ A probe got one import short on 2026-08-23: it needs
`import 'package:at_auth/at_auth.dart';`, which is what exports
`RegistrarApiEndpoint`.

**Blocked, and what lifts it:** ~~publishing anything past at_chops waits on
at_chops 3.6.0 reaching pub.dev; at_lookup's publish additionally waits on
at_commons 5.16.0~~ — both published 2026-08-21. ⚠️ **That did NOT leave the
train unblocked, and this paragraph said it had until 2026-08-22.**
[14.49.2](detail/implementation-plan.md#14492-every-remaining-package-publishes-as-a-release-candidate)
moved every remaining package to a candidate the same week, so the live gate is
now **at_lookup `3.7.0-rc1`, which is not on pub.dev** (latest is 3.6.1;
re-derive with
`curl -s https://pub.dev/api/packages/at_lookup | python3 -c "import sys,json;print(json.load(sys.stdin)['latest']['version'])"`).
⛔ **at_auth floors `^3.7.0-rc1`, and that does NOT block its carve — this
sentence said it did until 2026-08-23.** A pub workspace resolves its siblings
by path, so [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179)
resolved and went 47/47 green with at_lookup unpublished. What the publish gates
is **publishing at_auth**, never carving or merging it. Each package still waits on its own predecessor being released before it
can declare a floor against it, which is what the order in
[14.18](#1418-the-remaining-d1-initial-development-sequence) is for.
The remaining external gate is the one 14.18 records for the LAST carves, not
the next: the spike's test packs need a VE image that verifies ML-DSA PKAM,
settled by moving CI to `dev_env`.

⚠️ **CI on this branch cannot catch up by itself.** Nothing fires on push
here — the workflow is `workflow_dispatch` only on this branch — so the newest
run is as new as the last manual dispatch and no newer.

✅ **THE BRANCH IS GREEN, at the current tip.** Measured 2026-08-22 with the
command below: runs **`32588333812`** (at_client_sdk, 11/11) and
**`32588342275`** (at_libraries, 13/13), both `success`, both on
**`64480808d`** — which was HEAD when this was written and is now the newest
commit that **touches code**. Re-derived 2026-08-23: HEAD is 8 commits past it
and `git diff --name-only 64480808d..HEAD` is entirely under `docs/`, so this
green still covers every line of code on the branch. Re-run the check below
rather than extending that reasoning to the next commit. CI's own per-suite counts match the local ones —
at_auth 342, at_client 1509, at_onboarding_cli 54, at_client_flutter 37,
functional 178, e2e 37, `end2end_test_14` 37, pqe2e 17 — so the green is not a
skipped suite.

⚠️ **This paragraph read "THE BRANCH IS NOT GREEN" and named run `32482877878`
on `9a7260dc7` as newest.** That run's failure is now diagnosed and was never
this branch's code — [14.50](#1450-the-e2e-teardown-revokes-enrollments-belonging-to-other-runs) has it: a
concurrent run tore down this run's enrollments. **The harness defect it found
is still open**, and both green runs since had no other run in flight, so they
say nothing about whether it recurs. The arithmetic here was also wrong: it
said HEAD was "six commits past" `9a7260dc7`; it is **37**.

⚠️ **This paragraph named the older, successful run `32468769474` on
`2965330f1` and called it "the newest", concluding "success, 11/11 jobs".** It
was already false on the day it was written — the red run was dispatched three
hours later, on the same day. It is recorded here rather than deleted because
of *how* it misled: it opened with a staleness warning, hedged, and supplied
the re-derivation command, and all of that reads as diligence, so a reader
trusts the number and skips the command. Run the command.

```bash
gh workflow run at_client_sdk.yaml --ref gkc-pq-d1-spike
gh run list --branch gkc-pq-d1-spike --workflow at_client_sdk.yaml --limit 1 \
  --json headSha,conclusion --jq '.[] | [.headSha[0:9], .conclusion] | @tsv'
git log --oneline -1
```

✅ **The five finished `## TODO` rows were demoted on 2026-08-22.** This
paragraph read "Five `## TODO` rows below are finished and still sit in the
owed table" and named 14.41, 14.43, 14.48, 14.45 and most of 14.39. All five
now have `## DONE` rows and their bodies live in
[`detail/implementation-plan.md`](detail/implementation-plan.md); the genuinely
open residue each left behind was split into its own row rather than being
carried inside a closed one.

---

## TODO

| Item                            | What is owed                                                        | Blocked on                                                                       |
|---------------------------------|---------------------------------------------------------------------|----------------------------------------------------------------------------------|
| at_auth README | ⛔ **NOT a D1 gate, but it should ride [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179) with G1** — `packages/at_auth/README.md` describes `FileAtKeysIo` at `:144` and `:191` and **never mentions `at_auth_io.dart`**. The barrel split is the single most consumer-visible change in 4.0.0 — a `dart:io` consumer has to add one import — and the CHANGELOG says so at length while the README says nothing. No code miscompiles from it (the README shows no import statements at all), which is why it is not a gate. Found by the wrap-up docs sweep 2026-08-23 | Nothing. One or two sentences where `FileAtKeysIo` is first named |
| **acceptance audit** | ⛔ **D1 GATE — the gap is established and the design is ruled ([115](detail/decisions.md#115-the-acceptance-suite-is-4-arms-and-a-ledger-not-one-grid-2026-08-23)); what remains is the build** (gkc, 2026-08-23). **The rationale, in gkc's words:** *"we have literally hundreds of functional and end to end tests which cover the acceptance tests together. But there is no definitive place where it is easy to see the entirety of the pq project's acceptance tests being proven. The posture matrix test is the logical place to build test out."* So the problem is **legibility, not coverage**. Measured 2026-08-23, and **coverage was never the gap**: of the 68 live rows, 59 have live proof of some kind and 9 have none (12 LIVE_DIRECT, 43 LIVE_PARTIAL, 4 LIVE_INCIDENTAL, 9 NO_LIVE_PROOF). Only **29 of the 69** use-case ids are nameable anywhere in the live suite. ⚠️ **`tests/` holds 7 Dart packages** — the 4 live test packs plus `tests/pq_matrix/{current,published,scenario}`, the child processes the pair grid spawns. Count with `find tests -name pubspec.yaml`; a `tests/*/` glob returns 4 and reads as the whole answer. ⚠️ **The live corpus is 4 packs, not 2, and this row was scoped to 2 of them** — it read "**180** live test declarations across 65 files … a looser `grep -o 'test('` gives 225 and an indentation-anchored one 224". `tests/at_onboarding_cli_functional_tests` and `tests/at_onboarding_cli_functional_tests_proxy` are live packs as well, no citation reaches either, and the CLI one builds clients from a `PqPosture` in two arms — which makes it the best live evidence for UC-C1.6 and a second live proof of UC-A1.1. Across all 4 the strict matcher gives **194** and a multi-line-aware one **247**, and that gap is entirely declarations whose name sits on the next line, since an any-position same-line matcher also returns 194: `grep -rhoE "^[[:space:]]*test\([[:space:]]*'" tests/ --include='*.dart' | wc -l` against `perl -0777 -ne 'while (/(?<![A-Za-z0-9_])test\(\s*[\x27"]/gs){$n++} END{print "$n\n"}' $(find tests -name '*.dart')`. The posture matrix, the intended home, is **3** `test()` calls proving **2** use cases (UC-G1.14, UC-G1.15). ⚠️ **A citation count is not a coverage count** — an earlier pass here reported "27 of 68 have no live proof" when what it had measured was 27 with no live proof *cited from their acceptance scenario*. Do not restate it as coverage. For the record, the citation picture: of 68 scenarios, 2 cite the matrix, 39 cite some live test, 22 cite unit tests only, and 5 cite nothing and are themselves mock tests (UC-A3.1, UC-A3.4, UC-B3.1, UC-B3.2, UC-B5.2; UC-A3.1 runs against `MockAtClient()`). ⚠️ **And nothing checks the claims.** `catalogue_test.dart`'s five tests are all structural; none asks whether a scenario proves what its row asserts, and the `proves:` prose is matched against nothing ([14.19 item 29](detail/implementation-plan.md#1419-small-items-raised-2026-08-12-and-not-yet-acted-on)). The one known overclaim, item 36's three clauses of UC-A2.5/UC-A2.6, was found by hand. **Steps (1) and (2) are DISCHARGED, 2026-08-23** — they read "(1) for each of the 68, find where it is *actually* exercised live — searching the packs, not just reading citations; (2) decide which are genuinely **posture-dependent**, since several of A3's self-data cases may not vary by posture at all". Both are answered in [ruling 115](detail/decisions.md#115-the-acceptance-suite-is-4-arms-and-a-ledger-not-one-grid-2026-08-23), which carries the per-row map and the posture classification. gkc's A3 suspicion held: `PqPosture` declares 9 axes and only 6 vary across the stages, so 3 of the 5 A3 rows do not vary at all. **What is owed is step (3), and the shape is ruled rather than open**: only **3** of the 68 rows are shaped like a grid cell and **38** do not vary by posture, so the target is **4 arms and a generated ledger** — a 3-cell stage arm, the existing 4×4 pair grid, a transition arm for the edges the catalogue is full of, and a server-version arm — with 4 prerequisites named in the ruling, **2 of them now discharged**. ✅ This row said the sharpest was that "this pack has no `dart_test.yaml` and no `pq` tag (0 hits, against 9 in the e2e pack)" — built 2026-08-23: the tag is declared and 29 of its 49 test files carry it, chosen by the mechanisms they drive rather than their names, and `test/pq_tag_test.dart` re-derives the set so a new PQ test cannot sit outside it. ⛔ No `paths:` allowlist, deliberately — this pack's virtualenv is thrown away per run, so allowlisting would take the e2e pack's silent-omission risk with none of its benefit. ⚠️ **A fifth prerequisite was listed here and is now measured away**: this row said `PqPosture.pqActive` "currently breaks the monitor (`nskey_self_notify_live_test.dart:289`)". It does not. Equal-length interleaved arms across 2 fresh virtualenvs gave pqActive **16 of 18** monitors received against a control's **18 of 20**, with the atServer's log carrying `signingAlgo:mldsa65` authentications — both arms fail at the same rate with `AT0014`, so the failure is real but is **not posture-dependent**, and a pqActive cell is no worse off than a legacy one. ✅ **The ledger half of step (3) is BUILT, 2026-08-23** — `tool/acceptance_ledger.dart` plus the recording in `provenIn` and report emission in all three `runLocal.sh` runners; over all four report sources the catalogue reads **62 PROVEN · 1 NOT-EXERCISED · 6 NO-LIVE-CITATION** across 69 rows, the one gap being UC-B0.1's tagged legacy-server job. ⛔ **It did NOT need `manifest.dart` moved**, which this row and ruling 115 both listed as its prerequisite. **What step (3) still owes:** arm 1 (the 3-cell stage arm), then arms 2–4; **the clause level** of the ledger, which is the half that does touch the live tests and is what turns "UC-A2.5 has 3 unproven clauses" into a computed fact rather than a footnote; and **the CI combining job**, left unwired because it needs `actions/download-artifact` and neither this repo nor at_server carries a trusted pin for it — CI uploads the inputs today and the page is rendered on demand. ✅ **Two further gaps gkc named on 2026-08-23, both now BUILT.** They were: (a) nothing in the tree invoked the renderer — `git grep -P "dart\s+run\s+\S*acceptance_ledger"` returned exactly one hit, the usage comment inside the tool itself, so every ledger so far was assembled by hand from a scratch directory; and (b) nothing guarded the population wiring, with **0** tests reading `.github/workflows/` (positive control: the path string appears in 5 non-test files) and none reading the three `runLocal.sh`. What landed: **`tools/acceptance_ledger.sh`**, one command that runs the unit sources, optionally the live packs (`--with-live`), and renders; and **`packages/at_client/test/acceptance_ledger_wiring_test.dart`**, which asserts each of the four emitting jobs still carries its flag, that `unit_at_client` still sets `ACCEPTANCE_LEDGER`, that every emitter uploads with `always()`, and that each runner still gates the reporter on `ACCEPTANCE_REPORT`. ⚠️ **The rail's first version had a hole worth recording**: it asserted `contains('ACCEPTANCE_REPORT')` and `contains('--file-reporter json:')` separately, and a mutation making the guard read a *different* variable left both satisfied — the variable is named three times in each runner, so severing the coupling changed no substring. It now pins the coupling itself (`-n "${ACCEPTANCE_REPORT:-}"` and `--file-reporter json:${ACCEPTANCE_REPORT}`), which is the same weakness this section already records in `provenIn`, reproduced one layer up. Six mutations, each reddening its own assertion. ⚠️ **`provenIn` APPENDS to its citations file**, so two runs against one path double every citation and the ledger reports 278 for a catalogue of 139 — the driver deletes it rather than trusting the caller. **Re-derive**: `grep -rho 'UC-[ABCG][0-9]*\.[0-9]*[a-z]*' tests/at_functional_test/test tests/at_end2end_test/test | sort -u | wc -l` against the 69 in `acceptance.md` | Nothing |
| [14.43](detail/implementation-plan.md#1443-the-functional-suites-convergence-race) residue | ⛔ **NOT D1, and NOT PQ (gkc, 2026-08-23)** — recorded here only because this project has no other checked-in owed-work list. The behaviour is in `sync_service_impl.dart`, i.e. at_client's general sync, and no use case asserts sync ordering. The test-side fix landed in `ccf4987a4`. **A sync pull applies an OLDER server entry over NEWER local state** — the pull-side face of the versioning shape C fixed on the push side. Recorded when 14.43 closed and not designed since. Also open from that section: a driver-side `expect` failure on a protocol-green cell still dumps nothing | Nothing. The section carries the discriminators for any future red of the family |
| [14.45](detail/implementation-plan.md#1445-an-expired-key-the-client-cannot-delete-pins-it-in-a-hot-loop) residue | ⚠️ **In another repo: `at_persistence_secondary_server`.** Its keystore `get()` does not filter expired records, which is what let an expired key be read back and re-swept. Named here because this is where the work that found it lives; it does not land here | Separately owned. Not a D1 gate |
| [14.50](#1450-the-e2e-teardown-revokes-enrollments-belonging-to-other-runs) | ⛔ **NOT a D1 gate (gkc, 2026-08-23)** — e2e runs isolate locally and are serialized by structure on GitHub. ⚠️ Recorded because a reader will re-derive it: there is no top-level `concurrency:` key in any workflow, so `needs:` serializes the e2e jobs *within* a run and not across runs, and the incident that produced this row was cross-run. Stays as unblocked hygiene. **The e2e teardown revokes enrollments belonging to other runs.** `tests/at_end2end_test/test/enrollment_teardown.dart` revokes every approved enrollment on the shared `@ce2e1`-`@ce2e4` atSigns with `force: true`, not only the ones its own run created, so two overlapping CI runs tear down each other. **Diagnosed 2026-08-22** from the *other* run's log - the section carries the two timestamps 430 ms apart and the shared enrollment id. This row read *undiagnosed, and the newest CI run is red* until then. CI has since been green three times — 24/24 twice and 47/47 on [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179) — but every one of those windows was free of another run, so that is a rate and not a fix. Owed: a run-unique marker, so a teardown revokes only what its own run made | Nothing. Needs no permission and no publish, and it does not gate the at_auth carve |
| [14.18](#1418-the-remaining-d1-initial-development-sequence) | ⛔ **THIS IS D1's CRITICAL PATH** — D1 ends when the acceptance set passes and every rail is green, and the remaining carves and publishes are what gets there. Steps 32–34: the per-package release train. **Five of eight positions are through.** at_commons #2168, at_chops #2169, at_lookup #2174 and at_server_status #2177/#2178 are all **merged to trunk**; at_auth is [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179), **open with CI 47/47 green**. Remaining to carve: **at_client, at_client_flutter, at_onboarding_cli**. Re-derive the whole picture rather than reading this cell — for each package compare `pubspec.yaml` on trunk, on this branch, and `curl -s https://pub.dev/api/packages/<pkg> \| python3 -c "import sys,json;print(json.load(sys.stdin)['latest']['version'])"`. Measured 2026-08-22: pub.dev has at_commons 5.16.0, at_chops 3.6.0, at_lookup **3.6.1**, at_server_status **1.1.1**, at_auth **3.3.0**, at_client **3.14.0** | ⚠️ **Merged is not published, and only the publishes still gate anything.** at_lookup 3.7.0-rc1 and at_server_status 1.1.2-rc1 are on trunk and **not on pub.dev**, so every later package can carve and merge but none can publish until gkc publishes those. ⛔ **This cell used to say the at_auth PR's CI would fail to resolve until at_lookup published. That was wrong** — a pub workspace resolves siblings by path, so #2179 resolved and went green with at_lookup unpublished; the gate is on publishing, never on carving or merging. ⚠️ **at_client's `at_commons: ^5.15.0` floor is too low and will ship broken** — `notify_request_transformer.dart:154` calls `metadata.copy()`, which first exists in at_commons **5.16.0**. The same defect was found and fixed in at_auth during its carve; check every floor against first-use before carving at_client. ⚠️ **Owed at the real release, and it belongs to this row because it is the train's:** every constraint moved to an `-rc1` floor reverts to its stable form when these publish, or a stable release ships requiring a candidate. The rule is in [14.49.2](detail/implementation-plan.md#14492-every-remaining-package-publishes-as-a-release-candidate); re-derive the sites — `git grep -n 'rc1' -- 'packages/*/pubspec.yaml' 'tests/*/pubspec.yaml'` |
| [14.18](#1418-the-remaining-d1-initial-development-sequence) | **Step 20's rotation arm — STAYS IN D1** (gkc, 2026-08-23), which is why D1 now ends past the carve. Chain: publish at_auth 4.0.0 → add the `pending` value → build the arm | The publish, and a dedicated CRAM atSign. ⛔ **The "wait for the fleet" gate is CLOSED** — the two keyfile formats are disjoint for every file that exists (3.3.0 dispatches on `version` and never reaches its `keys` parse without one; a 4.0.0 typed document emits `version: 1` and no `keys`), and the one reachable conflict needs a 4.0.0 typed write into a keyfile a 3.3.0 app also opens, which cannot have happened: **no production `.atKeys` or keychain entry holds any PQ key material** (gkc, 2026-08-23) |
| [14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) | ⛔ **TRIAGED 2026-08-23: only item 36 is a D1 gate**, and it is the one known case of the catalogue asserting clauses no live row proves. Of the rest, three are not work at all (20, 21, 26 — each says so in its own text) and two belong elsewhere (14 is not PQ, 35 lands in `atGettingStarted`), leaving six that are open and not D1: 2, 4, 10, 28, 29, 34. Items 8, 23 and 30 were settled the same day. The headline count below overstates the work, which is why it keeps being re-argued — **17** open small items of 36 — the items are in `detail/`, none of them blocking. Re-derive rather than quoting: this row said 17 while the count was 10, then 15 while the count was 18, and the comment beside the command said 17 for two days after the row was fixed | Item 8 is the only one waiting on a ruling. Items 20 and 21 are examined-and-left, not work. Item 35 lands in `atGettingStarted`, not here |
| S-5 residual | ⛔ **POST-D1 CLEAN-UP, not a D1 gate** (gkc, 2026-08-23). ⚠️ **This row read "D1 GATE, and it lands on [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179) while that is open" earlier the same day**, and the PR-#2179 window no longer constrains it — after D1 that PR will be long merged, so the test goes wherever `RegistrarService` then lives. It is `G1` in [THE NEXT MOVE](#the-next-move), below the gates rather than at the top of them. Everything below is the harness, kept intact for whoever picks it up. **The registrar's switch to validating TLS certificates is untested, here and in CI.** `RegistrarService`'s default client used to accept ANY certificate - `badCertificateCallback` returning true unconditionally, on calls carrying the registrar API key. It is now a plain `package:http` client that validates, with the bypass behind `RegistrarIoClient.allowBadCertificates`, off by default and shouted when used. **Neither arm has a test**, and CI cannot catch a regression: `RegistrarIoClient` appears in ZERO CI job logs (control: `RegistrarService` appears), and `RegistrarIoClient.create()` has **no in-tree caller at all** - it is a public opt-in for consumers, which is deliberate, so do not delete it as dead code. Owed: a test pinning both arms against a self-signed local server. ⚠️ **Attempted and parked 2026-08-22**, so the next reader does not start cold: the shape works — mint a cert at test time with `openssl req -x509 -newkey rsa:2048 -nodes -subj /CN=localhost`, serve it with `HttpServer.bindSecure`, and point `RegistrarService` at `localhost:<port>`, which `Uri.https` accepts as an authority. Three arms, and the third is the positive control that proves the server is up: the default client refuses, `RegistrarIoClient.create()` with the flag off refuses, and with it on succeeds — without that third arm a refusal is indistinguishable from a server that never started, because `package:http` wraps connection-refused in the same `ClientException`. ⛔ **Do not commit a PEM fixture** — GitHub push protection can block a private key; mint it in `setUpAll`. | Nothing |
| [14.16](detail/implementation-plan.md#1416-four-residuals-the-issue-tree-audit-surfaced-2026-08-09) | ⛔ **STEP 29 LEAVES D1 — all four dispositioned 2026-08-23.** ① perf ceiling on real low-end hardware → post-D1 cleanup (#2153). ② UC-A3.4 → done 2026-08-17. ③ SS-4 resume → **ruled NO RESUME** (the election makes republishing a filed pair a regression) and **re-filed as orphan growth**: `store()` calls `addKey`, nothing in `crypto/nskey/` retires a filed private, so every abandoned mint — crash or the designed lease-expiry abandon — permanently adds key material to the user's `.atKeys`. ④ IS-1 drift → not D1; at_server #2683 is open, untouched since 2026-08-06, and already ruled to be pared back | Only ③'s orphan-growth half is owed here, and it is a decision before it is code |
| [14.12](#1412-a-mintlegacymaterialfalse-atsign-cannot-write-a-public-record) | ⛔ **NOT D1 (gkc, 2026-08-23) — it gates the post-R-2 stop-release.** A `mintLegacyMaterial:false` atSign cannot write a public record. Out of D1 because both moves it needs are B-3 phase 1, which is parked, and nothing about it blocks the carve; the live assertion in `pq_legacy_interop_live_test.dart` keeps it pinned and the flag must still not be recommended | Two moves its body names, neither scheduled: public-record signing onto the ML-DSA signing root, and self data off `selfEncryptionKey` onto the nskey path (B-3 phase 1). ⚠️ This cell read "Gates the stop-release" until 2026-08-18 — which is what 14.12 *blocks*, so anyone scanning this column for what is ready to start misread the row as ready |
| [14.42](#1442-why-enrollment-setup-takes-four-minutes) | **Why `enrollment_setup.dart` takes ~4 minutes.** Measured at 3:56 and 4:59 against the @ce2e atSigns; 30 seconds is nowhere near enough and the budget is now 15 minutes, which hides rather than explains it. gkc asked for the cause, 2026-08-20 — **not a D1 gate (2026-08-23), but owed to him rather than plan-generated hygiene, so do not quietly demote it.** ⚠️ **What this row still lacks is the thing that would let anyone start:** how to obtain `config14.yaml` and the `@ce2e` keyfiles locally. Until that is written down, the only route is a CI round trip. ⚠️ My sync-backlog reading is NOT established — `end2end_tests` runs the same four atSigns and the same suite in ~3 minutes | ⛔ **@ce2e-only — it does NOT reproduce locally, and this cell said it did.** `runLocal.sh` regenerates `config/config.yaml` from at_demo_data, and against demo atSigns the same four enrollments take about ONE SECOND — a local run reproduces the symptom's ABSENCE. The ~3-minute local repro belonged to a DIFFERENT and already-fixed defect (14.41 row 3's cache key). Reaching this one needs `config14.yaml` and the @ce2e keyfiles, i.e. a CI round trip, and nothing here records how to get those locally |
| [14.47](#1447-the-at_client-unit-tree-has-a-cross-file-isolation-flake) | **NOT a D1 gate (gkc, 2026-08-23) — hygiene.** It is green alone and green in the full suite, and reddens only in one hand-constructed non-alphabetical ordering that nothing actually runs, so no rail as invoked is at risk. Keep the reproduction recipe. **A unit-tree isolation flake**: `local_secondary_sync_queue_test.dart` failed 1-in-4 when run after the nskey/pq files in one non-alphabetical invocation — a same-file test's queue entry leaked into a later test, so the per-test store isn't always fresh. Green alone, green in the full suite | Reproduce at rate (~10 runs of the four-file order), then read the file's setUp for what makes the store per-test fresh |
| [14.46](#1446-executeverbs-sync-parameter-is-inert-on-both-secondaries) | **`executeVerb`'s `sync` parameter does nothing** — declared, never read, on at_client's both secondaries AND at_lookup. **Decided and phase 1 shipped 2026-08-20**: `@Deprecated` on all six declarations for 3.x, removal in 4.0; every cross-package and every prose-reasoned call site cleaned. ⛔ **NOT D1 (gkc, 2026-08-23)** — the removal rides at_client/at_lookup **4.0**, and nothing in the acceptance set asserts the parameter (its one catalogue mention is prose about a mock). Still in the section: a stale at_server comment #2169 will falsify, which lands in a sibling repo | **Removal at 4.0** — delete the parameter from all six declarations and let the compiler enumerate the ~76 remaining same-package sites |
| [14.44](#1444-residuals-from-the-at_chops-pr-review) | Residuals from the at_chops PR review. ✅ **The first is DONE 2026-08-22**, in the at_auth carve as this row said it should be — `encode` refuses an `ArgonHashParams` whose `hashLength` is not the value `decode` will use, which was the section's own preferred option over persisting it. **Two remain:** `XWingCore.combine` writes at hardcoded 32-byte offsets while sizing its buffer from actual lengths — ⛔ **both remaining residuals are POST-D1 (gkc, 2026-08-23)**, and the severity is worth recording: it is **correct for X-Wing**, whose four inputs are all 32 bytes, and **latent and silent** otherwise, because `setRange(0, 32, …)` takes the first 32 bytes of a longer input without error and yields a well-formed but wrong digest; and at_chops 3.6.0's CHANGELOG owes the resolution-skew sentence whose durable record is ruling 110's addendum | Nothing. Both remaining ones go whenever at_chops is next open |
| [14.11](#1411-deprecated_member_use-findings-across-the-workspace) | **STAYS IN D1, with the bucket-B migration** (gkc, 2026-08-23). Re-measured 2026-08-23: **754** findings — at_client 396, at_onboarding_cli 205, at_auth 153, at_lookup **0** (the section's table now carries both columns — the 2026-08-18 figures and these, so it needs no further update). Five buckets, and only **B** has a replacement that exists today: 71 credential-ladder uses (`enrollmentId` 59, `signingAlgoType` 12) moving onto the `AtAuthenticator` seam at_lookup 3.7.0 ships — **24 sites in `lib/`, 47 in tests**. A (AtChops compatibility API, 530) and C (legacy flat keyfile fields, 118) are transient and get **no ignores yet**; D (27) is at v5 | Nothing. Every package exits 0, so none of this blocks a carve |
| [14.34](#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart) | ⛔ **D1 GATE (gkc, 2026-08-23).** `self_enrollment_retrofit_live_test.dart` failed **once in five** pack runs. D1 now ends when every rail is green, and an unexplained live failure at that rate makes "green" a rate rather than a state — so it has to be understood before D1 closes | Unexplained. Not a flake and not fixed — a rate, not a kind |
| [14.29](#1429-the-residuals-1425-surfaced) | ⛔ **NOT D1 (2026-08-23)** — the section's own text says none of these blocks D1's remaining sequence, and SS-2's `__ssenv` half is explicitly *deferred, not owed*: the 2026-08-03 ruling took DEP4 off SS-2 and what is left is a pure optimisation. SS-2's `__ssenv` and two small S-3 items — none blocking. Re-read 2026-08-18: B-1's residuals had shipped and S-3's migration test existed, so this row said **three B-1 residuals, three small S-3 items** against an actual none and two | — |
| [14.39](#1439-pqposture-and-the-rollout-it-drives) | `PqPosture` — **mostly DONE 2026-08-19**: the rename, the 3 postures, the posture-only refusal flag, the sender-side algorithm list and the CLI's `--posture` all shipped, live-green. **Client-driven retrofit at start is BUILT 2026-08-19**, sequenced into `_init` rather than re-pointing a live client; unit-green and **live-green** — functional 174/174 (after one 173/174 whose single failure was [14.34](#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart)), e2e pq 54/54, and the `legacy-server` arm 2/2 against the pinned `atsigncompany/virtualenv:vip-p3.15.0`. **Owed: public-data signature verification** (undesigned) — ⛔ **POST-D1, and deliberately NOT in the acceptance catalogue (gkc, 2026-08-23)**: `dataSignature` appears zero times in `acceptance.md`, against 28 mentions of "signature" as a control, so nothing asserts it. ⚠️ Worth stating plainly since it reads as an omission otherwise: `pqActive` already **signs** public data and nothing anywhere verifies it — not at_client, not the atServer — so we emit a signature no one checks, knowingly | Nothing |

### 14.39 `PqPosture` and the rollout it drives

⛔ **The one thing still owed here — public-data signature verification — is
POST-D1 and deliberately NOT in the acceptance catalogue** (gkc, 2026-08-23).
`dataSignature` appears zero times in `acceptance.md`. Everything else in this
section shipped 2026-08-19.

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

### 14.34 An unexplained intermittent in `self_enrollment_retrofit_live_test.dart`

⛔ **D1 GATE (gkc, 2026-08-23).** D1 now ends when every rail is green, and an
unexplained live-pack failure at **once in five** makes "green" a rate rather
than a state. It has to be understood before D1 closes.

One full-pack run on 2026-08-17 came back **166/167**: the test timed out after
40 s at `await firstNotification`. **Five pack runs were made that day and only
that one failed** — the others were 167/167 and 168/168 ×3 — and the file passes
alone.

⚠️ **Very probably the same phenomenon as
[14.43](detail/implementation-plan.md#1443-the-functional-suites-convergence-race), and the two rows were
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

**New evidence 2026-08-23, from a throwaway probe built for something else, and
it narrows the suspect list.** A rig that enrolled clients in a loop and waited
45s on each for any notification saw **2 of 20** default-posture clients and
**2 of 18** `PqPosture.pqActive` clients receive nothing, each carrying
`Monitor|Failed to start notifications: Exception: The connection went away
before a response arrived` (`AT0014`). Two things follow. **The signing
algorithm is not the variable** — both arms fail alike, and the arms genuinely
differed (`mldsa65` against a null resolution falling back to `rsa2048`), so a
retrofitted client's monitor is no more fragile than a legacy one's. And the
failure is reachable **without** a retrofit at all, which this section's
scenario has always included.
⚠️ **Read that rate as the rig's rather than the product's**: the probe built 20
clients for one atSign in one process, which is not a shape production has, and
both runs aborted on `AT0014` before finishing. What it supports is the
comparison between the arms, not the absolute figure. ⛔ **An earlier version of
the same rig reported 6 of 30 and that number was entirely its own** — it held
every client open until it hit the atServer's `inbound_max_limit`, which the
far-side log states outright as `Wrote stats to 12 monitor connections`. That
ceiling is worth knowing before writing any multi-client live rig.

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

⚠️ **The byte-identical gate held for three carves and NOT for at_auth, so
"empty" is the default rather than the rule.** at_auth's carve departs from the
spike in three files on purpose, each recorded in entry 4 of
[`## THE NEXT MOVE`](#the-next-move): two dependency floors that were too low,
a CHANGELOG sentence justifying a breaking change by naming a consumer that
does not do the thing on trunk, and a test dartdoc citing a `docs/projects/`
path. The gate's value is that every departure is *deliberate and named* —
treat a non-empty result as a list to justify line by line, not as a failure,
and carry the same edits back to the spike when trunk merges in.

⚠️ **A carve of a package with dependents is NOT package-only when the version
is a MAJOR.** A pub workspace refuses to resolve if any member's constraint
excludes the new version, so every job dies at `dart pub get` before a single
test runs — the failure looks nothing like a version problem. Widen every
workspace member's constraint in the same commit, and grep unscoped:
`git grep -n -P '^\s+at_<pkg>:' -- '*pubspec.yaml'`.

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
holds the detail — but it is **not** what defines D1's end. **D1 ends when
every acceptance test passes and every rail is green, the posture matrix
included** (gkc, 2026-08-23); this sequence is the work that gets there. ⚠️ This
said D1 "ends at step 34, when the stacked PRs are merged", then briefly that it
ended at the at_auth publish and the rotation arm. Both are superseded.

⛔ **What blocked the VE image (established 2026-08-20, after two
misdiagnoses).** The blocker was **not** an at_server release:
`preserveFirstEnrollmentOnRetrofit` is on at_server `trunk` (8 hits). It was
**CI pulling the production VE image**.

⚠️ **This paragraph opened "What actually gates D1 … D1 is done when the spike
is in trunk and the eight packages are released", and that is the SUPERSEDED
definition** — replaced by the 2026-08-23 ruling ten lines above, which the
paragraph sat directly beneath while contradicting it. The carve and the
publishes are still owed and still sequenced (G6), but they do not define D1's
end. Recorded rather than deleted because of the shape: the paragraphs that
corrected the definition all carry ⚠️ markers and this one carried ⛔ **What
actually gates D1**, so the falsified sentence read as the most authoritative
line on the page precisely because nobody had annotated it. Its heading is now
about the image, which is what its body is actually about.

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
| 5 | **DONE 2026-08-13 — the `retired` key path, in three commits.** `6a5eac838`: `PackageKey` gains `status`, a `KeyEntryStatus` of `active` or `retired`, and `bestKeyFor` on both a key package and an nskey advertisement passes a retired key over, so `kpid` is the *active* enc key's kid. Emitted only when retired — absent already reads as active — and an unrecognised value read as retired. ⚠️ **That last clause held only until 2026-08-22**, when `KeyEntryStatus` became an open String (14.49.1): an unrecognised value is now carried through verbatim and is neither offered for new operations nor trusted to verify old ones. The 2026-08-13 reading was right that it must not be *used*, and wrong that `retired` says so — a retired key still verifies what it signed. `f956b2146`: `PersistedApkamKeys` becomes `{encKeys: [PersistedEncKey]}` and `KeyPackageRegistration` expands, advertises and answers for every held key, with `encKeyFor(kid)` replacing `encSecretKey` and `heldKpids` listing every address. `f6fc3796e`: the sweep, the wake-up subscription and the sync listener cover every held address (`EnvelopeAddressing.regexForAny`/`sweepRegexForAny`), and `_consume` opens with the key the envelope names. **Three things ruling 9 got wrong or omitted**, all recorded in `decisions.md` 95: the sweep filter is a **fifth** consequence and the one that makes the other four reachable; the keyfile already records the status (`CryptographicMaterial.CryptographicMaterialStatus`, `AtKeys.retireKey`, and an `AtKeysAssurance` rule enforcing one active `publicEncapsulation` per enrollment and algorithm), so deriving it from `createdAt` was wrong; and `dead` material is not adopted at all. Rails: at_client 1210/1210, functional 146/146. **Nothing rotates yet** — the writer is step 16. ⚠️ app-facing: `PersistedApkamKeys` is what apps build in `loadApkamKeys`/`saveApkamKeys` | [`decisions.md` 95](detail/decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12) rulings 6–9 — without the plural holding the field is decorative. The **name collision** was settled 2026-08-12 (gkc) and landed as ruled: the per-entry wire value is a Dart `KeyEntryStatus`, and `KeyPackageStatus` — the reader's verdict on a whole package (`present`/`absent`/`rejected`/`unsupported`) — keeps its name. Nothing renamed |
| 6 | **DONE — mostly with step 2a, completed 2026-08-13.** `parseApskValue` reads the array **and** the released bare string, refuses a structured value advertising nothing it understands rather than guessing, and skips entries whose `use` or `alg` it does not know; `apsk_formats_test.dart` covers all of that plus "the array form is unmistakable to a bare-RSA consumer". Finished on 2026-08-13 by giving `ApskSigningKey` a `status` and having `apskSigningKeys` read it — **keeping** a retired entry, because this list is what verifies stored envelopes and a retired key is precisely what signed the older ones. `KeyEntryStatus` moved from at_client to **at_auth** in the same change so all three advertising records name one type, narrowing [94](detail/decisions.md#94-three-records-advertise-keys-and-only-one-of-them-speaks-the-vocabulary-2026-08-11)'s "one vocabulary cannot mean one Dart type" — that was true of a type living in at_client, and at_auth is the lower package. **Found by the re-verify:** `design.md` 9.3's JSON example omitted `kid`, which the reader requires, so the document the design showed is one every reader treats as empty and then refuses; corrected, and pinned. `advertised.first` and the singular `ParsedApsk` are steps 7–9's business, not a gap here | [`design.md` 9.3](design.md#9-subsystem-g--signature-agility-the-authsigning-key-split) |
| 7 | **DONE 2026-08-13.** `SigningAlgoType.strongestFirst` + `strongestOf` in at_chops — purely additive (two statics on the existing enum; no member added, moved or renamed, so it does not touch the unresolved 3.6.0-versus-major question). Deliberately **not** declaration order: members are declared in the order they were added and reordering them is a wire change, so preference is a second statement. `mldsa65` first, categorically — the only member Shor does not break — then RSA-4096, `ed25519`, `ecc_secp256r1`, RSA-2048 by classical security level. Total on purpose: a partial order leaves the choice undefined for exactly the pair nobody thought about. **The tripwire is completeness, not just the literals**: a new `SigningAlgoType` left out of the order turns `test/signing_strength_test.dart` red, which is what stops it becoming silently unrankable. Wired straight into `parseApskValue`, which took `advertised.first` — the order entries arrive in is the *signer's* choice, so an enrollment advertising ML-DSA-65 beside RSA-2048 was verified against whichever it listed first | [14.17](detail/implementation-plan.md#1417-signature-agility--complete) |
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
| 18b | ✅ **DONE 2026-08-13.** `SigningKeyMinting` (at_client) mints a keypair for every algorithm the in-use set names and the enrollment does not hold, advertises it, and **then** files it through `WrittenAtKeysIo.update` — the store's atomic verb, because a client's start files conveyed key material through the same keyfile and a hand-rolled read → mutate → write would drop whichever addition flushed first. Wired as the **ninth** `PqClientBootstrap` step, `mintInUseSigningKeys`, gated by `PqStartupGates` and placed **before every step that signs** (seeding, both link publications and the sweep all emit signed envelopes), so a key minted on a start is advertised before anything signs with it. Which writer depends on whether there is an enrollment record: `enroll:update` where there is one — the atServer is the only writer of an enrollment's `_apsk` — and a direct publish under `primary` where there is not. Inert with an empty in-use set (the 3.x default) and inert for a client with no key source, which is the tested no-`AtKeysIo` property. `RsaKeyPair.generate()` rather than `AtChopsUtil.generateAtPkamKeyPair()`, which returns a type at_chops deprecates. **Proven by three mutations**: swapping to file-then-publish reddens the ordering test, dropping the retained authentication key reddens the advertisement tests, and minting an already-held algorithm reddens both idempotence tests. ⚠️ **The second of those mutations no longer discriminates** — row B2 removed the retention it was probing. Its replacement is B2's own pair: gutting the withdrawn-signing-key selector (`retiredSigningKeysFor` on the day, `withdrawnSigningKeysFor` since 2026-08-22) reddens the two retained-signing-key tests, and removing the dedup reddens the third. Rails: at_client **1257/1257** (2 skipped), acceptance **57** (2 skipped) |
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
| 30 | `deprecated_member_use` across the workspace. ⚠️ **RE-DERIVED 2026-08-20 at `26644e779`: 780, not the 666 this row used to record** — at_client **396**, at_onboarding_cli **205**, at_auth **153**, at_lookup **26**, at_chops 0, at_commons 0 (`dart analyze lib test` per package, `grep -c deprecated_member_use`). ⛔ **THAT RULING IS SUPERSEDED. It read "RULED 2026-08-20: all 780 are in D1's bar" until 2026-08-23**, when gkc ruled the opposite: the findings are triaged into five buckets and **only bucket B — the 71 credential-ladder uses — is D1 work**; A and C are transient and get no ignores yet, D waits for v5. Re-measured the same day: **754**, with at_lookup at **0**, not 26. ⚠️ **76 of them are this project's own**, added deliberately by the at_lookup consolidation's six credential deprecations and the `AtLookupImpl` constructor deprecation; the other 704 are the at_chops compatibility shim, `AtSigningInput` and `apkamPublicKey`. Clearing the 76 means moving at_client's eight readers of `atLookUp.enrollmentId` and the `atChops` readers off those members — the work filed as **BLOCKS THE MAJOR** in `docs/projects/at-lookup-consolidation/plan.md` section 6. That is non-breaking: the members stay, their callers leave. | [14.11](#1411-deprecated_member_use-findings-across-the-workspace) |
| 31 | ✅ **DONE — nothing owed since 2026-08-10.** The one item (the functional pack's compose hardcoding a local image) is struck in the body; the external gate it names is step 32's blocker, not a checklist entry. This row carried no state until 2026-08-18, which in this table reads as open | [14.15](detail/implementation-plan.md#1415-pre-pr-rails-checklist) |

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
→ at_commons **5.16.0** → at_auth **4.0.0-rc1** → at_client's GA minor, and finally
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


### 14.14 A client with no enrollment id is treated as fully privileged

✅ **CLOSED 2026-08-23, and moved to `## PARKED`.** Both halves were already
ruled and nobody had closed the row: the privilege by this resolver's own
dartdoc, the `primary` identity by [14.18](#1418-the-remaining-d1-initial-development-sequence)
step 13. Kept so the question is not re-derived. The original text follows.

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

⛔ **NOT D1 (gkc, 2026-08-23) — this gates the post-R-2 stop-release.** Both
moves it needs are B-3 phase 1, which is parked, and nothing about it blocks
the carve. The live assertion in `pq_legacy_interop_live_test.dart` keeps it
pinned, and the flag must still not be recommended to anyone.

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

**STAYS IN D1, with the bucket-B migration only** (gkc, 2026-08-23). Of the
754 findings measured 2026-08-23, bucket B — 71 credential-ladder uses with a
replacement that already exists — is D1 work; A and C are transient and get no
ignores yet, and D waits for v5. The five buckets are tabled below.

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

| package | 2026-08-18 | **2026-08-23** |
|---|---|---|
| `at_client` | 345 | **396** |
| `at_onboarding_cli` | 183 | **205** |
| `at_auth` | 110 | **153** |
| `at_lookup` | 28 | **0** |
| `at_chops`, `at_commons` | 0 | 0 |

**754 today**, and at_lookup went to zero — its deprecated members went with the
`AtLookUp.withSecureSocket` work. Every package still exits 0, so none of this
blocks a carve.

**The five buckets** (gkc, 2026-08-23: "it's not all or nothing; some we should
ignore because they are a transient state; others will need to be actually
fixed"). Re-derive rather than quoting — group the findings by the symbol the
message quotes:

| bucket | n | what it is | replacement? |
|---|---|---|---|
| **A** AtChops compatibility API | 530 | `AtChops*`, `AtPkamKeyPair`, `AtEncryptionKeyPair`, `AtSigningInput`/`Mode`, `PkamSigningAlgo`, `RsaSigningAlgo` | ✗ — no dispatcher selects by `SigningAlgoType`. gkc: `// ignore:` when we act, PKAM signing especially |
| **B** credential ladder | 71 | `enrollmentId` 59, `signingAlgoType` 12 | ✓ **`AtAuthenticator` / `authenticatorForChops()`** — shipped in at_lookup 3.7.0 |
| **C** legacy flat keyfile fields | 118 | `defaultSelfEncryptionKey`, `apkamPrivateKey`/`PublicKey`, `apkamSymmetricKey`, `defaultEncryption*` | ✗ — retained until the ecosystem is PQ ([37](detail/decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05)) |
| **D** at_auth response family | 27 | `atAuthKeys`, `AtAuthResponse`, `AtOnboardingResponse` | scheduled — relabelled to **v5** on 2026-08-22 |
| **E** singletons | 8 | `metadata`, `hashingAlgoType`, `atSign`, `AtLookupImpl` | case by case |

⛔ **Only bucket B is D1 work**, ruled 2026-08-23: 24 sites in `lib/` and 47 in
tests move onto the authenticator seam. A and C get **no ignores yet** — the
decision was to record the buckets and change no code. D waits for v5.

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

⚠️ **This paragraph used to read as though the atServer imposed a modulus
check on the authentication path. It does not, and the correction matters
because the old wording reads as a live hazard.** What at_server's
`apkam_signature_verifier.dart` actually carries is its own *reason for
declining a migration*: "rsa2048 and ecc_secp256r1 stay on the compatibility
API **deliberately**. `RsaSignatureAlgo` refuses any modulus that is not
exactly 2048 bits, which `PkamSigningAlgo` does not… Both are changes to what
verifies on the authentication path, which is not a refactor's to make." PKAM
authenticates today under both `rsa2048` and `mldsa65`, and nothing in this
tree is at risk. What is genuinely true on our side is narrower: at_client_sdk
**signs** rather than verifies, and bucket A has no drop-in replacement because
nothing non-deprecated selects an algorithm from a `SigningAlgoType` — a caller
writes the two-way branch itself. That is a missing convenience, not a
behaviour risk.


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

### 14.42 Why enrollment setup takes four minutes

⛔ **NOT a D1 gate (gkc, 2026-08-23), but owed to gkc personally** — he asked
for the cause on 2026-08-20, so this is not plan-generated hygiene and is not
to be quietly demoted. What it still lacks is how to obtain `config14.yaml` and
the `@ce2e` keyfiles locally; until that is written down the only route is CI.

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

### 14.50 The e2e teardown revokes enrollments belonging to other runs

**DIAGNOSED 2026-08-22, and it is a harness defect, not a product one.** This
section was titled "The newest CI run on this branch is red" until the cause
was found; the run that prompted it is long superseded, and CI has since been
**24/24 green twice** (`f82ca0a46`, `64480808d`).

`tests/at_end2end_test/test/enrollment_teardown.dart` revokes **every**
approved enrollment on the shared `@ce2e1`–`@ce2e4` atSigns with `force: true`,
not only the ones its own run created. Two CI runs overlapping on those atSigns
therefore tear down each other's work. Measured, from the *other* run's log
rather than inferred from this one: run `32483465296` on branch
`gkc-pq-d1-at-lookup` logged
`Revoking the enrollment permission for id: 121bc733-…` at `12:51:23.182Z`, and
run `32482877878` failed **430 ms later** with
`error:AT0027: 121bc733-… is revoked` — an enrollment its own `setUpAll` had
created at `12:44:40`. That run's teardown revoked eight: its own four and all
four of the other's.

⚠️ **Still open, and passing runs are not evidence it is fixed.** Both green
runs since had no other run in flight (checked `gh run list` across each
window), so the mechanism had no opportunity to fire. It is a rate, not a kind.
The fix is for the teardown to revoke only what its own run created, which
needs a run-unique marker on the enrollment.

**The original evidence, kept because it is what a recurrence will look like:**

```bash
gh run list --branch gkc-pq-d1-spike --workflow at_client_sdk.yaml --limit 3 \
  --json databaseId,headSha,conclusion,createdAt \
  --jq '.[] | [(.databaseId|tostring), .headSha[0:9], .conclusion, .createdAt] | @tsv'
```

Run `32482877878` on `9a7260dc7`: **10 of 11 jobs green, `end2end_test_14`
red.** Eight of its twelve tests failed, all in `setUpAll`, all with the same
cause:

```
Exception: Unable to authenticate | Cause: Exception: pkam auth failed for
@ce2e1 - Exception: Failed connecting to @ce2e1.
error:AT0027:enrollment_id: 121bc733-…
```

So the failure is **authentication against a shared @ce2e atSign**, before any
test asserts anything. `notify_with_isolate_test.dart` also hit
`PathNotFoundException: Deletion failed, path = 'test/hive/@ce2e1'`, which is a
teardown of state that was never created — a consequence of the same setUpAll
failing, not a second defect.

⚠️ **This is a hypothesis, not a diagnosis: nothing has been run to confirm
it.** The shape matches the class this tree already names — a live test whose
server-side enrollment state is one-shot per `(appName, deviceName)` and
therefore collides on a re-run — and `AT0027` naming an `enrollment_id` points
the same way. What has NOT been established is whether the enrollment was
denied, already approved, or expired, and whether the run before it left the
state behind. Read the atServer's own log before believing any of it; a
cross-process claim read from the client side is a claim about the client.

Related but **not** established as the same thing:
[14.42](#1442-why-enrollment-setup-takes-four-minutes) is also @ce2e-only and
also about enrollment setup. Two @ce2e enrollment oddities are not one finding
until something says so.

**The full log is 15,197 lines and its tail reaches the runner's cleanup**, so
it is not truncated — fetched with
`gh api /repos/atsign-foundation/at_client_sdk/actions/jobs/96772989540/logs`,
never `gh run view --log-failed`, which returns a truncated stream here.

### 14.47 The at_client unit tree has a cross-file isolation flake

⛔ **NOT a D1 gate (gkc, 2026-08-23) — hygiene.** It is green alone and green
in the full suite, and reddens only in one hand-constructed non-alphabetical
ordering that nothing actually runs, so no rail as invoked is at risk. The
reproduction recipe below is the part worth keeping.

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

Not pooled with [14.43](detail/implementation-plan.md#1443-the-functional-suites-convergence-race): that is
the functional pack against a live atServer; this is the unit tree and Hive
state on disk. What it wants: run the four-file order ~10 times either side of
any suspect change, and read `local_secondary_sync_queue_test.dart`'s setup
for what makes its store per-test fresh — the leak says sometimes it isn't.

### 14.46 `executeVerb`'s `sync` parameter is inert, on both secondaries

⛔ **NOT D1 (gkc, 2026-08-23)** — the removal rides at_client/at_lookup **4.0**,
and nothing in the acceptance set asserts the parameter: its one appearance in
the catalogue is prose about a mock. Phase 1 already shipped, so the API is
honest today.

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
- ⛔ **`docs/projects/pq/post-quantum-cryptography.md` is gkc's private working
  draft. HANDS OFF — do not read it for review, do not register it with the
  docs rail, do not commit it, do not delete it.** ⚠️ **This bullet said
  "either finish and track it or delete it" until 2026-08-23**, which is an
  instruction to either publish gkc's private notes or destroy them, and the
  line count beside it stayed accurate so the row read as maintained. It was
  deliberately untracked and gitignored by `220537523`; verify rather than
  trusting this sentence:
  `git check-ignore -q docs/projects/pq/post-quantum-cryptography.md && echo ignored`.

### 14.44 Residuals from the at_chops PR review

⛔ **Both remaining residuals are POST-D1 (gkc, 2026-08-23)** — they ride the
next at_chops touch. The first residual, the passphrase envelope's `hashLength`,
landed 2026-08-22 in the at_auth carve and is recorded at the end of this
section.

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

✅ **Done 2026-08-22, the second way**, as the second commit of
[PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179).
`encode` compares against `ArgonHashParams().hashLength` rather than a literal
32, so at_auth holds no second copy of at_chops' default and the guard tracks
the value `decode` will actually derive at — confirmed by reading `decode`,
which sets only `memory`, `iterations` and `parallelism` and lets the length
fall through. The refusal names the parameter and the offending value, because
the failure it replaces blamed the passphrase. Two tests, mutation-proven
**separately**: disabling the guard reddens only the refusal and the failure
quotes that test's own message matcher; inverting it reddens the control that
proves the default is still accepted. Nothing outside the new test varies
`hashLength` anywhere in the tree, which is what made the guard the cheaper
option — the persisted-field version would have shipped a format no test could
exercise.

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
| [14.49](detail/implementation-plan.md#1449-keyentrystatus-becomes-a-typed-string-and-the-release-train-is-all-candidates) | `KeyEntryStatus` becomes an open String, and every remaining package publishes as a release candidate | ✅ **DONE 2026-08-22.** Both halves shipped: [14.49.1](detail/implementation-plan.md#14491-keyentrystatus-becomes-a-typed-string-wrapper--done-2026-08-22) made the status an open token a reader carries through verbatim instead of flattening to `retired`, with both collapsing seams fixed, the verify half wired at two call sites and the `_apsk` selector widened; [14.49.2](detail/implementation-plan.md#14492-every-remaining-package-publishes-as-a-release-candidate) ruled the rest of the train onto `-rc1` floors. ⚠️ This section sat in **no table at all** until 2026-08-22 — not TODO, not DONE, not PARKED — so every command that counts work by row was blind to 230 lines of it |
| [14.41](detail/implementation-plan.md#1441-what-the-first-ci-runs-on-the-spike-branch-found) | The first CI runs on the spike branch, and the four red rows they found | ✅ **DONE** — CI fully green, run 32392240064, 11 of 11, on `f24ee3ab6` (the head with `origin/trunk` merged in, so it covers at_commons #2168 and the 15 commits trunk brought). Only **one** of the four was a product defect; two were harness assumptions holding by luck and one was a CI step running the wrong image. What the section surfaced beyond those has its own rows: the convergence race ([14.43](detail/implementation-plan.md#1443-the-functional-suites-convergence-race), also closed) plus [14.42](#1442-why-enrollment-setup-takes-four-minutes) and [14.47](#1447-the-at_client-unit-tree-has-a-cross-file-isolation-flake), both still open |
| [14.43](detail/implementation-plan.md#1443-the-functional-suites-convergence-race) | The functional suite's convergence race — four shapes, each diagnosed and fixed | ✅ **DONE 2026-08-21.** All four shapes have diagnosed, mutation-proven fixes; the last members were classified (`sync_multiple`'s red carries shape C's signature) or fixed (the rotated-advertisement stale read, `ccf4987a4`); the driver dumps child output on failure (`fce13ca52`). Rate at `112e1f740`: 0 family reds in 10 valid packs. ⚠️ **Fixed on this branch, NOT on trunk** — shape A's `_throwIfStopped` and the `stop()` done-completer arrive with the at_client PR, so any carve off trunk still meets it; measured on the at_auth carve 2026-08-22, 1 red in 5 packs. The open residue has its own TODO row |
| [14.48](detail/implementation-plan.md#1448-a-primary-client-can-sign-with-a-key-its-own-advertisement-just-withdrew) | A `primary` client could sign with a key its own advertisement had just withdrawn | ✅ **DONE 2026-08-21 by [ruling 114](detail/decisions.md#114-a-signer-waits-for-its-own-mint-the-mint-alone-does-not-2026-08-21)** — the sign path awaits the mint (`09f9a974c`), differential- and mutation-proven, pack green. The cause was four things at once: fire-and-forget startup minting, publish-before-file, the sign path's auth-key fallback, and the shared composer withdrawing the auth key on the first mint. The residue the ruling named — the durable pre-mint-envelope question and the verifier's pre-mint cache asymmetry — was **closed 2026-08-23**: each needs PQ material to exist in production and none does, per the standing premise at the top of this file |
| [14.45](detail/implementation-plan.md#1445-an-expired-key-the-client-cannot-delete-pins-it-in-a-hot-loop) | An expired key the client could not delete pinned it in a hot loop | ✅ **DONE.** The spin is fixed — a sweep that removes nothing now backs off 30s instead of re-arming at zero; it was **225,721 failed sweeps across three `_nskeylock` records** in one local pack, **47.4%** of its log lines, and pre-existing on trunk. The refusal is fixed with it: a namespace check rather than immutability, and the sweep now bypasses it. ⛔ **NOT the cause of [14.43](detail/implementation-plan.md#1443-the-functional-suites-convergence-race)** — the run carrying all three loops was green, 177/177; a rate effect is not excluded, presence is. ⛔ Why the lock is synced to local storage at all is **parked** (gkc, 2026-08-20). The cross-repo residue has its own TODO row |
| [14.40](detail/implementation-plan.md#1440-at_client-publishes-as-a-minor-and-the-heading-now-says-so) | ✅ **DONE — RULED 2026-08-20: at_client publishes as `3.15.0`, a MINOR.** Heading and pubspec both moved; the three `**BREAKING**` labels were rewritten because nothing published was removed — verified against the published 3.14.0 archive, where `disallowLegacyEncryption`, `keyEstablishmentAlgorithms`, `PqPosture` and `ReleasePosture` appear in **zero** files against a control of `AtClientPreference` in 20 | — |
| 14.38  | `at_activate` can administer a PQ-native atSign             | DONE 2026-08-19, live-green (CLI functional pack 17/17 against a locally built `at_virtual_env:local`). All three agreed changes landed, and two of them had been recorded as done when they were not: the `_initAtClient` overwrite survived a change to *which* preference field it read, and the file-stream site was named as methods that do not exist. The row also claimed `--posture` reached every command — it reached every *parser* while twelve commands ignored the value. Detail: [14.38](detail/implementation-plan.md#1438-activate_cli-cannot-administer-a-pq-native-atsign) |
| 14.37  | `pqSeal` version `0x01` removed outright, and the last homegrown key schedule with it | DONE 2026-08-18 — **one commit, not the two this row prescribed.** gkc reframed it from *retire safely* to *is there any value in `0x01` over `0x02`* — there is none: same KEM, so no diversity; self-generated vectors against the working group's; and its only distinctive feature, AES-256-GCM, is immaterial on a 32-byte content key. `_SealVersion.custom` had no other user, so `atPQv1-base` left the tree entirely. ⚠️ The two-commit plan's first step was also **mis-specified** — it named `SecretSharingAlgos.suites`, which neither seal site reads. Ruling [110](detail/decisions.md#110-the-0x01-seal-version-is-retired-stop-emitting-before-removing-2026-08-18) amended in place. Detail: [14.37](detail/implementation-plan.md#1437-the-0x01-seal-version-removed-outright) |
| 14.15  | Pre-PR rails checklist                                  | DONE 2026-08-10 — the compose-image item is struck in the body and nothing needs reverting before a PR. It stayed in TODO until 2026-08-18 because the section opened with a condition instead of a status. The external gate it names is step 32's blocker |
| 14.17  | Signature agility, and the G1 cluster joins the catalogue | DONE 2026-08-18 — steps 1–5 done, step 6 out of scope by gkc's ruling; the last piece was the signed-envelope 3×3. ⚠️ **This row sat in TODO reading "the owed half" for the rest of that day**, while the section's own body said COMPLETE — the shape the plan's own re-derivation warning names, where a body says closed and the heading nothing keys on says open. A cold read caught it. The section heading moved with this row. Body: [14.17](detail/implementation-plan.md#1417-signature-agility--complete) |
| 14.36  | `send()` composes its command with `NotifyVerbBuilder`, and finally has live coverage | DONE 2026-08-17 — the hand-rolled `notify:` string is gone; `useAtKeyToString = true` is required, since the name is split across `key` and `namespace`. One wire delta, `:notifier:SYSTEM`. **`send()` had no live test at all before this**, so the wire delta was landed with one added rather than on the inference that `notify()` already sends the token. The architecture guard moved with it: requiring `toAtProtocolFragment` in this file would now force the hand-rolled command back, so it asserts the absence of one instead. Body: [14.36](detail/implementation-plan.md#1436-sends-command-is-hand-rolled-where-a-tested-builder-exists) |
| 14.35  | `send()` splits its name at the first dot, and says what the parameter is | DONE 2026-08-17 — gkc ruled the parameter is `<id>.<namespace>` and poorly named; `namespace` deprecated for `idAndNamespace`, a dot-free name now throws at the call site. Unit **1401 (2)**, analyze exit 0. The one-line fix this row first proposed was measured WRONG — it would have changed the ciphertext binding. Body: [14.35](detail/implementation-plan.md#1435-notificationservicesend-throws-away-the-namespace-it-was-given) |
| 14.33  | Closed as mis-stated: the refusal it named is unreachable | CLOSED 2026-08-17 — `shared_key.*` is written by a raw `UpdateVerbBuilder` at a `Secondary`, downstream of a refusal that fires before `provider.encrypt`, so it can never reach it. No client-side blocker remains for R-2. The real gap it was standing in front of is [14.35](detail/implementation-plan.md#1435-notificationservicesend-throws-away-the-namespace-it-was-given). Ruling [107](detail/decisions.md#107-a-local-record-is-not-encrypted-and-the-legacy-refusal-exempts-it-2026-08-17) amended in place. Detail: [14.33](detail/implementation-plan.md#1433-closed-the-shared_key-refusal-was-never-reachable) |
| 14.30  | A notification that outruns its key is parked and re-driven | DONE 2026-08-17 — ruling [106.5](detail/decisions.md#1065-ruled-park-and-re-drive-not-readiness-at-the-hand-back-2026-08-17); proven live end to end (parked → asked → answered → filed → re-driven → decrypted). Three further defects fixed on the way, all invisible to unit tests. Body: [14.30](detail/implementation-plan.md#1430-a-content-notification-can-outrun-the-key-that-opens-it) |
| 14.32  | An in-process `_apsk` write no longer clobbers a just-minted advertisement | DONE 2026-08-17 — ruling [102.2](detail/decisions.md#1022-the-in-process-window-is-closed-by-serialising-the-writers-2026-08-17); proven live, `_apsk.primary` ends on the mldsa65 array where it ended on bare RSA. Body: [14.32](detail/implementation-plan.md#1432-a-primary-clients-ml-dsa-signing-key-is-not-visible-to-its-verifiers) |
| 14.31  | A `local:` record is not encrypted, and the legacy refusal exempts it | DONE 2026-08-17 — six related defects, not one; the listener no longer dies from a refused watermark. Ruling [107](detail/decisions.md#107-a-local-record-is-not-encrypted-and-the-legacy-refusal-exempts-it-2026-08-17). Body: [14.31](detail/implementation-plan.md#1431-a-refused-watermark-write-permanently-disables-the-monitor) |
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
