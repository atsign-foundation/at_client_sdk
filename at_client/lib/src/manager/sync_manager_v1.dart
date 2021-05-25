import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_commons.dart';

class SyncManagerV1 {
  var _syncInProgress = false;

  var _completionPercentage;

  String _atSign;

  SyncManagerV1(this._atSign, this._preference);

  LocalSecondary _localSecondary;

  RemoteSecondary _remoteSecondary;

  AtClientPreference _preference;

  void sync(Function successCallBack, Function errorCallback,
      {String regex}) async {
    //4. Prevent a sync when one is already in progress
    if (_syncInProgress) {
      return;
    }
    await _sync(successCallBack, errorCallback, regex: regex);
    _syncInProgress = true;
    return;
  }

  Future<void> _sync(Function successCallBack, Function errorCallback,
      {String regex}) async {
    try {
      await syncOnce(regex: regex);
      _syncInProgress = false;
    } on AtConnectException {
      // do we need await to _sync ?
      Future.delayed(Duration(seconds: 5),
          () => _sync(successCallBack, errorCallback, regex: regex));
    } on Exception catch (e) {
      // 1. Let the app developer know of a sync failure and return. It's on app developer to reinitatenthe Sync
      errorCallback(this, e);
      return;
    }
    //2. Sync method can return thr sync object that can inform if an active sync is in progress
    successCallBack(this);
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
