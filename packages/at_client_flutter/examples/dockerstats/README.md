# dockerstats — Flutter dashboard for live container telemetry

A multi-platform (macOS / Linux / Windows / Android / iOS) Flutter
app that subscribes to live docker-container stats over the Atsign
Protocol, persists each sample to an on-device SQLite database
under a multi-tier roll-up, and renders four time-series charts
(CPU, Memory, Network I/O, Block I/O) over a user-selectable
window (5 m → all).

This is the **canonical worked example** of an SDK pattern that
isn't enforced by the API but is the right shape for a class of
real applications: **deliver via short-lived notifications, store
in a relational database**. It's deliberately the example for a
shape of workload where mis-applying `AtCollection<T>` would be
wrong (see [Why notifications, not AtCollection](#why-notifications-not-atcollection)
below).

> **Web is not a supported target.** The Flutter scaffold may
> generate a `web/` directory but `at_client` and
> `at_client_flutter` don't run on web — atSign onboarding and
> key storage rely on platform plugins that have no web
> implementation today. Don't try `flutter run -d chrome`.

## Where this fits

- **CLI publisher / CLI subscriber.** The matching CLI tools live
  in [`packages/at_client/example/bin/`](../../../at_client/example/bin/)
  and are documented in
  [`packages/at_client/example/README.md`](../../../at_client/example/README.md#dockerstats--notification-based-live-telemetry).
  The CLI publisher is the data source for this Flutter app; the
  CLI subscriber is a one-line-per-sample debug tool useful when
  verifying the publisher↔receiver round-trip without launching
  Flutter.
- **`AtCollection<T>` flutter sibling.** For the *opposite* shape
  of workload — a typed shared *dataset* rather than a stream of
  observations — see the
  [`todos` example](../todos/README.md). dockerstats and todos
  are deliberately positioned side-by-side to make the trade-off
  visible.
- **Flutter onboarding plumbing.**
  [`at_client_flutter`](../../README.md) — keychain storage,
  atKeys-file login, atSign-selection dialogs.

If you've never touched the platform: read the
[`at_client` README's "atSign lifecycle (short version)"](../../../at_client/README.md#atsign-lifecycle-short-version)
first — the onboarding dialogs this app uses drive that flow.

## Architecture at a glance

```
docker / simulator
        │
        ▼
publisher CLI ── notificationService.send ──▶ recipient atServer
        (one notification per container per cycle, JSON sample
         in body, 5-min ttln, no AtCollection, no sync queue)
                                                       │
                                                       ▼
                              Flutter dashboard subscribes
                                       │
                                       ▼
                        on-device SQLite (5-tier roll-up)
                                       │
                                       ▼
                                charts (fl_chart)
```

The publisher does **not** use `AtCollection<T>`. It calls
`atClient.notificationService.send(to, namespace, body, ...)` once
per sample, with the namespace derived from the container and host
names so a single subscriber regex catches all of them:

```
notification key = <recipient>:sample.<container>.<host>.dockerstats.demos<publisher>
notification body = jsonEncode(sample.toJson())
```

The dashboard subscribes once with a regex anchored on its own
atSign, decodes each body into a `StatSample`, and writes it to
the local SQLite store. Charts render off the local store; the
display-window selector controls how far back to query, not what
to fetch from the network (every sample is already on-device).

## Roll-up: balancing storage size against chart usability

The SQLite layer implements a **five-tier roll-up** that compacts
older raw samples into progressively coarser averages. Each tier
has a bucket size (the time window samples are averaged over) and
a retention duration (how long rows live at that bucket size before
being rolled into the next coarser tier).

| tier | bucket  | retention before roll-up | rows / container, steady state |
|------|---------|--------------------------|-------------------------------:|
| 0 (raw) | 5 s     | last 6 h                 | ~4320 |
| 1       | 1 min   | 6 h – 72 h               | ~3960 |
| 2       | 15 min  | 72 h – 45 d              | ~4320 |
| 3       | 1 hour  | 45 d – 6 mo              | ~4320 |
| 4       | 8 hours | 6 mo onwards, indefinite | ~1095 / year |

Tier boundaries are chosen so that **every tier holds approximately
the same number of rows per container** in steady state (within
±1.5 % at the default 5 s publishing rate) — each boundary scales
both the bucket size and the retention by the same factor (12× /
15× / 4× / 8×). Two consequences:

- **Storage stays bounded.** A year of raw 5 s samples is ~6.3 M
  rows per container; rolled up under this scheme it's ~16 k.
  Roughly 400× compression with no information loss at the
  resolution the chart can actually render.
- **Chart fidelity stays consistent across zoom levels.** At any
  selected window the chart's x-axis fits a few hundred to a few
  thousand pixels, and the rolled-up bucket size at each tier is
  the same order of magnitude as the per-pixel time span:
  - 5 m – 5 h window → tier 0 (5 s buckets, ~1 sample / px).
  - 1 d – 7 d window → tier 0 + 1 + 2 (1-min / 15-min on the
    older side).
  - 1 mo – 6 mo window → tier 2 + 3 (15-min / 1-hour).
  - 2 y – all → all tiers; tier 4 8-hour buckets on the oldest
    end.

  So the resolution roll-up drops is resolution the chart couldn't
  show anyway.

### Render-time re-bucketing

To hide the *visual* phase change as the chart crosses a tier
boundary (a denser tier-0 trace meeting the sparser tier-2 trace
would otherwise show a step in apparent sampling rate), the
dashboard does a second, render-time re-bucketing: every visible
sample is snapped to a bucket whose size matches the coarsest tier
in the selected window. Picking the 7-day window, for example,
re-buckets the on-device tier-0 5-second samples into 15-minute
buckets at render time so the whole trace is uniform-density.

The render-time helpers live in
[`lib/screens/dashboard.dart`](lib/screens/dashboard.dart)
(`_chartBucketMs` / `_rebucketSeries`).

### Aggregation semantics

Per-bucket aggregation is per-field — picked to preserve **meaning**
across roll-up boundaries, not just produce a numerically plausible
average:

| field                              | aggregation across a bucket                              |
|------------------------------------|----------------------------------------------------------|
| `cpu_pct`, `mem_usage`, `mem_pct`  | **weighted mean** (by `sample_count` of the source row)  |
| `net_rx`, `net_tx`, `blk_read`, `blk_write` | **last-in-bucket** (cumulative counters — consumers diff neighbouring buckets to recover a rate) |
| `restart_count`                    | **max** (monotonic event count)                          |
| `sample_count` (synthetic column)  | **sum** (records how many raw samples a row represents)  |

The `sample_count` column is the lever that keeps weighted means
correct across cascading roll-up passes — when a tier-2 row gets
rolled into a tier-3 bucket it still carries the count of the
underlying raw samples it represents, so a tier-2 row that
absorbed 900 raw samples weights its average accordingly against
a tier-2 row that only absorbed 60.

The algorithm is in
[`lib/services/roller.dart`](lib/services/roller.dart); unit
tests in [`test/roller_test.dart`](test/roller_test.dart) cover
the boundary firing, aggregation math, and the cascade behaviour
where a single roll-up call moves a stale sample from tier 0 all
the way through to tier 4.

Roll-up itself runs as a `Timer.periodic` job (catch-up pass at
service init, then hourly); each pass processes everything that
has aged past its tier boundary and migrates it into the next
coarser tier under a single atomic SQLite transaction.

## Why notifications, not AtCollection

The deliberate trade-off: notifications are a **transient delivery
channel** — durable storage of a high-frequency time series belongs
in a database designed for time series, not in the atServer's
key-value store, and not on a sync queue that has to push every
sample across the network.

| concern                       | `AtCollection<T>`                                       | notifications + local DB (this app)                |
|-------------------------------|---------------------------------------------------------|----------------------------------------------------|
| What it's optimized for       | typed shared *dataset* (todos, contacts, documents)     | *stream* of high-frequency observations            |
| Where authoritative data sits | atServer (per-record), sync mirrors to every viewer     | publisher chooses retention; each subscriber has its own local store |
| Per-record server cost        | one keystore entry + sync per write                     | one notification, dropped after `ttln`             |
| Per-record client storage     | follows server; sync queue maintains it                 | application chooses (here: tiered roll-up)         |
| Filter / aggregate over time  | scan local copy of dataset                              | SQL over the local store                           |
| When samples are lost         | doesn't happen — sync recovers                          | publisher-offline ≤ `ttln`: delivered; > `ttln`: gone, next sample flows |

`AtCollection<T>` is the right tool when you want a typed,
end-to-end-encrypted shared *dataset* (todos, contacts, documents)
— a tree of records each side reads, queries, and writes against.
It is the wrong tool when you want a *stream* of high-frequency
observations whose long-term storage layout (downsampling, roll-up,
retention tiering) is the dominant design concern. dockerstats
picks the right tool for each half of that pipeline.

The CLI sibling [`todos`](../todos/README.md) example shows the
*other* side of this trade-off in the same monorepo — a typed,
shared, real-time dataset rendered through the AtCollection API.

## Running

### Prerequisites

- Flutter SDK installed and a target platform configured
  (`flutter doctor` should be clean).
- One or two registered atSigns. Free atSigns at
  [my.noports.com/no-ports-plans](https://my.noports.com/no-ports-plans);
  paid / custom at [my.atsign.com](https://my.atsign.com).

### First run

The publisher and dashboard are separate processes. Open two
terminals:

```sh
# Terminal 1 — publisher (real, requires `docker` on PATH).
cd packages/at_client/example
dart run bin/dockerstats_publish.dart \
    -a @alice -P 5s --other-at-signs @bob

# Or simulated, no docker required:
dart run bin/dockerstats_publish.dart \
    -a @alice -P 2s --other-at-signs @bob \
    --simulate --simulate-hosts 3
```

```sh
# Terminal 2 — Flutter dashboard.
cd packages/at_client_flutter/examples/dockerstats
flutter pub get
flutter run -d macos    # or linux / windows / android / ios
```

The launch screen offers the same onboarding paths as the
[`todos`](../todos/README.md) example — keychain or `.atKeys`
file. After login the four-chart dashboard appears; samples start
filling in as the publisher cycle ticks.

### Seeding the DB for cross-tier chart development

To see what the dashboard looks like with realistic data across
every roll-up tier without waiting for actual roll-ups to elapse,
use the seed-DB tool:

```sh
cd packages/at_client_flutter/examples/dockerstats

# 1. Bootstrap the DB by launching the app once.
flutter run -d macos -t lib/main_smoke.dart \
  --dart-define=DOCKERSTATS_SMOKE_ATSIGN=@<your-atSign>
# (Then quit the app.)

# 2. Find the DB file the app created.
DB="$(find ~/Library -name '_<your-atSign>.db' 2>/dev/null | head -1)"

# 3. Seed a year of synthetic cross-tier data (~96 k rows).
dart run tool/seed_db.dart --db-path "$DB" --span 1y \
  --containers 6 --clear-first

# 4. Re-launch and step through the window selector
#    (5m → 15m → 1h → 5h → 1d → 7d → 1m → 6m → 2y → all).
#    Each window pulls from a different tier mix.
flutter run -d macos -t lib/main_smoke.dart \
  --dart-define=DOCKERSTATS_SMOKE_ATSIGN=@<your-atSign>
```

See the tool's own `--help` for the full set of flags
(`--run-rollup` triggers `Roller.rollUpAll()` after seeding,
useful as a no-op smoke test of the roll-up code path; the seed
samples are already pre-aligned to each tier's bucket size).

## Source tour

| Path                                                                                          | What lives there                                                              |
|-----------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------|
| [`lib/main.dart`](lib/main.dart)                                                              | App entry, `MaterialApp`, launch / onboarding switch                          |
| [`lib/main_smoke.dart`](lib/main_smoke.dart)                                                  | Headless main for the seed-DB workflow — bypasses onboarding                  |
| [`lib/onboarding.dart`](lib/onboarding.dart)                                                  | Keychain + .atKeys file login flows; AtClient construction                    |
| [`lib/models/stats_models.dart`](lib/models/stats_models.dart)                                | `StatSample` and friends — mirror of the publisher's domain types             |
| [`lib/services/dockerstats_service.dart`](lib/services/dockerstats_service.dart)              | Notification subscribe + DB write + roll-up scheduler + window cache          |
| [`lib/services/samples_db.dart`](lib/services/samples_db.dart)                                | SQLite schema, per-atSign DB path, raw insert / query helpers                 |
| [`lib/services/roller.dart`](lib/services/roller.dart)                                        | The five-tier roll-up algorithm — pure-Dart, takes a raw `Database`           |
| [`lib/services/window_cache.dart`](lib/services/window_cache.dart)                            | In-memory `ChangeNotifier` over the current window's samples; chart data source |
| [`lib/services/atsign_colors.dart`](lib/services/atsign_colors.dart)                          | Stable per-atSign / per-host / per-container colour assignment                |
| [`lib/screens/dashboard.dart`](lib/screens/dashboard.dart)                                    | Two-mode dashboard (hosts view, drill-down view); render-time re-bucketing    |
| [`lib/widgets/stats_chart.dart`](lib/widgets/stats_chart.dart)                                | One `fl_chart` time-series chart; gap-break + downsample + adaptive ticks     |
| [`test/roller_test.dart`](test/roller_test.dart)                                              | Tier transitions, aggregation math, multi-tier cascade                        |
| [`tool/seed_db.dart`](tool/seed_db.dart)                                                      | Synthetic year-of-data seeder for cross-tier chart development                |

## Tests

```sh
flutter test --concurrency=1
```

The roll-up algorithm is covered by pure-Dart unit tests in
[`test/roller_test.dart`](test/roller_test.dart) and uses
`sqflite_common_ffi`'s in-memory database (`inMemoryDatabasePath`)
so the tests run without touching disk. Widget tests live in
[`test/widget_test.dart`](test/widget_test.dart).

## Further reading

- [`packages/at_client/example/README.md` — dockerstats CLI tools](../../../at_client/example/README.md#dockerstats--notification-based-live-telemetry)
- [`at_client` README](../../../at_client/README.md) — the SDK
  this app sits on; covers `AtClient`, `NotificationService`,
  `AtCollection<T>`, the local-first sync model.
- [`at_client_flutter` README](../../README.md) — the Flutter
  onboarding layer this app uses.
- [todos example](../todos/README.md) — the AtCollection-shaped
  counterpart in the same monorepo.
