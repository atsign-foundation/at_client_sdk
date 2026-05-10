/// Owns the AtCollections that back the dockerstats dashboard.
///
/// Subscribes to the root `nodes` collection's `subUpdates` stream;
/// for each `samples` event we fetch the typed leaf via
/// [AtCollection.getDescendant], which walks the parent chain
/// (nodes → atsigns → samples) internally and returns the typed
/// `CItem<StatSample>`.
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

  void dispose() {
    _subUpdatesSub?.cancel();
  }
}
