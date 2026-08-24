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
is *what to do first*.

⛔ **This document records only what is still owed** (gkc, 2026-08-23). What has
been done is in the codebase and in `git log`; it is not repeated here. The one
exception is a claim somebody would otherwise re-derive — a rejected proposal, a
measurement that closed a question — and those live in
[`decisions.md`](decisions.md), because a rejection is a decision and no commit
can contain a thing that was never built.

**D1 ends when every acceptance test passes and every rail is green, the posture
matrix included**, with the acceptance set complete, implemented and verified
(gkc, 2026-08-23). Everything else is a judgement call.

⚠️ **The D1 gates are `G2`–`G7`.** `G1` sits below them under **POST-D1
CLEAN-UP** — it was a gate until 2026-08-23 and keeps its letter, because prose
above and below cites these letters and renumbering would silently repoint every
one of them.

**The release train's live gate**: at_chops 3.6.0, at_commons 5.16.0,
**at_lookup 3.7.0-rc1** and **at_server_status 1.1.2-rc1** are all on pub.dev as
of 2026-08-24, so the train is clear as far as **at_auth**, which is next and is
not yet published. ⚠️ **This read "at_lookup 3.7.0-rc1 is not on pub.dev", and
the command beneath it confirmed that — wrongly.** pub.dev's `latest` field
excludes prereleases, so an `-rc1` never appears there however published it is.
Re-derive against the versions list, never `latest`:
`curl -s https://pub.dev/api/packages/at_lookup | python3 -c "import sys,json;print([v['version'] for v in json.load(sys.stdin)['versions']][-5:])"`.

⚠️ **A second workstream is open and is NOT in this table** — the knowledge
base, agreed with gkc 2026-08-20. Its plan, format, rail design and ordered
method are in [`docs/knowledge/README.md`](../../knowledge/README.md), which is
a scaffold with no nuggets written yet. If that is what you are here for, open
that file instead; the list below is the PQ release work.

**THE D1 GATES, in order. Everything above this line is history.**

**G2. Build the acceptance suite out per [ruling 115](detail/decisions.md#115-the-acceptance-suite-is-4-arms-and-a-ledger-not-one-grid-2026-08-23).**
The gate that D1's own definition rests on, and the largest. gkc's framing:
hundreds of functional and e2e tests cover the acceptance set between them, and
there is no definitive place to see the whole of it being proven; the posture
matrix is the logical place to build that out. **The gap is now established and
the design is ruled** — the first two of this entry's three owed steps are
discharged, and what remains is the build. **Of that build, four pieces have
landed (2026-08-23) and are named here so they can be grepped rather than
re-derived:** the ledger (`packages/at_client/tool/acceptance_ledger.dart`),
its local driver (**`tools/acceptance_ledger.sh`**, `--with-live` for the live
packs), its wiring rail
(**`packages/at_client/test/acceptance_ledger_wiring_test.dart`**) and **arm 1**
(**`tests/at_functional_test/test/pq_stage_arm_test.dart`**). ⚠️ **This read
"Arms 2–4 and the ledger's clause level have not [landed]"** — on 2026-08-24
arms 2 and 3 were built and arm 4 was cancelled, so what remains of this entry
is the ledger's **clause level** alone. Read the ✅ markers below before
starting anything here.

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
jobs upload the inputs. Rendered from a real CI run's artefacts across both
workflows it reads **63 PROVEN · 0 NOT-EXERCISED · 6 NO-LIVE-CITATION** across
69 rows (2026-08-23). ⚠️ This said "over all four report sources … 62 PROVEN ·
1 NOT-EXERCISED", which was a LOCAL render; UC-B0.1 is the differing row and
only CI exercises it. Re-derive with `tools/acceptance_ledger.sh`. The full description is in
[acceptance.md section 14](acceptance.md#14-test-harness--implverify-mapping).
⚠️ `manifest.dart` is still where it was, and that still blocks the *in-pack
rails* idea — a different thing, wanting each pack to assert its own citations
— so the prerequisite stands for that reason and not for this one.

✅ **Arms 2 and 3 are BUILT (2026-08-24) — do not build them again.** Arm 2 is
`tests/at_functional_test/test/pq_posture_grid_test.dart` (**7** `test()` calls)
and arm 3 is `tests/at_functional_test/test/pq_advance_ladder_test.dart` (**1**,
phased). ⚠️ **This paragraph read "So what remains of this entry is arms 2 and
3, plus the clause level of the ledger"**, and before that "arms 2–4 … arms 3
and 4 need the EE at a named `at_server` ref". Both halves of the older claim
changed on 2026-08-24: **arm 4 is cancelled** by gkc (the hosted fleet will run
the version a release requires), and **neither arm 2 nor arm 3 needed the EE**
— the belief that a transition could not run in the VE generalised the matrix's
rule against re-minting in a *cell* to an advance, and 24 retrofits across five
live runs on one virtualenv refuted it. **So what remains of this entry is the
ledger's clause level alone.**

**The design was ruled with gkc on 2026-08-24 and is written up in
[acceptance.md section 14](acceptance.md#the-arms), with the provisioning in
[how the postures are provisioned](acceptance.md#how-the-postures-are-provisioned).**
Do not re-derive it from ruling 115, which is amended rather than rewritten.
In short:

1. **Arm 2 replaced the 4×4** with one in-process grid over sender posture ×
   receiver **readiness** — self and cross-atSign puts, gets and notifications,
   with per-cell expected outcomes, carrying the signed-envelope exchange
   (which stays posture × posture) too. ⚠️ This read "receiver posture" for
   both grids; the data-path axis became readiness on 2026-08-24, for the
   reason in [how the postures are
   provisioned](acceptance.md#how-the-postures-are-provisioned).
2. **Arm 3 is a separate ladder**, legacy → pqReady → pqActive on one
   enrollment, asserting the `.atKeys` shape per rung and re-reading
   pre-advance data. Both rungs evict `AtClientImpl.atClientInstanceMap`
   first.
3. **`tests/pq_matrix/` was cut to the released peer** — the scenario package,
   both programme arms and the `##PQM##` line protocol are gone, and
   `tests/at_functional_test/test/pq_released_peer_test.dart` keeps UC-G1.14
   proven. ⚠️ This read "`tests/pq_matrix/` **is deleted**", and the directory
   is still tracked: the released-peer test spawns
   `tests/pq_matrix/published/bin/read_apsk.dart`, which imports
   `published/lib/arm.dart`, so `published/` and `scenario/` survive and
   `current/` is what went. Re-derive with `git ls-files tests/pq_matrix`.
4. **Provisioning is 2 atSigns × 9 enrollments across 2 namespaces**, live
   proven 2026-08-24, each cell holding its own Hive store and its own
   `InMemoryAtKeysIo` — without the latter a minted nskey private is filed
   nowhere and every reader fails. ⚠️ This read "**7** enrollments across **5**
   namespaces", which was the design before the receiver axis became readiness.
   Re-derive from `cellSpec` in the arm: 4 sender postures + a second pqActive
   sender + 3 receiver postures + an unready receiver.

⚠️ **The grid discharges far less of the catalogue than "a structured suite over
the acceptance set" suggests, and that was measured rather than assumed.**
Classifying all 69 rows against these arms gives **0 fully covered, 32 partial,
34 reached by no arm, 2 out of scope, 1 needing a released peer**. The reason is
structural: the arms assert *outcomes*, while a large share of clauses assert
record shapes, orderings, negatives, and that an artefact signed earlier still
verifies. Nearly every unreached row is already proven live elsewhere. Treat the
grid as the legible core, not as a replacement for the packs.

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
than a coverage count. ⚠️ It also read "the matrix is still 3 `test()` calls
proving 2 use cases" — the rollout matrix was **deleted** on 2026-08-24 and its
two rows rehomed: UC-G1.15 onto `pq_posture_grid_test.dart`, UC-G1.14 onto
`pq_released_peer_test.dart`.

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

**G6. [RECOMMENDED] The train**, and it is the head of this list because its
next step is unblocked and nothing else's is. ⚠️ This read "Merge #2179 →
**gkc publishes at_lookup 3.7.0-rc1** → gkc publishes at_auth"; at_lookup
3.7.0-rc1 and at_server_status 1.1.2-rc1 were both published by 2026-08-24, so
that middle step is done.

**What to do, in order:** merge
[#2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179) — OPEN,
MERGEABLE, CI green on 2026-08-24 — then **gkc publishes at_auth 4.0.0-rc1**,
then carve at_client → at_client_flutter → at_onboarding_cli. ⚠️ **Before carving at_client, raise its `at_commons` floor**:
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
now **at_auth `4.0.0-rc1`, which is not on pub.dev**. ⚠️ This named at_lookup
`3.7.0-rc1` and said it was unpublished; it was published by 2026-08-24, and the
command below was reading `latest`, which never shows a prerelease. Re-derive
with
`curl -s https://pub.dev/api/packages/at_lookup | python3 -c "import sys,json;print([v['version'] for v in json.load(sys.stdin)['versions']][-5:])"`).
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

⛔ **CI HAS NOT COVERED THE CURRENT CODE, and this paragraph claimed it had.**
The last CI-verified commit is **`64480808d`** — runs **`32588333812`**
(at_client_sdk, 11/11) and **`32588342275`** (at_libraries, 13/13), both
`success`, measured 2026-08-22. Since then, re-derived 2026-08-24:

```bash
git rev-list --count 64480808d..HEAD                              # 53
git diff --name-only 64480808d..HEAD | grep -vc '^docs/'          # 108
```

⚠️ **This paragraph read "THE BRANCH IS GREEN, at the current tip … HEAD is 8
commits past it and `git diff --name-only 64480808d..HEAD` is entirely under
`docs/`, so this green still covers every line of code on the branch."** Both
figures were wrong when written, not merely overtaken: the acceptance-ledger
commits of 2026-08-23 had already touched `tool/acceptance_ledger.dart`,
`proven_elsewhere.dart`, `docs_structure_test.dart`, the three `runLocal.sh`
runners and 30-odd functional test files. The paragraph even carried its own
warning — *"Re-run the check below rather than extending that reasoning to the
next commit"* — and the reasoning was extended anyway, which is the failure it
was written to prevent. **Nothing fires on push on this branch** (the workflow
is `workflow_dispatch` only), so a dispatch is the only way to move this line.
⚠️ The per-suite counts below are from that 2026-08-22 run and several have
moved since — the functional pack is **186** locally as of 2026-08-23, not the
178 named here. CI's own per-suite counts matched the local ones **at that
commit** —
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
| **at_chops 3.6.1 — [PR #2181](https://github.com/atsign-foundation/at_client_sdk/pull/2181)** | ⛔ **Carved and OPEN, and it is NOT in the train's ordering above** — it was cut on 2026-08-24 from trunk, not from the spike, because at_chops 3.6.0 is already published and had no in-progress CHANGELOG heading to fold into. Message-only change: `PkamMlDsa65SigningAlgo.sign` reported a bare `ML-DSA-65 secret key must be 4032 bytes: N`, which names neither the credential nor the likeliest cause. A PKAM key of ~1.2 kB is an RSA-2048 private key, which a caller holds by naming one enrollment's algorithm while carrying another's credentials. Owed: merge, then gkc publishes 3.6.1. ⚠️ **Nothing depends on it** — no floor in this tree requires 3.6.1, so it can land whenever; but it is a second at_chops publish the train's ordering does not mention | Nothing. It is independent of at_auth and of the spike |
| arm 2's flake rate is not re-bounded | ⚠️ `pq_posture_grid_test.dart` was **4 of 5** green before 2026-08-24's fix — three isolated runs and one full pack green, one full pack red on two cells. Both causes were the test's, not the product's: the envelope test re-read a record sealed to the receiver's namespace key once per receiver, dragging the nskey **conveyance race** into a claim about verifiers; and the notification cell asserted delivery absolutely against a monitor that drops at a measurable rate (14.34's family). Both are fixed — the envelope reads once by the holder and every posture's verifier runs against those bytes, and the notification re-sends once so a drop is absorbed while two independent drops still fail. **But there has been exactly ONE full-pack run since (178/178), so the new rate is 1 of 1.** Owed: run the functional pack a few more times and record the rate, or accept it as unbounded and say so | Nothing. `cd tests/at_functional_test && VIRTUALENV_IMAGE=at_virtual_env:local ./runLocal.sh` |
| spike CI result unseen | ⚠️ Both workflows were dispatched against `gkc-pq-d1-spike` on 2026-08-24 (`gh workflow run at_client_sdk.yaml --ref gkc-pq-d1-spike`, same for `at_libraries.yaml`) and **the result was never read** — the session ended first. It is the first CI over arms 1–3, the deleted rollout matrix, the released-peer test and the enrolment fix; everything before that was local only. ⚠️ **A red there may be the IMAGE, not the code**: CI's functional job uses `atsigncompany/virtualenv:dev_env` while every local run used `at_virtual_env:local`, and they differ in whether they can verify an ML-DSA PKAM signature — which is exactly what arm 2's pqActive cells, arm 3's rungs and `pq_native_app_enrollment_test.dart` rest on. Check the image before the code | Nothing. `gh run list --branch gkc-pq-d1-spike --limit 4` |
| ~~app enrollments cannot be PQ-native~~ **FIXED 2026-08-24** | ✅ **DONE — do not rebuild it.** `AtEnrollmentRequest` now **requires** `signingAlgo` on both constructors (no default, so the compiler enumerated all 22 call sites across 6 packages), and also forwards `advertisedSigningKey`, which the base class declared and neither constructor passed on. `mintApkamKeyPair` is shared with onboarding so the two cannot drift. A non-rsa2048 enrolment files typed material under the enrollment id once the atServer names it — the flat copy STAYS, because one enrollment named by the keyfile's own `enrollmentId` resolves the same either way, and clearing it breaks the approval handshake, which needs the keypair and the symmetric key from one `toAtChops`. ⚠️ **Three things the API change alone did not fix, each found by a failing run rather than by reading:** `enroll` did not forward `signingAlgo` to `sendEnrollRequest`, so the parameter would have existed and done nothing; `enrollmentKeyPackageBuilder` was never told the algorithm, though it has always taken one; and the approval handshake never set `signingAlgoType`, so an ML-DSA enrolment PKAM'd under at_lookup's rsa2048 default. **Proven at two layers**: `tests/at_functional_test/test/pq_native_app_enrollment_test.dart` (an mldsa65 enrolment keeps its id, an rsa2048 one still retrofits — the control) and `tests/at_onboarding_cli_functional_tests/test/pq_native_enroll_test.dart` against a real VE, where the assertion that matters is that the enrolment **authenticates**: PKAM is record-authoritative, so a client holding ML-DSA material can only authenticate if the atServer's record says ML-DSA. ⛔ **What is NOT covered, and is separate**: every other atServer implementation would record an ML-DSA enrollment and then never authenticate it. That gap is pre-existing, independent of this fix, and lives on an unmerged branch | Nothing. `--posture` now reaches the enrolment in `at_activate enroll`, defaulted once at the `enroll`/`sendEnrollRequest` boundary where a caller has no rollout position to read |
| doc-set reduction, phases 3–5 | ⛔ **RULED BY gkc 2026-08-23, AFTER D1 — do not start it while D1 is open.** The end state is five files: `roadmap.md` (stale, needs a pass), `design.md`, `acceptance.md`, `decisions.md` (seriously shrunk) and this plan, which from now records **only what is still owed**. Phases 1 and 2 landed 2026-08-23 — the rejections and measurements became [rulings 116 and 117](decisions.md), and this plan went 1,878 → 1,075 lines. **What remains, and phase 3 MUST precede phase 4:** (3) trim the **117** ruling bodies in `detail/decisions.md` and inline them into `decisions.md` — they average **98 lines each**, and only **4 of 116** rulings are dead, so this is an editorial pass over live content rather than a purge of obsolete ones; (4) delete `detail/` and repoint or remove the **250** links into it (113 from this file, 63 acceptance, 62 design, 9 roadmap, 2 decisions, 1 seal-spec), rewriting `docs_structure_test.dart`, which enforces index↔body correspondence both ways and names `detail` 28 times — the rail changes in the SAME commit or CI goes red; (5) substitute explanations for the code that cites `detail/` paths, which is a standing rule violation as well as a broken link: ⚠️ **this item shrank on 2026-08-24** — it named `pq_rollout_matrix_test.dart` and a dartdoc in `tests/pq_matrix/current/lib/envelope_exchange.dart`, and both files are now deleted along with the rollout matrix. The README was rewritten in the same change and cites `detail/` no longer, so **item (5) is discharged**. Measured 2026-08-24: only two code files still name `detail/`, and neither is item (5)'s — `cross_cutting_test.dart` reads `detail/decisions.md` as a build input and this row already exempts it, and `docs_structure_test.dart` is the rail item (4) rewrites. Re-derive before acting: `git grep --untracked -n 'detail/' -- tests packages | grep -v '\.md:'`. `cross_cutting_test.dart` reads `detail/decisions.md` as a build input and is fine. ⚠️ **Phase 3 is where this goes wrong silently** — a ruling trimmed too far reads complete, and 112 of 116 rulings are still in force. Re-derive the size: `for f in docs/projects/pq/*.md docs/projects/pq/detail/*.md; do echo "$(grep -c '' $f) $f"; done` | Nothing but D1 closing. `detail/` is **19,141 lines against 7,231 live**, so this is most of the reduction |
| arm 1 vs arm 3 bucketing | ⛔ **A RULING IS OWED FROM gkc, and it is not a research task** — the measuring is done. [`acceptance.md`'s "Which rows arm 1 owes"](acceptance.md#which-rows-arm-1-owes) has both readings and the evidence; nothing here repeats them. In short: section 14's kind table says **3** transition rows, its arm-3 paragraph names **12**, and four rows — UC-B1.1, UC-B1.2, UC-B4.4, UC-A5.3 — are assigned to arm 1 and arm 3 at once, so the published "21 axis and consequence rows" double-counts. The two readings differ in what arm 1 *is*: under the count an arm-1 cell must drive a retrofit, so the arm stops being three static clients; under the prose a retrofit is an edge and belongs to arm 3. **Arm 1 as built sidesteps it** by covering only the 14 rows both derivations agree on, so nothing is blocked — but arm 3 cannot be scoped until this is settled, and the count table stays wrong until then | Nothing but the ruling. Arm 3 is the work it unblocks — arm 4 was cancelled 2026-08-24 |
| at_auth README | ⛔ **NOT a D1 gate, but it should ride [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179) with G1** — `packages/at_auth/README.md` describes `FileAtKeysIo` at `:144` and `:191` and **never mentions `at_auth_io.dart`**. The barrel split is the single most consumer-visible change in 4.0.0 — a `dart:io` consumer has to add one import — and the CHANGELOG says so at length while the README says nothing. No code miscompiles from it (the README shows no import statements at all), which is why it is not a gate. Found by the wrap-up docs sweep 2026-08-23 | Nothing. One or two sentences where `FileAtKeysIo` is first named |
| **acceptance audit** | ⛔ **D1 GATE — the gap is established and the design is ruled ([115](detail/decisions.md#115-the-acceptance-suite-is-4-arms-and-a-ledger-not-one-grid-2026-08-23)); what remains is the build** (gkc, 2026-08-23). **The rationale, in gkc's words:** *"we have literally hundreds of functional and end to end tests which cover the acceptance tests together. But there is no definitive place where it is easy to see the entirety of the pq project's acceptance tests being proven. The posture matrix test is the logical place to build test out."* So the problem is **legibility, not coverage**. Measured 2026-08-23, and **coverage was never the gap**: of the 68 live rows, 59 have live proof of some kind and 9 have none (12 LIVE_DIRECT, 43 LIVE_PARTIAL, 4 LIVE_INCIDENTAL, 9 NO_LIVE_PROOF). Only **29 of the 69** use-case ids are nameable anywhere in the live suite. ⚠️ **`tests/` holds 7 Dart packages** — the 4 live test packs plus `tests/pq_matrix/{current,published,scenario}`, the child processes the pair grid spawns. Count with `find tests -name pubspec.yaml`; a `tests/*/` glob returns 4 and reads as the whole answer. ⚠️ **The live corpus is 4 packs, not 2, and this row was scoped to 2 of them** — it read "**180** live test declarations across 65 files … a looser `grep -o 'test('` gives 225 and an indentation-anchored one 224". `tests/at_onboarding_cli_functional_tests` and `tests/at_onboarding_cli_functional_tests_proxy` are live packs as well, no citation reaches either, and the CLI one builds clients from a `PqPosture` in two arms — which makes it the best live evidence for UC-C1.6 and a second live proof of UC-A1.1. Across all 4 the strict matcher gives **194** and a multi-line-aware one **247**, and that gap is entirely declarations whose name sits on the next line, since an any-position same-line matcher also returns 194: `grep -rhoE "^[[:space:]]*test\([[:space:]]*'" tests/ --include='*.dart' | wc -l` against `perl -0777 -ne 'while (/(?<![A-Za-z0-9_])test\(\s*[\x27"]/gs){$n++} END{print "$n\n"}' $(find tests -name '*.dart')`. The posture matrix, the intended home, is **3** `test()` calls proving **2** use cases (UC-G1.14, UC-G1.15). ⚠️ **A citation count is not a coverage count** — an earlier pass here reported "27 of 68 have no live proof" when what it had measured was 27 with no live proof *cited from their acceptance scenario*. Do not restate it as coverage. For the record, the citation picture: of 68 scenarios, 2 cite the matrix, 39 cite some live test, 22 cite unit tests only, and 5 cite nothing and are themselves mock tests (UC-A3.1, UC-A3.4, UC-B3.1, UC-B3.2, UC-B5.2; UC-A3.1 runs against `MockAtClient()`). ⚠️ **And nothing checks the claims.** `catalogue_test.dart`'s five tests are all structural; none asks whether a scenario proves what its row asserts, and the `proves:` prose is matched against nothing ([14.19 item 29](detail/implementation-plan.md#1419-small-items-raised-2026-08-12-and-not-yet-acted-on)). The one known overclaim, item 36's three clauses of UC-A2.5/UC-A2.6, was found by hand. **Steps (1) and (2) are DISCHARGED, 2026-08-23** — they read "(1) for each of the 68, find where it is *actually* exercised live — searching the packs, not just reading citations; (2) decide which are genuinely **posture-dependent**, since several of A3's self-data cases may not vary by posture at all". Both are answered in [ruling 115](detail/decisions.md#115-the-acceptance-suite-is-4-arms-and-a-ledger-not-one-grid-2026-08-23), which carries the per-row map and the posture classification. gkc's A3 suspicion held: `PqPosture` declares 9 axes and only 6 vary across the stages, so 3 of the 5 A3 rows do not vary at all. **What is owed is step (3), and the shape is ruled rather than open**: only **3** of the 68 rows are shaped like a grid cell and **38** do not vary by posture, so the target is **4 arms and a generated ledger** — a 3-cell stage arm, the existing 4×4 pair grid, a transition arm for the edges the catalogue is full of, and a server-version arm — with 4 prerequisites named in the ruling, **2 of them now discharged**. ✅ This row said the sharpest was that "this pack has no `dart_test.yaml` and no `pq` tag (0 hits, against 9 in the e2e pack)" — built 2026-08-23: the tag is declared and 29 of its 49 test files carry it, chosen by the mechanisms they drive rather than their names, and `test/pq_tag_test.dart` re-derives the set so a new PQ test cannot sit outside it. ⛔ No `paths:` allowlist, deliberately — this pack's virtualenv is thrown away per run, so allowlisting would take the e2e pack's silent-omission risk with none of its benefit. ⚠️ **A fifth prerequisite was listed here and is now measured away**: this row said `PqPosture.pqActive` "currently breaks the monitor (`nskey_self_notify_live_test.dart:289`)". It does not. Equal-length interleaved arms across 2 fresh virtualenvs gave pqActive **16 of 18** monitors received against a control's **18 of 20**, with the atServer's log carrying `signingAlgo:mldsa65` authentications — both arms fail at the same rate with `AT0014`, so the failure is real but is **not posture-dependent**, and a pqActive cell is no worse off than a legacy one. ✅ **The ledger half of step (3) is BUILT, 2026-08-23** — `tool/acceptance_ledger.dart` plus the recording in `provenIn` and report emission in all three `runLocal.sh` runners; rendered from a real CI run's artefacts across both workflows the catalogue reads **63 PROVEN · 0 NOT-EXERCISED · 6 NO-LIVE-CITATION** across 69 rows (2026-08-23). ⚠️ This said “over all four report sources … **62 PROVEN · 1 NOT-EXERCISED** … the one gap being UC-B0.1's tagged legacy-server job”, which was a LOCAL render — UC-B0.1 is exactly the row a local run cannot reach and CI can, so the gap was in the runs supplied rather than in the coverage. ⛔ **It did NOT need `manifest.dart` moved**, which this row and ruling 115 both listed as its prerequisite. ✅ **Arm 1 is BUILT (2026-08-23)** — `tests/at_functional_test/test/pq_stage_arm_test.dart`, three enrollments of one atSign at one posture each, functional pack **186/186**, and **UC-C1.2 executed live for the first time**. It covers the 14 rows both derivations of the arm-1 set agree on rather than the contested 21 (see the `arm 1 vs arm 3 bucketing` row above), and it does **not** measure UC-C1.4, since `enrolAndAuthenticate` builds pq-mode enrollments only and every cell therefore holds `keyExchangeMode` constant. ✅ **Arms 2 and 3 are BUILT (2026-08-24)** — `tests/at_functional_test/test/pq_posture_grid_test.dart` is the grid (sender posture × receiver readiness, 9 enrollments over 2 atSigns, 7 `test()` calls) and `tests/at_functional_test/test/pq_advance_ladder_test.dart` is the ladder; `tests/pq_matrix/` was cut to `published/` and `scenario/`, which `tests/at_functional_test/test/pq_released_peer_test.dart` spawns to keep UC-G1.14 proven. **What step (3) still owes:** this clause read "**arms 2 and 3**", and before that "arms 2–4" until gkc cancelled arm 4 on 2026-08-24; the design of arms 2 and 3 was ruled the same day ([acceptance.md section 14](acceptance.md#the-arms)). What is left is **the clause level** of the ledger, which is the half that does touch the live tests and is what turns "UC-A2.5 has 3 unproven clauses" into a computed fact rather than a footnote; and **the CI combining job**, left unwired because it needs `actions/download-artifact` and neither this repo nor at_server carries a trusted pin for it — CI uploads the inputs and rendering is local, which is now one command (`tools/acceptance_ledger.sh`) rather than the four hand-assembled ones this row's "rendered on demand" implied. ✅ **Two further gaps gkc named on 2026-08-23, both now BUILT.** They were: (a) nothing in the tree invoked the renderer — `git grep -P "dart\s+run\s+\S*acceptance_ledger"` returned exactly one hit, the usage comment inside the tool itself, so every ledger so far was assembled by hand from a scratch directory; and (b) nothing guarded the population wiring, with **0** tests reading `.github/workflows/` (positive control: the path string appears in 5 non-test files) and none reading the three `runLocal.sh`. What landed: **`tools/acceptance_ledger.sh`**, one command that runs the unit sources, optionally the live packs (`--with-live`), and renders; and **`packages/at_client/test/acceptance_ledger_wiring_test.dart`**, which asserts each of the four emitting jobs still carries its flag, that `unit_at_client` still sets `ACCEPTANCE_LEDGER`, that every emitter uploads with `always()`, and that each runner still gates the reporter on `ACCEPTANCE_REPORT`. ⚠️ **The rail's first version had a hole worth recording**: it asserted `contains('ACCEPTANCE_REPORT')` and `contains('--file-reporter json:')` separately, and a mutation making the guard read a *different* variable left both satisfied — the variable is named three times in each runner, so severing the coupling changed no substring. It now pins the coupling itself (`-n "${ACCEPTANCE_REPORT:-}"` and `--file-reporter json:${ACCEPTANCE_REPORT}`), which is the same weakness this section already records in `provenIn`, reproduced one layer up. Six mutations, each reddening its own assertion. ⚠️ **`provenIn` APPENDS to its citations file**, so two runs against one path double every citation and the ledger reports 278 for a catalogue of 139 — the driver deletes it rather than trusting the caller. **Re-derive**: `grep -rho 'UC-[ABCG][0-9]*\.[0-9]*[a-z]*' tests/at_functional_test/test tests/at_end2end_test/test | sort -u | wc -l` against the 69 in `acceptance.md` | Nothing |
| [14.43](detail/implementation-plan.md#1443-the-functional-suites-convergence-race) residue | ⛔ **NOT D1, and NOT PQ (gkc, 2026-08-23)** — recorded here only because this project has no other checked-in owed-work list. The behaviour is in `sync_service_impl.dart`, i.e. at_client's general sync, and no use case asserts sync ordering. The test-side fix landed in `ccf4987a4`. **A sync pull applies an OLDER server entry over NEWER local state** — the pull-side face of the versioning shape C fixed on the push side. Recorded when 14.43 closed and not designed since. Also open from that section: a driver-side `expect` failure on a protocol-green cell still dumps nothing | Nothing. The section carries the discriminators for any future red of the family |
| [14.45](detail/implementation-plan.md#1445-an-expired-key-the-client-cannot-delete-pins-it-in-a-hot-loop) residue | ⚠️ **In another repo: `at_persistence_secondary_server`.** Its keystore `get()` does not filter expired records, which is what let an expired key be read back and re-swept. Named here because this is where the work that found it lives; it does not land here | Separately owned. Not a D1 gate |
| [14.50](#1450-the-e2e-teardown-revokes-enrollments-belonging-to-other-runs) | ⛔ **NOT a D1 gate (gkc, 2026-08-23)** — e2e runs isolate locally and are serialized by structure on GitHub. ⚠️ Recorded because a reader will re-derive it: there is no top-level `concurrency:` key in any workflow, so `needs:` serializes the e2e jobs *within* a run and not across runs, and the incident that produced this row was cross-run. Stays as unblocked hygiene. **The e2e teardown revokes enrollments belonging to other runs.** `tests/at_end2end_test/test/enrollment_teardown.dart` revokes every approved enrollment on the shared `@ce2e1`-`@ce2e4` atSigns with `force: true`, not only the ones its own run created, so two overlapping CI runs tear down each other. **Diagnosed 2026-08-22** from the *other* run's log - the section carries the two timestamps 430 ms apart and the shared enrollment id. This row read *undiagnosed, and the newest CI run is red* until then. CI has since been green three times — 24/24 twice and 47/47 on [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179) — but every one of those windows was free of another run, so that is a rate and not a fix. Owed: a run-unique marker, so a teardown revokes only what its own run made | Nothing. Needs no permission and no publish, and it does not gate the at_auth carve |
| [14.18](#1418-the-remaining-d1-initial-development-sequence) | ⛔ **THIS IS D1's CRITICAL PATH** — D1 ends when the acceptance set passes and every rail is green, and the remaining carves and publishes are what gets there. Steps 32–34: the per-package release train. **Five of eight positions are through.** at_commons #2168, at_chops #2169, at_lookup #2174 and at_server_status #2177/#2178 are all **merged to trunk**; at_auth is [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179), **open with CI 47/47 green**. Remaining to carve: **at_client, at_client_flutter, at_onboarding_cli**. Re-derive the whole picture rather than reading this cell — for each package compare `pubspec.yaml` on trunk, on this branch, and `curl -s https://pub.dev/api/packages/<pkg> \| python3 -c "import sys,json;print([v['version'] for v in json.load(sys.stdin)['versions']][-5:])"`. ⚠️ **Measured 2026-08-22 with a command that could not see a prerelease**, and it read "pub.dev has … at_lookup **3.6.1**, at_server_status **1.1.1**". Re-measured 2026-08-24 against the versions list: pub.dev has at_commons 5.16.0, at_chops 3.6.0, **at_lookup 3.7.0-rc1**, **at_server_status 1.1.2-rc1**, at_auth 3.3.0, at_client 3.14.0 | ⚠️ **Merged is not published, and only the publishes still gate anything.** ⚠️ This said at_lookup 3.7.0-rc1 and at_server_status 1.1.2-rc1 were "on trunk and **not on pub.dev**"; both were published by 2026-08-24, so the live gate is now **at_auth 4.0.0-rc1**. Every later package can carve and merge but none can publish until gkc publishes those. ⛔ **This cell used to say the at_auth PR's CI would fail to resolve until at_lookup published. That was wrong** — a pub workspace resolves siblings by path, so #2179 resolved and went green with at_lookup unpublished; the gate is on publishing, never on carving or merging. ⚠️ **at_client's `at_commons: ^5.15.0` floor is too low and will ship broken** — `notify_request_transformer.dart:154` calls `metadata.copy()`, which first exists in at_commons **5.16.0**. The same defect was found and fixed in at_auth during its carve; check every floor against first-use before carving at_client. ⚠️ **Owed at the real release, and it belongs to this row because it is the train's:** every constraint moved to an `-rc1` floor reverts to its stable form when these publish, or a stable release ships requiring a candidate. The rule is in [14.49.2](detail/implementation-plan.md#14492-every-remaining-package-publishes-as-a-release-candidate); re-derive the sites — `git grep -n 'rc1' -- 'packages/*/pubspec.yaml' 'tests/*/pubspec.yaml'` |
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

**Public-data signature verification — POST-D1, undesigned, and deliberately
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


### 14.34 An unexplained intermittent in `self_enrollment_retrofit_live_test.dart`

### 14.34 An unexplained intermittent in
`self_enrollment_retrofit_live_test.dart`

⛔ **D1 GATE (gkc, 2026-08-23).** D1 ends when every rail is green, and an
unexplained live-pack failure makes "green" a rate rather than a state.

`tests/at_functional_test/test/self_enrollment_retrofit_live_test.dart` times
out after 40 s at `await firstNotification` (the `.timeout(const
Duration(seconds: 40))` at line 261, awaited at line 290) during a full
functional pack run, and passes when the file runs alone. Seen **1 of 5** pack
runs on 2026-08-17 and **1 of 2** on 2026-08-19 at `327cf4fa2`; the retrofit
sequencing landed between those trees, so the two rates must not be pooled. It
is not a flake and not fixed — record any further occurrence with its
numerator, denominator and tree rather than re-classifying it.

**What the 2026-08-19 occurrence established: the notification WAS
delivered.** The client log carries exactly one `Received
@alice🛠:rf2cmon-57335863.buzz@alice🛠`, on a monitor whose PKAM went out as
`signingAlgo:rsa2048`. Two clients had monitors listening — the legacy owner
and the retrofitted ML-DSA one — and the test awaits the latter. So the open
question is **which monitor the atServer considered a subscriber**, a fact
with no near-side representation at all.

**Already ruled out** (see `decisions.md`): posture and signing algorithm are
not the variable, and the failure is reachable without a retrofit.

⚠️ **`runLocal.sh` ends with `docker compose down`, so a run chasing this must
copy the atServer log out first**: `docker cp test-virtualenv-1:/apps/logs
<dir>`.

**If it recurs,** the bisect point is `0668cf91d` — code there is the
local-key fix without the `_apsk` write serialisation, so green at that commit
pins it on the serialisation.

⚠️ **Probably the same phenomenon as
[14.43](detail/implementation-plan.md#1443-the-functional-suites-convergence-race)**
— both are functional-pack convergence waits, both pass when the file runs
alone — but nobody has shown one cause covers both. If 14.43 is worked, work
this row with it.

⚠️ **Also owed, and nearly lost in the 2026-08-23 cut:** The triage owes one
sentence ("diagnose the intermittent") and calls ~28 of 70 lines archaeology,
but two of those lines are the METHOD for the owed diagnosis, not a record of
it. (a) The instruction to copy the atServer log out before `runLocal.sh`
tears the container down — the section says outright that the one occurrence
with evidence had its far-side log destroyed, and the whole investigation now
turns on a fact that exists only in that log. (b) The bisect point and why it
discriminates. Neither is in any commit; both are reasoning about what to do
next.

⚠️ **Also owed, and nearly lost in the 2026-08-23 cut:** The instruction
attached to the owed diagnosis — that this is very probably 14.43's phenomenon
and should be worked with it, and is explicitly not asserted as identical. It
matters more than it reads, because 14.43 has since been FIXED and
re-measured, which 14.34 does not say: whoever picks up this owed D1 gate
should re-measure the rate before diagnosing anything. If the owed rewrite
becomes "diagnose the 40 s timeout", that pointer goes and the work restarts
from the 2026-08-17 framing.


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
at_client_flutter → at_onboarding_cli. Live state is [`G6`](#the-next-move);
the publish order is [detail — what still has to be published, in
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
five errors for six days. The dispatch and comparison commands are in [`## THE
NEXT MOVE`](#the-next-move).

Each carve merges to trunk on its own. ⛔ **The spike branch itself never
merges** — it is carved from, never landed.

Step 20's rotation arm is owed and is ranked as [`G7`](#the-next-move); do not
restate it here. ⚠️ 14.18's version of its blocker was stale — the
fleet-adoption wait is closed and the matrix now builds its own enrollments
through `enrolStage`, so "the matrix's demo atSigns hold no enrollment" is no
longer the reason it needs its own atSign.

Step 30's owed half is ranked as [`G4`](#the-next-move) and detailed in
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
⛔ **Item 36 IS a D1 gate** — it is `G5` in [THE NEXT MOVE](#the-next-move),
the one known case of the catalogue asserting clauses no live row proves. This
section used to say "none blocks anything"; that stopped being true when item
36 was raised.

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
71 `deprecated_member_use` sites — `enrollmentId` 59, `signingAlgoType` 12;
**24 in `lib/`, 47 in tests**, across `at_client`, `at_onboarding_cli` and
`at_auth` — move onto the `AtAuthenticator` seam. The replacement is
`authenticatorForChops()`
(`packages/at_auth/lib/src/auth/at_authenticator.dart:91`, exported from
`at_auth`); the migration pattern is already in the tree at
`packages/at_client/lib/src/client/remote_secondary.dart:94` and
`packages/at_client/lib/src/service/notification_service_impl.dart:271`.
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
run-unique marker already exists: `enrollment_setup.dart:109` submits with
`appName: 'wavi-$random'` (`random = Uuid().v4().hashCode`, line 100) and
`Enrollment` exposes `appName`
(`packages/at_client/lib/src/response/enrollment.dart`). What is missing is
agreement between the two steps — setup and teardown are separate `dart test`
invocations (`.github/workflows/at_client_sdk.yaml:324` and `:340`) sharing no
state — so derive the marker from something both can read (`GITHUB_RUN_ID` is
the obvious candidate) and filter both loops on it. ⚠️ Green CI runs are not
evidence this is fixed: every green window since the diagnosis had no other
run in flight, so the mechanism had no opportunity to fire — it is a rate, not
a kind.

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
| R-2   | at_client 4.0.0 posture defaults                     | After D1, and now after 14.39. **The default `PqPosture` becomes `pqActive`** ([ruling 113](detail/decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18)) — one value, replacing the two coupled edits it used to be. Still a pure default-flip carrying no code of its own. Issue #2016 |
| D2-1  | Carve `at/pqmls` + D1-E shape fixes                  | D2, out of D1 |

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
# ALL THREE runLocal.sh default VIRTUALENV_IMAGE to `at_virtual_env:local`, so a
# bare run is the PQ-capable arm — the var only has to be set by hand when
# driving `dart test` directly. ⚠️ This said "Both", and there are three:
# `find tests -name runLocal.sh`. The third is the CLI pack's, added
# 2026-08-19, and it defaulted to the published `vip` — which cannot verify
# ML-DSA PKAM — until 2026-08-23.
# ⚠️ The two live figures moved for reasons worth knowing rather than growth:
# functional 169 → 174 (the matrix's cells, once its driver stopped asking the
# arms for stage names that no longer exist), and both packs were RED at
# `c9de7d997` while every unit suite was green — analyze cannot see a string
# argument, so nothing caught it until the pack ran.
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
