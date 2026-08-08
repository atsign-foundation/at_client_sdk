# D1 acceptance burn-down

The executable form of [`docs/projects/pq/acceptance.md`](../../../../docs/projects/pq/acceptance.md).
Every use case in that catalogue has a test here, carrying its Given/When/Then
inline — asserted directly, or cited to the live test that asserts it.

**This is the progress bar for D1.** The catalogue is the target; this directory
is how far we've got.

> **The two counting faults audited 2026-08-03 were fixed 2026-08-04**, and
> all seventeen owed rows are now discharged. R-1 then landed its
> scheme-negotiation rows — and the 2026-08-05 re-examination **removed the
> marker/negotiation machinery** (`decisions.md` 36), so the B3, B4 and
> readiness-invariant rows were re-proven against the app-decides model: the
> two-release ladder asserted directly, the B4 rows cited to the live
> cold-start and data-path tests. The retrofit rows followed on 2026-08-05
> (`decisions.md` 45): the B1 trio and both B2 rows are now cited to live e2e
> coverage. **B-2 landed 2026-08-06** (`decisions.md` 47), taking the four A5
> rotation and revocation rows with it, and **KE-1 landed 2026-08-07**
> (`decisions.md` 50), *adding* five rows — A2.4, A3.5, A4.5, A4.6, A4.7 — all
> green on arrival, because the project that added them is the project that
> proved them. **ON-1's client half landed 2026-08-08**, taking **UC-A1.1**
> with it: a CRAM activation is PQ-native, proven live — the ML-DSA-65 APKAM
> re-authenticates on a fresh connection with no RSA APKAM in existence, so
> the atServer verified an ML-DSA PKAM signature against the enrollment
> activation created. **UC-B4.2 and UC-B0.1 followed the same day**, taking the
> suite to **45 of 45** — every row green, up from 1 before the repair and 5
> after it. (The runner's own count
> is higher — it includes `catalogue_test.dart`'s three guards, which are not
> scenarios. That gap is why the old "4 of 43" figure was itself wrong in the
> optimistic direction while everything else under-counted.)
>
> 1. **A row proven in another package can now be claimed.** `provenIn`
>    (`proven_elsewhere.dart`) cites the live test that establishes a row and
>    asserts it is still there. It does not re-run the proof — this suite runs
>    inside `at_client`'s unit tests and can never reach the functional or e2e
>    packages — but a renamed or deleted live test now turns the citing row red
>    instead of letting its evidence vanish unnoticed.
> 2. **`blockers.dart` no longer names landed projects.** SS-2, SS-4 and B-1
>    have landed, so their 21 rows are no longer *blocked*. Most were not yet
>    *proven* either, and that is a different backlog: they carry
>    `owed: scenario not yet written`. Conflating "the project owes this" with
>    "we owe this a test" is what made the old number misleading in both
>    directions at once.
> 3. **All seventeen are now discharged**, leaving **0** owed. Fifteen were
>    written or cited; **UC-A3.2** turned out to be a catalogue error rather
>    than a missing test, and **UC-B5.1** turned out to need production code
>    that did not exist. Four of the fifteen are
>    cross-cutting invariants — reads-are-universal, appMetadata-is-authoritative,
>    the published nskey's fetchable-not-enumerable property (cited, not
>    duplicated: `underscore_public_key_hiding_test` already proves it with
>    controls), and the performance budget, which needed
>    [`decisions.md` section 28](../../../../docs/projects/pq/decisions.md)
>    written first: the B-1 harness had been run when it was built, but its
>    numbers were never recorded, so the row was asking for a budget that
>    existed nowhere a reader could find it. Then UC-A3.4 and UC-B5.2 as unit
>    rows, and two more proven live once a functional test for the immutable
>    signing-root create existed: the cross-cutting create-once invariant and
>    UC-B5.3's race. UC-A3.2 followed once its catalogue text was corrected —
>    it had described a mint trigger that was never built — and then UC-A2.2
>    and UC-A2.3, the latter proven at two layers at once because the row
>    insists the namespace boundary holds at the atServer and not by a
>    client-side refusal alone. UC-B5.1 went the other way: picking it up
>    showed its headline mechanism is not built, so it is now *blocked* rather
>    than owed — see below.

> **The number is still a floor, and now says why.** A row is green only when
> something in this repo asserts it — inline, or by citation.

```
dart test test/acceptance --concurrency=1
```

## Why this exists

The catalogue is thorough and maps cleanly to projects, but until now it had
never touched the codebase — no `UC-` reference existed outside `docs/`. A
scenario you cannot run is a scenario nobody is burning down. Making the
catalogue executable-but-skipped turns an 800-line document into a count.

## How to work with it

- **Picking up a project?** Grep its id in `blockers.dart` to see exactly which
  scenarios you owe. That list is your definition of done.
- **Landing a project?** Delete its constant from `blockers.dart`; the analyzer
  then points at every scenario now owed an implementation.
- **A scenario is green** when its `fail('not implemented')` is replaced by real
  assertions and its `skip:` is gone. Nothing else counts as done.
- Some scenarios finally belong in `tests/at_functional_test` or
  `tests/at_end2end_test` (separate packages). The `blockers.dart` constant names
  the target layer. Keep the placeholder here until the real assertion exists
  somewhere, so the count stays honest.
- A constant names a scenario's **first** gate, so a project that is only ever a
  *later* gate has none. The target moves: RF-2c's e2e rows sat behind R-1,
  RF-2b and RF-SRV until all three landed (2026-08-05), at which point RF-2c
  became their first gate — and, since its only remaining deliverable IS those
  rows, they became `owed:` rather than `blocked:`.
- `catalogue_test.dart` is the one test here that is not skipped. It fails if a
  use case loses its scenario, if a blocker constant guards nothing, or if the
  counts below drift from the tests. Fix the count in the same PR.

## The catalogue

**45 rows** — the catalogue's 35 use cases become 36 scenarios (UC-A5.1 splits,
below), plus 9 cross-cutting invariants.

| Cluster                       | Scenarios                        | Blocked on   |
|-------------------------------|----------------------------------|--------------|
| A1 · PQ-native onboard        | A1.1 ✅                           | —            |
| A2 · enrollments              | A2.1 ✅, A2.2 ✅, A2.3 ✅, A2.4 ✅  | —            |
| A3 · self data                | A3.1 ✅, A3.2 ✅, A3.3 ✅, A3.4 ✅, A3.5 ✅ | —      |
| A4 · shared data              | A4.1 ✅, A4.2 ✅, A4.3 ✅, A4.4 ✅, A4.5 ✅, A4.6 ✅, A4.7 ✅ | — |
| A5 · rotation & revocation    | A5.1(a) ✅, A5.1(b) ✅, A5.2 ✅, A5.3 ✅ | —            |
| B0 · atServer prerequisite    | B0.1 ✅                           | —            |
| B1 · retrofit                 | B1.1 ✅, B1.2 ✅, B1.3 ✅           | —            |
| B2 · retirement & lockout     | B2.1 ✅, B2.2 ✅                    | —            |
| B3 · mixed-PQ intra-atSign    | B3.1 ✅, B3.2 ✅                    | —            |
| B4 · mixed-PQ cross-atSign    | B4.1 ✅, B4.2 ✅, B4.3 ✅, B4.4 ✅   | —            |
| B5 · retrofit edge cases      | B5.1 ✅, B5.2 ✅, B5.3 ✅           | —            |
| cross-cutting invariants      | 9 (9 ✅)                          | —            |

Note that **A5.1 is split into (a) and (b)** here where the catalogue writes it
as one use case with two When/Then pairs. They are different levers with
different costs — CK rotation is O(1) coarse forward secrecy; nskey-keypair
rotation is O(n)-per-enrollment revocation and post-compromise security — and
conflating them is the specific mistake the plan warns against, so they burn down
separately.

## The shape of the problem this exposes

Sorting by blocker showed why D1 felt slow for so long: B-1 alone gated **11 of
the 45** rows, and no data-path row could go green until **B-1** (XL) and
**SS-4** (L–XL) landed, so the programme had no demonstrable increment in its
centre. Both have now landed, their rows were re-labelled from "waiting on a project"
to "waiting on a test", and that backlog has since been **worked to zero**.

**0 of the 45** rows are skipped — every scenario in the catalogue is now
either asserted here or cited to a live test that asserts it.

**UC-B0.1 was the last, and it went green 2026-08-08.** It had carried the
label `blocked: RF-SRV` long after RF-SRV's server half landed, because nobody
re-read it; what actually blocked it was the *harness*. The row needs an
atServer **without** the retrofit verbs to abort against, and no image here
provided one — until `atsigncompany/virtualenv:vip-p3.15.0`, a release-pinned
tag that stays pre-PQ for good (`vip` itself gains post-quantum support and
stops being a legacy atServer). The row is proven against that pin, in
`tests/at_end2end_test/test/pq/legacy_server_abort_test.dart`, tagged
`legacy-server` so the ordinary PQ job excludes it.

Running it found a real defect, which is the argument for having written it
rather than waived it: the abort was clean but left the enrollment request it
had just created sitting `pending` on the server, one per retry. at_auth now
denies it on the way out, and where it cannot — a scoped parent has no
`__manage` — the refusal says so rather than implying the server was left
clean.

**UC-B4.2 went green 2026-08-08**, and how it did is worth keeping. It was
labelled `blocked: ON-1 · layer: tests/at_end2end_test` on the reasoning that
only two atSigns can show the inbound direction — true, but the layer was wrong
twice over: `tests/at_end2end_test` runs in CI against long-lived cicd atSigns
and so can never CRAM-activate anything, and its initializer dereferences
`apkamPublicKey!`, which is null in every PQ-native keyfile. The functional pack
runs against the virtualenv container in CI as well as locally, and drives two
atSigns in one file. The row is proven there, by
`tests/at_functional_test/test/pq_legacy_interop_live_test.dart`, which mints
all three atSigns it needs — a pre-PQ one, a PQ-native one, and a PQ-native one
that opted out of legacy material — so "legacy peer" is asserted rather than
borrowed from a demo atSign some other file has already retrofitted.

Nothing is *owed a test*: the last such rows, the B1 trio, were
discharged 2026-08-05 by the retrofit e2e coverage. The guard asserts
the skipped total, which is what it can measure; the blocked/owed split lives
in `blockers.dart`'s labels and in this sentence. That is a much more
useful ledger than the one this started as: grep a project id and you get
exactly the scenarios it will turn green.

Four of the seventeen needed something other than a test to discharge them,
which is the part worth remembering. Two were documentation problems in
opposite directions — UC-A3.2 described a mint trigger that was never built,
while UC-B5.1 described a pull mechanism that *should* exist and did not. One
needed a measured budget recorded before it could assert anything. And one
needed a production fix underneath the fix: UC-B5.1 could not be driven at all
until `AtClientImpl`'s instance cache was keyed by `(atSign, enrollmentId)`.

**UC-B5.1 needed production code and a cache fix, not just a test.** Its
headline mechanism — `requestSecret` as the route to the signing root — had no
initiator at all, and once one existed it still could not be driven, because
`AtClientImpl` cached client instances by atSign alone: every "enrollment" in a
test was `identical` to the approver's client, so the request was a client
asking itself over a connection carrying no enrollment id. Keying that cache by
`(atSign, enrollmentId)` — the `(owner, id)` rule the rest of the codebase
already follows — unblocked it, and the row is now proven between two genuinely
distinct approved enrollments. See
[`decisions.md` sections 30-32](../../../../docs/projects/pq/decisions.md).

**UC-A3.2 was the one row whose catalogue text was wrong rather than untested.**
Its WHEN described a mint triggered by the first put — never built, and in
direct contradiction with UC-A3.3, which requires a cold-namespace write to fail
and is proven live. Ruled 2026-08-04 that the code was right; `acceptance.md`
4.2 now describes start-time seeding, and the row is proven. See
[`decisions.md` section 29](../../../../docs/projects/pq/decisions.md).
(The rows rooted on RF-SRV — B0 and B2 — never depended on either, and can
still move in parallel.)

Two things followed, both now recorded in
[`implementation-plan.md`](../../../../docs/projects/pq/implementation-plan.md):
UC-A3.1 as a walking skeleton, reachable with the nskey private supplied by a
test fixture instead of the substrate; and splitting B-1 into the ordered chunks
`B-1a`…`B-1e`, each a reviewable PR whose done-condition is a named scenario
turning green. The plan holds the chunk table and the rationale — this README
follows the plan, it does not replace it.
