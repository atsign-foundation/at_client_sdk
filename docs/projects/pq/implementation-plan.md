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
`proves:` prose is matched against nothing. ✅ **The clause level closes the
second half of that**: a citation pins the THEN clauses it claims and the
ledger counts them, so the known overclaim — three clauses of
UC-A2.5/UC-A2.6 — is computed rather than found by hand. ⚠️ This read "The
clause-by-clause audit is a D1 gate and is in `## TODO`". What the pins do
*not* check is whether the cited test really establishes the clause; that
judgement is still the citation's, written in `proves:`.

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

⚠️ **The letters are not a count and never were — read the list, do not infer
from the range.** `G1` sits below the gates under **POST-D1 CLEAN-UP**: it was a
gate until 2026-08-23 and keeps its letter, because prose above and below cites
these letters and renumbering would silently repoint every one of them. `G0` was
then added at the FRONT on 2026-08-24 for the same reason, so the sequence now
runs G0, G2–G7 with G1 elsewhere. ⚠️ This said "the D1 gates are `G2`–`G7`",
which G0 falsified the day it was written, and the same sentence had already
been copied into memory.

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

⛔ **"Top-down" does not mean "start at the top" — TWO of these are startable
here and now, and they are G3 and G4.** A cold read on 2026-08-25 got as far as
the list and then could not say what to do, because the ranked head is blocked
on something a session cannot do. That is the failure this list exists to
prevent, so it is now stated rather than left to be re-derived:

| gate | startable in this repo, by a session? |
| ---- | ------------------------------------- |
| G0, G2, G5 | **No** — discharged |
| G3 | **Diagnosed, ruled and fixed 2026-08-25.** What is left is one full functional pack run carrying the change |
| **G4** `[RECOMMENDED]` | **YES** — and it was unblocked on 2026-08-24 when its stated gate turned out already lifted |
| G6, G7 | **No** — a merge and a publish, both gkc's |

⚠️ **`[RECOMMENDED]` moved from G0 to G3 and then to G4, both on 2026-08-25** —
first when at_server merged the G0 fix, then when G3 was diagnosed, ruled and
fixed the same day. This table's first row read "G0 `[RECOMMENDED]` — **No.** Diagnosed,
fixed and verified; what is owed is the MERGE of at_server PR #2771", under a
note saying G0 kept the recommendation because the merge should be chased and
was "not the thing to *type* first". The merge happened, so the recommendation
now sits on something a session can start typing on.

**G0. ✅ DISCHARGED 2026-08-25 — an atServer answered concurrent cross-atSign
lookups with each other's records.** Nothing here is startable: the fix is on
at_server trunk. The entry is kept for the same reason G2's is — it carries the
diagnosis, the measurements, the controls and the three instrument faults, and
the deferred pooling discussion in [`## TODO`](#todo) is written against it.

The defect, in an atServer that predates the fix: two `lookup:` requests for
different records of the same peer atSign, in flight at the same moment on one
atServer, can each come back carrying the other's record — **with no exception
raised**, so an app receives a well-formed record that is not the one it asked
for. Nothing is stored wrongly; the record at rest is correct at both ends.

⚠️ **This entry read "A conveyance payload is landing at VALUE record
addresses" until 2026-08-24, and that was wrong.** The write was never at
fault. `llookup:all:` on the sender's own atServer and `lookup:all:` from the
receiver both return the correct 6668-byte value for the very record whose read
had just handed back a 44-character content key. What the earlier entry read as
a misplaced payload was one read being answered with another read's response.

**It is not a PQ defect.** PQ made it visible: an nskey read issues a *second*
cross-atSign lookup, for the `<ckKid>.__ck` conveyance, from inside the first
one's decrypt — so a single `get` puts two relayed lookups in flight where a
legacy read has one. (Why legacy never surfaced it is untested; I have not
measured a legacy arm.)

**Start by RUNNING the standalone probe, which has no PQ in it at all:**

```bash
docker rm -f test-virtualenv-1        # recycle the VE first, always
cd tests/at_functional_test
VIRTUALENV_IMAGE=at_virtual_env:local ./runLocal.sh   # or bring the VE up alone
dart test test/concurrent_relayed_lookup_test.dart --concurrency=1 --run-skipped
```

Four sockets on `@bob🛠`, four different records of `@alice🛠`, asked together.
`tests/at_functional_test/test/pq_read_returns_another_record_test.dart` is the PQ symptom
this was found through, at 13-22 wrong reads per 50 cycles, and it clears
under the fix — see the table below. ⛔ It must run FIRST on a freshly
recycled virtualenv; after this probe in the same one it reads 0.
Measured 2026-08-24 against `at_virtual_env:local`, `@alice🛠` under write load:

| in flight at once | requests | answered correctly | answered with another record | refused or timed out |
| ----------------- | -------- | ------------------ | ---------------------------- | -------------------- |
| 1 (control)       | 120      | 120                | 0                            | 0                    |
| 4                 | 480      | 41                 | 35                           | 404                  |

The refusals name the same event from the other side: 250 `AT0011-Internal
server exception : Connection failed to @alice🛠`, 18 `AT0023-Timeout waiting
for response`, and 16 `AT0003-Invalid syntax` in reply to a `lookup:all:` the
control arm sends cleanly 120 times.

**The mechanism, read in at_server at `a0deee69` and confirmed unchanged on
its trunk at `a37e3e3b`:** ⚠️ **This said `a0deee69` was "the revision
`at_virtual_env:local` was built from", and that was never supported** — see
the note in [Re-deriving the state](#re-deriving-the-state). What matters is
that trunk carries it, which was checked directly.

- `AtCacheManager` holds one `DummyInboundConnection` and passes it to
  `OutboundClientManager.getClient(otherAtSign, thatConnection)` on every
  relayed lookup (`packages/at_secondary_server/lib/src/caching/cache_manager.dart`).
- `OutboundClientPool.get` matches a pooled client with
  `client.inboundConnection.equals(...)`, and `DummyInboundConnection.equals`
  returns true for **any** other `DummyInboundConnection` — so every relayed
  lookup to a given atSign, from every client connection, gets the same
  `OutboundClient` and therefore the same socket. The atServer's own log shows
  it: three `retrieved outbound client to @alice🛠 ... from pool` inside 140 µs.
- `OutboundClient.lookUp` writes its request and reads whatever the listener
  queues next, with **no mutex** across the pair. The client half of the same
  conversation does hold one — `AtLookupImpl._process` keeps
  `requestResponseMutex` across `_sendCommand` + `messageListener.read`.
- `getClient` is not atomic either: two concurrent misses each create and add a
  client, so the pool can hold duplicates for one key (observed, 6 ms apart).

✅ **RULED by gkc 2026-08-24, then REVISED by him the same day. The revision is
what stands.** ⚠️ **This entry recorded "all three, not a choice between them"
and that is superseded** — the pool-key change is OUT, and gkc wants the
question it raises taken on its own:

> "The one thing I'm not sure about is pool-keying the relayed lookup
> connection on the real inbound connection. I think I'd rather serialize on a
> single connection for now, and have a longer discussion on how to handle
> outbound connection pooling and concurrency at a later date"

**In scope:**

1. **Lock `OutboundClient` across each request/response pair.** On its own this
   fixes the swap: the shared client is retained, so relayed lookups queue on
   one socket instead of interleaving on it.
2. **Make `OutboundClientManager.getClient` atomic per pool key**, so two
   concurrent misses stop each creating and adding a client for one key.

**Out of scope, deliberately:** keying the pool on the asking inbound
connection, and `DummyInboundConnection.equals` answering true for any other
dummy. Changing `equals` was never in it —
`NotifyConnectionPool.getOutboundClient` builds a fresh dummy per call and
relies on that match to reuse a connection at all, so identity equality there
would open a connection per notification.

⚠️ **Carry this into that later discussion**: with the shared dummy retained,
every relayed lookup to a given remote atSign now serialises behind every other
one. That is correct and it is a throughput characteristic — and a request
queued on the mutex is waiting *before* its 5 s read budget starts, because the
timeout begins after acquisition.

**Three things the diagnosis did not have, established in at_server at trunk
`a37e3e3b`:**

- `InboundConnectionImpl.equals` matches on remote **address and port**, not
  object identity. So "key the pool on the real inbound connection" would not
  have been the identity keying it sounded like, which is its own reason the
  deferred discussion is the right home for it.
- `NotifyConnectionsPool.getOutboundClient` has the **same non-atomic
  get/connect/add shape** as `OutboundClientManager.getClient`. The ruling
  names only `getClient`.
- `PolVerbHandler` holds a **third** `DummyInboundConnection`, and because any
  dummy matches any other, pol's outbound clients and the relayed-lookup
  clients share one pooled client per atSign at `handshakeRequired: false` —
  so pol's `lookUp`/`plookUp` interleave on the same socket as relayed lookups
  today.

⛔ **A claim in the diagnosis was WRONG, and it is recorded because a lock
design is what rests on it.** This entry said the send/read pairs inside
`_establishHandShake` "run under `connect()` before the client is reachable
from the pool". They do not: `PolVerbHandler` and `ScanVerbHandler` both call
`connect()` on a client they have just taken *from* the pool, behind
`if (!oc.isConnectionCreated)` and `if (!outBoundClient.isHandShakeDone)`
guards that `getClient`'s default `connect: true` normally makes false. Latent
rather than hot, but the stated property does not hold. The lock design
survives for a different reason: `connect()`'s callees are the leaf wire
operations, so locking only those leaves no nesting. ⚠️ **`plookUp` delegates
to `lookUp` and must therefore NOT take the lock itself** — a "lock every
public method" pass deadlocks there.

✅ **VERIFIED END TO END ON THE REAL WIRE, 2026-08-24.** ⚠️ **This continued
"and G0 STAYS OPEN, because nothing is merged"; it merged on 2026-08-25.** Every
atServer built before that merge still carries the defect, which is why the
before-and-after images below are worth keeping rather than deleting.

Two virtualenv images built from named refs, `g0base` from trunk `a37e3e3b` and
`g0fixed` from `af957440`, run minutes apart on one machine with one probe:

| `concurrent_relayed_lookup_test` | g0base | g0fixed |
| -------------------------------- | ------ | ------- |
| width 1 (the control)            | 60/60 ok | 60/60 ok |
| width 4, requests                | 120    | 120     |
| **answered correctly**           | **15** | **120** |
| **answered with another record** | **7**  | **0**   |
| "Internal server exception"      | 54     | 0       |
| "connection went away"           | 26     | 0       |
| "Invalid syntax"                 | 11     | 0       |
| "Timeout waiting for response"   | 7      | 0       |

Zero exceptions of any kind in the fixed arm's whole log. ⚠️ **The baseline
*mix* is approximate and must not be quoted as exact** — the harness tests
message text in a fixed order, so a message carrying two of the phrases lands
in whichever is tested first. The totals, the crossings and the fixed arm's
zeros are solid; zero needs no bucketing.

**What made this readable rather than merely encouraging**, and what to repeat:
the baseline arm was run first and had to fail before the fixed arm could mean
anything; the two compiled `secondary` binaries were `shasum`-compared to prove
the arms differ in the varied thing; and the at_server session wrote its
predictions down *before* seeing any number.

✅ **The PQ symptom clears under the fix too — and the harness is sound.**
⚠️ **This entry said `pq_read_returns_another_record_test.dart` "HAS STOPPED
DISCRIMINATING", and that was wrong.** It discriminates perfectly well; what
had changed was the position I ran it from. Measured across 350 cycles:

| image | at_server ref | ok | wrong | errored |
| ----- | ------------- | -- | ----- | ------- |
| `g0old` | `a0deee69` | 26 / 21 | **17 / 20** | 7 / 9 |
| `dev_env` (what CI runs) | not identifiable | 24 | **19** | 7 |
| `g0base` | trunk `a37e3e3b` | 30 / 11 | **13 / 22** | 7 / 17 |
| `g0fixed` | `af957440` | **50 / 50** | **0 / 0** | **0 / 0** |

Five unfixed runs, 250 cycles, 91 wrong reads. Two fixed runs, 100 cycles,
none. Every run image-asserted — `ve_up.sh` inspects the running container and
refuses if compose fell back to its own default, which is a real trap here.

⛔ **RUN THIS HARNESS FIRST, ON A FRESHLY RECYCLED VIRTUALENV, OR IT READS 0
AND MEANS NOTHING.** Every run that went first reproduced; every run that
followed `concurrent_relayed_lookup_test` in the same virtualenv read 0 wrong —
five and three, cleanly split, on both fixed and unfixed images. That is a
confounder in the *harness rig*, not in any atServer, and it cost two wrong
conclusions before it was found: first that the harness had stopped working,
then that trunk masked the symptom. Neither was true.

**Volume is not the lever, so do not reach for caching.** The atServer issues
essentially the same number of relayed lookups either way — 378 during the PQ
phase in the suppressed position against 408 and 418 when it runs alone, all
counted from `AtCacheManager`'s own `remoteLookUp:` log lines with a positive
control on the same file. The lookups still happen and they stop crossing, so
what narrows is the overlap *window*. **The leading candidate is untested**: in
a clean virtualenv the first relays each wait on an outbound connection being
established and handshaken, which is slow enough for several to pile up on the
shared client, whereas a warmed connection makes each relay short enough that
two are rarely in flight together. That would make the window a property of
connection state rather than of code, and therefore something that can widen
again with no change at all.

⛔ **Ruled out with evidence — do not re-derive any of these:**at_client’s read path (the key asked for is the key returned, and a `CONVEYANCE-FOR-VALUE` probe inside `GetResponseTransformer` never fired); the shared `AtKey` object between put and get (150 cycles, clean); metadata aliasing via `ckConveyanceKey`; `CryptoRuntime._stampEncrypted` colliding with a read (0 shared metadata objects over 15 runs); concurrent nskey seeding (serialising provisioning did **not** help); and the write itself, settled by the raw lookups above. (Moved here 2026-08-25 from the `## TODO` row that used to carry it, so G0 holds the substance and the row holds a pointer.)

⚠️ **Three instrument faults nearly produced confident wrong numbers here, and
two of them look authoritative.** The image-label fault is described in
[Re-deriving the state](#re-deriving-the-state). The second: a fresh git
worktree of at_server resolves `at_server_spec` to **hosted 5.1.0** instead of
the in-tree 5.2.1, because the path override lives only in an **untracked**
melos `pubspec_overrides.yaml` — it compiles clean and analyzes clean, so a
probe run against it would have measured a server nobody built. The third: an
`AT\d{4}` regex buckets nothing on the client side, because the codes are what
the **atServer** puts on the wire and at_client has already rewritten them into
message text by the time a caller sees the exception — one bucket where there
were four.

**Also owed in at_server, and not part of this fix** (both found by being
bitten): `tests/at_functional_test/runLocal.sh` and `tests/at_end2end_test/runLocal.sh`
each `mkdir -p` the `root` contents directory and not the `secondary` one, so
both work in a checkout that has run before and fail on a fresh clone — that
half is **FIXED: at_server
[PR #2772](https://github.com/atsign-foundation/at_server/pull/2772) merged to
trunk on 2026-08-25** as `064640bb`, and both runners now create the directory
(⚠️ this read "open as of 2026-08-25"); and the `at_server_spec` hosted fallback
above, which gkc has deliberately left for a considered decision, is filed
nowhere and reaches CI — its `unit_tests` job
runs `dart pub get` per package with no melos step, so a PR changing
`at_server_spec` and `at_secondary_server` together tests the new server
against the old published spec, green.

**Where the work landed**: **at_server
[PR #2771](https://github.com/atsign-foundation/at_server/pull/2771)**, branch
`gkc-outbound-client-concurrency`, **merged to at_server trunk 2026-08-25** as
merge commit `8f4a985a`. ⚠️ **This paragraph read "open and not merged … what is owed is the
merge"**, and before that "three commits, head `52d63b63` — unpushed as of
2026-08-24". Re-derive rather than trusting
either: `gh pr view 2771 --repo atsign-foundation/at_server`, or
`git -C <at_server> merge-base --is-ancestor af957440 origin/trunk`. The merge
carries four files — `outbound_client.dart`, `outbound_client_manager.dart`,
their CHANGELOG entry, and a new `outbound_client_concurrency_test.dart` —
which is the ruled scope and nothing beyond it. `af957440`, the ref every
measurement above was taken against, is now an ancestor of trunk. Its own
rails: that new concurrency test, the package suite at 1030/1030, and
at_server's two real-wire suites at 239 and 47.

⚠️ **The merge leaves one rig action owed, and nothing performs it
automatically.** `at_virtual_env:local` on this machine is whatever tree last
built it, so it does *not* become a fixed atServer by virtue of the merge —
rebuild it from at_server trunk before anything here trusts that tag again,
using the recipe in [Re-deriving the state](#re-deriving-the-state), and pin the
image explicitly on every live run until then. ⛔ **And "just build trunk" is no
longer a baseline**: trunk carries the fix, so an image built from it is a FIXED
arm. An unfixed control has to come from `a37e3e3b` or from `8f4a985a`'s first
parent — `at_virtual_env:g0base` already is one. The relay probe named above
tells the two apart in seconds and is the only thing that reliably does. No image label can answer "which
at_server code is in this image"; that is the first of the three instrument
faults below.

⚠️ **Also owed, and separate**: at_lookup's
`OutboundMessageListener.read` handles `AT0014 "Unexpected response found"` by
popping one entry off `_queue` and clearing `_buffer` **without draining the
queue or closing the connection**, unlike both timeout paths beside it. A stale
queued response is then handed to the next command, offsetting every read after
it. It did not fire in any of these runs; it is a hazard on its own merits.

⚠️ **This displaced G6 as the recommendation on 2026-08-24, and handed
it on to G3 on 2026-08-25 when the fix merged** — see the table above. The
reasoning while it stood, kept because it is the standing tie-breaker: release
sequencing will keep, and a cross-atSign read that silently returns the wrong
record was the sharpest thing open anywhere in the tree.

**G2. ✅ DISCHARGED 2026-08-24 — build the acceptance suite out per [ruling 115](detail/decisions.md#115-the-acceptance-suite-is-4-arms-and-a-ledger-not-one-grid-2026-08-23).** Arms 1–3, the ledger and its clause level are all built; arm 4 is cancelled. Nothing here is startable — the entry is kept because it carries the design and the measurements, and because a reader who deletes it re-derives ruling 115 from scratch.
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
"Arms 2–4 and the ledger's clause level have not [landed]"**, and then "what
remains of this entry is the ledger's clause level alone" — on 2026-08-24 arms
2 and 3 were built, arm 4 was cancelled, and the clause level was built, so
**nothing in this entry is owed**. Read the ✅ markers below before starting
anything here.

✅ **Arm 1 is BUILT (2026-08-23) — do not build it again.** This paragraph
opened "Start here, and it is startable now: build **arm 1**, the 3-cell stage
arm, in `tests/at_functional_test`", and that is done:
`test/pq_stage_arm_test.dart`, **186/186** in the full pack *as it then was* — ⚠️ the pack is **183** now (181 pass, 2 skipped), the two skips being the G0 harnesses; do not read 186 as current, with
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
live runs on one virtualenv refuted it. ✅ **The clause level is BUILT too (2026-08-24)**, so this entry owes nothing.
⚠️ **This read "So what remains of this entry is the ledger's clause level
alone."** `provenIn` takes `clauses:` — distinctive fragments, each of which
must resolve to exactly one THEN clause of its row — and
`tool/acceptance_ledger.dart` renders a per-row checklist plus a catalogue
total. First render: **129 clauses across 68 live rows**, 7 pinned by a proven
citation, UC-A2.4 at **5 of 6**. ⛔ It did NOT need `manifest.dart` moved to
`lib/`, which both this plan and ruling 115 gave as its prerequisite: the tool
imports `../test/acceptance/manifest.dart`, so one parser serves the tool,
`provenIn` and the docs rail.

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

**G3. [RECOMMENDED] Diagnose [14.34](#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart).**
A live-pack failure at once in five, unexplained. A gate only because D1 now
ends when every rail is green, and at that rate "green" is a rate rather than a
state.

✅ **DIAGNOSED 2026-08-25, with the far-side log this time captured.** ⚠️ This
entry read *"Start by RE-MEASURING the rate, not by diagnosing"*; the rate turned
out to be the wrong instrument and the diagnosis came from the margin instead —
see below. **What is now owed is a decision about the fix, not an investigation.**

**What happens.** The atServer receives the test's ping *before* it has processed
the retrofitted client's `monitor:`, so at that instant nothing is subscribed and
the notification is written to **no connection at all**. Captured on the atServer's
own log, one failing run, times are the atServer's:

| | |
| --- | --- |
| `RCVD: notify:…rf2cmon-618149102…` | `09:42:08.207762` |
| `NotificationManager enqueue …rf2cmon-618149102…` | `09:42:08.208185` |
| `RCVD: monitor:selfNotifications` (the retrofit client) | `09:42:08.210581` |
| `SENT: notification:` for that id | **never, to any connection** |

The client had written `monitor:` 6.9 ms earlier (`AtLookup|SENDING: monitor:
selfNotifications` at `10:42:08.203687` local, `Monitor|monitor started` 248 µs
after) — so the inversion is in how long the atServer took to *read* the command
on a socket it had just PKAM-authenticated, not in what order the client sent.

**Why the test's guard cannot close it, and why no guard could.** Three facts,
each read in source rather than inferred:

- `AtLookupImpl._openNotificationStream` emits `notificationConnectionUp = true`
  — which is what becomes `NotificationListenerState.listening` — immediately
  after `await _connection!.write(command)`. It means *"we wrote `monitor:`"*,
  never *"the atServer is delivering to us"*.
- `MonitorVerbHandler.processVerb` subscribes the connection to the atServer's
  notification broadcast stream only when it *processes* that command.
- ⛔ **The `monitor:` verb is unacknowledged by design**: at_server's
  `MonitorResponseHandler.getResponseMessage` returns `''`, so the atServer writes
  **zero bytes** back. There is no signal on that socket a client could wait for.

And nothing recovers the gap: a first-ever monitor sends `monitor:selfNotifications`
with no watermark, and only `monitor:…:<epochMillis>` replays from the store. A
long-lived client is exposed on its **first** subscribe only; this test builds a
brand-new client every run, so it is exposed every run.

**The margin is the instrument; the pass/fail outcome is not.** Measured
2026-08-25 against `at_virtual_env:g0fixed`, as microseconds between the atServer
receiving `monitor:` and receiving the ping (positive = the monitor got there
first). Two arms differing in one thing — an environment-driven pause inserted
between the client calling itself `listening` and the ping going out:

| arm | n | margin, µs |
| --- | -: | --- |
| no pause (the shipped behaviour) | 10 | **−2819**, +92, +114, +121, +225, +859, +975, +1063, +1155, +3472 |
| 500 ms pause | 6 | +503734, +504348, +505349, +506870, +509759, +510254 |

One negative value, and it is the failing run. A distribution straddling zero is
the finding — not the failure count.

⛔ **Do not use the pass/fail rate to decide anything here.** The identical
unpaused arm gave **4 failures of 10** and then **0 of 10** within one hour, same
image, same virtualenv, same test bytes. That is the same shape as G0's ordering
confounder and it has already produced two wrong conclusions on this row. The
margin yields a number from every run, including the ones that pass.

**To reproduce**: bring the virtualenv up on a named image and leave it up
(`docker compose up -d` in `tests/at_functional_test/test` with `VIRTUALENV_IMAGE`
set, then the pkamLoad wait out of that pack's `runLocal.sh`), run
`dart test test/self_enrollment_retrofit_live_test.dart --concurrency=1` in a
loop, and **copy `/apps/logs` out before any compose-down**
(`docker cp test-virtualenv-1:/apps/logs <dir>`). ⚠️ The atServer logs at FINEST
here and **rotates at ~52 MB**, so `alice🛠.log` alone covers only the last few
seconds of a 20-run block — read `alice🛠.log.*` too, or a grep returns a
confident zero. Pair each notification with the `monitor:` nearest it in time and
subtract.

✅ **RULED by gkc 2026-08-25, after the shape below was measured: fix the
CALLER and the test, not the protocol.** The window is real but it is largely
self-healing in production — `getLastNotificationTime()` seeds the watermark to
`DateTime.now()` on its first call and returns null, so the *next* monitor
reconnect asks the atServer to replay from just before the window and the
missed notification arrives then. ⚠️ That seed is a **client** clock compared
against the atServer's own notification timestamps, so a client running ahead
of its atServer skips the replay and the notification is gone; "delayed rather
than lost" is conditional on clock agreement, not on the race.

**What that ruling produced, and it is not confined to the test:**

⛔ **`AtRpc` was exposed and undefended, which is what turned the ruling.**
`AtRpc.start()` subscribes for response notifications and returns — it does not
even wait for `listening`, so it is *more* exposed than the test was. The caller
then sends a request, and the far side answers with a notification back over
that same listener. Measured across 94 monitor starts in this session, the gap
between `subscribe()` returning and `monitor:` reaching the socket ran **19 ms
to 383 ms, median 152** — long enough for a fast round trip to beat it, and the
microsecond figures below are only the *residual* after a `listening` wait.
`sendRequest`'s retry loop does not cover it: it sets `sent = true` as soon as
the notify succeeds and retries only on an exception. `AtRpcClient.call()` is
the sharp end — it returns a future completed only by the response, with **no
timeout**, so a lost response hangs the caller for good.

**Built 2026-08-25:** `AtRpc.ready()` and `AtRpc.listenerReadyTimeout`, with
`sendRequest` awaiting readiness when `isClient`; and the ping in
`self_enrollment_retrofit_live_test.dart` retried until one lands rather than
sent once. Rails: `packages/at_client/test/rpc/at_rpc_readiness_test.dart`
(4 tests, four mutations each reddening its own assertion — the wait deleted,
the current-state read deleted, the `isClient` guard removed, and the timeout
swallowed), at_client unit **1550** and at_policy **5** at exit 0, at_client
`dart analyze lib test` exit 0 / 422 info and the format gate exit 0,
`tests/at_functional_test` analyze exit 0 / 246 info.

**Live, against `at_virtual_env:g0fixed`.** The shipped shape ran **8 of 8
green**, one ping each — the window fell the right way every time, so those runs
do not exercise the retry. The retry was proven separately by forcing the window
open (skipping the client's `listening` wait, which puts the ping inside it
every time) and varying only whether the ping is retried: **retry off, 3 of 3
failed** with `TimeoutException` on the awaited notification; **retry on, 2 of 3
passed**. ⚠️ The third was red for an unrelated reason — a keyfile lock
contention (`Could not acquire the keyfile lock`) on `rf2b-t5@alice🛠.atKeys`
inside `mintLegacyKeyfile`. That is **one sighting** under an artificial
configuration, absent from 30 pre-change runs and from 8 post-change shipped
runs; it is a sighting, not a rate, and it is not attributed to anything.

⚠️ **What is NOT owed: the protocol change.** The four candidates were weighed
and gkc chose the caller-side fix. The protocol option is real and is already
specified upstream — see the `monitor:` acknowledgement row in
[`## TODO`](#todo), which also carries a correction to that specification that
must be settled before anyone builds it.

The four candidates, kept because the ruling is only legible against them:

1. **Fix the test only** — have it prove registration before it pings (send a
   warm-up notification and wait for it, or retry the ping). Closes this gate;
   leaves every app with the same window on its first subscribe.
2. **Acknowledge `monitor:`** — the atServer returns a line once it has
   subscribed, and at_lookup holds `up` until it arrives. Closes it for everyone,
   and it is a protocol seam: at_server plus at_lookup in one sweep, with a
   timeout fallback so an older atServer that answers nothing does not hang a
   client (which reopens the window against old servers, knowingly).
3. **Send a watermark when there is none** — ⚠️ the epoch is compared against the
   atServer's own notification timestamps, so a client-local `DateTime.now()`
   makes delivery depend on clock agreement between two machines. A
   server-supplied value would fix that, and **there is none to hand on the
   monitor connection**: the `from:` challenge on the self path is a bare
   `Uuid().v4()` with no timestamp in it (read in at_server's
   `FromVerbHandler`, trunk, 2026-08-25). So this option costs a new
   server-clock source before it costs anything else.
4. **Do nothing and say so in the API** — document that `listening` means the
   command was written, and that a first subscribe has no delivery guarantee.

⛔ Read [14.34](#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart)
and [14.43](detail/implementation-plan.md#1443-the-functional-suites-convergence-race)
together before acting: they were written months apart without noticing each
other, and the instruction to work them together is the part that keeps getting
lost.

**G4. Migrate 14.11's bucket B** — the 71 credential-ladder uses
(`enrollmentId` 59, `signingAlgoType` 12) onto the `AtAuthenticator` seam that
at_lookup 3.7.0-rc1 ships. ⚠️ **This read "ships **on trunk** — pub.dev is
still 3.6.1, and in this file that distinction is the whole gate", and it was
wrong**: `3.7.0-rc1` has been on pub.dev since 2026-08-23. pub.dev's `latest`
field excludes prereleases, which is the trap this file names at the top and
then fell into here. So the distinction G4 called its whole gate does not
exist, and nothing external blocks this entry. 24 sites in `lib/`, 47 in tests, across
at_client, at_onboarding_cli and at_auth. The only one of the five
`deprecated_member_use` buckets with a replacement that exists today.

**G5. ✅ DISCHARGED 2026-08-24 — close 14.19 item 36.** All three clauses are
live-proven in `tests/at_functional_test/test/key_package_amendment_live_test.dart`
and pinned from `a2_enrollment_test.dart`, so the ledger counts them. ⚠️ This
read "**The work is still owed** — computing a gap is not closing it", and
before that "three clauses … it was found by hand".

**Two of the three changed what the catalogue says, and that is the part worth
reading before trusting the row:**

- **A2.6's "state gate" is not a check inside `enroll:update`.** There is none.
  The outcome holds because a revoked enrollment can no longer authenticate at
  all (`AT0027 … is revoked`) *and* every other connection, the fully
  privileged owner included, is refused as not-self (`AT0011 … enroll:update is
  self-only`). ⚠️ **One arm is still unproven**: an enrollment revoked while it
  holds an already open, already authenticated connection — the live arm
  reconnects, so it measures the post-revocation handshake.
- **A2.5's envelope clause said "superseded", and nothing is superseded here.**
  An amendment **joins** a key; the original stays `active`, which the test now
  asserts. Supersession is rotation's shape.
- The negotiation clause's axis is **`AtClientPreference.sealsToKeyAlgorithms`**
  — what a sender picks among the keys a recipient offers — not
  `keyEstablishmentAlgorithms`, which is what an atSign mints. A test varying
  the second observes nothing.

Each arm is mutation-proven: same sender order collapses the negotiation
differential, sealing nothing beforehand reddens the carry test's precondition,
and skipping the revoke makes the refused request succeed.

**G6. The train** — ⚠️ this read `[RECOMMENDED]` and was the head of the list
until G0 displaced it on 2026-08-24. It is still the next *release* step, and its
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
them. So the D1 gates are **G0 and G2–G7**, and G1 sits here. ⚠️ This read
"**G2–G7**" until 2026-08-25 — the same falsified sentence that the note under
[`## THE NEXT MOVE`](#the-next-move) had already corrected in its own copy, left
standing here because a claim with two homes only ever gets fixed in the one you
have open.

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
# Both figures GROW with every commit, so they are stamped with the head they
# were measured at rather than a date — an unstamped answer beside its own
# command reads as current forever. Re-run; do not quote.
git rev-list --count 64480808d..HEAD                              # 53 at 52ad01a59
git diff --name-only 64480808d..HEAD | grep -vc '^docs/'          # 108 at 52ad01a59
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
| **at_chops 3.6.1 — [PR #2181](https://github.com/atsign-foundation/at_client_sdk/pull/2181)** | ⛔ **MERGED 2026-08-24, and NOT yet published — pub.dev tops out at at_chops `3.6.0`, so what is owed here is the publish, not the review.** ⚠️ This row read "Carved and OPEN" until 2026-08-24. It is NOT in the train's ordering above** — it was cut on 2026-08-24 from trunk, not from the spike, because at_chops 3.6.0 is already published and had no in-progress CHANGELOG heading to fold into. Message-only change: `PkamMlDsa65SigningAlgo.sign` reported a bare `ML-DSA-65 secret key must be 4032 bytes: N`, which names neither the credential nor the likeliest cause. A PKAM key of ~1.2 kB is an RSA-2048 private key, which a caller holds by naming one enrollment's algorithm while carrying another's credentials. Owed: merge, then gkc publishes 3.6.1. ⚠️ **Nothing depends on it** — no floor in this tree requires 3.6.1, so it can land whenever; but it is a second at_chops publish the train's ordering does not mention | Nothing. It is independent of at_auth and of the spike |
| `acceptance-report.json` is ignored only on this branch | ⚠️ **Deferred by gkc 2026-08-25 — recorded so the deferral is not silent.** `.gitignore` here carries `acceptance-report.json`, `citations.jsonl` and `acceptance-ledger.md`; **`gkc-pq-d1-at-auth` and trunk carry none of them**. A per-run report is sitting in `packages/at_auth/` at 220 KB, and on the carve branch a `git add <directory>` wants to track it — the commit hook refused exactly that on 2026-08-25.<br><br>⚠️ **gkc's reason was that [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179) merges to trunk shortly, and that does not by itself fix it**: #2179's head is `gkc-pq-d1-at-auth`, which is the branch LACKING the ignore. Trunk gets it when this branch merges, not when #2179 does | Nothing. It resolves itself when this branch lands; until then, name files rather than directories when staging on the carve |
| **the `monitor:` verb has no acknowledgement** | ⚠️ **NOT D1, and it is a protocol seam across three repositories.** A client writes `monitor:` and there is nothing to read back — at_server's `MonitorResponseHandler` returns the empty string on success — so it cannot tell acceptance from refusal, and reports a connection as up the moment the command is *written*. Specified upstream as [at_protocol#367](https://github.com/atsign-foundation/at_protocol/issues/367) with three open sub-issues: at_commons [#2175](https://github.com/atsign-foundation/at_client_sdk/issues/2175) (a `prompts` parameter on the verb, opt-in and additive, and it ships first), at_server [#2764](https://github.com/atsign-foundation/at_server/issues/2764) (answer the command, and terminate every notification with a prompt), at_lookup [#2176](https://github.com/atsign-foundation/at_client_sdk/issues/2176) (send it, wait for the answer, frame on the prompt).<br><br>⛔ **A correction to that specification, to settle BEFORE anyone builds it.** #367 says the acknowledgement lets "a refused `monitor:` be reported as a failure". Today `monitor:` is **not** refused: `MonitorVerbHandler.processVerb` checks only that the connection is authenticated, subscribes it, and the refusal then happens per notification inside `_sendNotification` via `isAuthorized`, dropping each one with a server-side warning the app never sees. A replay does not rescue it either — replayed notifications go through the same check. So the acknowledgement ALONE does not fix the case #367 leads with; at_server must also decide the refusal **at `monitor:` time**. #2764 gestures at this ("A refusal must be answerable too") as an aside rather than as the work.<br><br>⚠️ **Cost, so the deferral is a decision rather than a drift**: at_server is a separate repository and needs the at_commons carrying the parameter *published* before it can be written against it, and at_lookup's half re-does a release-train position that has already shipped (3.7.0-rc1). ⚠️ **This also said the parameter "needs a version gkc chooses" because at_commons is published at 5.16.0 with no in-progress heading. That is wrong**: trunk and this branch are both at 5.16.0, but [PR #2182](https://github.com/atsign-foundation/at_client_sdk/pull/2182) is open and already bumps at_commons to **5.17.0**, so the parameter folds into an in-progress heading that exists — on another branch, which is why a check scoped to this one missed it. Re-derive with `gh pr list --repo atsign-foundation/at_client_sdk --state open` rather than reading a version out of the working tree. The window it closes is measured in **G3** | gkc scheduling it, after the release train. The caller-side mitigation is already built — see G3 |
| **atServer outbound connection pooling and concurrency** | ⚠️ **IN ANOTHER REPO (`at_server`), and gkc asked for it as a discussion rather than a change** — 2026-08-24, when he took pool keying out of the G0 fix: *"I'd rather serialize on a single connection for now, and have a longer discussion on how to handle outbound connection pooling and concurrency at a later date"*. Recorded so the deferral does not read as a decision.<br><br>**What that discussion has to weigh**, all established while diagnosing G0: every relayed lookup to a remote atSign now serialises behind every other one, and a request queued on the mutex is waiting before its 5 s read budget even starts; `InboundConnectionImpl.equals` matches on remote address and port rather than object identity, so keying on "the real inbound connection" is not the identity keying it sounds like; `NotifyConnectionsPool.getOutboundClient` has the same non-atomic get/connect/add shape that G0 fixes in `getClient`; and `PolVerbHandler` holds a third `DummyInboundConnection`, so pol's `lookUp`/`plookUp` share a pooled client with relayed lookups at `handshakeRequired: false` <br><br>**Four residual findings belong to this discussion**, all pre-existing and none claimed by the G0 fix: `poolSize` is not enforced across different pool keys, so concurrent misses for different atSigns can take the pool past its declared maximum; an evicted client is dropped without `close()`, leaking its socket; `OutboundMessageListener` can queue a bare `@atSign@` prompt as its own entry when the response and the prompt arrive in separate socket reads, and `read()` accepts a bare prompt as valid — a mis-pairing channel a mutex does not touch, since making an exchange's two steps adjacent never validates or drains the queue; and there is no bound on a slow-but-alive peer. The bare-prompt path has exactly **one** sighting in the wild — a single `FormatException` in the g0base arm — which is a sighting and not a rate | gkc scheduling it. Not a D1 gate |
| **at_auth `enrollment_submitter`: two defects from the #2179 review** | ✅ **BOTH FIXED 2026-08-25, on both branches** — see `git log` for `fix(at_auth): a builder failure no longer degrades a first enrollment`. ⚠️ This row read "neither fixed". It is kept because the two corrections below are what stop the review being re-applied as written, and because the at_client half of (b) is NOT on the at_auth carve branch: at_client's PQ secret sharing is not there at all. From srieteja's review of [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179), 2026-08-25. The other four items in that review are fixed and on both branches.<br><br>**(a) A PQ first enrollment can activate with no encapsulation key.** `_buildMetadata` writes the keys into a fresh `InMemoryAtKeysIo`, then wraps only the `builder(keysIo)` call in try/catch — it logs `severe` and returns null. `_handleFirstEnrollmentRequest` submits anyway, with no equivalent of the `isPq`/`keyPackage` guard the OTP path has. ⚠️ **The review calls this permanent capability loss and it is not**: that rested on a doc line saying `metadata.keyPackage` is written only by the request that creates the record, which the code itself retracted on 2026-08-19 — `KeyPackageMinting` rewrites it whole by the enrollment's own `enroll:update`. So it is degraded and recoverable. ⚠️ **The recommended fix cannot be written as stated**: `FirstEnrollmentRequest` has no `keyExchangeMode`, so there is no `isPq` on that path — the only signal is `metadataBuilder != null`.<br><br>**(b) `_handleAtEnrollmentRequest` never adopts what the builder filed.** `metadataBuilder` runs before the request so it can advertise a key package, so everything it files lands in the atSign-scope container; after `enrollmentIdFromServer` arrives only the flat APKAM keypair is re-filed under it. `_handleSelfEnrollmentRequest` and `onboard()` both call `adoptMaterials` and this path does not, so `keysForEnrollment(id)` never returns the key package's private half and it is left behind when the enrollment is retired.<br><br>⛔ **DO NOT apply the one-liner the review recommends.** Adding `adoptMaterials` at the `enrollmentIdFromServer` assignment breaks the PQ OTP flow: `enrollmentApkamSymmetricKeyResolver` → `keyPackageMaterial(keys)` is called with **no** enrollment id, so re-homing the material under one puts it where that resolver cannot see it. It looks obviously right, which is why it is written down here | gkc scheduling them. Neither blocks the 4.0.0-rc1 publish |
| **atServer: concurrent cross-atSign lookups are answered pairwise** | ✅ **DONE — diagnosed, fixed, verified on the real wire, and [at_server PR #2771](https://github.com/atsign-foundation/at_server/pull/2771) merged to at_server trunk on 2026-08-25** as merge commit `8f4a985a`. ⚠️ This cell read "what is owed is the MERGE … which is open", and before that carried its own copy of the measurements, saying "the branch is unpushed" while G0 said it was pushed. The table of measurements, the mechanism and the controls are in **G0** in [`## THE NEXT MOVE`](#the-next-move); this row is a pointer. ⚠️ **The merge does not rebuild `at_virtual_env:local`** — that tag is still whatever tree last built it | One rig action: rebuild the local virtualenv image from at_server trunk before the next live run that needs a fixed atServer |
| **several content keys alive for one `(nskeyOwner, namespace)` scope** | ⚠️ **A second defect, found while diagnosing G0 and separate from it.** One CK per writing enrollment per scope, cut at that enrollment's first write, no re-minting — three sender enrollments produced three CKs under `(bob, ns)` and three under `(alice, ns)`. `CurrentCkPointer` is the only thing meant to converge them and cannot as written: it is put **`localOnly`** into each enrollment's own store and reaches siblings only by sync, so cold enrollments writing together each read no pointer and each mint. `CkManager._resumeCurrent`'s "cutting a fresh one" fired **zero** times across the run. Sync dropped four of those pointer writes, logging `sync queue race: __ckcur.… missing persisted record; removing`.<br><br>**Why it matters beyond waste**: `rotateContentKey` supersedes only the CK in hand, so a rotation asking for forward secrecy leaves the other enrollments' keys live and their data readable — read from the source, **not run**. The measurements are in **G0** in [`## THE NEXT MOVE`](#the-next-move) | gkc ruling on whether one CK per enrollment per scope is the intent. If not: the pointer needs a remote-first write taken with an atomic verb or an interlock, and rotation needs to supersede every CK in scope |
| arm 2's UC-G1.15 read returns a content key | ⛔ **DIAGNOSED, FIXED and VERIFIED — it is an atServer defect with nothing PQ about it.** The substance, the measurements and the ruled-out list all live in **G0** in [`## THE NEXT MOVE`](#the-next-move); this row is a pointer and must not grow a second copy. ⚠️ It carried its own copy until 2026-08-25, and the two had already begun to disagree | Nothing here — G0 names what is owed |
| spike CI result read, and 12 commits behind | ✅ **Both workflows were `success` at `f304bf383`, 2026-08-24T12:38.** ⚠️ That is **12 commits behind head** and does not cover them — and in this repo docs are build inputs for the acceptance rail, so a plan edit can redden CI. Re-derive rather than trusting this line:<br>`gh run list --repo atsign-foundation/at_client_sdk --branch gkc-pq-d1-spike --workflow at_client_sdk.yaml --limit 1 --json headSha,conclusion` (and the same for `at_libraries.yaml`), then `git rev-list --count <headSha>..HEAD`<br><br>⚠️ This row read "spike CI result unseen" until 2026-08-24, when the answer had been sitting there for hours | A dispatch against head, once the branch stops moving |
| ~~app enrollments cannot be PQ-native~~ **FIXED 2026-08-24** | ✅ **DONE — do not rebuild it.** `AtEnrollmentRequest` now **requires** `signingAlgo` on both constructors (no default, so the compiler enumerated all 22 call sites across 6 packages), and also forwards `advertisedSigningKey`, which the base class declared and neither constructor passed on. `mintApkamKeyPair` is shared with onboarding so the two cannot drift. A non-rsa2048 enrolment files typed material under the enrollment id once the atServer names it — the flat copy STAYS, because one enrollment named by the keyfile's own `enrollmentId` resolves the same either way, and clearing it breaks the approval handshake, which needs the keypair and the symmetric key from one `toAtChops`. ⚠️ **Three things the API change alone did not fix, each found by a failing run rather than by reading:** `enroll` did not forward `signingAlgo` to `sendEnrollRequest`, so the parameter would have existed and done nothing; `enrollmentKeyPackageBuilder` was never told the algorithm, though it has always taken one; and the approval handshake never set `signingAlgoType`, so an ML-DSA enrolment PKAM'd under at_lookup's rsa2048 default. **Proven at two layers**: `tests/at_functional_test/test/pq_native_app_enrollment_test.dart` (an mldsa65 enrolment keeps its id, an rsa2048 one still retrofits — the control) and `tests/at_onboarding_cli_functional_tests/test/pq_native_enroll_test.dart` against a real VE, where the assertion that matters is that the enrolment **authenticates**: PKAM is record-authoritative, so a client holding ML-DSA material can only authenticate if the atServer's record says ML-DSA. ⛔ **What is NOT covered, and is separate**: every other atServer implementation would record an ML-DSA enrollment and then never authenticate it. That gap is pre-existing, independent of this fix, and lives on an unmerged branch | Nothing. `--posture` now reaches the enrolment in `at_activate enroll`, defaulted once at the `enroll`/`sendEnrollRequest` boundary where a caller has no rollout position to read |
| doc-set reduction, phases 3–5 | ⛔ **RULED BY gkc 2026-08-23, AFTER D1 — do not start it while D1 is open.** The end state is five files: `roadmap.md` (stale, needs a pass), `design.md`, `acceptance.md`, `decisions.md` (seriously shrunk) and this plan, which from now records **only what is still owed**. Phases 1 and 2 landed 2026-08-23 — the rejections and measurements became [rulings 116 and 117](decisions.md), and this plan went 1,878 → 1,075 lines. **What remains, and phase 3 MUST precede phase 4:** (3) trim the **117** ruling bodies in `detail/decisions.md` and inline them into `decisions.md` — they average **98 lines each**, and only **4 of 116** rulings are dead, so this is an editorial pass over live content rather than a purge of obsolete ones; (4) delete `detail/` and repoint or remove the **250** links into it (113 from this file, 63 acceptance, 62 design, 9 roadmap, 2 decisions, 1 seal-spec), rewriting `docs_structure_test.dart`, which enforces index↔body correspondence both ways and names `detail` 28 times — the rail changes in the SAME commit or CI goes red; (5) substitute explanations for the code that cites `detail/` paths, which is a standing rule violation as well as a broken link: ⚠️ **this item shrank on 2026-08-24** — it named `pq_rollout_matrix_test.dart` and a dartdoc in `tests/pq_matrix/current/lib/envelope_exchange.dart`, and both files are now deleted along with the rollout matrix. The README was rewritten in the same change and cites `detail/` no longer, so **item (5) is discharged**. Measured 2026-08-24: only two code files still name `detail/`, and neither is item (5)'s — `cross_cutting_test.dart` reads `detail/decisions.md` as a build input and this row already exempts it, and `docs_structure_test.dart` is the rail item (4) rewrites. Re-derive before acting: `git grep --untracked -n 'detail/' -- tests packages | grep -v '\.md:'`. `cross_cutting_test.dart` reads `detail/decisions.md` as a build input and is fine. ⚠️ **Phase 3 is where this goes wrong silently** — a ruling trimmed too far reads complete, and 112 of 116 rulings are still in force. Re-derive the size: `for f in docs/projects/pq/*.md docs/projects/pq/detail/*.md; do echo "$(grep -c '' $f) $f"; done` | Nothing but D1 closing. `detail/` is **19,141 lines against 7,231 live**, so this is most of the reduction |
| arm 1 vs arm 3 bucketing | ⛔ **A RULING IS OWED FROM gkc, and it is not a research task** — the measuring is done. [`acceptance.md`'s "Which rows arm 1 owes"](acceptance.md#which-rows-arm-1-owes) has both readings and the evidence; nothing here repeats them. In short: section 14's kind table says **3** transition rows, its arm-3 paragraph names **12**, and four rows — UC-B1.1, UC-B1.2, UC-B4.4, UC-A5.3 — are assigned to arm 1 and arm 3 at once, so the published "21 axis and consequence rows" double-counts. The two readings differ in what arm 1 *is*: under the count an arm-1 cell must drive a retrofit, so the arm stops being three static clients; under the prose a retrofit is an edge and belongs to arm 3. **Arm 1 as built sidesteps it** by covering only the 14 rows both derivations agree on, so nothing is blocked — but arm 3 cannot be scoped until this is settled, and the count table stays wrong until then | Nothing but the ruling. Arm 3 is the work it unblocks — arm 4 was cancelled 2026-08-24 |
| at_auth README | ⛔ **NOT a D1 gate, but it should ride [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179) with G1** — `packages/at_auth/README.md` describes `FileAtKeysIo` at `:144` and `:191` and **never mentions `at_auth_io.dart`**. The barrel split is the single most consumer-visible change in 4.0.0 — a `dart:io` consumer has to add one import — and the CHANGELOG says so at length while the README says nothing. No code miscompiles from it (the README shows no import statements at all), which is why it is not a gate. Found by the wrap-up docs sweep 2026-08-23 | Nothing. One or two sentences where `FileAtKeysIo` is first named |
| **acceptance audit** | ⛔ **D1 GATE — the gap is established and the design is ruled ([115](detail/decisions.md#115-the-acceptance-suite-is-4-arms-and-a-ledger-not-one-grid-2026-08-23)); what remains is the build** (gkc, 2026-08-23). **The rationale, in gkc's words:** *"we have literally hundreds of functional and end to end tests which cover the acceptance tests together. But there is no definitive place where it is easy to see the entirety of the pq project's acceptance tests being proven. The posture matrix test is the logical place to build test out."* So the problem is **legibility, not coverage**. Measured 2026-08-23, and **coverage was never the gap**: of the 68 live rows, 59 have live proof of some kind and 9 have none (12 LIVE_DIRECT, 43 LIVE_PARTIAL, 4 LIVE_INCIDENTAL, 9 NO_LIVE_PROOF). Only **29 of the 69** use-case ids are nameable anywhere in the live suite. ⚠️ **`tests/` holds 7 Dart packages** — the 4 live test packs plus `tests/pq_matrix/{current,published,scenario}`, the child processes the pair grid spawns. Count with `find tests -name pubspec.yaml`; a `tests/*/` glob returns 4 and reads as the whole answer. ⚠️ **The live corpus is 4 packs, not 2, and this row was scoped to 2 of them** — it read "**180** live test declarations across 65 files … a looser `grep -o 'test('` gives 225 and an indentation-anchored one 224". `tests/at_onboarding_cli_functional_tests` and `tests/at_onboarding_cli_functional_tests_proxy` are live packs as well, no citation reaches either, and the CLI one builds clients from a `PqPosture` in two arms — which makes it the best live evidence for UC-C1.6 and a second live proof of UC-A1.1. Across all 4 the strict matcher gives **194** and a multi-line-aware one **247**, and that gap is entirely declarations whose name sits on the next line, since an any-position same-line matcher also returns 194: `grep -rhoE "^[[:space:]]*test\([[:space:]]*'" tests/ --include='*.dart' | wc -l` against `perl -0777 -ne 'while (/(?<![A-Za-z0-9_])test\(\s*[\x27"]/gs){$n++} END{print "$n\n"}' $(find tests -name '*.dart')`. The posture matrix, the intended home, is **3** `test()` calls proving **2** use cases (UC-G1.14, UC-G1.15). ⚠️ **A citation count is not a coverage count** — an earlier pass here reported "27 of 68 have no live proof" when what it had measured was 27 with no live proof *cited from their acceptance scenario*. Do not restate it as coverage. For the record, the citation picture: of 68 scenarios, 2 cite the matrix, 39 cite some live test, 22 cite unit tests only, and 5 cite nothing and are themselves mock tests (UC-A3.1, UC-A3.4, UC-B3.1, UC-B3.2, UC-B5.2; UC-A3.1 runs against `MockAtClient()`). ⚠️ **And nothing checks the claims.** `catalogue_test.dart`'s five tests are all structural; none asks whether a scenario proves what its row asserts, and the `proves:` prose is matched against nothing ([14.19 item 29](detail/implementation-plan.md#1419-small-items-raised-2026-08-12-and-not-yet-acted-on)). The one known overclaim, item 36's three clauses of UC-A2.5/UC-A2.6, was found by hand. **Steps (1) and (2) are DISCHARGED, 2026-08-23** — they read "(1) for each of the 68, find where it is *actually* exercised live — searching the packs, not just reading citations; (2) decide which are genuinely **posture-dependent**, since several of A3's self-data cases may not vary by posture at all". Both are answered in [ruling 115](detail/decisions.md#115-the-acceptance-suite-is-4-arms-and-a-ledger-not-one-grid-2026-08-23), which carries the per-row map and the posture classification. gkc's A3 suspicion held: `PqPosture` declares 9 axes and only 6 vary across the stages, so 3 of the 5 A3 rows do not vary at all. **What is owed is step (3), and the shape is ruled rather than open**: only **3** of the 68 rows are shaped like a grid cell and **38** do not vary by posture, so the target is **4 arms and a generated ledger** — a 3-cell stage arm, the existing 4×4 pair grid, a transition arm for the edges the catalogue is full of, and a server-version arm — with 4 prerequisites named in the ruling, **2 of them now discharged**. ✅ This row said the sharpest was that "this pack has no `dart_test.yaml` and no `pq` tag (0 hits, against 9 in the e2e pack)" — built 2026-08-23: the tag is declared and 35 of its 55 test files carry it, chosen by the mechanisms they drive rather than their names, and `test/pq_tag_test.dart` re-derives the set so a new PQ test cannot sit outside it. ⛔ No `paths:` allowlist, deliberately — this pack's virtualenv is thrown away per run, so allowlisting would take the e2e pack's silent-omission risk with none of its benefit. ⚠️ **A fifth prerequisite was listed here and is now measured away**: this row said `PqPosture.pqActive` "currently breaks the monitor (`nskey_self_notify_live_test.dart:289`)". It does not. Equal-length interleaved arms across 2 fresh virtualenvs gave pqActive **16 of 18** monitors received against a control's **18 of 20**, with the atServer's log carrying `signingAlgo:mldsa65` authentications — both arms fail at the same rate with `AT0014`, so the failure is real but is **not posture-dependent**, and a pqActive cell is no worse off than a legacy one. ✅ **The ledger half of step (3) is BUILT, 2026-08-23** — `tool/acceptance_ledger.dart` plus the recording in `provenIn` and report emission in all three `runLocal.sh` runners; rendered from a real CI run's artefacts across both workflows the catalogue reads **63 PROVEN · 0 NOT-EXERCISED · 6 NO-LIVE-CITATION** across 69 rows (2026-08-23). ⚠️ This said “over all four report sources … **62 PROVEN · 1 NOT-EXERCISED** … the one gap being UC-B0.1's tagged legacy-server job”, which was a LOCAL render — UC-B0.1 is exactly the row a local run cannot reach and CI can, so the gap was in the runs supplied rather than in the coverage. ⛔ **It did NOT need `manifest.dart` moved**, which this row and ruling 115 both listed as its prerequisite. ✅ **Arm 1 is BUILT (2026-08-23)** — `tests/at_functional_test/test/pq_stage_arm_test.dart`, three enrollments of one atSign at one posture each, functional pack **186/186**, and **UC-C1.2 executed live for the first time**. It covers the 14 rows both derivations of the arm-1 set agree on rather than the contested 21 (see the `arm 1 vs arm 3 bucketing` row above), and it does **not** measure UC-C1.4, since `enrolAndAuthenticate` builds pq-mode enrollments only and every cell therefore holds `keyExchangeMode` constant. ✅ **Arms 2 and 3 are BUILT (2026-08-24)** — `tests/at_functional_test/test/pq_posture_grid_test.dart` is the grid (sender posture × receiver readiness, 9 enrollments over 2 atSigns, 7 `test()` calls) and `tests/at_functional_test/test/pq_advance_ladder_test.dart` is the ladder; `tests/pq_matrix/` was cut to `published/` and `scenario/`, which `tests/at_functional_test/test/pq_released_peer_test.dart` spawns to keep UC-G1.14 proven. **What step (3) still owes:** this clause read "**arms 2 and 3**", and before that "arms 2–4" until gkc cancelled arm 4 on 2026-08-24; the design of arms 2 and 3 was ruled the same day ([acceptance.md section 14](acceptance.md#the-arms)). ✅ **The clause level is BUILT (2026-08-24)** — ⚠️ this read "What is left is **the clause level** of the ledger, which is the half that does touch the live tests and is what turns "UC-A2.5 has 3 unproven clauses" into a computed fact rather than a footnote". It is now that computed fact: `clauses:` on `provenIn` pins a citation's THEN clauses by distinctive fragment (a fragment matching none or two is an error), `tool/acceptance_ledger.dart` renders the checklist, and `docs_structure_test.dart` guards the parser so a prose reformat cannot silently reduce every row to 0/0. Measured on the first render: **129 clauses across 68 live rows**, 7 pinned by a proven citation, UC-A2.4 **5 of 6** with the `pqSeal ver 0x03` clause uncovered, UC-A2.6 **0 of 3** with the revoked-E4 state gate confirmed absent from the cited live test (`grep -ci revoke` on it returns 0 against 53 for `enroll`). ⛔ It did NOT need `manifest.dart` moved to `lib/`. What is left is **the CI combining job**, left unwired because it needs `actions/download-artifact` and neither this repo nor at_server carries a trusted pin for it — CI uploads the inputs and rendering is local, which is now one command (`tools/acceptance_ledger.sh`) rather than the four hand-assembled ones this row's "rendered on demand" implied. ✅ **Two further gaps gkc named on 2026-08-23, both now BUILT.** They were: (a) nothing in the tree invoked the renderer — `git grep -P "dart\s+run\s+\S*acceptance_ledger"` returned exactly one hit, the usage comment inside the tool itself, so every ledger so far was assembled by hand from a scratch directory; and (b) nothing guarded the population wiring, with **0** tests reading `.github/workflows/` (positive control: the path string appears in 5 non-test files) and none reading the three `runLocal.sh`. What landed: **`tools/acceptance_ledger.sh`**, one command that runs the unit sources, optionally the live packs (`--with-live`), and renders; and **`packages/at_client/test/acceptance_ledger_wiring_test.dart`**, which asserts each of the four emitting jobs still carries its flag, that `unit_at_client` still sets `ACCEPTANCE_LEDGER`, that every emitter uploads with `always()`, and that each runner still gates the reporter on `ACCEPTANCE_REPORT`. ⚠️ **The rail's first version had a hole worth recording**: it asserted `contains('ACCEPTANCE_REPORT')` and `contains('--file-reporter json:')` separately, and a mutation making the guard read a *different* variable left both satisfied — the variable is named three times in each runner, so severing the coupling changed no substring. It now pins the coupling itself (`-n "${ACCEPTANCE_REPORT:-}"` and `--file-reporter json:${ACCEPTANCE_REPORT}`), which is the same weakness this section already records in `provenIn`, reproduced one layer up. Six mutations, each reddening its own assertion. ⚠️ **`provenIn` APPENDS to its citations file**, so two runs against one path double every citation and the ledger reports 278 for a catalogue of 139 — the driver deletes it rather than trusting the caller. **Re-derive**: `grep -rho 'UC-[ABCG][0-9]*\.[0-9]*[a-z]*' tests/at_functional_test/test tests/at_end2end_test/test | sort -u | wc -l` against the 69 in `acceptance.md` | Nothing |
| [14.43](detail/implementation-plan.md#1443-the-functional-suites-convergence-race) residue | ⛔ **NOT D1, and NOT PQ (gkc, 2026-08-23)** — recorded here only because this project has no other checked-in owed-work list. The behaviour is in `sync_service_impl.dart`, i.e. at_client's general sync, and no use case asserts sync ordering. The test-side fix landed in `ccf4987a4`. **A sync pull applies an OLDER server entry over NEWER local state** — the pull-side face of the versioning shape C fixed on the push side. Recorded when 14.43 closed and not designed since. Also open from that section: a driver-side `expect` failure on a protocol-green cell still dumps nothing | Nothing. The section carries the discriminators for any future red of the family |
| [14.45](detail/implementation-plan.md#1445-an-expired-key-the-client-cannot-delete-pins-it-in-a-hot-loop) residue | ⚠️ **In another repo: `at_persistence_secondary_server`.** Its keystore `get()` does not filter expired records, which is what let an expired key be read back and re-swept. Named here because this is where the work that found it lives; it does not land here | Separately owned. Not a D1 gate |
| [14.50](#1450-the-e2e-teardown-revokes-enrollments-belonging-to-other-runs) | ⛔ **NOT a D1 gate (gkc, 2026-08-23)** — e2e runs isolate locally and are serialized by structure on GitHub. ⚠️ Recorded because a reader will re-derive it: there is no top-level `concurrency:` key in any workflow, so `needs:` serializes the e2e jobs *within* a run and not across runs, and the incident that produced this row was cross-run. Stays as unblocked hygiene. **The e2e teardown revokes enrollments belonging to other runs.** `tests/at_end2end_test/test/enrollment_teardown.dart` revokes every approved enrollment on the shared `@ce2e1`-`@ce2e4` atSigns with `force: true`, not only the ones its own run created, so two overlapping CI runs tear down each other. **Diagnosed 2026-08-22** from the *other* run's log - the section carries the two timestamps 430 ms apart and the shared enrollment id. This row read *undiagnosed, and the newest CI run is red* until then. CI has since been green three times — 24/24 twice and 47/47 on [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179) — but every one of those windows was free of another run, so that is a rate and not a fix. Owed: a run-unique marker, so a teardown revokes only what its own run made | Nothing. Needs no permission and no publish, and it does not gate the at_auth carve |
| [14.18](#1418-the-remaining-d1-initial-development-sequence) | ⛔ **THIS IS D1's CRITICAL PATH** — D1 ends when the acceptance set passes and every rail is green, and the remaining carves and publishes are what gets there. Steps 32–34: the per-package release train. **Five of eight positions are through.** at_commons #2168, at_chops #2169, at_lookup #2174 and at_server_status #2177/#2178 are all **merged to trunk**; at_auth is [PR #2179](https://github.com/atsign-foundation/at_client_sdk/pull/2179), **open with CI 47/47 green**. Remaining to carve: **at_client, at_client_flutter, at_onboarding_cli**. Re-derive the whole picture rather than reading this cell — for each package compare `pubspec.yaml` on trunk, on this branch, and `curl -s https://pub.dev/api/packages/<pkg> \| python3 -c "import sys,json;print([v['version'] for v in json.load(sys.stdin)['versions']][-5:])"`. ⚠️ **Measured 2026-08-22 with a command that could not see a prerelease**, and it read "pub.dev has … at_lookup **3.6.1**, at_server_status **1.1.1**". Re-measured 2026-08-24 against the versions list: pub.dev has at_commons 5.16.0, at_chops 3.6.0, **at_lookup 3.7.0-rc1**, **at_server_status 1.1.2-rc1**, at_auth 3.3.0, at_client 3.14.0 | ⚠️ **Merged is not published, and only the publishes still gate anything.** ⚠️ This said at_lookup 3.7.0-rc1 and at_server_status 1.1.2-rc1 were "on trunk and **not on pub.dev**"; both were published by 2026-08-24, so the live gate is now **at_auth 4.0.0-rc1**. Every later package can carve and merge but none can publish until gkc publishes those. ⛔ **This cell used to say the at_auth PR's CI would fail to resolve until at_lookup published. That was wrong** — a pub workspace resolves siblings by path, so #2179 resolved and went green with at_lookup unpublished; the gate is on publishing, never on carving or merging. ⚠️ **at_client's `at_commons: ^5.15.0` floor is too low and will ship broken** — `notify_request_transformer.dart:154` calls `metadata.copy()`, which first exists in at_commons **5.16.0**. The same defect was found and fixed in at_auth during its carve; check every floor against first-use before carving at_client. ⚠️ **Owed at the real release, and it belongs to this row because it is the train's:** every constraint moved to an `-rc1` floor reverts to its stable form when these publish, or a stable release ships requiring a candidate. The rule is in [14.49.2](detail/implementation-plan.md#14492-every-remaining-package-publishes-as-a-release-candidate); re-derive the sites — `git grep -n 'rc1' -- 'packages/*/pubspec.yaml' 'tests/*/pubspec.yaml'` |
| [14.18](#1418-the-remaining-d1-initial-development-sequence) | **Step 20's rotation arm — STAYS IN D1** (gkc, 2026-08-23), which is why D1 now ends past the carve. Chain: publish at_auth 4.0.0 → add the `pending` value → build the arm | The publish, and a dedicated CRAM atSign. ⛔ **The "wait for the fleet" gate is CLOSED** — the two keyfile formats are disjoint for every file that exists (3.3.0 dispatches on `version` and never reaches its `keys` parse without one; a 4.0.0 typed document emits `version: 1` and no `keys`), and the one reachable conflict needs a 4.0.0 typed write into a keyfile a 3.3.0 app also opens, which cannot have happened: **no production `.atKeys` or keychain entry holds any PQ key material** (gkc, 2026-08-23) |
| [14.19](#1419-small-items-raised-2026-08-12-and-not-yet-acted-on) | ✅ **Item 36 — the one D1 gate here — is CLOSED 2026-08-24.** All three clauses are live-proven in `key_package_amendment_live_test.dart` and pinned so the ledger counts them; two of the three corrected the catalogue's own wording (there is no revocation check inside `enroll:update`, and an amendment joins rather than supersedes). ⚠️ This read "**TRIAGED 2026-08-23: only item 36 is a D1 gate**, and it is the one known case of the catalogue asserting clauses no live row proves" — it was, and it no longer is. Of the rest, three are not work at all (20, 21, 26 — each says so in its own text) and two belong elsewhere (14 is not PQ, 35 lands in `atGettingStarted`), leaving six that are open and not D1: 2, 4, 10, 28, 29, 34. Items 8, 23 and 30 were settled the same day. The headline count below overstates the work, which is why it keeps being re-argued — **17** open small items of 36 — the items are in `detail/`, none of them blocking. Re-derive rather than quoting: this row said 17 while the count was 10, then 15 while the count was 18, and the comment beside the command said 17 for two days after the row was fixed | Item 8 is the only one waiting on a ruling. Items 20 and 21 are examined-and-left, not work. Item 35 lands in `atGettingStarted`, not here |
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

**A lead from G0, NOT a diagnosis.** G0's mechanism is an atServer sharing one
outbound connection between unrelated relays, because `AtCacheManager` hands
`OutboundClientPool.get` a `DummyInboundConnection` and
`DummyInboundConnection.equals` answers true for any other one. The
**notification** path has the same shape in its own pool:
`NotifyConnectionPool.getOutboundClient` builds a fresh
`DummyInboundConnection()` per call and matches it the same way, so every
notification to a given destination atSign shares one `OutboundClient` too
(at_server `a0deee69`,
`packages/at_secondary_server/lib/src/notification/notify_connection_pool.dart`).

That is a shared mechanism, not a shared cause: this row's open question is
which *inbound* monitor the atServer treated as the subscriber, and nothing
shown so far reaches that from the outbound pool. ⚠️ **This said the two
rates "matching at 1 in 5", and they do not match**: the PQ harness measures
13-22 wrong of 50 — 26% to 44% — against this row's 1 of 5 pack runs and then
1 of 2. They were never the same figure, and a coincidence would not have been
evidence in any case. ⛔ **The G0 lead is DEAD, settled 2026-08-25.** This paragraph proposed
running the pack against a G0-fixed atServer as "the cheap check". It was run —
20 iterations against `at_virtual_env:g0fixed`, which carries the G0 fix — and
the timeout still occurs. The cause is unrelated to outbound pooling: the
atServer receives the ping before it has processed the receiving client's
`monitor:`, so nothing is subscribed and the notification reaches no connection.
The evidence, the margin measurement and the four candidate fixes are in **G3**
in [`## THE NEXT MOVE`](#the-next-move); this paragraph is a pointer.

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
#     dart:3.11.2 sh -c 'dart pub get && dart compile exe bin/main.dart -o secondary'
#   ... same for at_root_server ... copy both into
#   tools/build_virtual_environment/ve/contents/atsign/{root,secondary}/ ...
#   cd <dir>/tools/build_virtual_environment/ve && docker build -f ./Dockerfile -t <tag> .
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
# G0 fix, merged to at_server trunk on 2026-08-25 as `8f4a985a`. So the three
# live packs below were last measured against an atServer that still answers
# concurrent cross-atSign lookups pairwise. Rebuild the image from a named ref
# before re-measuring, and record which ref.

cd packages/at_client         && dart analyze lib test                     # exit 0, 422 info
cd packages/at_client         && dart format . -o none --set-exit-if-changed  # exit 0 — a CI gate
cd packages/at_client         && dart test --concurrency=1                 # 1546
cd packages/at_client         && dart test test/acceptance --concurrency=1 # 111
cd packages/at_auth           && dart analyze --fatal-warnings lib test    # exit 0, 158 info
cd packages/at_auth           && dart test --concurrency=1                 # 351
cd packages/at_lookup         && dart test --concurrency=1                 # 137
cd packages/at_commons        && dart test --concurrency=1                 # 518
cd packages/at_chops          && dart test --concurrency=1                 # 428
cd packages/at_onboarding_cli && dart test --concurrency=1                 # 54
cd tests/at_functional_test   && dart analyze test                         # exit 0, 246 info
cd tests/at_end2end_test      && dart analyze test                         # exit 0, 83 info
cd tests/at_onboarding_cli_functional_tests && dart analyze test           # exit 0, 15 info
VIRTUALENV_IMAGE=<a-ref-you-named> bash tests/at_functional_test/runLocal.sh              # 181 pass, 2 skipped, EXIT=0
#   ⚠️ RE-MEASURED 2026-08-25 at 93b239069 against at_virtual_env:g0fixed (a
#   G0-FIXED atServer, unlike every other figure in this block): same 181 pass,
#   2 skipped, and it carries the AtRpc and retrofit-test changes. The other
#   fifteen rows below/above still stand at bef991985 against a37e3e3b.
VIRTUALENV_IMAGE=<a-ref-you-named> bash tests/at_end2end_test/runLocal.sh                 # 54, EXIT=0
VIRTUALENV_IMAGE=<a-ref-you-named> bash tests/at_onboarding_cli_functional_tests/runLocal.sh  # 18, EXIT=0
# ✅ ALL SIXTEEN were re-measured together on 2026-08-25 at `bef991985`, against
# at_server `a37e3e3b`, so this block carries ONE date rather than a mix.
# The analyze counts are tallied by severity (`grep " - " | awk '{print $1}' |
# sort | uniq -c`) and are all `info`; the exit code is the verdict, never the
# count.
# ⚠️ Run the FUNCTIONAL pack twice before believing a red: 14.34 is a recorded
# intermittent in self_enrollment_retrofit_live_test.dart, and a single red is
# a rate observation rather than a regression. (2026-08-20 at 327cf4fa2 a first
# run was 173/174, the failure being 14.34.)
# ⚠️ The e2e default EXCLUDES the `legacy-server` arm (`-x legacy-server`, see
# that runner's own header), and that arm needs the PINNED PRE-PQ image or it
# stops testing the thing it exists for — the same image CI uses for it:
#   VIRTUALENV_IMAGE=atsigncompany/virtualenv:vip-p3.15.0 \
#     bash tests/at_end2end_test/runLocal.sh 26000 test/pq -t legacy-server
# ⚠️ The two skipped functional tests are deliberate — the G0 reproduction
# harnesses, which are run by hand. `--run-skipped` runs them and the pack goes
# red at the rate G0 records.
# ⚠️ Figures move for reasons worth knowing rather than growth: functional
# 169 → 174 (the matrix's cells, once its driver stopped asking the arms for
# stage names that no longer exist) → 183 (the acceptance arms and the G0
# harnesses), and both packs were RED at `c9de7d997` while every unit suite was
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
