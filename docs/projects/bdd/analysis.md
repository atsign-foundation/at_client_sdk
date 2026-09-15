# Analysis: the acceptance proof mechanism today, and what BDD would replace it with

**Measured 2026-09-02** against `at_client_sdk` branch `gkc-pq-d1-spike` at `e05d245b0`
and `at_java` at `1122a9ffb` (detached at that day's `origin/trunk`). Every figure
below carries the command that produced it or the URL it was read from, and every
figure the design in [`design.md`](design.md) rests on was checked a second time by
an independent reader told to refute it. Two of my own claims failed that check and
are corrected here rather than quoted: `liveProofOwed` has 37 entries, not 38; and
the five host packages are Dart-only in their own pubspecs but their *workspace*
resolution still needs a Flutter SDK on disk.

This document describes what exists. What to build is in [`design.md`](design.md),
the phasing is in [`roadmap.md`](roadmap.md), and the questions only Gary can answer
are in [`decisions.md`](decisions.md).

Every `file:line` here is a line number at `e05d245b0` (or `1122a9ffb` for at_java);
read it with `git show e05d245b0:<path>` rather than against a later head, since a
line number keeps resolving after the code under it has moved. Nothing in this
analysis was executed except the counts shown with their commands and the one pub
resolution probe in [section 2.4](#24-cucumber_gherkin-is-the-parser-and-there-is-no-runner);
every other statement about behaviour is a reading of source.

## Table of contents

- [1. The mechanism that exists today](#1-the-mechanism-that-exists-today)
- [2. The Dart BDD packages on pub.dev](#2-the-dart-bdd-packages-on-pubdev)
- [3. Cucumber facts a shared corpus depends on](#3-cucumber-facts-a-shared-corpus-depends-on)
- [4. The at_java Cucumber pack](#4-the-at_java-cucumber-pack)
- [5. The other SDKs](#5-the-other-sdks)
- [6. The translation sample](#6-the-translation-sample)
- [7. The Gherkin conventions already in use](#7-the-gherkin-conventions-already-in-use)
- [8. How this analysis was produced](#8-how-this-analysis-was-produced)

## 1. The mechanism that exists today

The PQ project already has an executable acceptance catalogue, which is why this
is a migration and not a greenfield. It has four parts, and a BDD replacement has
to answer for each of them.

### 1.1 The catalogue and its clause parser

[`docs/projects/pq/acceptance.md`](../pq/acceptance.md) holds the use cases as
Markdown. A use case is *defined* by a heading matching
`^#{2,4} +(?:[\d.]+ +)?UC-[ABCG]\d+\.\d+[a-z]? +— ` (`manifest.dart:289-290`), and
the catalogue counts 98 of them, one of which is `WITHDRAWN` (UC-C1.3):

```bash
git grep -cP '^#{2,4} +(?:[\d.]+ +)?UC-[ABCG]\d+\.\d+[a-z]? +— ' -- docs/projects/pq/acceptance.md   # 98
git grep -cP '^#{2,4} .*WITHDRAWN' -- docs/projects/pq/acceptance.md                                 # 1
```

Each row carries Given, When, a `Steps` list, Then, often a per-enrollment state
table, and `Cross-ref` and `Impl/verify` bullets. Only the Then is parsed.
`catalogueClauses()` (`packages/at_client/test/acceptance/manifest.dart:717-794`)
recognises two forms: a `- **Then:**` bullet whose `  - ` sub-bullets are each one
clause (the headline sentence contributes nothing when sub-bullets exist), and the
italic `*Then*` / `*And*` lines the G1 and G3 clusters use, each one clause. A clause
is collapsed to one line with single spaces. The suite reports 232 clauses at this
head (`dart test test/acceptance/catalogue_test.dart --concurrency=1` in
`packages/at_client` prints the `BURN-DOWN` line).

The parser has blind spots the translation sample ran into
([section 6](#6-the-translation-sample)): a `**Then:**` with sub-bullets drops its
own headline sentence, so UC-A3.3's primary assertion (the write fails, naming the
namespace) is outside the 232; `- **And:**` bullets are never clauses and 4 exist
(`grep -n '^- \*\*And' docs/projects/pq/acceptance.md`); an assertion written inside
a When bullet is invisible; section 13's cross-cutting invariants have no `UC-`
heading, so they can cite tests but can never pin a clause; and in one row a status
sentence ("Built, and green live") is itself a counted clause.

### 1.2 The citation model

The scenarios in `packages/at_client/test/acceptance/*_test.dart` are plain
`package:test` `test()` calls whose names start with the use-case id. They do not
run the proof; they *cite* it. `provenIn(path, testName, proves:, clauses:)`
(`proven_elsewhere.dart:62-97`) asserts the cited file exists and still contains a
test whose name starts with `testName`, records `proves:` prose for a human, and
resolves each `clauses:` fragment to exactly one collapsed clause of the calling
row. `provenHere()` claims clauses proven inline. Counted at this head:

```bash
cd packages/at_client/test/acceptance
perl -0777 -ne 'while (/provenIn\(\s*'"'"'([^'"'"']+)'"'"'/gs){print "$1\n"}' *_test.dart | wc -l   # 362
grep -o 'provenHere(' *_test.dart | wc -l                                                          # 2
grep -o 'clauses:' *_test.dart | wc -l                                                             # 238
perl -0777 -ne 'while (/provenIn\(\s*'"'"'([^'"'"']+)'"'"'/gs){print "$1\n"}' *_test.dart | sort -u | wc -l   # 94 distinct files
```

Of the 362 `provenIn` citations, 122 point into a live pack (functional 90, e2e 29,
CLI 3) and 240 into in-process unit tests. Whether a citation counts as
*server-proven* is decided by the cited path's prefix against `livePackPaths`
(`manifest.dart:78-82`), never by how the scenario is written.

Three maps in `manifest.dart` are reviewed declarations with rails over them:
`liveProofExempt` (3 rows that may rest on an in-process proof, each with a reason
a reviewer can judge), `liveProofOwed` (37 rows whose live proof is owed, meant to
shrink) and `unprovableClauses` (1 clause, UC-G2.9 c3, unreachable as written). The
guards in `catalogue_test.dart` refuse a row in both maps, a spent entry, a reason
under 40 characters, and an id the catalogue does not define. Two exact figures,
`provenClauseCount = 227` and `serverProvenClauseCount = 90`, fail in both
directions, so a pin and its count move in one diff.

### 1.3 The ledger, and what CI emits

`packages/at_client/tool/acceptance_ledger.dart` says whether a cited test *ran and
passed*, which a citation cannot. It joins two inputs: the citations `provenIn`
appends to a JSONL file when `ACCEPTANCE_LEDGER` is set (recorded through
`package:test`'s `Invoker`, `proven_elsewhere.dart:99-118`), and the runners' own
`--file-reporter json` streams. The join reads only `testStart` and `testDone`
events, matches on the *basename* of the test's `url` and on the reported name
*containing* the cited name (`acceptance_ledger.dart:102-126, 173-181`). Verdicts
are about the runs supplied: `PROVEN`, `FAILED`, `NOT-EXERCISED`, worst wins per
row, `NO-LIVE-CITATION` for a row citing nothing.

Two consequences matter for any replacement. A scenario that is not a `package:test`
test is invisible on both sides of that join, so a BDD runner that executes
scenarios outside `test()` breaks the ledger by construction. And the `url` is the
file that *declared* the test, so a runner that registers tests from a shared driver
file reports the driver's path, never the `.feature` path.

CI emits the stream from five jobs across two workflows
(`grep -n 'file-reporter json' .github/workflows/*.yaml`): `unit_at_client`,
`functional_tests`, `pqe2e_tests` and `legacy_server_tests` in `at_client_sdk.yaml`
and the `build_and_test` matrix in `at_libraries.yaml`. The CLI pack's job
(`functional_tests_at_onboarding_cli`, `at_libraries.yaml:303`) runs with no
reporter and no upload, although it is a declared live pack with 3 citations, so a
CI-rendered ledger can never show those rows exercised. Rendering is a local step
(`tools/acceptance_ledger.sh`), by decision.

None of this is on `origin/trunk` yet (`git grep -n 'file-reporter' origin/trunk --
.github/workflows/` finds nothing, and
`git cat-file -e origin/trunk:packages/at_client/tool/acceptance_ledger.dart` says
the file is not there). The whole mechanism lives on the spike branch, which is
worth knowing before designing its successor: the thing being replaced has not
shipped.

### 1.4 The rails that read the document's text

Several tests parse `acceptance.md` and its siblings as build inputs, and a change
to the catalogue's *shape* turns them red:

| Rail | Reads | Fails when |
|---|---|---|
| `catalogue_test.dart` | UC headings, scenario names, `blockers.dart`, the README's `**N rows**` | a heading has no scenario or a scenario names no heading; a mention is not a definition; a `skip:` has no blocker or a blocker guards nothing; counts drift |
| `catalogue_test.dart` (clause group) | `catalogueClauses()`, every `clauses:` pin | the two exact figures move without their constants; a pin resolves to 0 or 2 clauses; an unprovable entry is well-formed but proven |
| `docs_structure_test.dart` | the status table rows `^\|\s*(UC-…)\s*\|[^\|]*\|\s*(\w[\w ]*?)\s*\|`, the headline `**N PROVEN · N BLOCKED · N WITHDRAWN** across N use cases and N scenarios`, the plan's `## TODO` table, every `pq_*_test.dart` name, every cited file | a status disagrees with the tree; the headline disagrees with the table; a TODO row points at a section that says done; a `DONE` claim cites a row that is not PROVEN; a live row states no THEN clause; a test file is named nowhere under `docs/projects/pq/` |
| `architecture_guard_test.dart` | the source tree | a mechanism the catalogue says does not exist appears (the verifier's accept lever), a serializer is duplicated, a directory gains an undeclared test file |
| `acceptance_ledger_wiring_test.dart` | both workflow files, three `runLocal.sh` | an emitting job loses its reporter flag or its `if: always()` upload, `unit_at_client` loses `ACCEPTANCE_LEDGER`, a runner stops gating on `ACCEPTANCE_REPORT` |

The id shape has two homes, contrary to the manifest's own "in ONE place":
`manifest.dart:277` admits `UC-[ABCG]\d+\.\d+[a-z]?` while
`acceptance_ledger.dart:62,152` admits `UC-[A-Z][0-9]+\.[0-9]+[a-z]*`.

### 1.5 What plain Gherkin does not give you

Listed so that a design can say, for each one, *kept*, *replaced by*, or *dropped
deliberately*. The current design provides:

1. A `proves:` judgement in prose per citation, explaining why the cited test
   establishes the row.
2. A clause-level denominator parsed from the specification document itself, with
   two exact-figure columns that fail in both directions.
3. Server-proven versus in-process decided by where the proof runs, not by how the
   scenario reads.
4. Citing a test in another package without re-running it, then a separate join
   saying whether it ran.
5. Fragment pins rather than indexes, so an inserted clause re-points nothing and a
   reworded clause deliberately breaks its pin.
6. Exemptions, debts and unprovables as reviewed declarations with a minimum-length
   reason, a no-overlap rule and forced deletion once spent.
7. Withdrawn rows that keep their heading, owe nothing, and still have a status row.
8. Unnumbered cross-cutting invariants that count as rows, cite tests, and cannot
   pin clauses.
9. One catalogue row split into two scenarios by an `(a)`/`(b)` suffix the id
   grammar ignores (98 use cases, 108 scenarios).
10. A document that is design prose as well as acceptance rows, where only the Then
    structure is parsed.
11. A status table and a headline sentence generated from the tree and guarded
    against hand edits.
12. Cross-checks into the plan: a `DONE` claim must cite a proven row, a TODO row may
    not point at a finished section.
13. Nameability: every `pq_*_test.dart` and every cited file must be named somewhere
    in the doc set.
14. Blockers as named constants reconciled both ways against `skip:`.
15. Source-shaped guards that are explicitly not rows, including the ruling that an
    absence clause gets a tripwire cited without `clauses:` rather than a proof
    (gkc, 2026-08-31).
16. Verdicts about the runs supplied, never about the code.
17. The use-case id carried in the `package:test` test name, so the run-time ledger
    needs no separate row parameter.

### 1.6 Where the three live packs differ

A step library has to respect three isolation models, not one.
`tests/at_functional_test` recycles its virtualenv per run, has no `paths:`
allowlist by design, hand-allocates one-shot CRAM atSigns in `config/config.yaml`
comments, and derives its `pq` tag set with `pq_tag_test.dart`.
`tests/at_end2end_test` has two regimes: the non-PQ files run against the long-lived
`@ce2e1..@ce2e4` behind a `paths:` allowlist and a durable-write guard
(`test_preferences.dart:82-108`), while `test/pq/` runs against a per-run virtualenv
with `@eve🛠` reconfigured to a zero self-enrollment grace. The CLI pack spawns
`at_activate` as a child process per command (`cliCommandTimeout` is 120 s), runs without
`pkamLoad` because it CRAM-onboards, and leaves `*.enrollment.checkpoint` debris that
its own `runLocal.sh` does not clear (12 present at the time of reading).

The fixtures a "World" would wrap, as the survey found them: three per-pack preference
builders with different storage layouts, `legacyPlusPqProviders` declared twice,
`enrolAndAuthenticate` and `EnrolledClient` duplicated between the functional and e2e
packs with a signature gap the e2e copy records as owed. Helpers that do not exist
and Gherkin steps would need: a notification wait with a monitor positive control
(re-implemented inline in 5 files), a raw record read (inline in 32 files), a typed
enrollment fetch, a revoke or deny helper, a CRAM atSign allocator, a stop-all
teardown (`HiveInstances.closeAll` has 0 callers), a run-id and unique-namespace
factory, and a two-process driver.

#### The packs are built to run side by side, and that bears on how a migration is sequenced

Two of the three take a base port, and the design is deliberate rather than
incidental. `tests/at_functional_test/runLocal.sh` accepts one as its first argument
(`./runLocal.sh 27000` puts the root at 27000, secondaries at 27001-27080 and Redis
at 27099), and its `docker-compose.yaml` header states the purpose: the shift exists
"so it can run alongside another virtualenv (e.g. the e2e suite) on a different base
port". `tests/at_end2end_test/runLocal.sh` takes the same argument, defaulting to
26000, and its compose carries a top-level `name: at_end2end_test` and
`container_name: e2e_virtualenv` so the two projects cannot collide. Both composes
override the entrypoint to `/atsign/entrypoint.sh`, because the published image's own
CMD runs supervisord directly and would ignore the variable. CI already relies on it:
`pqe2e_tests` and `legacy_server_tests` run at 26000. On the Dart side
`TestUtils.rootServerPort`, `check_docker_readiness.dart`, `check_test_env.dart`,
`check_local_env.dart` and `local_setup.dart` all read `VIRTUALENV_BASE_PORT` and
apply the same shift, `(base + 1) - 25000`, to a secondary's port.

So the functional pack, the e2e pack and the in-process suites in `at_client` and
`at_auth` (which need no container at all) are three lanes that can advance at once,
each still `--concurrency=1` inside itself.

Two things stand between that and more lanes, and both are small. The functional
compose templates every port except `"443:443"` and `"127.0.0.1:9001:9001"`, and it
has no top-level `name:` key, so a second functional-shaped virtualenv in the same
directory would collide on those two ports and share a compose project. And the CLI
pack is not base-port aware at all: its compose hardcodes 6379, 64, 443, 9001 and
25000-25999 with no entrypoint override and no `VIRTUALENV_BASE_PORT`, which is why
its own `runLocal.sh:36` says it binds the same ports as the functional pack. Giving
it the same treatment the other two already have is straightforward and is worth doing
(gkc, 2026-09-02); the CLI pack hosts the retrofit rows and is otherwise a lane that
blocks the biggest one.

There is also a second environment. The **ephemeral environment** is built from the
at_server tree by `tools/build_ephemeral_environment/buildee.sh` as
`at_ephemeral:local`, distinct from the VE that every live pack loads
([`docs/knowledge/sdk.md`](../../knowledge/sdk.md) is the authority on the two being
different things built by different tools). Three of its properties matter to this
project: `runee.sh <name> <base-port>` runs several EEs side by side, each claiming a
100-port range bound to 127.0.0.1; an EE built at a ref *is* an atServer at that ref,
because its Dockerfile compiles the tree it was given; and its atSign list is a
mounted file defaulting to 26 phonetic-alphabet atSigns, so a lane gets atSigns named
for their role and freshly CRAM-activatable rather than drawing on a shared one-shot
pool. It serves the same `vip.ve.atsign.zone` certificates as the VE, so the root
domain literal in the packs does not change, and its `EPHEMERAL_BASE_PORT` contract is
the one `TestUtils.rootServerPort` already implements. It has been used to good effect
in practice: the at_talk demo session drove a live EE, and two findings the PQ plan
records as measured on 2026-08-26 (a first CRAM enrolment being wildcard-only, and a
retrofitted enrolment failing an authenticated verb) came from it. The standing caution
is to build every EE from a named ref and never pull `ephemeral:latest`, which is
rebuilt monthly while the VE publishes per commit.

Why this belongs in an analysis of a BDD migration: the slowest column of the work is
getting bindings green against a real atServer, and the harness already supports more
than one lane doing that. The EE's fresh-atSign property also bears directly on the
one-shot CRAM constraint that otherwise forces the retirement rule in
[`design.md` section 3.3](design.md#33-fixtures-that-do-not-exist-yet).

### 1.7 Two orphan feature files

The repo already contains two Gherkin files, and nothing has ever read them:
`tests/at_functional_test/test_scenarios/atclient_apkam.feature` (4 scenarios) and
`tests/at_onboarding_cli_functional_tests/test_scenarios/apkam/onboarding_cli.feature`
(6 scenarios), both added by Murali in March 2024; the first was hand-edited in June
2025 to track an atServer error-code change, so it is maintained prose with no
runner. `git grep -n -P '\.feature|test_scenarios' -- ':!*.feature'` returns nothing,
and `git log --all -S'test_scenarios' -- ':!*.feature'` returns no commit. They are
written in wire language ("Enroll request command is sent to the server with the
following", `| errorCode | AT0022 |`), which is a third abstraction level beside
at_java's API language and the catalogue's domain language.

## 2. The Dart BDD packages on pub.dev

The sweep covered every pub.dev result for `gherkin` (55), `bdd` (51) and the first
pages of `cucumber` and `behavior driven`, plus the cucumber GitHub organisation
(141 repositories). Fetched 2026-09-01 and 2026-09-02; each row's facts were then
re-fetched by a second reader. The four questions that decide fitness here: is it
Dart-only, does it read `.feature` files, does each scenario become a
`package:test` `test()` (so the JSON reporter, `-t`/`-x` and `--concurrency=1`
apply), and is it maintained.

| Package | Latest, published | Dart-only | Reads `.feature` | `test()` per scenario | Maintenance |
|---|---|---|---|---|---|
| `bdd_framework` | 4.0.7, 2025-12-11 | No: `flutter` and `flutter_test` deps, `flutter: >=3.0.0`, in all 15 versions | Export only | Yes, but names carry a declaration-order counter and tags are always null | Active repo (2026-04-08); unreleased `main` adds a `package:test` runner and a hard `patrol` dependency |
| `gherkin` (jonsamwell) | 3.1.0, 2022-07-01 | Yes | Yes, at run time | No: own `GherkinRunner`, the `test()` wrapper is commented out, 0 of 107 lib files import `package:test` | Dormant since 2022-12-15; `uuid ^3` conflicts with this workspace's `uuid` 4.x; issue #80 asks it to archive in favour of `cucumber_gherkin` |
| `flutter_gherkin` | 2.0.0, 2021-05-25 | No | Yes | No | Last push 2024-03-18; 47 open issues |
| `ogurets` | 4.0.3, 2022-05-23 | Yes, but `dart:mirrors` (VM JIT only) | Yes, hand-rolled regex parser (no `Rule`, no `Example:`, no `# language:`) | No: own runner, one `test()` per feature file at best | Dormant since 2023-01; `intl ^0.17` conflicts with this workspace's `intl` 0.20.2 |
| `bdd_widget_test` | 2.1.4, 2026-06-01 | Generator yes; generated code imports `flutter_test` by default | Yes, at build time via `build_runner` | Yes: one `testWidgets()` per scenario with scenario tags as `tags:` and feature tags as `@Tags` | Active; parser being replaced by `cucumber_gherkin` in open PR #124 with 4 breaking changes |
| `cucumber_gherkin` | 42.0.1, 2026-08-09 | Yes (`sdk ^3.8.0`, sole dependency `cucumber_messages`) | Yes: it is a parser and compiler to Cucumber Messages | N/A, parser only | Maintained inside `cucumber/gherkin` by the Cucumber project; verified publisher `cucumber.io`; 160/160 points |
| `gherkart` | 0.2.1, 2026-03-01 | Yes | Yes | Yes, via a user adapter, tags forwarded | 3 releases, 0 stars, last commit 2026-03-03, hand parser without `Rule` |
| `pickled_cucumber` | 1.7.0, 2026-08-27 | Yes, `dart:mirrors` | Yes | Yes, but no tags, no `group()`, no Outline, no data tables | Active, single author, "does not aim to be a full Cucumber implementation" |

Not found on pub.dev (HTTP 404): `gherkin_parser`, `cucumber_dart`, `dart_cucumber`,
`bdd`, `gherkin_wire`, `dart_bdd`, `bdd_test`. Discontinued or Dart-3-incompatible:
`spec`, `dherkin2`, `cucumber_wire`, `bdd_test_style`.

### 2.1 `bdd_framework`, the package the question named

It is a fluent Dart DSL, `Bdd(feature).scenario('..').given('..').when('..').then('..').run((ctx) async {...})`,
and it *writes* `.feature` files from those strings through a `FeatureFileReporter`;
it has no parser (the only `File(` calls in its 21 library files are the reporter's
`delete` and `create`). Every one of its 15 published versions depends on
`flutter: sdk: flutter` and `flutter_test: sdk: flutter`, so it cannot be a dev
dependency of a Dart-only package and would force `flutter test` on the live packs.
The unreleased `main` adds a `package:test` runner but also makes `patrol` (a native
Flutter plugin needing Flutter 3.32) a regular dependency, and by code reading its
Dart runner catches every error, prints it and returns, leaving the `test()` green
(`bdd_runner.dart:202-222` with a null error handler; the Flutter runners do report
the exception). Test names are `'<counter> <scenario text>'`, so inserting one
scenario renames every later one, which is hostile to a ledger keyed on names. The
cross-SDK flow it offers runs the wrong way: Dart would generate what at_java
consumes, and a feature authored or amended on the Java side could never run here.

### 2.2 The `gherkin` family is a dead end

`gherkin` 3.1.0 is the only established pure-Dart runner that reads `.feature`
files, and it executes them in its own loop from `main()`, so `dart test` sees no
scenarios and its `JsonReporter` writes a separate Cucumber-JSON-shaped file. It
also cannot be added to this workspace as published: it needs `uuid ^3.0.6` while
eight workspace pubspecs pin `uuid ^4` and the lock resolves 4.5.3. The fix PRs (#77,
#79) have sat unmerged since 2025 with no owner reply, and on 2026-08-20 the author
of `cucumber_gherkin` opened issue #80 asking the owner to recommend that package
and archive this one.

### 2.3 `bdd_widget_test` is viable only as codegen we own

It reads `.feature` files at build time and emits one test per scenario and per
Outline row, with tags in the right places. Everything else pulls against this
repo: the templates hardcode `flutter/material` and `flutter_test` imports and a
one-argument `(tester)` closure that `package:test`'s zero-argument `test()` body
rejects, so a pure-Dart use needs `customHeaders`, a hand-written shim behind
`testMethodName`, and `testerType` set to our own class (each option is documented;
the recipe is not). Step parameters are written in the feature text as Dart
expressions in braces, `{Icons.add}`, `{42}`, copied verbatim into the generated
call, which a Cucumber-JVM step definition would have to match as literal text. A
`build_runner` step lands between editing a feature and running it. And its parser
is being swapped for `cucumber_gherkin` in an open PR with four breaking changes,
including renamed Outline test titles, which are the names a ledger would key on.

### 2.4 `cucumber_gherkin` is the parser, and there is no runner

On 2026-07-16 the Cucumber project merged PR #640, "Revive package as
cucumber_gherkin", rewriting the long-dormant `dart/` directory of
`github.com/cucumber/gherkin` onto the shared Berp-generated grammar
(`gherkin.berp`, the same file Cucumber-JVM's parser is generated from), the
`cucumber_messages` types, and the common `testdata` acceptance corpus. It shipped
in Gherkin 42.0.0 (2026-07-19) and is on pub.dev as `cucumber_gherkin` 42.0.1
(2026-08-09) under the verified publisher `cucumber.io`, MIT, with `cucumber_messages`
34.2.1 beside it. Its CI runs on Dart 3.8 and 3.12 across ubuntu, windows and macos.

Its public API is one function and one options class:

```dart
List<messages.Envelope> generateMessages(String data, String uri, [GherkinOptions options]);
```

returning `source`, `gherkinDocument`, `pickle` and `parseError` envelopes. A
`Pickle` is a compiled scenario (Background merged in, Outline rows expanded) with
`name`, `uri`, `tags` and `steps`; each `PickleStep` carries `text`, an optional
`argument` (data table or doc string) and a `type` of `context`, `action` or
`outcome`, which is the Given/When/Then classification with `And`/`But` already
resolved to the preceding keyword. That last field is what makes a clause count
mechanical: an `outcome` step is a Then clause.

A scratch package outside the repo with `sdk: ^3.6.0`, `test: ^1.25.0` and
`cucumber_gherkin: ^42.0.1` resolved cleanly on the local Dart 3.12.2, and CI's
`dart-channel: [stable, beta]` both sit above the package's 3.8 floor. Step
binding, hooks, the World and the `test()` wiring are not in the package: cucumber.io's
installation page (updated 2026-09-01) lists 30 implementations and none is Dart, and
none of the 141 repositories in the cucumber organisation is Dart-named. Whatever
runs the pickles here is this repo's own code.

## 3. Cucumber facts a shared corpus depends on

Gherkin 42 grammar (`gherkin.berp`): a `Feature` has an optional `Background`,
scenarios and `Rule`s; a `Rule` has its own optional `Background` and scenarios; tags
attach to `Feature`, `Rule`, `Scenario` and `Examples` only, never to `Background` or
a step, and are inherited downwards; `Scenario Outline` is a `Scenario` with
`Examples`; `*` is a real step keyword; `# language:` selects one of 80 dialects. A
pre-18 parser rejects a tagged `Rule` (Gherkin 18.0.0, 2021-03-24).

Cucumber Messages is the NDJSON stream of `Envelope`s (28 schemas,
`jsonschema/messages.schema.json`) that Cucumber-JVM 6+, Cucumber-JS 7+ and
Cucumber-Ruby 4+ emit through their `message` formatter; Cucumber-JVM 7.x still
emits the legacy `json` too, since 7.28.0 by converting from Messages. Report tools
split along that line: `@cucumber/html-formatter` reads Messages, masterthought and
Cluecumber read legacy JSON.

Three ways implementations have shared one set of `.feature` files, oldest first:
a git submodule (`cucumber-tck`, consumed by cucumber-jvm 1.0.0 and cucumber-js 0.5.3,
archived 2019); one source repository published as a package per platform (the
current Compatibility Kit, `@cucumber/compatibility-kit` on npm,
`io.cucumber:compatibility-kit` on Maven, `cucumber-compatibility-kit` on RubyGems, all
30.0.0 on 2026-08-05, where the features are data, the steps are per language and the
contract is the message stream with volatile fields excluded); and a monorepo with a
shared `testdata/` directory every port reads in place (the Gherkin repo itself).

Cucumber-JVM 7.14 with `cucumber-junit-platform-engine` locates features through
`@SelectClasspathResource("features")`, which resolves whatever the test classpath
holds; features outside the module reach it by a Maven `<testResources>` entry, by
`@SelectDirectories`/`@SelectFile`, or by the `cucumber.features=<path>` property
(which then ignores JUnit's selectors). Tag selection differs per side: Cucumber tag
expressions use `and`/`or`/`not` and keep the `@`; `package:test` uses `&&`/`||`/`!`
on bare names declared in `dart_test.yaml`; JUnit uses `&`/`|`/`!`. Cucumber-JVM
already maps `@slow` to the JUnit tag `slow`, so one Gherkin vocabulary can serve all
three selectors if names avoid characters any of them reserves.

## 4. The at_java Cucumber pack

`at_java` runs Cucumber-JVM 7.14.0 (the 7.x line is current; 7.34.7 is the latest)
with `cucumber-junit-platform-engine`, `cucumber-picocontainer` for constructor
injection and a testcontainers `ComposeContainer` that starts
`atsigncompany/virtualenv:dev_env` when `vip.ve.atsign.zone:64` is unreachable. Seven
feature files under `at_client/src/test/resources/features/` hold 39 scenarios, 236
step lines, 141 distinct step texts and 151 step definitions, with no Outlines and no
tags. CI runs them: `.github/workflows/ci.yml` invokes
`mvn --batch-mode clean install`, failsafe binds `integration-test` and `verify`,
and run 33146133503 (2026-08-28) shows `Tests run: 39, Failures: 0 … CucumberIT`.
The most recent trunk run (2026-08-31) failed earlier, in surefire, so the Cucumber
suite did not execute that day.

The step language is API-shaped and would not bind to a Dart implementation as
written: `When AtClient.put for SharedKey test shared with @colin and value "hello
world"`, `Then exception was AtKeyNotFoundException and message matches "does not
exist in keystore"`, `When @srie Activate.onboard with SrieKeys._cramKey from
at_demo_apkam_keys.dart in at_demo_data package`. Five parameter types (`{atsign}`,
`{path}`, `{ordinal}`, `{exception}`, `{timeunit}`), a per-scenario `AtClientContext`
World keyed by `(atSign, enrollmentId)`, a three-way client addressing convention
(`{ordinal} {atsign} …`, `{atsign} …`, bare for the current client), regex-cell
tables with an empty cell as wildcard, and an `@After` teardown that scans and deletes
every non-protected key and reverses every enrollment: those are portable and worth
carrying. The `{exception}` type enumerates four Java classes, the Monitor feature
uses at_java enum spellings, and the Backgrounds carry harness lines
(`root server endpoint is vip.ve.atsign.zone:64`, `atsign keys path is …`).

at_java has no post-quantum code: `git grep -n -i -E 'mldsa|ml-dsa|mlkem|x-wing|post.?quantum|dilithium|kyber' -- '*.java'`
returns 0 lines over 179 Java files (positive control `rsa`: 26 files), PKAM signs
with `SHA256withRSA` (`AuthenticationCommands.java:130`), and the ten commits trunk
gained after the checkout add none. BouncyCastle 1.84, which it already pins, ships
ML-DSA, ML-KEM, X-Wing and HPKE (added in 1.79 and 1.78), so the primitives are on
its classpath; the wiring is not. One unmerged branch, `feat/pqc-atkeys-model`
(2026-08-11, no PR), adds the algorithm names `mldsa65`, `mlkem768`, `xwing` as open
vocabulary strings in a `CryptographicMaterial` model and performs no PQ operation.
So "at_java next" means at_java can bind the non-PQ features soon and the PQ
features only after it implements PQ; the shared format and infrastructure come
first either way.

## 5. The other SDKs

Of the 69 non-archived repositories in `atsign-foundation` (`gh repo list … --limit
300`, 111 in total, 42 archived), nine are SDKs. Only at_java has any BDD; the
recursive tree of each of the others was fetched (`truncated: false` on every one)
and grepped for `.feature`, `cucumber`, `gherkin`, `behave`, `godog`, `specflow`,
`pytest-bdd`, with the positive control matching this repo's two orphan files.

| Repo | Language | Tests today | BDD tooling in the ecosystem |
|---|---|---|---|
| `at_c` | C | hand-rolled `main()` per test under CTest, functional tests against a virtualenv compose | `cucumber-cpp` (needs Cucumber-Ruby in the loop), or C++20 runners `cwt-cucumber`, `amp-cucumber-cpp-runner` |
| `at_python` | Python | `unittest` against live atSigns; `pytest` pinned as a dev dependency but unused | `pytest-bdd` 8.1.0, `behave` 1.3.3 |
| `at_rust` | Rust | inline `#[test]`s; CI runs clippy only, no `cargo test` | `cucumber-rs` 0.23.0 |
| `at_go` | Go | none; no CI | `godog` 0.16.0 |
| `at_client_arduino`, `at_esp32`, `at_pico_w` | C, C++, MicroPython | Unity on host, none, `.exp` expected-output files | none realistic on device |

`at_protocol` holds no conformance or acceptance suite of any kind, and its
`decisions/2024-07-platform-sdks.md` promises that "an atSDK specification will be
created based on the Dart & Java implementations", which nothing has delivered. A
shared, executable feature corpus is a candidate for that specification, and the
infrastructure every SDK already converges on (the `dev_env` virtualenv image at
`vip.ve.atsign.zone:64` and the `at_demo_data` 1.2.0 key set) is what makes one
corpus runnable from more than one language.

## 6. The translation sample

Eleven rows were translated by hand into Gherkin in the catalogue's domain language,
chosen to cover every shape the catalogue uses: UC-A1.1 (bullet Then), UC-A2.1 (with a
Steps list), UC-A3.3 (headline outside the parser), UC-A5.1 (the `(a)`/`(b)` split),
UC-B5.6 (an atServer-side interlock), UC-C1.3 (withdrawn), UC-G1.2 (italic packed
style), UC-G1.7 (assertion plus control), UC-G2.9 (an unprovable clause), UC-G3.10, and
one section-13 invariant. The drafts are in [`samples/`](samples/) with the clause
maps; the full report is referenced in [section 8](#8-how-this-analysis-was-produced).

What the sample measured: 26 clauses became 102 Then/And steps (3.9 per clause) in
24 scenarios and outlines, with 110 distinct phrasings (Given 27, When 20, Then 63);
16 of those steps assert text the parser does not count today. Extrapolated to 98
rows and 232 clauses, with the assumption that Then reuse rises from the sample's
1.0 to 2.0 as a corpus grows: 560 to 650 distinct step definitions and 140 to 170
scenarios, against 108 `test()` scenarios and 364 citations today. Those are an
extrapolation from 11 rows, not a measurement, and the rate they rest on (Then reuse
rising to 2.0) is the first thing to re-measure once a cluster has landed. By the
sample's proportions, 55 to 60% of Then bindings land in `tests/at_functional_test`,
5% each in the CLI and e2e packs, and 30 to 35% in `packages/at_client` and
`packages/at_auth` unit suites, which under the evidence standard is a debt the
tags would make visible rather than a destination.

The friction that changes the design, each hit once:

- `Steps` lists, per-enrollment state tables, `Cross-ref` and `Impl/verify` bullets
  have no Gherkin home; the tables are Then steps in disguise and sometimes describe
  a different arm than the row's Given.
- Design justification ("because", "so that", "rather than") sits inside clauses;
  Gherkin keeps the outcome and loses the argument, which for UC-G2.9 is 60 of the
  row's 87 lines and is, the row says, recorded nowhere else.
- Controls are packed inside the clause they control; a control has to become its
  own scenario or an Examples row so it can go red on its own.
- Absences ("nothing encapsulates to it, at onboarding or ever") have one positive
  form, the refusal a party meets, and where no party can meet it the scenario is
  `@unprovable` with a Then no binding can pass.
- "Must run against a real atServer" is unsayable in Gherkin; a proof-level tag is a
  claim the ledger must check against where the binding runs.
- The `(a)`/`(b)` split is outside the id grammar; tags carry it.
- The Given often names what no fixture builds ("@alice pq-native" rows are proven
  with `legacyPlusPqProviders` approvers), and `enrolAndAuthenticate` fuses submit,
  approve and wait into one helper while some rows need the pending state as an
  observable.
- Section 13 invariants are outside the 232 by design; translating them grows the
  denominator by every step unless counted in a column of their own.
- Withdrawn rows are the one shape Markdown serves better: a tagged, step-less
  scenario keeps the id addressable and owes nothing, but the seventeen lines of
  *why* become comments no tool reads.
- The ledger joins `package:test` tests, and a runner exposes scenarios as tests,
  not steps; a clause-level burn-down needs a step log or a second parse of the
  `.feature`.
- A step whose truth differs by SDK ("a build that implements ML-DSA") needs a
  per-SDK tag rather than two wordings.
- at_java's features are API language, so sharing a domain-language corpus means a
  second Java step layer, not reuse of `SharedKey.feature`'s.

## 7. The Gherkin conventions already in use

Gary's `aupoqua/bdd/README.md` (13 features, not a git repo) states the house style
for feature files, and it is stricter than at_java's practice: user language only,
with mechanism names banned from scenarios; one `.feature` per epic; a Feature
narrative in user language; a `Background` for shared Givens; a tag set of `@happy`,
`@security`, `@adversarial`, `@negative`, `@residual`, `@limitation`, `@assumption`,
`@to-build`; a `# US n.n` comment tracing each scenario to its source item; and a
reusable step catalogue kept deliberately small. The catalogue's own vocabulary
(`@alice`, `alice1`, postures, namespaces) is the domain language here, and the
sample followed it. The two orphan feature files in this repo use wire language and
at_java uses API language, so three abstraction levels are in play before any
runner exists; a shared corpus has to pick one.

## 8. How this analysis was produced

Twelve reading and research agents ran in parallel (one per candidate package, one
for the Cucumber ecosystem, and one each for the in-repo mechanism, the live-pack
fixtures, the translation sample, at_java and the other SDKs), every one read-only;
`git status --short` was empty in both repos before and after. Thirteen adversarial
verifiers then took the facts the design would rest on and tried to refute each one
against its primary source. Verdicts: 5 confirmed outright, 7 confirmed with
precision corrections folded in above, and one partly refuted: the claim that no
Dart port of the official Gherkin parser exists, which is how `cucumber_gherkin`
surfaced. The full reports are working files, not part of this doc set; what they
established is here, with its source, and anything not carried here is not relied on.

Re-derive rather than quote:

```bash
cd packages/at_client && dart test test/acceptance/catalogue_test.dart --concurrency=1   # BURN-DOWN and REACHABLE lines
git grep -cP '^#{2,4} +(?:[\d.]+ +)?UC-[ABCG]\d+\.\d+[a-z]? +— ' -- docs/projects/pq/acceptance.md
grep -c "^  'UC-" packages/at_client/test/acceptance/manifest.dart                          # 41 = 3 exempt + 1 unprovable + 37 owed
curl -s https://pub.dev/api/packages/cucumber_gherkin | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["latest"]["version"],d["latest"]["published"])'
git -C ~/dev/atsign/repos/at_java grep -c -i -E 'mldsa|ml-dsa|mlkem|x-wing|post.?quantum' -- '*.java'   # no output = 0 files
```
