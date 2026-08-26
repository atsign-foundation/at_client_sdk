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
| **P0** | urgent — on D1's critical path and startable now |
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
all-or-nothing verdict.** ⚠️ The denominator has moved since — the corpus is
**153** as of the same day's later work — so treat the 13 as a floor and
re-derive both with the command in
[Re-deriving the state](#re-deriving-the-state). That is legal by design — `provenIn`'s own dartdoc
says omitting it is not a failure, and the ledger reports such a row as having
unpinned clauses rather than pretending they are covered — but it means the
clause level is a *facility* that is 9% adopted, not a property the catalogue
has. Re-derive, never quote:

```bash
cd packages/at_client && rm -f /tmp/cit.jsonl &&   ACCEPTANCE_LEDGER=/tmp/cit.jsonl dart test test/acceptance --concurrency=1 >/dev/null
# ⛔ rm first — provenIn APPENDS, and a stale file reads as ~2x the citations
python3 -c "import json;r=[json.loads(l) for l in open('/tmp/cit.jsonl')];print(len(r),'citations,',sum(1 for x in r if not x.get('clauses')),'unpinned')"
```

And what no rail checks at all is whether the cited test really *establishes*
the clause; that judgement is the citation's, written in `proves:`. Reading
those is the [acceptance audit](#the-acceptance-audit), which is finished —
the reading it describes was done on 2026-08-26 and what it found is
[a row of its own](#what-the-citation-audit-left-owed).

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
beneath [ruling 114](detail/decisions.md#114-a-signer-waits-for-its-own-mint-the-mint-alone-does-not-2026-08-21)
(durable pre-mint auth-fallback envelopes, and the verifier's pre-mint cache
asymmetry). Each needed a PQ-material holder to exist, and none does.

⚠️ **It is a statement about today, not a licence.** The moment a released build
starts writing PQ material, every one of those questions becomes reachable and
has to be re-asked rather than re-cited from here.

⚠️ **A second workstream is open and is NOT in the list below** — the knowledge
base, agreed with gkc 2026-08-20. Its plan, format, rail design and ordered
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

⚠️ **A row leaves this table when it is done — it does not gain a ✅.** There is
nowhere to move it to: what was done is in `git log`. A rail enforces the
direction (`packages/at_client/test/acceptance/docs_structure_test.dart`, "no
TODO row names a section whose body declares itself done").

### P0 — on D1's critical path, and startable now

| Item | What is owed | Blocked on |
| ---- | ------------ | ---------- |
| [a client that exits during its startup tail abandons seeding](#a-client-that-exits-during-its-startup-tail-abandons-seeding) | **Reproduce it in this tree, then fix it.** A short-lived client at a seeding posture takes the mint interlock and dies before publishing, so the atSign has no namespace key and no peer can seal to it — it sends post-quantum and cannot receive. Confirmed live in both directions on 2026-08-26. ⛔ **Nothing tells the caller**, and the only symptom is at the FAR end, where a different atSign reports the wrong party as unseeded | Nothing. Three in-tree reproduction attempts failed; the row says how |
| [14.18](#1418-the-remaining-d1-initial-development-sequence) **the release train** | **gkc publishes at_auth 4.0.0-rc1**, then carve at_client (stacked) → at_client_flutter → at_onboarding_cli. Six of the eight positions are through by merge; what is left is publishes | gkc. ⚠️ **Merged is not published, and only the publishes gate anything now** |
| **at_chops 3.6.1** | **Publish it.** [PR #2181](https://github.com/atsign-foundation/at_client_sdk/pull/2181) merged to trunk on 2026-08-24 and pub.dev still tops out at `3.6.0`. Independent of at_auth and of the spike | gkc |

### P1 — must do before D1 closes

| Item | What is owed | Blocked on |
| ---- | ------------ | ---------- |
| [what the citation audit left owed](#what-the-citation-audit-left-owed) | **Five open findings.** F16 is the one that matters: the nskey mint lock's live refusal is proven for `_rootlock` and only modelled by a mock for `_nskeylock`, which is the same measurement the seeding P0 is missing, so one live test discharges both. F15 and F8 are unasserted clauses; F1 and F3 are ledger-precision work. ⚠️ **F11, F12 and F18 closed 2026-08-26** — the `enroll:update` refusals are now asserted by the atServer's own messages, and UC-G1.12 turned out to be green for a refusal that was not the guard it names | Nothing |
| [14.11](#1411-deprecated_member_use-findings-across-the-workspace) **bucket B** | Migrate the **88** credential-ladder uses (`enrollmentId` 75, `signingAlgoType` 13) onto the `AtAuthenticator` seam. 26 in `lib/`, 62 in `test/`, across at_client, at_onboarding_cli, at_client_flutter and at_auth. It is what "that package's own work is done" means in [14.18](#1418-the-remaining-d1-initial-development-sequence), so it gates the carves | Nothing |
| **advertisement fetch volume, ttr and client caching** | Three questions, one subject, raised by gkc 2026-08-26 after a wire capture showed **110 `_apsk` lookups in a single short client run** — more than either control atSign made. (1) Why are there so many? Establish what re-fetches, and whether anything is re-reading per operation what it could hold. (2) Should an advertisement carry a `ttr`, and if so how long — it is a public record that peers must not read stale after a rotation, and rotation is the revocation lever. (3) How should a client cache advertisements it has fetched, and for how long? ⛔ **These interact**: a client-side cache with no server-side `ttr` is a rotation that does not take effect, and a `ttr` shorter than a session is the fetch volume in (1) by design | Nothing. It needs a measurement, then a ruling |
| [the at_client carve stack](#the-at_client-carve-stack) | Get the nine-layer stack plan into git, and make the **five decisions** it cannot make for itself. A file in no layer never lands | Whoever cuts the stack |
| [arm 1 vs arm 3 bucketing](#arm-1-vs-arm-3-bucketing) | **A ruling from gkc** — the measuring is done. Arm 3 cannot be scoped and the catalogue's count table stays wrong until it is settled | gkc's ruling. Nothing else |
| [a wildcard enrolment seeds nothing](#a-wildcard-enrolment-seeds-nothing) | **A ruling from gkc** on whether an atSign reachable only through a wildcard (`*`) enrolment is expected to publish namespace keys. Today it publishes none, so nobody can seal to it in any namespace, and the doc comment that said otherwise was false | gkc's ruling. The measuring is done |
| [content keys per scope](#content-keys-per-scope) | **A ruling from gkc** on whether one content key per writing enrollment per scope is the intent. If not: `CurrentCkPointer` needs a remote-first write through an atomic verb, and rotation needs to supersede every CK in scope | gkc's ruling, then the fix |
| [the late-arriving nskey private](#the-late-arriving-nskey-private) | File a late-arriving nskey private **only for a generation this client actually asked for**. The reverted attempt filed any arrival, which breached the seeding guarantee | Nothing |
| [14.18](#1418-the-remaining-d1-initial-development-sequence) **step 20's rotation arm** | Add the `pending` enrollment status value and build the rotation arm against its own dedicated CRAM atSign. ⛔ There is **no** fleet-adoption wait — see the standing premise | The at_auth publish, and a dedicated CRAM atSign |
| **CI at head** | Dispatch both workflows at head and read them. "Every rail green" is half of D1's definition, and **nothing fires on push on this branch** — the workflows are `workflow_dispatch` plus `push`/`pull_request` on `trunk` only, so the newest run is only ever as new as the last manual dispatch. ⚠️ **Dispatch matters beyond staleness**: CI's at_client job runs a **bare** `dart analyze` that reads `benchmark/`, which the routine `dart analyze lib test` never opens — that hid five errors for six days. ⛔ **And docs are build inputs here**, so a plan edit alone can redden the acceptance rail. Re-derive, never quote:<br>`gh run list --branch gkc-pq-d1-spike --limit 4 --json headSha,conclusion,workflowName --jq '.[] \| [.headSha[0:9], .workflowName, .conclusion] \| @tsv'`<br>`gh workflow run at_client_sdk.yaml --ref gkc-pq-d1-spike` | A head worth dispatching |

### P2 — should be done if there is time

| Item | What is owed | Blocked on |
| ---- | ------------ | ---------- |
| **`notificationStatusEnum` is not an outcome, and its name says it is** | **A dartdoc fix, not a behaviour change** — raised by the at_talk demo session 2026-08-26 and routed here by gkc, because every app author meets it and only one of them is that session. `NotificationResult.notificationStatusEnum` initialises to `undelivered`. With `checkForFinalDeliveryStatus: true`, which is the **default**, `_waitForAndHandleFinalNotificationSendStatus` polls and sets it from the atServer, so it means what it says. Pass **`false`** and that method returns early: the field is never assigned on the success path, so an accepted send, a refused send and a failed send all read `undelivered`. The only signal left is `atClientException == null`, which no field name suggests. ⚠️ **Verified here against the source, and the request understated one thing and overstated another**: the enum *is* assigned `delivered` on the default path, so the trap is narrower than "only ever assigned undelivered" — it needs the caller to opt out of polling. And the `on AtException` handler's own comment reads *"Setting notificationStatusEnum to errored"* while it sets `undelivered`, naming a value the enum does not have (`{delivered, undelivered}`). **Owed, and the comment comes first**: a reader who reaches that handler while debugging is told the distinction they are hunting for exists, goes looking for where `errored` is set, and concludes their build is stale — worse than an undocumented field, which at least does not mislead. Then the qualifier on `notificationStatusEnum` and on `NotificationResult`, naming `atClientException == null` as what to read instead. ✅ **Confirmed by the requesting session 2026-08-26**: `bin/at_talk.dart` passes `checkForFinalDeliveryStatus: false`, so the mis-scored cells were the inert opted-out path and the narrowing above is the accurate statement of the defect. ⛔ **No change to when the exception is caught rather than thrown was asked for, and none should be smuggled into a docs fix** | Nothing |
| **a pq enrolment costs a post-approval round trip** | Measure it, and decide whether the enrolment APIs should say so. A legacy enrollee carries its own symmetric key in and is done at approval; a pq enrollee must then **collect** the key the approver encapsulated to its key package, polling for the envelope (`enrollmentApkamSymmetricKeyResolver`, 30 s budget, 2 s interval). ⚠️ **Found 2026-08-26 by it breaking two tests**, not by design review: two authorisation tests in the CLI functional pack wait 10 s before approving and have a 30 s budget, and under the `pqReady` default that no longer fit — they now name `legacy` because they assert authorisation, not key exchange. The pin keeps them honest; it does not measure the cost | Nothing. It needs a measurement and then a judgement about whether callers are told |
| [the registrar certificate test](#the-registrar-certificate-test) | Three arms against a self-signed cert. The last S-5 behaviour change that exercises nothing, and the only one with a security consequence. ⛔ **POST-D1 clean-up, not a gate** (gkc, 2026-08-23) | Nothing. It lands wherever at_auth is next touched |
| [14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) | Item 8 is the only one still waiting on a ruling. Items 20 and 21 are examined-and-left, not work; item 35 lands in `atGettingStarted` | gkc, on item 8 |
| **at_auth `enrollment_submitter`** | Both defects are fixed in at_auth on both branches. What is left: **the at_client half of (b)** is not on the at_auth carve branch, because at_client's PQ secret sharing is not there at all. ⛔ **Do not apply the one-liner the review recommends** — it breaks the PQ OTP flow; see [detail](detail/implementation-plan.md#the-enrollment_submitter-review-and-why-the-recommended-fix-is-wrong) | gkc scheduling it |
| **a retrofit leaves the enrolment record memo stale** | `LocalSecondary.getEnrollmentDetails()` memoises into a field for the object's lifetime (`enrollment ??=`), and `_settleEnrollmentIdentity` is what populates it — with the OLD record, because it reads appName/deviceName/grants off it in order to carry them over. `_rederiveFromEnrollment` rebuilds the signer, the lookup and the id and does **not** clear it, so afterwards the client runs as the new enrolment while the record describing what it may do is the old one's. ⚠️ **Benign today and only by luck**: the retrofit copies the grants verbatim, so both records answer `isEnrollmentAuthorizedForOperation` identically. Two live readers — that gate on every non-`local:` local write, and `PqClientBootstrap._reconcileEnrollmentSnapshot`, which writes the stale record's appName/deviceName/namespaces into the keyfile under the NEW id. Found by a sweep after the [retrofitted-enrolment fix](#a-retrofitted-enrolment-cannot-run-an-authenticated-verb) and verified here | Nothing |
| **at_lookup `OutboundMessageListener.read`** | `AT0014 "Unexpected response found"` pops one entry off `_queue` and clears `_buffer` **without draining the queue or closing the connection**, unlike both timeout paths beside it. A stale queued response is then handed to the next command, offsetting every read after it. It fired in none of the relayed-lookup runs that found it; it is a hazard on its own merits | Nothing |
| [14.42](#1442-why-enrollment-setup-takes-four-minutes) | Why `enrollment_setup.dart` takes ~4 minutes. gkc asked for the cause, 2026-08-20 — not a D1 gate, but owed to him rather than plan-generated hygiene | ⛔ **@ce2e-only — it does not reproduce locally** |
| [14.50](#1450-the-e2e-teardown-revokes-enrollments-belonging-to-other-runs) | Scope the e2e teardown to the run that created the enrollments | Nothing. Needs no permission and no publish |
| [14.47](#1447-the-at_client-unit-tree-has-a-cross-file-isolation-flake) | A unit-tree isolation flake in `local_secondary_sync_queue_test.dart`. Green alone and green in the full suite; red only in one hand-constructed ordering nothing runs | Reproduce at rate first |
| [14.44](#1444-residuals-from-the-at_chops-pr-review) | Two remain, both ⛔ **POST-D1** (gkc, 2026-08-23): at_chops 3.6.0's CHANGELOG owes the resolution-skew sentence (amend that section in place), and `XWingCore.combine` sizes its buffer from its inputs' actual lengths while writing at literal offsets 0/32/64/96/128 | Nothing. Both ride the next at_chops touch |
| **third-party dependency floors** | at_client alone declares **seven** below what it resolves — `path`, `crypto`, `uuid`, `archive`, `http`, `async`, `meta` — all minor or patch gaps, none checked against first use. The sibling floors were swept 2026-08-25; these were not.<br><br>⚠️ **And the gap runs the OTHER way too, which nothing here was watching.** at_client declares `at_persistence_secondary_server: ^5.1.0` and this workspace resolves **5.1.0**, so every pack exercises that version and only that version — while any consumer resolving fresh today takes **5.2.1**, which we have never run against. Found 2026-08-26 by the at_talk demo session, whose external resolution took 5.2.1 while mine took 5.1.0 and neither side would have noticed. That layer owns local storage, the commit log and the keystore. ⚠️ The same version pair already cost time once, when the local keystore's expired-record handling was characterised from 5.2.1's source while the workspace resolved 5.1.0 — the claims held in 5.1.0 by luck. "Readable as interchangeable" is what makes this expensive | Nothing. Two questions, not one: are the seven floors too low, and is at_client actually correct against the top of the range it already admits |
| **at_auth README** | `packages/at_auth/README.md` describes `FileAtKeysIo` at `:144` and `:191` and never mentions `at_auth_io.dart`, which is the barrel it now lives behind. One or two sentences where `FileAtKeysIo` is first named | Nothing |
| [14.16](detail/implementation-plan.md#1416-four-residuals-the-issue-tree-audit-surfaced-2026-08-09) | Only ③'s **orphan-growth** half is owed here, and it is a decision before it is code. SS-4 resume was ruled NO RESUME | The decision |
| **rebuild `at_virtual_env:local`** | The concurrent-relayed-lookup fix merged to at_server trunk; the local tag is whatever tree last built it, so it did not become a fixed atServer by virtue of the merge. Rebuild from a named ref before the next live run that needs one. ⛔ Trunk is now a **fixed** arm — an unfixed control has to come from `a37e3e3b` | Nothing. The recipe is in [Re-deriving the state](#re-deriving-the-state) |

### P3 — nice to have, explicitly after D1, or in another repo

| Item | What is owed | Blocked on |
| ---- | ------------ | ---------- |
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
[what the citation audit left owed](#what-the-citation-audit-left-owed).

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
`tests/at_onboarding_cli_functional_tests_proxy` are live packs as well, no
citation reaches either, and the CLI one builds clients from a `PqPosture` in two
arms — which makes it the best live evidence for UC-C1.6 and a second live proof
of UC-A1.1.

⚠️ **A citation count is not a coverage count.** An earlier pass reported "27 of
68 have no live proof" when what it had measured was 27 with no live proof *cited
from their acceptance scenario*. Do not restate it as coverage.

### What the citation audit left owed

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

**F16 is now the one that matters, and it shares a measurement with the open
seeding P0.** `neither key record is immutable; the lock that mints them is`
names `_rootlock@owner` and `_nskeylock.<ns>@owner`, and proves the live refusal
for the first only. The nskey lock is covered by a raw-literal pin of the
client's intent and by a mock that models the refusal on the key name — and a
mock cannot test a refusal it does not model, so the guard's presence and its
absence look the same.
[The seeding P0](#a-client-that-exits-during-its-startup-tail-abandons-seeding)
records its self-perpetuating-interlock arm as reasoned from the code rather than
measured. **It is the same measurement, and one live test discharges both.**
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
- **F1** — the clause level is 9% adopted, so the ledger cannot show which part
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
   nothing published throws rather than minting. A short-lived client relaunched
   in a loop could in principle never get through. Not observed — the reported
   run's frame never left the process — so this one is reasoned from the code,
   not measured.

**And `startupComplete` cannot be the answer as it stands.** It is the only
signal a caller has, and `stop()` breaks the step loop and completes it anyway,
so it resolves identically whether the work ran or was skipped. A caller that
waits for it still cannot tell.

⚠️ **What is owed is a reliable in-tree reproduction, and three attempts have
failed.** Recorded so they are not repeated:

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

The next attempt should start by establishing that a bare
`AtClientImpl.create` with an `atKeysIo` and a run-unique namespace seeds at
all — the arms that do publish all reach their client through
`enrolAndAuthenticate`, and that difference is unexplained.

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

⚠️ **One live probe discharges part of this row and part of another.** The
interlock arm below is reasoned from the code rather than measured, and
[F16](#what-the-citation-audit-left-owed) needs the same measurement from the
other direction: whether the atServer refuses a second `_nskeylock` create the
way it demonstrably refuses a second `_rootlock` one. `_nskeylock` is covered
today by a raw-literal pin of the client's intent and by a mock that models the
refusal, and a mock cannot test a refusal it does not model.
`pq_signing_root_mint_lock_test.dart` already takes, releases and re-takes a
lock live; the same shape against `nskeyMintLockKey` answers both.

⚠️ **And the interlock half is the sharper one**: if the lock cannot be made
self-healing, a client that takes it should release it on shutdown, and one that
finds it held with nothing published should say so at warning rather than
throwing something the caller cannot interpret. A cron-driven notifier is
precisely a short-lived client relaunched in a loop.

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

**The replacement** is `authenticatorForChops()`
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
| R-2   | at_client 4.0.0 posture defaults                     | After D1. **The default `PqPosture` becomes `pqActive`** ([ruling 113](detail/decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18)) — one value, replacing the two coupled edits it used to be. Still a pure default-flip carrying no code of its own. Issue #2016.<br><br>⚠️ **R-2 is now a ONE-STAGE step, not two.** The shipped default moved `legacy` → **`pqReady`** on 2026-08-26, so R-2 is `pqReady` → `pqActive` — the two axes ruling 113 names as the only difference between them (the data signing key becomes ML-DSA, and post-quantum writes become the default). This row said "and now after 14.39" while 14.39's posture work was owed; it landed |
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

# the citation audit's denominator. ⛔ `rm -f` FIRST — provenIn APPENDS, and a
# stale file reads as roughly twice the corpus (measured: 284 where the answer
# was 145, and the doubling looked like a real property of the suite).
cd packages/at_client && rm -f /tmp/cit.jsonl && \
  ACCEPTANCE_LEDGER=/tmp/cit.jsonl dart test test/acceptance --concurrency=1 >/dev/null
wc -l < /tmp/cit.jsonl            # RUN IT. 2026-08-26: 153
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

# row 2 and row 12: the external gates. The at_auth release is a pub.dev
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
cd packages/at_client         && dart test test/acceptance --concurrency=1 # 111
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
