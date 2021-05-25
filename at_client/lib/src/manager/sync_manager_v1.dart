import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_commons.dart';

class SyncManagerV1 {
  var _syncInProgress = false;

  String _atSign;

  SyncManagerV1(this._atSign);

  LocalSecondary _localSecondary;

  RemoteSecondary _remoteSecondary;

  AtClientPreference _preference;

  void sync(Function successCallBack, Function errorCallback, {String regex}) {
    if (_syncInProgress) {
      return;
    }
    _sync(successCallBack, errorCallback, regex: regex);
    _syncInProgress = true;
  }

  void _sync(Function successCallBack, Function errorCallback,
      {String regex}) async {
    syncOnce(successCallBack, errorCallback, regex: regex);
    _syncInProgress = false;
  }

  void syncOnce(Function successCallBack, Function errorCallback,
      {String regex}) async {
    if (!NetworkUtil.isNetworkAvailable()) {
      errorCallback(
          this, AtConnectException('Internet connection unavailable to sync'));
    }
    if (!(await _remoteSecondary.isAvailable())) {
      errorCallback(
          this, AtConnectException('Secondary server is unavailable'));
    }
    //#TODO implement
    successCallBack(this);
  }
}
