import 'dart:async';

import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_client/src/service/sync_service_impl.dart';

/// The [SyncService] for a client whose storage writes straight through to
/// the atServer: there is no local replica, so every [sync] reports success
/// without touching the network.
class WriteThroughSyncService implements SyncService {
  WriteThroughSyncService(this.atSign);

  final String? atSign;

  final _listeners = <SyncProgressListener>{};

  Function? _onDone;

  @override
  void sync(
      {@Deprecated('Use SyncProgressListener') Function? onDone,
      Function? onError}) {
    final done = onDone ?? _onDone;
    scheduleMicrotask(() {
      final now = DateTime.now().toUtc();
      final progress = SyncProgress()
        ..syncStatus = SyncStatus.success
        ..atSign = atSign
        ..startedAt = now
        ..completedAt = now
        ..pendingPushCount = 0;
      for (final listener in List.of(_listeners)) {
        listener.onSyncProgressEvent(progress);
      }
      done?.call(SyncResult()
        ..syncStatus = SyncStatus.success
        ..lastSyncedOn = now
        ..dataChange = false);
    });
  }

  @override
  @Deprecated('Use SyncProgressListener')
  void setOnDone(Function onDone) => _onDone = onDone;

  @override
  Future<bool> isInSync() async => true;

  @override
  bool get isSyncInProgress => false;

  @override
  void addProgressListener(SyncProgressListener listener) =>
      _listeners.add(listener);

  @override
  void removeProgressListener(SyncProgressListener listener) =>
      _listeners.remove(listener);

  @override
  void removeAllProgressListeners() => _listeners.clear();
}

/// The default [SyncService] for [client]: a [WriteThroughSyncService] when
/// its storage does not replicate the atServer, otherwise a [SyncServiceImpl].
Future<SyncService> defaultSyncServiceFor(AtClient client) async {
  if (client is AtClientImpl && client.storage?.replicatesServer == false) {
    return WriteThroughSyncService(client.getCurrentAtSign());
  }
  return await SyncServiceImpl.create(client);
}
