/// Owns the AtCollections that back the dockerstats dashboard.
///
/// Two listeners on the root `nodes` collection drive the rolling
/// window:
///   - `subUpdates`: each `samples`-level update walks the parent
///     chain via [AtCollection.getDescendant] to fetch the typed
///     `CItem<StatSample>`, then adds it to the window.
///   - `subDeletes`: each `samples`-level delete (most often a
///     keystore-side TTL expiry, dispatched from
///     `DataDeleted(wasExpired: true)` on the data-event path) maps
///     `event.id` (= the publisher's `s.millis.toString()`) back to
///     the matching sample and removes it from the window.
library;

import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;

import '../models/stats_models.dart';
import 'rolling_window.dart';

const String dockerstatsNamespace = 'dockerstats.demos';
const String collectionRootName = 'nodes';
const String subAtsignsName = 'atsigns';
const String subSamplesName = 'samples';
const Duration sampleExpiration = Duration(minutes: 10);

class DockerstatsService {
  final AtClient atClient;
  final RollingWindow window;
  final _log = AtSignLogger('dockerstats');

  late final AtCollection<HostNode> nodes;

  StreamSubscription<CSubItemUpdated>? _subUpdatesSub;
  StreamSubscription<CSubItemDeleted>? _subDeletesSub;

  DockerstatsService({required this.atClient, RollingWindow? window})
    : window = window ?? RollingWindow();

  Future<void> init() async {
    AtCollection.registerFactory<HostNode>(
      HostNode.fromJson,
      typeTag: 'HostNode',
    );
    AtCollection.registerFactory<AtsignOnHost>(
      AtsignOnHost.fromJson,
      typeTag: 'AtsignOnHost',
    );
    AtCollection.registerFactory<StatSample>(
      StatSample.fromJson,
      typeTag: 'StatSample',
    );

    nodes = await atClient.collection<HostNode>(
      '$collectionRootName.$dockerstatsNamespace',
      sampleExpiration,
      eventSource: EventSource.both,
    );

    _subUpdatesSub = nodes.subUpdates.listen(
      _onSubUpdate,
      onError: (Object e, StackTrace st) =>
          _log.warning('subUpdates error: $e\n$st'),
    );
    _subDeletesSub = nodes.subDeletes.listen(
      _onSubDelete,
      onError: (Object e, StackTrace st) =>
          _log.warning('subDeletes error: $e\n$st'),
    );

    // Seed the rolling window from anything the previous session
    // already synced into the local keystore. Subscriptions are
    // attached first so any concurrent live events are not lost;
    // [RollingWindow.add] is idempotent on (host, atSign, millis),
    // so a backfilled sample arriving twice (once via getItems,
    // once via a live event) is safe.
    await _backfill();
  }

  /// Walk the parent chain (nodes → atsigns → samples) and seed the
  /// rolling window from everything currently in the local keystore.
  /// Each level's failure is logged and skipped — one bad host or
  /// atSign chain doesn't abort the rest.
  Future<void> _backfill() async {
    try {
      final hosts = await nodes.getItems();
      for (final hostItem in hosts) {
        final atsignsColl = nodes.subCollection<AtsignOnHost>(
          parent: hostItem,
          subName: subAtsignsName,
          defaultExpiration: sampleExpiration,
        );
        try {
          final atsigns = await atsignsColl.getItems();
          for (final atsignItem in atsigns) {
            final samplesColl = atsignsColl.subCollection<StatSample>(
              parent: atsignItem,
              subName: subSamplesName,
              defaultExpiration: sampleExpiration,
            );
            try {
              final samples = await samplesColl.getItems();
              for (final sampleItem in samples) {
                window.add(sampleItem.obj);
              }
            } catch (e, st) {
              _log.warning(
                'backfill samples for atsign=${atsignItem.id} '
                'host=${hostItem.id}: $e\n$st',
              );
            }
          }
        } catch (e, st) {
          _log.warning('backfill atsigns for host=${hostItem.id}: $e\n$st');
        }
      }
    } catch (e, st) {
      _log.warning('backfill hosts: $e\n$st');
    }
  }

  Future<void> _onSubUpdate(CSubItemUpdated e) async {
    if (e.subName != subSamplesName || e.ancestry.length != 2) return;
    // Skip any defensive null-owner events. With current at_client the
    // notification path recovers `parents` from the decrypted payload
    // directly, so this should be unreachable for live events — but
    // legacy items predating that change can still surface here.
    if (e.ancestry.any((a) => a.owner == null)) return;
    try {
      final item = await nodes.getDescendant<StatSample>(
        ancestry: e.ancestry,
        id: e.id,
        owner: e.owner,
        leafExpiration: sampleExpiration,
        leafFromJson: StatSample.fromJson,
        leafTypeTag: 'StatSample',
      );
      if (item != null) {
        window.add(item.obj);
      }
    } catch (err, st) {
      _log.warning('failed to fetch sample ${e.id}: $err\n$st');
    }
  }

  void _onSubDelete(CSubItemDeleted e) {
    if (e.subName != subSamplesName || e.ancestry.length != 2) return;
    window.removeById(e.id);
  }

  void dispose() {
    _subUpdatesSub?.cancel();
    _subDeletesSub?.cancel();
  }
}
