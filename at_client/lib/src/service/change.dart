
import 'package:at_commons/at_commons.dart';

abstract class Change {
  AtKey getKey();

  AtValue getValue();

  OperationEnum getOperation();

  void notify({Function? onSuccess, Function? onError});

  Future<void> sync({Function? onDone, Function? onError,String? regex});

  /// True if in sync
  Future<bool> isInSync();

  /// Status of the change. #TODO replace string with enum
  String getStatus();
}