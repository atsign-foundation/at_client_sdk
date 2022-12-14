import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_commons/at_commons.dart';

class AtCollectionUtil {
  static AtKey formAtKey({
    required String key,
    String? sharedWith,
    int? ttl,
    int? ttb,
  }) {
    return AtKey()
      ..key = key
      ..metadata = Metadata()
      ..metadata!.ttr = -1
      ..sharedWith = sharedWith
      ..metadata!.ttl = ttl
      ..metadata!.ttb = ttb
      ..sharedBy = AtClientManager.getInstance().atClient.getCurrentAtSign();
  }
}
