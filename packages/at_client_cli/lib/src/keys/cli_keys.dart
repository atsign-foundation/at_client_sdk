import 'package:at_client/at_client_io.dart';
import 'package:at_client/hive.dart';
import 'package:at_client_cli/src/util/utils.dart';
import 'package:at_utils/at_utils.dart' show AtUtils;

/// The keyfile and local store a command-line program keeps for an atSign,
/// where at_client_cli's own programs keep them.
abstract final class CliKeys {
  /// The keyfile store for [atSign] at `~/.atsign/keys/<atSign>_key.atKeys`,
  /// or at [path]; encrypted under [passPhrase] when one is given.
  static FileAtKeysIo fileFor(String atSign,
      {String? path, String? passPhrase}) {
    final file = path ??
        getDefaultAtKeysFilePath(
            getHomeDirectory(throwIfNull: true)!, AtUtils.fixAtSign(atSign));
    return FileAtKeysIo(filePath: (_) => file, passPhrase: passPhrase);
  }

  /// A Hive store for [atSign] at `~/.atsign/storage/<atSign>/<program>/<id>`,
  /// or under [path]; the client closes it when it stops.
  static AtClientStorage storageFor(String atSign,
      {required String program,
      String id = defaultPathUniqueID,
      String? path}) {
    final fixed = AtUtils.fixAtSign(atSign);
    return HiveAtClientStorage(
        atSign: fixed,
        storagePath: path ??
            standardAtClientStorageDir(
                    atSign: fixed, progName: program, uniqueID: id)
                .path,
        closedByClient: true);
  }
}
