import 'package:at_auth/src/keys/io/file_io.dart' show getDefaultAtKeysFilePath;
import 'package:at_commons/at_commons.dart' show AtException;

/// The default keyfile path for [atsign] under [homeDirectory], the path
/// `FileAtKeysIo` uses when it is given none.
///
/// Throws [AtException] saying there is no home directory, and how to name
/// the keyfile instead, when [homeDirectory] is null.
String defaultAtKeysFilePathUnder(String? homeDirectory, String atsign) {
  if (homeDirectory == null) {
    throw AtException('there is no home directory to find the keyfile in; '
        "give FileAtKeysIo the keyfile's path as filePath");
  }
  return getDefaultAtKeysFilePath(homeDirectory, atsign);
}
