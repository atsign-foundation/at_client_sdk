# dockerstats — Flutter dashboard for live container telemetry

A multi-platform (macOS / Linux / Windows / Android / iOS) Flutter
app that subscribes to live docker-container stats over the Atsign
Protocol, persists every sample to an on-device SQLite database
under a **five-tier incremental roll-up** (tier 0 raw, then 1 min /
15 min / 1 h / 8 h aggregates, all maintained on insert), and
renders four time-series charts (CPU, Memory, Network I/O, Block
I/O). The visible time window is a fully dynamic zoomable /
scrollable range — pick a span from 5 minutes to the full data
extent and drag through history, or jump to a preset (1h / 1d /
1m / 1y / all). Charts read **one tier per query** at the
resolution the visible window needs, so a year-of-data view
renders in milliseconds.

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
       on-device SQLite — single `tiered_samples` table with a
       `granularity` column (0=raw, 1=1min, 2=15min, 3=1h, 4=8h).
       Each notification triggers ONE transaction:
         · INSERT OR IGNORE the raw row at tier 0;
         · UPSERT the bucket containing it at tiers 1..4
           (sums += values, count += 1, last-in-bucket
            preserved for cumulative counters).
                                       │
                                       ▼
       read path picks ONE tier whose source bucket ≤ chart's
       pixel-budget bucket size, optionally GROUP BY further in
       SQL to match the budget exactly
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
atSign, decodes each body into a `StatSample`, and feeds it into
the storage layer (which writes raw + maintains tier rollups in
one transaction — see "Storage" below).

## Storage: tiered, sums + count

The SQLite schema is a single `tiered_samples` table, primary key
`(granularity, at_sign, hostname, container_id, millis)`, with
each row representing one bucket at one tier:

| tier | bucket    | source values held                                      | retention            |
|------|-----------|---------------------------------------------------------|----------------------|
| 0    | raw       | one row per raw notification, `sample_count = 1`        | last 90 days only    |
| 1    | 1 min     | running sums + count of raw rows in the minute         | forever              |
| 2    | 15 min    | running sums + count of raw rows in the bucket         | forever              |
| 3    | 1 hour    | running sums + count of raw rows in the bucket         | forever              |
| 4    | 8 hours   | running sums + count of raw rows in the bucket         | forever              |

The aggregated tiers store **running sums and a count** rather
than pre-computed averages. The read query both:

  - emits the right average per row (`cpu_sum / sample_count`);
    and
  - aggregates FURTHER across multiple tier rows when the
    dashboard's pixel-budget bucket is larger than the source
    tier's bucket (`SUM(cpu_sum) / SUM(sample_count)` — a correct
    weighted mean, unlike `AVG(cpu_avg)` which would be an
    unweighted mean of means).

Cumulative monotonic counters (`net_rx`, `net_tx`, `blk_read`,
`blk_write`) are stored as the **last value in the bucket**.
Monotonic event counters (`restart_count`) keep the max.

Writes are **synchronous on insert**: one transaction per
notification containing a tier-0 `INSERT OR IGNORE` plus four
tier-1..4 UPSERTs. `INSERT OR IGNORE` makes the whole transaction
idempotent on `(at_sign, hostname, container_id, millis)` — a
re-delivered notification doesn't double-count any tier.

**Tier-0 retention.** Tier 0 (raw) is kept for the last 90 days
only; older raw rows are swept once a day. Aggregated tiers 1–4
are kept indefinitely, and because they're maintained incrementally
during each bucket's lifetime, dropping older raw rows doesn't lose
any chart fidelity — the aggregated tiers carry every metric the
dashboard reads at all but the very newest windows. At the
publisher's default 5 s cadence that caps disk growth to ~3 GB
per container per 90 days for raw plus a few hundred MiB per
container per year for the aggregated tiers.

## Read path: pick a tier per window

For each visible time range the dashboard picks **one tier** whose
natural bucket is ≤ the chart's pixel-budget bucket (~1000
buckets per series). When the visible span / 1000 lands between
two tier sizes, the query reads the coarser tier and runs one
additional SQL `GROUP BY` to combine multiple tier rows into
chart-budget buckets.

Indicative behaviour for a year of 5 s data (38 M tier-0 rows,
~9 % more across tiers 1–4):

| visible span      | chosen tier | source rows scanned | chart-budget bucket  | query time  |
|-------------------|-------------|--------------------:|----------------------|------------:|
| 5 min – 1 h       | 0 (raw)     | ≤ 4,000             | 5 s                  | < 5 ms      |
| 5 h               | 0           | ~21,000             | ~18 s                | ~15 ms      |
| 1 d               | 1 (1 min)   | ~8,600              | ~1.4 min             | < 10 ms     |
| 7 d               | 1           | ~60,000             | ~10 min              | ~40 ms      |
| 1 mo              | 2 (15 min)  | ~17,000             | ~43 min              | ~10 ms      |
| 6 mo              | 3 (1 h)     | ~26,000             | ~4.3 h               | ~15 ms      |
| 1 y, 2 y, all     | 4 (8 h)     | ~6,600              | ~8.8 h               | < 10 ms     |

Every window comes in well under the human "instant" threshold
because no query ever scans more than a few tens of thousands of
rows, regardless of how dense the underlying raw data is. There's
no rendering or visual seam at the tier boundary — the dashboard
reads a single tier per query.

## Incremental live updates

Each new notification:

  1. is `INSERT`ed at tier 0 and rolled into tiers 1–4 in one
     transaction (the synchronous write path described above);
  2. is also folded into the in-memory
     [`WindowCache`](lib/services/window_cache.dart) — when the
     sample falls inside the currently visible range, the cache
     merges it into the existing accumulator for its bucket. The
     chart's latest-bucket value updates smoothly as new samples
     fold in. Samples outside the current visible range are
     dropped from the live-update path (they're already in the
     DB and surface on the next range change).

There's no DB re-query per notification. The SQL aggregation only
runs on a range change. At the publisher default 5 s cadence × 6
containers that's ~1 cache merge / second per notification —
nothing.

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
| Per-record client storage     | follows server; sync queue maintains it                 | application chooses (here: raw kept 90 d, tier-rollups kept forever) |
| Filter / aggregate over time  | scan local copy of dataset                              | SQL over the local store                           |
| When samples are lost         | doesn't happen — sync recovers                          | publisher-offline ≤ `ttln`: delivered; > `ttln`: gone, next sample flows |

`AtCollection<T>` is the right tool when you want a typed,
end-to-end-encrypted shared *dataset* (todos, contacts, documents)
— a tree of records each side reads, queries, and writes against.
It is the wrong tool when you want a *stream* of high-frequency
observations whose query / aggregation / windowing is the dominant
design concern. dockerstats picks the right tool for each half of
that pipeline.

The CLI sibling [`todos`](../todos/README.md) example shows the
*other* side of this trade-off in the same monorepo — a typed,
shared, real-time dataset rendered through the AtCollection API.

## Dashboard controls: visible time range

The visible time range is a freely scrollable, freely zoomable
window. The toolbar above the chart grid carries (left to right):

- ⏪ / ◀ — pan left by one full span / by half a span.
- − / + — zoom out / in by 2×, **centred on the current view's
  midpoint**.
- ▶ / ⏩ — pan right by half / one full span.
- A readout — either `"Past 1h (live)"` when the right edge is
  pinned to `now`, or `"<from> → <to> (<span> ending <relative>
  ago)"` when scrolled to a historical window.
- Preset chips: **1h · 1d · 1m · 1y · all**. Tapping one jumps to
  a live range of that span; `all` zooms out to the full data
  extent.
- A **LIVE** badge — **bright blue when live, dimmed when
  historical** — also a button to snap back to live without
  losing the current span.
- A **Fit** button — zooms the range to cover all data and pins
  live.

The 2×2 chart grid also accepts **mouse-wheel zoom** (cursor-
anchored — the time point under the pointer stays fixed across
zoom) and **click-drag pan** (drag right to reveal older data,
drag left to advance toward `now`). Both gestures share the same
"snap to live when past `now`, clamp at earliest sample on the
left" rules as the toolbar buttons.

The minimum visible span is 5 minutes; the maximum is the full
data extent. Zooming out beyond available data does nothing
(no extrapolation past `earliestMs`); zooming in past 5 min stops
at 5 min.

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

### Seeding the DB for cross-window chart development

To see what the dashboard looks like with realistic data across
all the window selectors without waiting for a real publisher to
emit samples for hours / days / months, use the seed-DB tool:

```sh
cd packages/at_client_flutter/examples/dockerstats

# 1. Bootstrap the DB by launching the app once.
flutter run -d macos -t lib/main_smoke.dart \
  --dart-define=DOCKERSTATS_SMOKE_ATSIGN=@<your-atSign>
# (Then quit the app.)

# 2. Find the DB file the app created.
DB="$(find ~/Library -name '_<your-atSign>.db' 2>/dev/null | head -1)"

# 3. Seed 90 days of synthetic samples at 30s spacing
#    (~260k tier-0 rows / container × 6 = ~1.5M raw rows,
#    plus tiers 1–4 populated by cascading SQL GROUP BY).
dart run tool/seed_db.dart --db-path "$DB" \
  --span 90d --rate 30s --containers 6 --clear-first

# 4. Re-launch and exercise the zoom / pan controls. Every
#    visible window reads from one tier — no rendering pause
#    even at "all" over a full year of 5s data.
flutter run -d macos -t lib/main_smoke.dart \
  --dart-define=DOCKERSTATS_SMOKE_ATSIGN=@<your-atSign>
```

The seed tool writes tier-0 rows at the publisher cadence you
choose, then post-aggregates tiers 1–4 via cascading SQL
`GROUP BY` — each tier built from the one immediately below.
Output is indistinguishable from a DB populated by a live
publisher running for the same span.

To stress-test the worst-case ("all" over a year of 5 s data,
~38 M raw rows), pass `--rate 5s --span 1y`. The raw seed takes
several minutes; the aggregated tiers add ~1 minute total. The
benchmark tool [`tool/bench_queries.dart`](tool/bench_queries.dart)
times each window's query against the resulting DB and is what
produced the per-window numbers in [Read path: pick a tier per
window](#read-path-pick-a-tier-per-window) above.

## Source tour

| Path                                                                                          | What lives there                                                              |
|-----------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------|
| [`lib/main.dart`](lib/main.dart)                                                              | App entry, `MaterialApp`, launch / onboarding switch                          |
| [`lib/main_smoke.dart`](lib/main_smoke.dart)                                                  | Headless main for the seed-DB workflow — bypasses onboarding                  |
| [`lib/onboarding.dart`](lib/onboarding.dart)                                                  | Keychain + .atKeys file login flows; AtClient construction                    |
| [`lib/models/stats_models.dart`](lib/models/stats_models.dart)                                | `StatSample` and friends — mirror of the publisher's domain types             |
| [`lib/models/visible_range.dart`](lib/models/visible_range.dart)                              | `VisibleRange` value class + pure-function transformations (zoom / pan / live / fit) |
| [`lib/services/dockerstats_service.dart`](lib/services/dockerstats_service.dart)              | Notification subscribe + DB write + tier pick + cache management              |
| [`lib/services/samples_db.dart`](lib/services/samples_db.dart)                                | `tiered_samples` schema, transactional insert + UPSERT, range-aware query     |
| [`lib/services/window_cache.dart`](lib/services/window_cache.dart)                            | In-memory `ChangeNotifier` over the current range; bucket accumulators        |
| [`lib/services/atsign_colors.dart`](lib/services/atsign_colors.dart)                          | Stable per-atSign / per-host / per-container colour assignment                |
| [`lib/screens/dashboard.dart`](lib/screens/dashboard.dart)                                    | Two-mode dashboard, range control bar, wheel-zoom + drag-pan gestures         |
| [`lib/widgets/stats_chart.dart`](lib/widgets/stats_chart.dart)                                | One `fl_chart` time-series chart; gap-break + adaptive ticks                  |
| [`tool/seed_db.dart`](tool/seed_db.dart)                                                      | Synthetic-data seeder: tier-0 raw write + cascading tier-1..4 roll-up         |
| [`tool/bench_queries.dart`](tool/bench_queries.dart)                                          | Per-window SQL-query timing harness against a seeded DB                       |

## Tests

```sh
flutter test --concurrency=1
```

Widget tests live in [`test/widget_test.dart`](test/widget_test.dart).

## Further reading

- [`packages/at_client/example/README.md` — dockerstats CLI tools](../../../at_client/example/README.md#dockerstats--notification-based-live-telemetry)
- [`at_client` README](../../../at_client/README.md) — the SDK
  this app sits on; covers `AtClient`, `NotificationService`,
  `AtCollection<T>`, the local-first sync model.
- [`at_client_flutter` README](../../README.md) — the Flutter
  onboarding layer this app uses.
- [todos example](../todos/README.md) — the AtCollection-shaped
  counterpart in the same monorepo.
