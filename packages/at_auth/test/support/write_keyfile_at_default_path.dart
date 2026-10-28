import 'package:at_auth/at_auth_io.dart';
import 'package:at_commons/at_commons.dart';

import '../test_utils/at_keys.dart';

/// Writes keys for the atSign in `args` through a `FileAtKeysIo` built with
/// no file path, so the keyfile lands at the default path under `HOME`.
Future<void> main(List<String> args) async {
  final atsign = args.single;
  await FileAtKeysIo().write(atsign, legacyAtKeys(atsign: atsign.toAtsign()));
}
