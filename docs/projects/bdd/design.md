# Design: executable Gherkin for the acceptance catalogue

**Status:** proposal, 2026-09-02. Nothing here is built. Three designs were drafted
independently against the fact base in [`analysis.md`](analysis.md) (one led by
continuity of the measure, one by cross-SDK sharing, one by minimal scope), three
adversarial judges scored them against fixed criteria by opening the code each rested
on, and a completeness critic then read the lot for what everyone had missed. This
document is the synthesis: the minimal design as the base, with the parts of the other
two that the judges showed it needed. Where the panel left a claim unverified it is
marked so here, with the probe that settles it in
[section 9](#9-probes-to-run-before-anything-is-built). The questions that are
Gary's to answer are in [`decisions.md`](decisions.md), and this design takes none of
them.

## Table of contents

- [1. The shape in one paragraph](#1-the-shape-in-one-paragraph)
- [2. The runner](#2-the-runner)
- [3. Step definitions and the World](#3-step-definitions-and-the-world)
- [4. Where the features live, and who runs which scenario](#4-where-the-features-live-and-who-runs-which-scenario)
- [5. Tags](#5-tags)
- [6. The measure](#6-the-measure)
- [7. What happens to acceptance.md and the rails](#7-what-happens-to-acceptancemd-and-the-rails)
- [8. at_java and the other SDKs](#8-at_java-and-the-other-sdks)
- [9. Probes to run before anything is built](#9-probes-to-run-before-anything-is-built)
- [10. Risks](#10-risks)
- [11. What was considered and not taken](#11-what-was-considered-and-not-taken)

## 1. The shape in one paragraph

The `.feature` files are the specification and live at `features/pq/` in this repo,
one per catalogue section, in the catalogue's domain language and under Gary's
aupoqua conventions. A small in-tree runner package (a workspace member under
`tools/`, dependency of nothing published) parses them with `cucumber_gherkin`, the
official Cucumber Dart parser, and registers one `package:test` `test()` per compiled
scenario with the test's `location:` set to the feature file, so every existing
instrument (`dart test --concurrency=1`, `-t`/`-x`, the JSON reporter, the five CI
jobs that upload it, the ledger's basename join) sees a scenario as an ordinary test
declared in the feature file. Each host package (the three live packs, `at_client`,
`at_auth`) has a five-line driver per feature that runs the scenarios it owns against
its own step definitions and its own World; a step's binding location is derived from
where the definition was registered, never typed, and the ledger checks a scenario's
proof-level tag against it. Per-step results travel as `print` events inside the same
JSON stream CI already uploads, so the measure moves from "THEN clauses parsed out of
Markdown" to "Outcome steps in the corpus" without a new artefact or a CI change
beyond giving the CLI pack the reporter it lacks. Rows migrate one section at a time,
and a frozen-sum guard carries the current figures across so the number never lies
during the move. at_java loads the same directory into a sibling classpath location
read by a second suite class, so its 39-scenario suite stays green while Cucumber-JVM
parses the corpus on every build; it binds PQ steps only once it has PQ code.

## 2. The runner

### 2.1 Parser

`cucumber_gherkin` 42.0.1 (`sdk ^3.8.0`, sole dependency `cucumber_messages`). Its
one function, `generateMessages(data, uri, [GherkinOptions])`, returns Cucumber
Messages envelopes; the ones the runner uses are `pickle` (a compiled scenario) and
`parseError`. The pickle compiler has already done the work a runner would otherwise
do: Background steps are prepended, each Examples row is its own pickle with
placeholders substituted, Rule backgrounds and tags are inherited, tags are the union
of feature, rule, scenario and examples tags, `Pickle.location` is populated (the
scenario line, or the Examples row), and each `PickleStep.type` is `context`, `action`
or `outcome` with `And`/`But` resolved to the preceding keyword. The runner therefore
has no code for Background, Outline, Rule or tag inheritance, and "a Then clause" is
mechanical: an `outcome` step.

Nothing else on pub.dev fits ([`analysis.md` section 2](analysis.md#2-the-dart-bdd-packages-on-pubdev)):
the runners that read `.feature` files execute outside `package:test`, the one
codegen tool emits Flutter tests, and the package the question named requires Flutter
and exports rather than reads Gherkin. Cucumber publishes no Dart runner, so the
parts above the parser are this repo's code whichever way it goes. The parser is
7,529 lines of Berp-generated Dart under MIT, so if the package were ever abandoned a
vendored copy is a copy, not a rewrite.

### 2.2 Package

A workspace member `tools/at_bdd` (`publish_to: none`, `environment: sdk: ^3.8.0`,
`resolution: workspace`), following `tools/wasm_shakedown`, the one existing tooling
member. Dependencies: `cucumber_gherkin`, `cucumber_messages` (for the types), `test`
(a regular dependency here, since the runner calls `test()` from `lib/`). Each host
names it in `dev_dependencies` in the by-name form the workspace already uses for
intra-workspace dependencies. The five hosts' own pubspecs stay Dart-only and a
pub.dev consumer of `at_client` or `at_auth` never sees it, because dev_dependencies
are not resolved for consumers. Two things about this are unverified and are probes
1 and 2 in [section 9](#9-probes-to-run-before-anything-is-built): whether a member
declaring `sdk: ^3.8.0` resolves under the root's `^3.6.0` and `flutter: ^3.29.2`
(and under the Dart that CI's Flutter job bundles), and whether
`dart pub publish --dry-run` in `packages/at_client` accepts a dev_dependency on an
unpublished workspace member. If the first fails, the root Flutter floor moves, which
is a decision ([`decisions.md`](decisions.md)); if the second fails, the fallback is
publishing `at_bdd` as a 0.x package, never a `dependency_overrides` entry.

Size, as a budget a reviewer can check function by function: `loadFeatures` 25 lines,
`runFeatures` (group, test, name, tags, skip, location) 60, the per-pickle body (step
loop, undefined and ambiguous handling, step log, failure propagation, World
lifecycle) 55, the expression compiler and registry 70, table and doc-string helpers
25, the step-log writer 10; about 250 lines of `lib/` and about 200 of its own tests.

### 2.3 What a scenario becomes

For each feature file, in file order, `group(feature.name, () { ... })`, with a nested
group per Rule. If the file produced any `parseError` envelope, the group holds a
single red `test('parses', ...)` quoting the errors and nothing else: a typo in the
specification is a red test in the JSON stream, not a suite that fails to load or a
scenario that silently disappears. For each pickle the host owns
([section 4.2](#42-which-host-runs-which-scenario)):

`test(name, body, tags: forwarded, timeout: ..., skip: reason, location: TestLocation(featureUri, line, column))`

- **Name.** The pickle's `@UC-*` tags with the `@` stripped, space-joined, then
  ` · ` and the scenario name: `UC-A5.1 UC-A5.1b · A namespace-key rotation excludes a
  revoked enrollment from the new generation`. The ledger already derives the row from
  the test name (`_ucInName`), so the join key does not change. An `@invariant`
  scenario has no id and no prefix. Two pickles in one group with the same name
  (Outline rows whose interpolated titles coincide) get ` #2`, ` #3` in row order; this
  is for the ledger, since `package:test` allows duplicate names by default
  (`allowDuplicateTestNames = true`).
- **Tags.** Every pickle tag except the `@UC-*` ones, `@` stripped, forwarded as
  `package:test` tags. `package:test` requires a tag to match
  `^[a-zA-Z_-][a-zA-Z0-9_-]*$` and throws otherwise, so `UC-A1.1` can never be a
  tag; the row id travels in the name, and `dart test -N 'UC-A1.1'` selects it. Every
  forwarded tag is declared in each host's `dart_test.yaml` (an undeclared tag only
  warns, but the declaration is where per-tag timeouts go).
- **Location.** The feature file's URI and the pickle's line and column. With a
  location override the JSON reporter emits exactly `url`, `line` and `column` and no
  `root_url`, so the ledger's basename join reads `a1_onboard.feature`; without it,
  every scenario in the repo would report the runner library's path as its `url`.
  Read from `test_core` 0.6.17 and `test_api` 0.7.11 source, not yet run end to end
  (probe 3).
- **Skip.** `@withdrawn` scenarios are registered with `skip: 'WITHDRAWN'` and the
  runner throws at declaration if such a pickle has any step, since a withdrawn row
  owes nothing and must never show a passing step. `@unprovable` scenarios are
  registered with `skip: 'UNPROVABLE'` for the same reason
  ([section 6.4](#64-exemptions-debts-unprovables-and-withdrawn-rows)). A skipped
  test is reported by `package:test` as `result: success, skipped: true`, and the
  ledger today reads only `result`; the ledger change in
  [section 6.5](#65-what-the-ledger-does) closes that hole.
- **Timeout.** Per tag, in each host's `dart_test.yaml` (`live: 5m`, `cli: 15m`);
  the CLI pack spawns an `at_activate` process per command with a 120 s bound and a
  scenario runs several. A duration is a mechanism and never appears in feature text.
- **Body.** Create the World; for each step in order, match it against the host's
  registry (no match is *undefined* and fails the test with a copy-pasteable
  definition snippet; more than one match is *ambiguous* and fails naming both); run
  the matched definition; on a throw, record the step `failed`, record the remaining
  steps `skipped`, and rethrow with the step text in the failure message; in `finally`,
  dispose the World. Declaration is synchronous (`readAsStringSync` plus a synchronous
  `generateMessages` inside `main()`), so there is no async-registration question.

### 2.4 Per-step records

After every step the runner prints one line, `##gherkin ` followed by JSON:
`{"v":1,"feature":"features/pq/a1_onboard.feature","line":72,"uc":["UC-A1.1"],"tags":["live","happy"],"type":"outcome","text":"...","status":"passed","ms":412,"definedIn":"tests/at_functional_test/test/steps/onboard_steps.dart"}`.
`package:test`'s JSON reporter turns every `print()` in a test body into a
`{"type":"print","testID":...,"message":...}` event, so the step log rides the same
`acceptance-report.json` the five emitting CI jobs already upload. No side file, no
new environment variable, no new upload step; the alternative (a JSONL file behind an
env var, the shape `ACCEPTANCE_LEDGER` has today) needs a workflow edit per job and a
second artefact to join, and was rejected for that. A Cucumber Messages NDJSON
emitter, which is what a Java run would produce and what `@cucumber/html-formatter`
renders, is deferred until at_java binds a PQ step; it is an 80-line addition to the
same hook and changes nothing above.

`definedIn` is the repo-relative path of the file that registered the matching
definition, read from the stack at registration time. It is never a string the
driver's author types. It plays the role the cited path plays today: whether it lies
under a live pack decides whether the step is server-proven, and the ledger compares
the scenario's proof-level tag against it (a tag is a claim, the binding's location is
the fact). The JSON reporter's `suite` event also carries the driver file's path, a
second instrument for the same fact.

## 3. Step definitions and the World

### 3.1 Cucumber Expressions, not bare regex

at_java binds with Cucumber Expressions and `@ParameterType`, and so does every other
Cucumber implementation, so a step's *expression string* can be pasted into a Java
`@Then("...")` unchanged with each side supplying its own parameter regexes. That is
the whole cross-SDK contract at the binding level. No Dart port of Cucumber
Expressions exists as a package (the project's README lists Go, Java, JavaScript,
Python, Ruby and .NET), so the runner implements the grammar: `{parameter}`, `(optional
text)`, `a/b` alternation and `\` escapes, compiled to one anchored `RegExp` per
expression. The Cucumber project publishes a test corpus for the grammar
(`testdata/cucumber-expression/{matching,parser,tokenizer,transformation}` in
`cucumber/cucumber-expressions`), and the implementation is tested against it the way
`cucumber_gherkin` is tested against Gherkin's.

Parameter types the PQ corpus needs, from the translation sample and the fixture
survey; the quoted forms follow the aupoqua rule of quoted actors, and the regexes are
written once in `features/parameter_types.yaml` so that a Dart test and, later, a
Java test can each assert their registered regex equals the file's:

| Placeholder | Matches | Resolves to |
|---|---|---|
| `{atsign}` | `"@alice"` | the World's handle for that atSign |
| `{enrollment}` | `"alice1"` | the World's `(atSign, enrollmentId, client)` handle; identity is `(owner, id)`, never id alone |
| `{namespace}` | `"app_1.my_apps"` | the run-unique namespace the World derives from it, because namespace keys are adopted rather than re-minted against a virtualenv that outlives one run |
| `{algorithm}` | `"mldsa65"`, `"rsa2048"` | the enum; the quoted literal is the raw-literal pin |
| `{posture}` | `a PQ-capable posture`, `a posture that configures no post-quantum providers` | a `PqPosture` a fixture can build, and only those |
| `{duration}` | `"5 seconds"` | `Duration` |
| `{int}`, `{word}`, `{string}` | Cucumber built-ins | as usual |

at_java's existing glue defines `{atsign}` as `@\S+`, unquoted. Two parameter types
with one name in one Cucumber runtime throw `DuplicateTypeNameException`, which is one
of the two reasons the Java side needs a separate glue package and suite
([section 8](#8-at_java-and-the-other-sdks)).

### 3.2 The World

One per scenario, created inside the test body and disposed in `finally`. The host
owns the type. For the functional pack it is what the fixture survey derived: a map
keyed `(atSign, enrollmentId?)` to `{AtClientManager (public constructor), AtClient,
AtClientPreference with a unique hiveStoragePath, AtKeysIo, EnrolledClient?}`; an actor
table (`"alice1"` to its handle); a run id and the run-unique namespaces derived from
it; one memoised approver per atSign, registered as a key-package holder;
subscriptions to cancel; and a `dispose()` that stops every client it created and
removes its entries from the client cache (clearing the cache stops nothing). The
invariant that nothing calls the singleton manager's `setCurrentAtSign` while two
managers are live holds inside the World.

Hooks are the driver's own `setUpAll`/`tearDownAll` around `runFeatures` (readiness
probes, the CLI pack's key-directory emptying) and the World's constructor and
`dispose()`; tagged hooks are not implemented until a second host needs one.

### 3.3 Fixtures that do not exist yet

The step library needs, and the packs do not have: a notification wait with a
monitor-readiness positive control and one retry (inline in 5 files today); a raw
record read (inline in 32); a typed enrollment fetch by id; revoke and deny helpers;
an allocator for one-shot CRAM atSigns (hand-kept in `config.yaml` comments today;
the demo roster has 40 `cramKeyMap` entries, 5 are `pkamLoad`ed, 3 functional files
CRAM-onboard today); a stop-all teardown (`HiveInstances.closeAll` has no caller); a
run-id and unique-namespace factory; and, for the CLI pack, deletion of
`*.enrollment.checkpoint` files in `dispose()`, since its `runLocal.sh` never clears
them. The two duplicated helpers (`enrolAndAuthenticate`/`EnrolledClient`, and
`legacyPlusPqProviders`) collapse to one home as a by-product.

One-shot CRAM atSigns force a rule the naive reading of "move the rows" misses: a
Gherkin UC-A1.1 that onboards `@xavier` while `pq_native_onboard_live_test.dart` still
onboards it in the same run is refused by the atServer. **A cited live test whose
assertions are all bound as steps is retired in the same PR; one that consumes a
one-shot resource is retired even if only partly bound, with its unbound assertions
promoted to steps first.** The migration therefore touches the 46 live cited files,
not only the 19 acceptance files.

There is a second route to the same problem, and it is worth weighing before the
allocator is built: a lane running against an ephemeral environment gets its own
atSign list, a mounted file defaulting to 26 freshly CRAM-activatable atSigns, rather
than drawing on the VE's shared one-shot pool
([`analysis.md` section 1.6](analysis.md#the-packs-are-built-to-run-side-by-side-and-that-bears-on-how-a-migration-is-sequenced)).
That would let a migrated scenario and the cited live test it replaces coexist for a
while instead of forcing retirement in the same PR. The retirement rule stays the
default here because it is what the VE requires and because retiring a superseded test
is the right end state regardless; the EE is what buys room if the rule turns out to
be the thing slowing a cluster down.

## 4. Where the features live, and who runs which scenario

### 4.1 Layout

`features/pq/<section>.feature` at the repo root, one file per catalogue section that
has rows (16 files for sections 2 to 13 and 15 to 18; sections 0, 1 and 14 are
vocabulary and harness design, not rows), plus `features/README.md` (ownership, the
tag vocabulary, the wording rules, the parameter types) and
`features/parameter_types.yaml`. Not under `docs/projects/pq/`, because
`docs_structure_test` reads every `.md` there as the doc set and executable inputs
are not documentation; not under a pack's `test/`, because the corpus is consumed by
five hosts and another repository; not a published package yet, because the
Compatibility Kit pattern (features as data, published per platform, steps per
language) is the destination once a second SDK binds a PQ step, and it starts as a
directory. Feature basenames are unique across the corpus (a rail), because the
ledger joins on basename. Hosts find the directory with the same walk-up locator
`manifest.dart` uses for `acceptance.md`.

The two orphan feature files under `test_scenarios/` are deleted in the first
cluster's PR, or rewritten under `features/` in the current vocabulary where a
scenario is still wanted; that choice is in [`decisions.md`](decisions.md).

### 4.2 Which host runs which scenario

Every host loads every file and runs only the pickles it owns. A scenario carries
exactly one proof-level tag and at most one product-surface tag, and the routing is
a fixed rule the corpus rail checks:

| Host | Driver | Runs |
|---|---|---|
| `tests/at_functional_test` | `test/gherkin_<section>_test.dart`, `@Tags(['pq'])` before `library;` | `@live` scenarios with no product-surface tag |
| `tests/at_end2end_test` | `test/pq/gherkin_<section>_test.dart` (under `test/pq/` so the `paths:` allowlist never names it, tagged `pq` as `suite_manifest_test` requires) | `@live` scenarios tagged `@legacy-server` (the pinned pre-PQ image) or `@zero-grace` (the `@eve🛠` secondary with `apkamSelfEnrollmentGraceHours=0`, which only this pack's virtualenv provisions and two retrofit rows need) |
| `tests/at_onboarding_cli_functional_tests` | `test/gherkin_<section>_test.dart` | `@live @cli` |
| `packages/at_client` | `test/acceptance/gherkin_<section>_test.dart`, declared in `manifest.dart` so `architecture_guard_test` keeps enumerating | `@in-process` scenarios |
| `packages/at_auth` | `test/gherkin_<section>_test.dart` | `@in-process` scenarios about the keyfile alone, if at_auth stays a host ([`decisions.md`](decisions.md)); otherwise none, and at_client binds them since it depends on at_auth |

The routing tags are product conditions (`@cli`: drives the `at_activate` process;
`@legacy-server`: needs the pinned image; `@zero-grace`: needs the reconfigured
secondary), never Dart package names, so a Java engineer reading the shared file meets
nothing about this repo's layout. A pickle that resolves to two hosts or none is red in
the corpus rail, and the ledger reports one that *ran* in two hosts as `DUPLICATED`.
Whether a scenario needs `@zero-grace` is a fact the scenario states in its Given.

### 4.3 The `pq_tag_test` rail

`tests/at_functional_test/test/pq_tag_test.dart` is bidirectional and non-recursive:
a file under `test/` that carries `@Tags(['pq'])` without matching its
mechanism-symbol regex is red, and so is a file that matches without the tag. A
five-line driver matches nothing. So the driver either carries a marker the regex
admits or the regex gains one; the design says which in the phase that adds the first
driver, and it is written down so nobody "fixes" the rail.

## 5. Tags

Every tag other than a row id is a lower-case hyphenated identifier,
`^[a-z][a-z0-9-]*$`: legal to `package:test`, to JUnit (which reserves only `, ( ) & | !`
and whitespace) and to Cucumber. Row ids `@UC-A1.1` are legal to Cucumber and JUnit
and travel in the Dart test name. One Gherkin spelling therefore serves all three
selectors, whose expression syntaxes differ (`@live and not @cli`, `live && !cli`,
`live & !cli`) but whose identifiers are the same.

| Tag | Kind | Meaning |
|---|---|---|
| `@UC-A1.1` (and `@UC-A5.1a` for a split arm) | row | the catalogue row; one scenario may carry several |
| `@pq` | area, feature level | every PQ feature carries it, the way aupoqua puts `@assumption` at feature level, so `-t pq`/`-x pq` and the two tag rails keep meaning |
| `@live` / `@in-process` | proof level, a claim | exactly one per scenario; checked by the ledger against where the binding ran |
| `@live-exempt`, `@live-owed`, `@unprovable`, `@withdrawn` | declaration | mirror the manifest's maps; the reason stays in the map, not in the shared file ([section 6.4](#64-exemptions-debts-unprovables-and-withdrawn-rows)) |
| `@cli`, `@legacy-server`, `@zero-grace` | product surface | routing, stated as a condition of the product or environment |
| `@control` | arm | a control scenario; a rail requires a sibling assertion scenario for the same row |
| `@happy`, `@negative`, `@security`, `@adversarial`, `@limitation`, `@assumption` | domain | Gary's aupoqua set |
| `@invariant` | section 13 | unnumbered by design; counted in its own column |
| `@dart`, `@java` | per-SDK truth | a step whose truth differs by SDK ("a build that implements ML-DSA") is tagged, never written twice |

Mechanism names (`verifyEnvelope`, `_rootlock`, `__ssenv`, `ensureCurrent`, ...) are
banned from step text and live in bindings; wire literals (provider ids, algorithm
spellings) are allowed as quoted values because they are the raw-literal pins. A rail
enforces the ban with a fixture feature as its positive control. Traceability comments
use the house form, `# acceptance.md section 2 UC-A1.1`, mirroring aupoqua's `# US n.n`.

## 6. The measure

### 6.1 Today, in one sentence

232 THEN clauses parsed from `acceptance.md` by a five-regex line parser, two exact
figures (`provenClauseCount = 227`, `serverProvenClauseCount = 90`) guarded in both
directions, three reviewed declaration maps, one withdrawn row, unnumbered invariants
that cannot pin, and citations that assert a test still exists rather than running
it; with the parser blind spots [`analysis.md` section 1.1](analysis.md#11-the-catalogue-and-its-clause-parser)
records.

### 6.2 The unit after the move

An **outcome step** (`PickleStep.type == outcome`) in a pickle that carries a
`@UC-*` tag and is not `@withdrawn`. The specification and the pin become one
artefact: what is asserted is what is bound, so the parser inversions disappear by
construction. A headline sentence becomes a step or is not asserted; an `And` is a
step; an assertion has no When to hide in; section 13 has scenarios.

### 6.3 Two pins, one measured figure, one roster

Two exact-figure pins in `manifest.dart`, successors of 227 and 90, guarded in both
directions: `liveOutcomeStepCount` (outcome steps in `@live` pickles) and
`inProcessOutcomeStepCount` (outcome steps in `@in-process` pickles). Each is a
*claim* about where proof runs; changing either means editing the constant in the
commit that adds or retags a scenario, and that edit is the review, exactly as
landing a pin is today.

The measured figure lives only in the ledger, where runs are: `outcome steps passed /
outcome steps declared`, per row and in total, with every `@live` claim verified
against the `definedIn` of the bindings that ran. "Proven" stops being a source-side
word; the ledger is the only place that may say it, and it says it about the runs
supplied (`NOT-EXERCISED` for a pickle in no report, as today).

A **per-host binding rail** (`test/gherkin_bindings_test.dart` in each host, about 20
lines) loads every feature, takes the pickles the host owns, and asserts every step
has exactly one match in its registry. Undefined and ambiguous are red at unit speed
without an atServer, which is what makes a wording change safe to review; it replaces
"every pin resolves to exactly one clause".

A **roster** of the 98 ids in `manifest.dart` asserts, on every run, that each id
appears in exactly one of {a heading in `acceptance.md`, a `@UC-*` tag in
`features/pq/`}, that the union equals the roster, and that no id is in both. Nothing
can be dropped in the move, because a dropped id fails the union; nothing can be
counted twice, because an id in both fails the disjointness. It also replaces "every
mention is a definition".

### 6.4 Exemptions, debts, unprovables and withdrawn rows

They stay where they are, as Dart maps in `manifest.dart` keyed by `UC-<id>` with a
reason of at least 40 characters, and the corpus rail cross-checks them against the
tags in both directions: every `@in-process` pickle's row is in `liveProofExempt` or
`liveProofOwed`; every key in either map has an `@in-process` pickle and no `@live`
pickle covering the whole row (a spent entry must be deleted); no key in both; every
`@unprovable` pickle's row is in `unprovableClauses`, whose value names the tripwire
test in `architecture_guard_test.dart` that must exist and pass (the ruling of
2026-08-31: an absence gets a source-shaped tripwire, never a passing step, and the
runner skips the scenario so it can never pass); every `@withdrawn` pickle has zero
steps, a `withdrawn` map entry with the date and ruling, and no other pickle claiming
its id.

The reasons do not enter the shared `.feature` files. Two of the three designs put
them in scenario descriptions; the judges preferred the maps, because a reason names
Dart test files and this repo's projects, which a Java engineer binding the same file
should not have to read past, and because the maps already have rails. Counts of the
maps are printed, never asserted: `liveProofOwed` is the debt, and its shrinking is
the burn-down that matters after the move.

### 6.5 What the ledger does

Small changes to `packages/at_client/tool/acceptance_ledger.dart`: `readReport` also
collects `print` events whose message starts with `##gherkin ` and records
`skipped`; a `--features <dir>` input parses the corpus for the denominator; verdicts
for Gherkin scenarios are `PASSED`, `FAILED`, `SKIPPED (WITHDRAWN|UNPROVABLE)` and
`NOT-EXERCISED`, with `MISATTRIBUTED` when a `@live` scenario's bindings did not run
under a live pack (or an `@in-process` one did) and `DUPLICATED` when two hosts ran
one pickle; the id regex becomes the manifest's `ucIdPattern`, closing the two-homes
defect; rendering shows a Gherkin table above the legacy table, then the invariants,
then totals for both worlds side by side, never summed. `acceptance_ledger_test.dart`
gains fixture reports carrying `print` events and skipped tests, and the pin reads
production output.

### 6.6 Carrying the figure across the migration

Rows migrate a section at a time, and a row is either Markdown (today's mechanics,
unchanged, `provenIn` still bridging) or Gherkin, never half. Three guards make the
period safe:

1. **The frozen sum.** `manifest.dart` gains `migratedRows`, a map from row id to the
   snapshot `(clauses, proven, serverProven)` the parser counted for that row at the
   moment it left. The exact-figure guard becomes `parsedProven + Σ snapshot.proven ==
   227`, `parsedServerProven + Σ snapshot.serverProven == 90` and `parsedTotal + Σ
   snapshot.clauses == 232`, all in both directions, until the last row moves. Nothing
   can fall while rows move, and a row cannot be counted twice (a heading with Then
   bullets and a snapshot is red; one with neither, unless withdrawn, is red).
2. **The per-row floor.** The same commit records the row's Markdown coverage as a
   ratio, and the rail asserts the Gherkin row's `serverBound/total` is at least
   `serverProven/clauses`. A ratio because the denominators differ (3.9 steps per clause
   on the sample); this is the one guard that stops a translation quietly turning a
   live-proven clause into an `@in-process` scenario.
3. **The roster**, above.

The translation's gain is announced rather than hidden: the ledger prints `GAINED
outcome steps beyond the migrated clauses: G`, where G is what the parser never saw
(UC-A3.3's headline, the 4 `- **And:**` bullets, assertions inside When bullets,
section 13). At the end (`parsedTotal == 0`) the snapshots, the two old constants, the
clause parser, `provenIn`/`provenHere`, the citations file and `ACCEPTANCE_LEDGER` are
deleted in one commit, and the last `BURN-DOWN` line is written beside the first full
`OUTCOME STEPS` line in `acceptance.md` so the discontinuity is recorded once. Section
13's invariants are a separate column throughout, so the row denominator does not grow
unannounced.

## 7. What happens to acceptance.md and the rails

`acceptance.md` is kept, not generated and not deleted. Sections 0, 1 and 14
(vocabulary, notation, harness design) stay and section 14 is rewritten to describe
the runner; each row keeps its heading, so every cross-reference in `decisions.md`
and the plan still resolves, and under the heading a one-line pointer names the
feature file and scenarios, followed by the Steps list, the per-enrollment table, the
Cross-ref and Impl/verify bullets and every provenance paragraph as design notes, the
material translation rule 8 keeps out of the features. The Then bullets go, because
their content is now the scenario. The status table and headline sentence stay until
the last row moves and are then deleted with their rails.

⚠️ The PQ plan rules doc-set surgery on `acceptance.md` for **after D1**; this design
edits it row by row. Whether that ruling covers this, and when the migration may start
relative to D1, is Gary's call and is the first question in
[`decisions.md`](decisions.md).

The rails, phase by phase (the phases are in [`roadmap.md`](roadmap.md)):

| Rail | Red when | Replaced by |
|---|---|---|
| `catalogue_test`: headings ↔ scenarios, mentions ↔ definitions | each cluster | the roster (union and disjointness); `scenarioUseCaseIds()` becomes the union of Dart scenarios and `@UC-*` tags |
| `catalogue_test`: the two exact figures | each cluster | the frozen-sum guard; then the two outcome-step pins |
| `catalogue_test`: exemption, debt and unprovable guards | never | unchanged maps, cross-checked against tags instead of citations |
| `catalogue_test`: every pin resolves to one clause | each cluster | the per-host binding rail |
| `docs_structure_test`: status table and headline | each cluster (counts move) | deleted with the table when the last row moves |
| `docs_structure_test`: every live row states a THEN clause | each cluster | every non-withdrawn `@UC-*` scenario has at least one outcome step |
| `docs_structure_test`: a `DONE` plan claim cites a PROVEN row | each cluster | PROVEN redefined as "has a pickle in the roster with every outcome step bound" |
| `docs_structure_test`: cited-file nameability | last cluster | retired with `provenIn`; `pq_*_test.dart` nameability stays |
| `architecture_guard_test`: undeclared test file | first at_client driver | drivers declared in `manifest.dart` |
| `pq_tag_test` (bidirectional, non-recursive) | first functional driver | a marker the regex admits, or the regex widened; decided and written down in that PR |
| `suite_manifest_test` (e2e) | first e2e driver | drivers under `test/pq/` carrying `pq` |
| `acceptance_ledger_wiring_test` | the CLI job gains a reporter | the job added to `emittingJobs` |

## 8. at_java and the other SDKs

at_java's `CucumberIT` selects the classpath directory `features`, scans it
recursively, and runs under Cucumber-JVM 7.x strict mode, where an undefined step
fails the scenario. Copying the corpus into that directory would turn its 39-scenario
suite red on the first PQ pickle; one of the three designs did exactly that and the
judges caught it. So:

1. A second `download-maven-plugin` execution at `generate-test-resources`, copying
   the block at_java already uses for `at_demo_data`, fetches a pinned archive of
   `at_client_sdk` (pinned by a `<version.shared_features>` property the way
   `version.at_demo_data` pins 1.2.0) and unpacks it under `target/`. Maven runs
   `generate-test-resources` before `process-test-resources`, so a `<testResource>`
   pointing into `target/` with `<targetPath>shared-features</targetPath>` lands the
   files on the test classpath as a *sibling* of `features/`. Re-listing the default
   `src/test/resources` is required once `<testResources>` is overridden.
2. A second suite class, `SharedFeaturesIT`, with
   `@SelectClasspathResource("shared-features")`, its own glue package (so its quoted
   `{atsign}` cannot collide with the existing `@\S+`), and
   `cucumber.filter.tags=@java` until at_java binds a PQ step. With no `@java`
   scenario, zero scenarios execute and the suite's value is that Cucumber-JVM parses
   the corpus on every at_java build: a Gherkin parse error throws at discovery and
   the JUnit launcher wraps it into an engine discovery error before any filter runs
   (traced in source by a judge; probe 4 runs it). When at_java gains PQ, the filter
   flips to `cucumber.execution.dry-run=true` first, a binding-completeness gate that
   needs no virtualenv, and then to real execution.
3. at_java's seven API-language features stay where they are, unshared, run by
   `CucumberIT` as today. Their portable parts (the `{ordinal}`/`{path}`/`{timeunit}`
   types, the three-way client addressing, the table semantics, the `fails` plus
   `exception was ... and message matches ...` shape) are adopted into the shared
   parameter types and step catalogue in domain language.
4. The `.feature` text is owned here, as the reference implementation's repository;
   each SDK owns its bindings; a wording change is a PR here that keeps every Dart
   binding rail green, and at_java picks it up by moving its pin. Proof-level tags are
   claims about the reference (Dart) binding, said so in `features/README.md`; a
   per-SDK host table in the ledger comes before a second SDK's stream is joined.
   Cucumber-JVM 7.14 emits `stepDefinition` envelopes with a source reference for
   every glue method, so a Java column is buildable when wanted.

Beyond at_java, [`analysis.md` section 5](analysis.md#5-the-other-sdks) lists the
SDKs and their tooling. The corpus is also a candidate for the atSDK specification the
2024 at_protocol decision promised and nothing delivered; that record belongs in
at_protocol and this design does not write it.

## 9. Probes to run before anything is built

Each is a few lines; each settles a claim the design rests on and nobody has run.

1. **Workspace SDK floor.** On a scratch branch, add `tools/at_bdd` with
   `sdk: ^3.8.0` and `cucumber_gherkin: ^42.0.1` to the root `workspace:` list; `dart
   pub get` from the root; then `flutter pub get` from `packages/at_client_flutter`
   (its CI job resolves the workspace with Flutter's bundled Dart, and which Dart the CI
   Flutter stable bundles is unread). Expected: both exit 0 and the lock names 42.0.1.
   A scratch package outside the workspace already resolves
   ([`analysis.md` section 2.4](analysis.md#24-cucumber_gherkin-is-the-parser-and-there-is-no-runner)),
   which says nothing about a 3.6 root.
2. **Publish dry-run.** Add the by-name dev_dependency to `packages/at_client` and run
   `dart pub publish --dry-run`; read the messages, not only the exit code.
3. **TestLocation end to end.** A one-test scratch package with `test('probe', () {
   print('##gherkin {}'); }, location: TestLocation(Uri.file('/x/f.feature'), 12, 3))`
   under `dart test --file-reporter json:`; expected `url` ending `f.feature`, `line`
   12, no `root_url`, and one `print` event with the test's id.
4. **The at_java parse gate.** On a scratch branch of at_java, a malformed
   `shared-features/bad.feature` plus the `SharedFeaturesIT` above with
   `cucumber.filter.tags=@java`; `mvn -Dit.test=SharedFeaturesIT -DfailIfNoTests=false
   verify`; expected: the build fails naming the parse error.
5. **CRAM demand against the pool.** Count the Givens in the drafted A1 and A2
   features that need an unactivated atSign, against the 40 `cramKeyMap` entries minus
   the 5 that `runLocal.sh` PKAM-loads, minus those spent by files that will still
   run.
6. **The clause count of the first cluster.** Run `catalogue_test` before and after
   removing `a1_onboard_test.dart` and `a2_enrollment_test.dart` from `scenarioFiles`
   on a scratch branch; the difference in the denominator is the cluster's clause
   count (30 by a Python re-implementation of the parser, unverified against the Dart
   one).

## 10. Risks

- **Dependency maintenance.** `cucumber_gherkin` has 3 releases in 2 months, one
  retracted, and one active author on the Dart port. Mitigations: one importing
  package, `^42.0.1`, MIT, generated code that can be vendored, and fixture pins that
  re-run on every upgrade. The `^3.8.0` floor is the sharper edge (probe 1).
- **Rails that go red looking like harness breakage.** Named per phase in
  [section 7](#7-what-happens-to-acceptancemd-and-the-rails) so nobody weakens a rail
  to get green.
- **One-shot CRAM atSigns and the cited live tests that still consume them.** The
  retirement rule in [section 3.3](#33-fixtures-that-do-not-exist-yet), and the
  allocator, which refuses a second grant in one run.
- **The CLI pack.** 120 s per spawned command, checkpoint debris, and a CI job that
  emits no report today, so every `@cli` step reads `NOT-EXERCISED` from CI until the
  reporter and upload are added.
- **Shared static state under `--concurrency=1`.** One isolate per feature file; the
  scenarios in it share the singleton manager and the client cache; the World's
  `dispose()` is the mitigation and the stop-all helper is a deliverable, not an
  optimisation.
- **Denominator growth read as regression.** The move multiplies the count by 3.9 on
  the sample and adds assertions the parser never counted; side-by-side rendering and
  the recorded last `BURN-DOWN` line are the defence against summing the two worlds.
- **Scope.** The brief names "all core test packs"; this design covers the PQ
  catalogue. The 21 non-PQ functional files, 10 allowlisted e2e files, 6 CLI files and
  the proxy pack are uncharacterised ([`decisions.md`](decisions.md)).

## 11. What was considered and not taken

- **`bdd_framework`.** Flutter-required in every version, exports rather than reads
  Gherkin, no tags API, counter-prefixed test names, and a Dart runner on its unreleased
  main that by code reading swallows failures. It would also run the cross-SDK flow
  backwards.
- **`gherkin` 3.1.0 or a fork of it.** Its own runner outside `package:test`, a `uuid
  ^3` conflict with this workspace, no commit since 2022 and an open request to
  archive in favour of `cucumber_gherkin`.
- **`bdd_widget_test` with a pure-Dart shim.** Feasible but a build step in every
  host, Dart expressions in the feature text, and a parser rewrite in flight that
  renames the test titles a ledger keys on.
- **A published `at_sdk_spec` package now.** Every wording change becomes a version
  bump and a publish, against the house rule that a bump is Gary's call; the pattern
  is right for the day a second SDK binds a PQ step, and a directory becomes a package
  with one move.
- **Declarations as scenario descriptions in the shared file.** Puts Dart test names
  and this repo's projects in front of every SDK's engineer; the maps already have
  rails.
- **Routing e2e PQ scenarios into the functional pack.** Two retrofit rows need the
  zero-grace secondary only the e2e virtualenv provisions; the catalogue already
  records that the functional pack cannot host UC-B2.2.
- **`@UC-A1_1` as the tag spelling.** Needed only because `package:test` rejects the
  dot; Cucumber and JUnit accept `UC-A1.1`, so the underscore would be a Dart-ism in the
  shared file. The id travels in the test name instead.
- **A typed `host` string in the step log.** A self-report the ledger would believe;
  the tag must be checked against where the binding ran, which the registering frame
  and the reporter's `suite` event both provide.
- **A Cucumber Messages emitter in the first release.** Correct destination, no
  consumer yet; 80 lines when at_java binds.
