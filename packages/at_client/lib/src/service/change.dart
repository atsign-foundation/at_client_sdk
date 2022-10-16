import 'package:at_client/src/service/sync_service.dart';
import 'package:at_commons/at_commons.dart';

abstract class Change {
  AtKey getKey();

  AtValue getValue();

  OperationEnum getOperation();

  /// Notifies to [AtKey.sharedWith] that a key [AtKey.key] has been newly created or the vaue
  /// of the key has changed. If internet is not available or [AtKey.sharedWith] secondary is down
  /// [onError] callback is invoked. If the key is notified successfully without any errors [onSuccess]
  /// callback is invoked.
  void notify({Function? onSuccess, Function? onError});

  /// Keeps the local storage and cloud secondary storage in sync.
  /// Pushes uncommitted local changes to remote secondary storage and vice versa.
  /// Refer [SyncService.sync] for usage details, callback usage and exceptions thrown
  Future<void> sync({Function? onDone, Function? onError, String? regex});

  /// Checks whether commit id on local storage and on cloud secondary server are the same.
  /// If the commit ids are equal then returns true. otherwise returns false.
  Future<bool> isInSync();

  /// Status of the change. #TODO replace string with enum
  String getStatus();
}
