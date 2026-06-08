import 'package:at_auth/src/keys/legacy/legacy_file_at_keys_io.dart';

export 'package:at_auth/src/keys/legacy/legacy_file_at_keys_io.dart'
    show getDefaultAtKeysFilePath, getHomeDirectory;

/// Compatibility wrapper for the legacy fixed-field file implementation.
///
/// Existing callers can continue using [FileAtKeysIo]. New code that needs to
/// be explicit about fixed-field legacy file behavior can use
/// [LegacyFileAtKeysIo] internally.
class FileAtKeysIo extends LegacyFileAtKeysIo {
  FileAtKeysIo({super.filePath, super.passPhrase});
}
