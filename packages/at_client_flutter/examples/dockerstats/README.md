# dockerstats — Flutter dashboard

Companion to `packages/at_client/example/bin/dockerstats_publish.dart`.
Receives docker container stats over the Atsign Protocol and renders
four time-series charts (CPU, Memory, Network I/O, Block I/O) over a
rolling 5-minute window.

## Three view levels

1. **All hosts** — one chart series per host, summed across the
   atSigns reporting on that host.
2. **Drill-down (per host)** — tap a host chip to see one series per
   atSign on that host.
3. **atSign filter** — chips above the charts toggle individual
   atSigns in or out of the visible set.

## Architecture

The receiver subscribes to `nodes.dockerstats.demos` (the root
`AtCollection<HostNode>`) and listens to `subUpdates` for any
descendant. On a `samples` event (`subName == 'samples'`,
ancestry length 2) we hand the ancestry plus leaf identity to
[`AtCollection.getDescendant<StatSample>`](../../../at_client/lib/src/collections/collections.dart),
which walks the parent chain (host CItem → `atsigns` sub →
atSign CItem → `samples` sub-sub) in one call and returns the
typed leaf. The whole receiver is `~10` lines of Dart on top of
the rolling-window store.

See `lib/services/dockerstats_service.dart` for the wiring and
`lib/services/rolling_window.dart` for the eviction logic. There is
also a CLI counterpart at
`packages/at_client/example/bin/dockerstats_subscribe.dart` that
uses the same `getDescendant` call and prints one line per
arriving sample — handy for verifying publisher↔receiver
round-trip without launching the Flutter app.

The publisher uses [`AtCollection.upsert`](../../../at_client/lib/src/collections/collections.dart)
for the host and atSign parent CItems so it's safely
re-runnable within the collection's TTL: a previous run's
self-keys persist server-side past process exit, and the strict
`create` verb would refuse on each restart. `upsert` doesn't.

## Running

```bash
# 1. Build the publisher in one terminal:
cd ../../../at_client/example
dart run bin/dockerstats_publish.dart \
    -a @alice -P 2s --other-at-signs @bob \
    --simulate --simulate-hosts 3

# 2. Launch the Flutter app and onboard as @bob in the other:
cd -                # back to this directory
flutter run -d macos     # or linux / android / ios
```

The dashboard appears empty until samples start arriving. Each
publisher cycle adds one point per `(host, atSign)` series. The
publisher's default 10-minute TTL means the receiver auto-prunes
stale data without any client-side eviction code.

## Notes on the sub-collection shape

Three-level nesting deliberately mirrors the model:

```
nodes (root)
  <hostId>           CItem<HostNode>
    atsigns (sub)
      <atSignId>     CItem<AtsignOnHost>
        samples (sub)
          <millis>   CItem<StatSample>      ← leaf, value = full snapshot
```

Stat-types (cpu, mem, net, block) are folded into a single snapshot
JSON value rather than split across sibling sub-collections — this is
~4× cheaper on atServer round-trips per cycle and lets the receiver
treat a sample as one atomic unit. See the publisher's
`lib/dockerstats/models.dart` for the on-wire shape.
