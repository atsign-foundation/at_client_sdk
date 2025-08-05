import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_commons/at_commons.dart';

class AtCollectionUtil {
  static AtClient? atClient;

  static AtClient _getAtClient() {
    atClient ??= AtClientManager.getInstance().atClient;

    return atClient!;
  }

  static AtKey formAtKey({
    required String key,
    String? sharedWith,
    int? ttl,
    int? ttb,
  }) {
    return AtKey()
      ..key = key
      ..metadata = Metadata()
      ..metadata.ttr = -1
      ..sharedWith = sharedWith
      ..metadata.ttl = ttl
      ..metadata.ttb = ttb
      ..sharedBy = _getAtClient().getCurrentAtSign();
  }
}
