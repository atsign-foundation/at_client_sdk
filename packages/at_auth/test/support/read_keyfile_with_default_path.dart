import 'package:at_auth/at_auth_io.dart';
import 'package:at_commons/at_commons.dart' show AtException;

/// Reads keys for the atSign in `args` through a `FileAtKeysIo` built with
/// no file path, and prints how the read failed.
Future<void> main(List<String> args) async {
  try {
    await FileAtKeysIo().read(args.single);
    print('read succeeded');
  } on AtException catch (e) {
    print('${e.runtimeType}: ${e.message}');
  } catch (e) {
    print('not an AtException: $e');
  }
}
