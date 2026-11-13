import 'dart:async';

import 'package:at_client/at_client.dart';

/// The sync service of a session whose reads and writes go to the atServer
/// ([RemoteLocalPref.remoteOnly]).
///
/// Such a client keeps nothing on the device that sync would reconcile, so a
/// sync would only copy the atServer's records into the page's memory. This
/// service never contacts the atServer: it is always in sync, and each
/// [sync] reports a success with no commit ids, which completes
/// `waitUntilCaughtUp` at once.
class NoSyncService implements SyncService {
  final String _atSign;
  final _listeners = <SyncProgressListener>{};
  static final _logger = AtSignLogger('NoSyncService');

  NoSyncService(this._atSign);

  @override
  void sync() {
    // Reported on a later microtask, as a real iteration would be, so a
    // listener added right after this call still hears it.
    scheduleMicrotask(() {
      final progress = SyncProgress()
        ..atSign = _atSign
        ..syncStatus = SyncStatus.success
        ..pendingPushCount = 0
        ..message = 'nothing on the device to sync';
      for (final listener in List.of(_listeners)) {
        try {
          listener.onSyncProgressEvent(progress);
        } catch (e, st) {
          // One listener's failure must not keep the event from the rest.
          _logger.warning('a sync progress listener threw', e, st);
        }
      }
    });
  }

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

/// The default services, with a [NoSyncService] in place of sync.
class NoSyncServiceFactory extends DefaultAtServiceFactory {
  @override
  Future<SyncService> syncService(AtClient atClient) async =>
      NoSyncService(atClient.getCurrentAtSign()!);
}
