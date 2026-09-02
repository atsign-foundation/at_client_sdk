# Roadmap: BDD for the acceptance catalogue, then the core packs, then the other SDKs

**Status:** feasibility study, 2026-09-02. Nothing is built. **Ruled the same day:
the work starts after D1 closes, then as soon as possible** ([`decisions.md` R1](decisions.md#r1-timing-relative-to-d1-after-d1-then-as-soon-as-possible-gkc-2026-09-02)).
No backlog row exists anywhere yet; where one should live is still an open question.
This file records the goal as Gary stated it, the document map, the phasing the study
proposes for the near-term goal, and the longer trajectory the near-term goal is the
first step of.

## The brief

Gary, 2026-09-02, quoted because it is written nowhere else in the repo or in memory:
*"we have docs/projects/pq/acceptance.md and we have a whole bunch of tests, and then
we have mechanisms which allow us to tell how many of the clauses in acceptance.md are
proven in tests. What I would like to do is move all of that to a BDD approach, using
something like bdd_framework, with a view to ultimately having all the core test packs
in BDD format, and used across our various SDK implementations with at_java (which
already uses a BDD style for much of its testing) being next."*

The near-term goal is the PQ catalogue. The study's answer to the framework question
is that `bdd_framework` cannot be used here (Flutter-only, and it exports Gherkin
rather than reading it), that no Dart BDD runner on pub.dev fits, and that the
Cucumber project now publishes an official Dart Gherkin *parser* on which a small
in-tree runner can stand ([`analysis.md` section 2](analysis.md#2-the-dart-bdd-packages-on-pubdev)).

## Document map

| Doc | What lives there |
|---|---|
| **roadmap.md** (this doc) | the brief, the goal and non-goals, the proposed phases with done-conditions and effort, the longer trajectory |
| [`analysis.md`](analysis.md) | what exists today (the catalogue, the citation model, the ledger, the rails, the fixtures), the Dart BDD packages, the Cucumber facts a shared corpus depends on, at_java, the other SDKs, the translation sample; every figure with its command |
| [`design.md`](design.md) | the runner, step definitions and the World, layout and routing, tags, the measure and how it is carried across, what happens to `acceptance.md` and the rails, at_java, the probes, the risks, and what was considered and not taken |
| [`decisions.md`](decisions.md) | what the facts settle, what this proposal chooses and the alternatives it rejects, and the questions only Gary can answer, each with options |
| [`samples/`](samples/) | 11 hand-translated rows as draft `.feature` files, with a README saying why each was picked |

## Goal and non-goals

The goal is one executable corpus of `.feature` files that states what the SDK must do
in the catalogue's domain language, is run by `dart test` in the packages that hold
the fixtures, feeds the acceptance ledger with a clause-level measure at least as
strict as today's, and can be loaded unchanged by at_java's Cucumber-JVM, and later by
the other SDKs, each binding the same text to its own code.

Not goals of the near-term work: rewriting at_java's seven API-language features
(they stay as its own API suite); publishing the corpus as a package (a directory
becomes a package with one move, when a second SDK binds a PQ step); implementing
post-quantum support in at_java (it has none, so it can bind the PQ features only
after that lands); translating the non-PQ packs (uncharacterised, and a scope question
in [`decisions.md`](decisions.md)).

## Phases for the near-term goal

Every phase has a done-condition a rail can check. Effort figures are engineer-weeks
and are **hypotheses with their arithmetic shown**, not measurements; the first
cluster is where the rates get measured and the rest re-estimated. The work starts
after D1 closes (ruled 2026-09-02); the acceptance mechanism being replaced lives on
`gkc-pq-d1-spike` today and reaches trunk with D1's carves, so the migration runs
against trunk.

### Phase 0: the runner, and nothing else

`tools/at_bdd` (about 250 lines of `lib/`, about 200 of tests, a fixture feature
exercising Background, Outline rows including a duplicate title, a data table, a doc
string, tags at every level, a step-less `@withdrawn` scenario, an `@unprovable`
scenario, an undefined step, an ambiguous step, and a failure followed by skipped
steps), added to the root `workspace:` list; `features/README.md` and an empty
`features/pq/`; a CI job running the package's own tests. Nothing reads `features/`
yet, so no existing rail changes colour.

Done when the package's own `dart test --concurrency=1 --file-reporter json:` pins the
emitted names, tags, `url` basename, `line` values, skip reasons and `##gherkin` lines
against production output, and `dart analyze --fatal-warnings` is clean. About 1 week.
The 6 probes in [`design.md` section 9](design.md#9-probes-to-run-before-anything-is-built)
run before this phase starts, since two of them can change its shape.

### Phase 1: ledger, rails and wiring

The ledger changes in [`design.md` section 6.5](design.md#65-what-the-ledger-does)
with fixtures; the roster, frozen-sum and per-row-floor guards in `manifest.dart` and
`catalogue_test.dart`, green against an empty corpus (98 Markdown rows, 0 Gherkin);
the five hosts' `dart_test.yaml` tag declarations and dev_dependency; the per-host
binding rail (vacuously green); `--file-reporter json:` and an `if: always()` upload
added to the CLI pack's CI job and to the wiring test's `emittingJobs`;
`tools/acceptance_ledger.sh --features`. No row moves.

Done when `acceptance_ledger_test.dart` renders a fixture holding legacy citations,
step-log events and a skipped test into both tables with the right verdicts, the
wiring test passes with six emitting jobs, and `unit_at_client` is green with the new
guards. About 1.5 weeks.

### Phase 2: the first cluster, A1 and A2

Seven rows (UC-A1.1, UC-A2.1 to UC-A2.6), all `@live` with in-process supplements,
one live pack, none in the exemption or debt maps, and the two translations already
drafted in [`samples/`](samples/). It meets the hardest fixture question (one-shot
CRAM activation in UC-A1.1) while the scope is seven rows, and A2 seeds the most
reused When (an enrollment approved for a scoped namespace), which A3 to A5, B1 and G3
reuse.

Contents: `features/pq/a1_onboard.feature` and `a2_enrollments.feature`; the
functional pack's World and step files and two drivers; the at_client in-process
steps; the fixture helpers the steps need
([`design.md` section 3.3](design.md#33-fixtures-that-do-not-exist-yet)); deletion
of `a1_onboard_test.dart` and `a2_enrollment_test.dart` and their `scenarioFiles`
entries; the seven rows' Then bullets replaced by a pointer under each heading; the
frozen sum, the floors and the roster moved by exactly what the guards print; the
cited live tests that consume one-shot atSigns retired or promoted per the rule in
that section; the two orphan `.feature` files dealt with per
[`decisions.md`](decisions.md).

Done when the functional pack's `runLocal.sh` shows every `@live` A1 and A2 scenario
passed, `packages/at_client` is green with the edited pins and the roster reads 91
Markdown plus 7 Gherkin, and `tools/acceptance_ledger.sh --with-live` renders the
seven rows with every outcome step passed, `NOT-EXERCISED = 0`, `MISATTRIBUTED = 0`.
About 1.5 weeks. **Then measure**: the Then-phrasing reuse ratio over the two files,
the days per row, and the clause count the cluster removed; write them into the plan
row and re-estimate phase 3 from them.

### Phase 3: the remaining clusters, one PR per section

In this order and for these reasons: **A3 to A5** (18 rows; brings the in-process
host to scale, the e2e pack for the cross-atSign rows, and the first `@live-owed`
declarations); **B0 to B5** (28 rows; B0.1 is the `legacy-server` special case run
alone against the pinned image; B5 is the largest section at 12 rows); **G1 to G3**
(38 rows; the in-process-heavy cluster holding 23 of the 37 owed rows and the CLI
pack's retrofit rows); **C1 and section 13** (7 rows including the withdrawn UC-C1.3,
and the invariants feature). Each PR repeats phase 2's done-condition with its own
numbers; the roster line is the progress bar.

Effort basis: 98 rows; the sample extrapolates to 560 to 650 distinct step
definitions, 5.7 to 6.6 new per row. At one engineer-day per row for the first 25
(0.25 day of feature text, 0.75 day binding six definitions and running them live)
and 0.6 day per row for the remaining 73 if Then reuse rises to 2.0 as the
extrapolation assumes, rows cost 69 days, about 14 weeks; if reuse does not appear,
98 days, about 20 weeks. Fixture gaps, costed one by one, about 2 weeks.

### Phase 4: retire the bridge

When the last Markdown row moves: delete `proven_elsewhere.dart`, the clause parser
and its regexes, the citations file and `ACCEPTANCE_LEDGER`, `blockers.dart`, the
status table and headline and the rails that read them, the cited-file nameability
rail, the frozen-sum snapshots and the two old constants; write the last `BURN-DOWN`
line beside the first full `OUTCOME STEPS` line in `acceptance.md`; rewrite section 14
to describe the runner. About 0.5 week.

### at_java, in parallel from phase 2

The pom changes in [`design.md` section 8](design.md#8-at_java-and-the-other-sdks):
a pinned fetch of the corpus, a sibling `shared-features` classpath directory, a
second suite class with its own glue package and a `@java` filter, so at_java's build
parses the corpus and its 39 scenarios stay green. About 1 week, excluding any PQ
implementation in Java. The Cucumber Messages emitter on the Dart side (about 80
lines) lands when at_java binds its first PQ step, so one ledger can read both runs.

### The total

3 weeks of mechanism (phases 0, 1 and 4) + 2 weeks of fixtures + 14 to 20 weeks of
rows = **19 to 25 engineer-weeks** for the PQ catalogue, plus 1 for the at_java load
route. The two figures this rests on, one day per row and reuse rising to 2.0, are
re-measured after phase 2. Two independent re-summations of the three panel designs
disagreed with each other and with the designs' own totals, which is the reason the
arithmetic is written out here rather than the result alone.

## What is owed, and where the list should live

One thing is owed: the migration, after D1 closes (ruled 2026-09-02). It has no row
anywhere yet, because where the row lives is Q3 in [`decisions.md`](decisions.md).
The PQ plan already records that the ONE-list rule has a second project beside it
(`docs/projects/wasm/`) and names two ways out: fold open items into the PQ `## TODO`
bands, or a `docs/projects/` index naming every live project. Under the PQ plan's own
bucket definitions an after-D1 item is P3 by definition, so the fold option is a single
P3 row pointing here. This project does not add a table of its own until Q3 is ruled.

## The longer trajectory

1. **The PQ catalogue** (this roadmap).
2. **The non-PQ packs.** 21 functional files without the `pq` tag, 10 allowlisted e2e
   files against the long-lived atSigns (a fourth isolation model, with a durable-write
   guard), 6 CLI files and the proxy pack. None is characterised yet; the same runner
   serves them, and the first question is whether they migrate or whether new tests
   are Gherkin-first from a date ([`decisions.md`](decisions.md)).
3. **at_java binds.** The load route lands early so the corpus is parsed on every
   at_java build; the non-PQ features can be bound as soon as they exist in domain
   language; the PQ features wait for PQ in Java (BouncyCastle 1.84 on its classpath
   already carries ML-DSA, ML-KEM, X-Wing and HPKE; the wiring does not exist).
4. **The corpus becomes a package.** When a second SDK binds a PQ step, `features/`
   is published the way the Compatibility Kit is, features as data per platform
   package manager, steps per language, the message stream as the contract.
5. **The other SDKs.** at_python (`pytest-bdd`), at_rust (`cucumber-rs`), at_go
   (`godog`), at_c (`cucumber-cpp` with Ruby in the loop, or a C++20 runner); the
   converged infrastructure they already share is the `dev_env` virtualenv image and
   the `at_demo_data` keys.
6. **The atSDK specification.** at_protocol's 2024 decision promised one based on the
   Dart and Java implementations and nothing delivered it; an executable corpus bound by
   two SDKs is a candidate, and the record of that belongs in at_protocol.

## Re-derive rather than quote

```bash
cd packages/at_client && dart test test/acceptance/catalogue_test.dart --concurrency=1   # BURN-DOWN and REACHABLE
git grep -cP '^#{2,4} +(?:[\d.]+ +)?UC-[ABCG]\d+\.\d+[a-z]? +— ' -- docs/projects/pq/acceptance.md   # rows
ls tests/at_functional_test/test/*_test.dart | wc -l; grep -l "^@Tags(\['pq'" tests/at_functional_test/test/*_test.dart | wc -l   # non-PQ = difference
find . -name '*.feature' -not -path './.git/*' -not -path './docs/*'                       # feature files outside the samples
```
