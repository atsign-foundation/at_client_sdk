
import 'package:at_commons/at_commons.dart';

abstract class Change {
  AtKey getKey();

  AtValue getValue();

  OperationEnum getOperation();

  void notify({Function? onSuccess, Function? onError});

  void sync({Function? onDone});

  /// True if in sync
  bool isInSync();

  /// Status of the change. #TODO replace string with enum
  String getStatus();
}