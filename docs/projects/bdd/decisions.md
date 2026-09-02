# Decisions: what the facts settle, what the proposal chooses, and what is Gary's to rule

**Status:** 2026-09-02, one ruling (the timing). Four kinds of entry, kept apart
because they carry different weight: conclusions the measured facts force, rulings
Gary has made, choices this proposal makes among live alternatives (recorded with the
alternative, so a rejected design is not re-proposed from scratch), and questions only
Gary can answer, each with options. A ruling gets a date and moves its question out of
the last list and into the second.

## 1. Settled by the facts

Each of these was checked by an independent verifier against the primary source
([`analysis.md` section 8](analysis.md#8-how-this-analysis-was-produced)).

- **`bdd_framework` is out.** Flutter-required in all 15 published versions, exports
  Gherkin rather than reading it, no tags API, counter-prefixed test names, and a
  cross-SDK flow that runs backwards.
- **No Dart BDD runner on pub.dev fits.** The two pure-Dart runners that read
  `.feature` files run outside `package:test` and are dormant; the codegen tool emits
  Flutter tests; the two young packages that emit a `test()` per scenario have hand
  parsers without `Rule` or without tags.
- **`cucumber_gherkin` 42.0.1 is the parser.** Official, `cucumber.io`-published,
  generated from the grammar Cucumber-JVM's parser is generated from, parser only. The
  runner is this repo's code. It resolves beside `test ^1.25` on the local SDK and CI's
  channels sit above its 3.8 floor.
- **Scenarios must be `package:test` tests**, or the ledger cannot see them.
- **The row id cannot be a `package:test` tag** (a dot is illegal); it travels in the
  test name. JUnit and Cucumber accept `UC-A1.1`.
- **`location:` must name the feature file**, or every scenario reports the runner
  library's path as its `url` and the ledger's basename join collapses.
- **Per-step results as `print` events need no CI change**; a side file needs edits in
  five jobs and a second artefact.
- **The CLI pack's CI job emits nothing** and must gain `--file-reporter json:` and an
  upload, or every `@cli` step reads `NOT-EXERCISED` from CI for ever.
- **at_java binds PQ only after implementing PQ**, and under Cucumber-JVM strict mode
  the corpus must land in a sibling classpath directory read by a second suite with its
  own glue, or a `not @pq` filter; copying it into `features/` turns the 39-scenario
  suite red.
- **Two retrofit rows need the zero-grace `@eve🛠` secondary** that only the e2e
  virtualenv provisions; they cannot be routed to the functional pack.
- **`pq_tag_test` is bidirectional and non-recursive**, so a driver file carrying the
  `pq` tag without matching its symbol regex is red; the first functional driver has to
  carry a marker or widen the regex, and say which.

## 2. Rulings

### R1. Timing relative to D1: after D1, then as soon as possible (gkc, 2026-09-02)

In Gary's words: *"complete D1 then do this as soon as possible afterwards while it's
still fresh."* Of the four options that were put (runner and first cluster during D1;
runner during D1 and rows after; everything after; the migration as the new definition
of D1 done), this is the third. Consequences: no phase starts while D1 is open, the
runner included; the PQ plan's ruling that doc-set surgery on `acceptance.md` waits for
D1 is respected rather than excepted; under the PQ plan's own bucket definitions the
whole migration is a P3 item by definition, which is a statement about sequence and
not about importance; and the mechanism being replaced will by then have reached
trunk with D1's carves, so the migration runs against trunk, not against the spike.
The question that stays open is where the owed row lives (Q3 below).

## 3. Choices this proposal makes, with the alternative

| Choice | Alternative not taken, and why |
|---|---|
| A thin in-tree runner on `cucumber_gherkin` (`tools/at_bdd`) | `bdd_widget_test` with a pure-Dart shim: a build step in every host, Dart expressions in feature text, and a parser rewrite in flight that renames the titles a ledger keys on |
| Features at `features/pq/` in this repo, a directory | a published `at_sdk_spec` package now: every wording change becomes a version bump and a publish, and a bump is Gary's call; right pattern for the day a second SDK binds a PQ step |
| Exemption, debt and unprovable reasons stay in `manifest.dart` maps; features carry tags only | reasons as scenario descriptions in the shared file: Dart test names and this repo's projects in front of every SDK's engineer, and no rails over them yet |
| The figure carried across by a frozen sum (`parsed + Σ snapshots == 227, 90, 232`, both directions) plus a per-row server-proven floor plus the 98-id roster | side-by-side worlds only: exact row identity but no guard on the clause figure, and a live clause could become an `@in-process` scenario with nothing red |
| The binding's location derived from the registering stack frame (and cross-checked with the reporter's `suite` path) | a `host` string typed by the driver's author: a self-report the ledger would believe, which the rule that a tag is a claim forbids |
| Routing tags are product conditions (`@cli`, `@legacy-server`, `@zero-grace`) | Dart package names (`@e2e-only`, `@at-auth`) in the shared file: this repo's layout in a spec other SDKs read |
| `@UC-A1.1` kept with the dot | `@UC-A1_1`: needed only by `package:test`, which never sees the row tag anyway; the underscore would be a Dart-ism in the shared file |
| `@withdrawn` as a tagged, step-less scenario plus a map entry | Markdown-only withdrawal: keeps the reason richer but makes the id unaddressable by tag; the map entry keeps the reason |
| `acceptance.md` kept: headings, a pointer per row, Steps and provenance as design notes | generated from the corpus (a second home for the feature text), or deleted (breaks every cross-reference in `decisions.md` and the plan) |
| Cucumber Messages emitter deferred until at_java binds a PQ step | in the first release: correct destination, no consumer yet |
| First cluster A1 and A2 | B5.6 first (the evidence-standard row): one row proves less about reuse and the CRAM allocator than seven do |
| `acceptance.md` traceability comments as `# acceptance.md section 2 UC-A1.1` | `§`: against the standing house rule on section references |

## 4. Questions for Gary

Each changes what gets built or when. Where one option is what the proposal assumed,
it is listed first, and the proposal changes if another is chosen. Q1 (timing) is
ruled: see R1.

### Q2. Scope of "core test packs"

- (a) The PQ catalogue only, this roadmap.
- (b) PQ now; the 21 non-PQ functional files, 10 allowlisted e2e files, 6 CLI files
  and the proxy pack as a later project with its own characterisation.
- (c) No migration of the non-PQ packs; new tests are Gherkin-first from a date.

### Q3. Where the backlog lives

The PQ plan's own open row on the index of projects names the two ways out.

- (a) Rows in the PQ `## TODO`, the way the at_lookup consolidation's remaining items
  were folded in, each linking to a section of [`roadmap.md`](roadmap.md).
- (b) A table in this project plus a `docs/projects/README.md` index naming every
  live project, which also settles the open row.
- (c) A table in this project and the open row re-ruled to allow one per project.

### Q4. Hosts: five or four?

- (a) Five, as today: `at_auth` binds the in-process scenarios about the keyfile
  alone.
- (b) Four: `at_client` depends on `at_auth`, so it binds them; `at_auth` keeps its
  unit tests as unit tests and gains no driver, no `dart_test.yaml`, no
  dev_dependency.
- (c) Six: at_server's own functional pack against the virtualenv binds the
  server-enforced clauses (a second create refused, UC-B0.1's server half); a cross-repo
  host with the same pin mechanism at_java would use.

### Q5. The Flutter floor

`cucumber_gherkin` needs Dart 3.8; the root pubspec pins `flutter: ^3.29.2`, which the
comment says ships Dart 3.7.2. Probe 1 in
[`design.md` section 9](design.md#9-probes-to-run-before-anything-is-built) says
whether pub refuses; if it does:

- (a) Raise the root `flutter:` floor in the commit that adds the runner member, to the
  first Flutter that ships Dart 3.8 (which one is unverified).
- (b) Leave the floor and accept that it is untested below 3.8.
- (c) Vendor the parser (7,529 generated lines, MIT) so no floor moves.

### Q6. The two orphan feature files

`tests/at_functional_test/test_scenarios/atclient_apkam.feature` (hand-edited by Gary
in June 2025) and the CLI pack's `onboarding_cli.feature`; nothing runs either.

- (a) Delete both in the first cluster's PR.
- (b) Rewrite the scenarios still wanted under `features/` in the current vocabulary,
  then delete.
- (c) Keep as prose.

### Q7. Evidence granularity

The evidence standard is per row today: a row rests on an in-process proof only with
a declared reason. Under Gherkin the natural unit is the scenario, and requiring a
declaration for every `@in-process` scenario raises the bar for rows that also cite
live tests (240 in-process citations today, most in such rows).

- (a) Per row, as today: a row is declared exempt or owed when *no* scenario of it is
  live.
- (b) Per scenario: every `@in-process` scenario's row must be in a map.

### Q8. Who owns and reviews the corpus

- (a) Gary alone, as for every doc in `docs/projects/`.
- (b) Gary plus a named at_java maintainer once at_java binds a step; neither repo has
  a CODEOWNERS file today.

### Q9. The at_protocol record

The corpus is a candidate for the atSDK specification at_protocol promised in 2024.

- (a) Write the decision record in at_protocol when a second SDK binds a step.
- (b) Write it now, naming the corpus as the intended vehicle.
- (c) Leave at_protocol alone.
