import 'package:at_client/src/service/sync_service.dart';
import 'package:at_utils/at_logger.dart';

/// The class represents the sync services for the end to end tests
class E2ESyncService {
  static final _logger = AtSignLogger('E2ESyncService');

  static final E2ESyncService _singleton = E2ESyncService._internal();

  E2ESyncService._internal();

  factory E2ESyncService.getInstance() {
    return _singleton;
  }

  Future<void> syncData(SyncService syncService) async {
    var _isSyncInProgress = true;

    syncService.sync(onDone: (syncResult) {
      _isSyncInProgress = false;
    });
    while (_isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 10));
    }
  }
}
