import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_commons.dart';

class SyncManagerV1 {
  var _syncInProgress = false;

  var _completionPercentage;

  String _atSign;

  static final Map<String, SyncManagerV1> _syncManagerMap = {};

  factory SyncManagerV1(String atSign, AtClientPreference preference) {
    if (_syncManagerMap.containsKey(atSign)) {
      return _syncManagerMap[atSign];
    }
    var syncManager = SyncManagerV1(atSign, preference);
    return syncManager;
  }

  LocalSecondary _localSecondary;

  RemoteSecondary _remoteSecondary;

  AtClientPreference _preference;

  void sync(Function onDone, Function onError, {String regex}) async {
    if (_syncInProgress) {
      return;
    }
    _syncInProgress = true;
    await _sync(onDone, onError, regex: regex);

    return;
  }

  Future<void> _sync(Function onDone, Function onError, {String regex}) async {
    try {
      await syncOnce(regex: regex);
      _syncInProgress = false;
      onDone(this);
    } on AtConnectException {
      Future.delayed(
          Duration(seconds: 5), () => _sync(onDone, onError, regex: regex));
    } on Exception catch (e) {
      onError(this, e);
      return;
    }
  }

  Future<void> syncOnce({String regex}) async {
    await _checkConnectivity();
    //#TODO implement
    return;
  }

  Future<bool> isInSync({String regex}) async {
    await _checkConnectivity();
    var lastSyncedEntry =
        await SyncUtil.getLastSyncedEntry(regex, atSign: _atSign);
    var lastSyncedCommitId = lastSyncedEntry?.commitId;
    var serverCommitId =
        await SyncUtil.getLatestServerCommitId(_remoteSecondary, regex);
    var lastSyncedLocalSeq = lastSyncedEntry != null ? lastSyncedEntry.key : -1;
    var unCommittedEntries = await SyncUtil.getChangesSinceLastCommit(
        lastSyncedLocalSeq, regex,
        atSign: _atSign);
    var isInSync = SyncUtil.isInSync(
        unCommittedEntries, serverCommitId, lastSyncedCommitId);
    return isInSync;
  }

  void _checkConnectivity() async {
    if (!NetworkUtil.isNetworkAvailable()) {
      throw AtConnectException('Internet connection unavailable to sync');
    }
    if (!(await _remoteSecondary.isAvailable())) {
      throw AtConnectException('Secondary server is unavailable');
    }
  }

  bool isSyncInProgress() {
    return _syncInProgress;
  }

  int completionPercentage() {
    return _completionPercentage;
  }
}
