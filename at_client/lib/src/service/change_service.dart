import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';

import 'change.dart';

abstract class ChangeService {
  Future<Change> put(AtKey key, dynamic value);
  Future<Change> putMeta(AtKey key);
  Future<Change> delete(key);
  Future<void> sync({Function? onDone});
  bool isInSync();
  Future<AtClient> getClient();
}
