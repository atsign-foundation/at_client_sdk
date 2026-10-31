# SDK map: design of the first slice

A static, double-clickable map of how the at_client SDK and the Atsign
Protocol work end to end, drawn from a curated model that a generator checks
mechanically against the code. The scenarios are
[`features/at_map/sdk_map.feature`](../../../features/at_map/sdk_map.feature);
every one has a test of the same title in `tools/at_map/test`.

READ means read in source; OBSERVED means run. Refs: at_client_sdk
`70be30a99`, at_server `d654f25bd`. Two designs were drafted independently
(A, a curated model; B, extraction first), debated, and merged; where this
note cites one of them, it says which.

## 1. Home and scope

In at_client_sdk:

- the model, YAML, in `docs/map/model/`;
- the generated files, committed, in `docs/map/data/`;
- the page, `docs/map/index.html` with `app.js` and `app.css`;
- the generator, `tools/at_map`, a `publish_to: none` workspace member run as
  `dart run at_map`.

The slice is the flow `share-record`, with the exits of every server handler
on its path. Slice 1b adds `explicit-notify` and `monitor-replay`. Intents and
claims are public prose in a public repository.

## 2. The model

- `roots.yaml` pins `server` (at_server trunk) by SHA, and `production` by tag
  name and SHA.
- `lanes.yaml` holds the participants, `<atSign>.<role>[.<instance>]`, roles
  held by @alice and @bob only, and the client sub-lanes.
- `stores.yaml`, `lenses.yaml`, `ratchet.yaml` (the test-evidence figure) and
  `flows/<id>.yaml`. A model file is capped at 64 KB, and its aliases at 5,000
  expanded nodes.

A step has:

- an id, never reused; a flow lists its `retired` ids;
- a lane, an optional sub-lane, and a one-line `intent`;
- one anchor: path, symbol and `contains`, matched exactly once as tokens;
- `reached`, from the previous step unless `from` names another: a call (the
  default), a `via` chain, a `via: untraced` with a note, a `hop` (bound by a
  stream or function-field binder, or declared), a `wire` verb with its
  `sample`, or a `push`;
- `claims` (`refuses`, `authorizes`), `pre` and `post`, each with an optional
  `backing`;
- `touches`, `links` and `navigateTo`; frames (`par/opt/loop/alt`) sit on the
  flow;
- `reviewed`: the body hash `at_map bless` records.

share-record's steps:

| Step | Lane | Anchor symbol | Reached |
|---|---|---|---|
| alice-put | alice.client | `AtClientImpl._putInternal` | entry |
| alice-encrypt | alice.client | `SharedKeyEncryption.encrypt` | `via: untraced`, from alice-put |
| alice-route | alice.client | `AtClientImpl.executeUpdateOrDelete` | call, from alice-put |
| alice-enqueue | alice.client | `LocalSecondary._enqueueForSync` | via `executeVerb`, `_update` |
| alice-push | alice.client | `SyncServiceImpl._pushFromSyncQueue` | declared hop: the durable `AtSyncQueue` |
| alice-server-batch | alice.server | `BatchVerbHandler.processVerb` | wire `batch:` |
| alice-server-update | alice.server | `UpdateVerbHandler.processVerb` | wire `update:`, nested |
| alice-server-queue | alice.server | `NotificationManager.enqueue` | via `notifyAfterStore`, `notify`, `NotificationManager.notify` |
| alice-server-send | alice.server | `PerAtSignNotifSender.send` | stream hop `notifs`, via `onNotif` |
| bob-server-from | bob.server | `FromVerbHandler.processVerb` | wire `from:` |
| bob-server-pol | bob.server | `PolVerbHandler.processVerb` | wire `pol` |
| bob-server-accept | bob.server | `NotifyVerbHandler._handlePolAuthenticatedConnection` | wire `notify:`, via `processVerb` |
| bob-server-push | bob.server | `NotificationManager._pushToMonitors` | via `NotificationManager.notify`, `enqueue` |
| bob-receive | bob.client | `Monitor._onNotification` | declared push |
| bob-deliver | bob.client | `NotificationServiceImpl.handleNotificationReceipt` | function-field hop, found by the binder |

**Backing rules.** A backing comes from the claimed lane's own root: an exit
on the step's own branch path, or a Gherkin step line matching exactly once,
compared as words. A backed server claim renders "enforced by <lane>"; a
client-lane check renders "client-side, best effort". An unbacked
authorization or refusal claim fails; other unbacked text is "unverified" and
counted.

## 3. The generator's two tiers

**Tier 1, parse-only.** `parseString` over the anchored files: the anchors,
the snippets (clamped to the declaration, escaped, and without at_client_sdk
line numbers), the skeleton under each intent, the body hashes, the Gherkin
backings and the stores.

**Tier 2, resolved.** `AnalysisContextCollection` over `packages/at_client`
and `packages/at_commons` here and `packages/at_secondary_server` in at_server:
the call edges, `via` chains and binders; the dispatch table read from
`_loadVerbHandlers`, each handler's `accept` replayed by a small evaluator and
its `VerbSyntax` read in both at_commons versions; and the exit walk. It needs
`dart pub get` in at_server's `packages/at_secondary_server`, so the at_server
checkout must be at the pinned SHA and clean; files are read from it with any
test overlays on top.

Both tiers' times are in [section 10](#10-measurements).

**Outputs:**

- `build` writes `data/core.js`, plus `data/flows/<id>.js` and `<id>.md`. Each
  records the model hash, the at_server SHA and the production SHA. JSON keys
  are sorted, there are no timestamps, and `<`, `>`, `&`, U+2028 and U+2029
  are escaped.
- `build --indexes` alone writes `data/indexes.js`: test, feature and example
  links, and the test evidence. It is labelled with the at_client_sdk commit it
  was built at.
- A build stages every file in a directory beside `data/` and renames each
  into place, and writes nothing when anything fails.

## 4. The exit walk

An exit is a throw of any type, a rethrow, an early return, an error response,
or a success written before a return. Each exit records:

- its guard: the innermost condition, negated in an else;
- its branch: the enclosing branch conditions;
- the method holding it, and the helper chain to it.

The walk starts at the step's path (the dispatched handler's `processVerb`,
then the `via` chain, then the anchor). In a path method, an arm that does not
reach the next path method is off the path, so `_handleAuthenticatedConnection`
is walked but none of its exits is on bob-server-accept's path. Earlier exits'
negations are implied by order. A branch of more than 6 conditions or 500
characters is marked "path not expanded". A throw a catch clause on the path
catches, by type, is not an exit. Helpers are followed into files within the
root, four deep: implicit `this`, `super`, static and top-level calls, never a
call on another object. In a helper only throws are exits, and an
`if (...) return;` narrows the statements after it. An unhandled construct
marks the inventory "incomplete".

Fixtures with positive and negative expectations cover if/else, else-if,
early returns, switch, try/catch, rethrow, and helpers in the class, in the
file and in another file (`tools/at_map/test/fixtures/exits`). B's first
extractor shows why: it inverted else-branch conditions and found 2 of the pol
branch's 8 refusals (OBSERVED, A).

**Test evidence.** An exit is "named by (text match)", never "tested", when a
string literal in an at_server test holds every fixed segment of its message
in order. A message with fewer than 12 fixed characters is "undecided".
`ratchet.yaml` holds the figure; a fall is reported, never failed.

## 5. The gate

The `map` job runs on every pull request and every trunk push, with at_server
cloned at the pinned SHA, full history and tags.

**It blocks on:**

- the schema, the model file cap and the alias cap;
- anchors resolving exactly once as tokens;
- every transition resolving;
- samples dispatching to the stated handler, and parsing, in both at_commons
  versions;
- `core.js` and `flows/*` matching a fresh build byte for byte;
- the production tag still resolving to its pinned SHA;
- retired ids not being reused;
- the backing rules;
- the links allowlist and the size budgets;
- no server-lane step changed since review: whoever bumps the pin reads and
  blesses its server steps, so server amber never goes public.

**It reports** amber client steps (hash differs from `reviewed`), the count of
unverified text, and the test-evidence figure against `ratchet.yaml`.

**Pins.**

- The trunk pin moves in whichever at_client_sdk pull request needs newer
  server code.
- The production pin moves in an at_client_sdk pull request opened by whoever
  cuts the `pN.N.N` at_server release.
- No bot moves either pin.
- The production pin feeds one lane note and nothing else: "Server lane at
  at_server trunk `<sha>`; production `<tag>` is N commits behind."
- Step-by-step comparison is `at_map diff-prod`, local only: never committed,
  and refused when `CI` is set, since CI logs are public. The weekly
  `map_drift` job logs counts; `at_map check --server <path>` lists steps
  locally.

## 6. The page

`index.html` loads `core.js` and `app.js` as classic scripts, and each flow
file and `indexes.js` through an inserted `<script>`, under a Content Security
Policy allowing only the page's own files. Routes are
`#flow=<id>&step=<step>`; a hand-written SVG renderer draws the lanes and
sub-lanes. The step panel shows the intent, the claims and contract with their
labels, the exits with guards and test evidence, the skeleton and the
snippet; at_client_sdk files are linked by relative path and at_server files
by permalink at the pinned SHA. Text goes in only through `textContent`, links
pass an allowlist, and nothing is vendored. The budgets, `core.js` up to 300
KB and each flow file up to 1.5 MB, are choices, not measurements.

OBSERVED in headless Chrome, driven over the DevTools protocol by
`tools/at_map/test/page_test.dart`: the page opens from disk, the deep link
selects its step, every request is a `file://` URL, and embedded markup stays
text. Firefox and Safari are unobserved.

## 7. Threats

The feature file's header answers each class.

- **Races.** Trunk already requires branches up to date, with required checks
  and a review, so making `map` a required check (a settings change once the
  job exists) prevents two green pull requests breaking trunk together. A
  build stages and renames, so an interrupted one leaves whole files.
- **Replay.** Each flow file records its inputs, and the gate refuses one a
  fresh build would not reproduce; retired ids stay retired.
- **DoS.** `contains` is a token sequence, never a regular expression; model
  files, source files, aliases, branches, snippets and outputs are capped.
- **Forgery.** Authority claims must be backed from the claimed lane's root and
  path; a client check is never labelled "enforced by"; the extractor has
  fixture controls; text renders as text and links come from an allowlist.
- **Impersonation.** Lanes are roles held by @alice and @bob, and the model
  refuses any other atSign in its prose. The generator connects to no atServer
  and reads no keys.

## 8. Phase 2

Traces from a test-side `RecordingLookUps` around `AtLookUpFactory`, since
`AtLookupImpl` logs as `'AtLookup'` (READ, A and B); "tripped by" from running
tests; slice 1b; the extractor in at_server's CI.

## 9. Rejected paths

- **LikeC4**: unproven over file://, no link property on dynamic steps, and npm
  plus a second modelling language.
- **openhop**: no source or link field on nodes, and a Vite module page that
  file:// refuses.
- **Pinning the production tag:** it breaks anchors to code not yet released,
  such as `_pushToMonitors`, which is absent at `p3.19.0` (OBSERVED).
- **A step-level production badge:** it could point at an unreleased security
  fix that deployed atServers lack, which public text may not do until the fix
  ships ("Lane note only").
- **Names-only gate:** a reader cannot tell the page lags its own clone.
- **Curated server boxes:** A's box missed the pol branch's 5 silent drops
  (READ, A). `_handlePolAuthenticatedConnection` changed in 5 pull requests in
  30 days while its literal stayed green (OBSERVED, A and B).
- **Gherkin-only contracts:** no feature states that a pol peer's foreign
  sharedBy is refused (READ, A).
- **CodeGraph as the checker:** it indexes a working tree, not a pinned ref,
  and name-matches callees (OBSERVED, A and B).

## 10. Measurements

All OBSERVED on 31 Oct 2026 on an Apple silicon Mac, Dart 3.13.3, at the refs
above.

- **Build time.** Three runs of `dart run at_map build`, each a fresh process:
  6.94 s to 7.37 s wall. Inside each, tier 1 took 0.20 s and tier 2 5.64 s to
  5.85 s. `dart run at_map check` took 7.11 s wall.
- **Size.** `docs/map/data` holds 152,014 bytes: `core.js` 3,508,
  `flows/share-record.js` 130,926 and `flows/share-record.md` 17,580.
- **Determinism.** Two builds were byte-identical, and a fresh build matched
  the committed files (`cmp`, `diff -r`); `A rebuild is byte-identical` tests
  it on every run.
- **The inventory.** share-record's eight server steps hold 71 exits on their
  paths: batch 1, update 27, queue 5, send 7, from 3, pol 5, accept 19 and push
  4. The walk lists helpers' throws, drops and early returns, so it counts more
  than the 20 refusal sites design A read by hand.
- **Test evidence** (`build --indexes`): 14 of the 71 are named by a test
  (text match), 22 are named by none, and 35 are undecided, having no message
  or under 12 fixed characters of one. None of the five pol exits is named.
- **Text-match precision.** Each named exit was disabled in turn (its `throw`
  guarded off) in a scratch at_server clone, and the at_server test files that
  name it were run. Of the 13 whose tests run without a live atServer, 12 went
  red; three of those are one `validateTTR` throw reached from three call
  sites. `_checkMaxLength`'s stayed green: the tests naming it check the
  keystore's own key-length limit in at_persistence_secondary_server, so that
  match is a false positive. The 14th is named only by a live-pack test, not
  run here.
- **The suite.** `dart test --concurrency=1` in `tools/at_map`: 59 tests, the
  53 scenarios, five more fixture controls and the scenario index, in about
  3 minutes.
- **Mutation pass.** For 52 of the 53 scenarios, a mutant of the code that
  makes the check turned that scenario's test red, failing on its own
  assertion. The 53rd, an index-only change passing the job, asserts a pass;
  its test carries a control showing the change does reach the indexes.

## Rulings

1. Pin at_server trunk. The step-level production badge first ruled is
   superseded by 6.
2. An unbacked authorization or refusal claim fails; other unbacked contract
   text is "unverified" and counted.
3. The gate as synthesised: blocking, reporting, indexes outside the gate, and
   a weekly drift job.
4. The home is at_client_sdk: `docs/map/` and `tools/at_map`.
5. The first slice is share-record end to end, with the per-path server
   inventory; 1b is explicit-notify and monitor-replay.
6. "Lane note only": one public lane note, and `diff-prod` local only, never
   committed or logged in CI.
7. "Whoever releases at_server" bumps the production pin; the trunk pin moves
   in the SDK pull request that needs it; no bot moves either.
8. The drift job's log gives counts only.
9. Pin-bump pull requests bless their server steps after reading them.

Settled by both designers, not ruled: "named by (text match)" evidence for the
slice, and indexes refreshed only through an explicit pull request.
