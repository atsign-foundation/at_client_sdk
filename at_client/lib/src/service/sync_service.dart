import 'dart:async';
import 'dart:convert';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/change.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_logger.dart';

///A [SyncService] object is used to ensure data in local secondary(e.g mobile device) and cloud secondary are in sync.
class SyncService {
  var _syncInProgress = false;

  static const syncQueueSizeThreshold = 5, idleTime = 30;

  bool _isStarted = false;

  late String _atSign;

  AtClientPreference _preference;

  late RemoteSecondary _remoteSecondary;

  String? _regex;

  DateTime? _lastSyncedTime;

  List<Change> syncRequestQueue = [];

  final _logger = AtSignLogger('SyncService');

  SyncService(this._atSign, this._preference);

  void start() {
    if (_isStarted) {
      return;
    }
    // Schedule something once in 5 seconds
    Timer.periodic(const Duration(seconds: 5), (_) => _checkForChange());
  }

  void sync(Change change) {
    // Queue each sync request
    syncRequestQueue.add(change);
  }

  void _checkForChange() {
    if (syncRequestQueue.isEmpty) {
      return;
    }
    if (syncRequestQueue.length >= 5 ||
        (_lastSyncedTime != null &&
            (DateTime.now().millisecond - _lastSyncedTime!.millisecond) >
                idleTime)) {
      _sync();
    }
  }

  void _sync() {
    if (_syncInProgress) {
      _logger.finer('Another Sync process is in progress.');
      return;
    }
    _syncInProgress = true;
    try {

    } on SecondaryNotFoundException catch (e) {
      _logger.severe(e.toString());
    } on AtConnectException catch (e) {
      _logger.severe(e.toString());
    }
  }

  Future<void> _checkConnectivity() async {
    if (!(await NetworkUtil.isNetworkAvailable())) {
      throw AtConnectException('Internet connection unavailable to sync');
    }
    if (!(await _remoteSecondary.isAvailable())) {
      throw SecondaryNotFoundException('Secondary server is unavailable');
    }
  }
}
