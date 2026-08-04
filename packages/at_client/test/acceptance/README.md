# D1 acceptance burn-down

The executable form of [`docs/projects/pq/acceptance.md`](../../../../docs/projects/pq/acceptance.md).
Every use case in that catalogue has a test here, carrying its Given/When/Then
inline, skipped with the project that must land before it can go green.

**This is the progress bar for D1.** The catalogue is the target; this directory
is how far we've got.

> **The two counting faults audited 2026-08-03 were fixed 2026-08-04**, and
> eleven owed rows have since been written. The suite now reads **16 of 40**
> scenario rows green, up from 1 before the repair and 5 after it. (The runner's own count
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
> 3. **Eleven of those owed rows are now written**, leaving **5** owed plus
>    one re-classified as blocked. Four are
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
  *later* gate has none — RF-2c's e2e orchestration sits behind RF-SRV, RF-2b and
  R-1 on the B clusters, and unblocks nothing on its own.
- `catalogue_test.dart` is the one test here that is not skipped. It fails if a
  use case loses its scenario, if a blocker constant guards nothing, or if the
  counts below drift from the tests. Fix the count in the same PR.

## The catalogue

**40 rows** — the catalogue's 30 use cases become 31 scenarios (UC-A5.1 splits,
below), plus 9 cross-cutting invariants.

| Cluster                       | Scenarios                        | Blocked on   |
|-------------------------------|----------------------------------|--------------|
| A1 · PQ-native onboard        | A1.1                             | ON-1         |
| A2 · enrollments              | A2.1 ✅, A2.2 ✅, A2.3 ✅           | —            |
| A3 · self data                | A3.1 ✅, A3.2 ✅, A3.3 ✅, A3.4 ✅  | —            |
| A4 · shared data              | A4.1 ✅, A4.4 ✅, A4.2, A4.3       | owed         |
| A5 · rotation & revocation    | A5.1(a), A5.1(b), A5.2, A5.3     | B-2          |
| B0 · atServer prerequisite    | B0.1                             | RF-SRV       |
| B1 · retrofit                 | B1.1, B1.2, B1.3                 | RF-2b        |
| B2 · retirement & lockout     | B2.1, B2.2                       | RF-SRV       |
| B3 · mixed-PQ intra-atSign    | B3.1, B3.2                       | R-1          |
| B4 · mixed-PQ cross-atSign    | B4.1, B4.2, B4.3, B4.4           | R-1, ON-1    |
| B5 · retrofit edge cases      | B5.2 ✅, B5.3 ✅, B5.1             | root pull    |
| cross-cutting invariants      | 9 (5 ✅)                          | owed, R-1    |

Note that **A5.1 is split into (a) and (b)** here where the catalogue writes it
as one use case with two When/Then pairs. They are different levers with
different costs — CK rotation is O(1) coarse forward secrecy; nskey-keypair
rotation is O(n)-per-enrollment revocation and post-compromise security — and
conflating them is the specific mistake the plan warns against, so they burn down
separately.

## The shape of the problem this exposes

Sorting by blocker showed why D1 felt slow for so long: B-1 alone gated **11 of
the 40** rows, and no data-path row could go green until **B-1** (XL) and
**SS-4** (L–XL) landed, so the programme had no demonstrable increment in its
centre. Both have now landed, and owed rows gate **5 of the 40** — the same
rows, re-labelled from "waiting on a project" to "waiting on a test", and then
worked down. That is a smaller problem with a different owner, and it is the
honest description of where the burn-down now stands. What remains owed is
almost entirely *live* work: **4 of the 5** need a running atServer (2
functional, 2 e2e), and exactly one is a unit row. That is not a coincidence —
the rows writable against mocked state were the ones written first, so the
residual is by construction the part that needs infrastructure.

**UC-B5.1 is blocked, not owed.** The substrate's request/answer round trip is
complete, on by default and unit-covered — but `requestSecret` has zero call
sites in `lib/`, so nothing ever asks for the signing root, and
`PqSigningRoot.mintIfAbsent` says so in its own dartdoc. The root carries no
namespace, so it is excluded from the `enroll:listns` fan-out by construction
and the pull is its only remaining route. Labelling that "owed a test" would
claim the code is finished, which is the exact conflation this burn-down was
repaired to remove. See
[`decisions.md` section 30](../../../../docs/projects/pq/decisions.md).

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
