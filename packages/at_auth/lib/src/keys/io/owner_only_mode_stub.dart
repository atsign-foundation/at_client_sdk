/// Mode 0600: read and write for the owner, nothing for anyone else.
const ownerOnlyMode = 0x180;

/// A file's owner and group, as numeric ids.
typedef OwnerAndGroup = ({int uid, int gid});

/// What [KeyfileDirectory.read] read: the file's bytes, and its owner and
/// group, or null when they cannot be reported.
typedef KeyfileRead = ({List<int> bytes, OwnerAndGroup? owner});

/// Whether [writeNewOwnerOnly] can run here: never, on a platform without
/// `dart:ffi`.
bool get ownerOnlyWritesAvailable => false;

/// Whether this process runs with an effective user id of 0; never reported
/// on a platform without `dart:ffi`.
bool get runningAsRoot => false;

/// A directory opened once; not available on a platform without `dart:ffi`,
/// where callers never open one because [runningAsRoot] is false.
final class KeyfileDirectory {
  KeyfileDirectory._();

  /// Not available on a platform without `dart:ffi`.
  static KeyfileDirectory open(String path) =>
      throw UnsupportedError('Opening a directory needs dart:ffi');

  /// The path the directory was opened at.
  String get path => throw UnsupportedError('Needs dart:ffi');

  /// Not available on a platform without `dart:ffi`.
  bool exists(String name) => throw UnsupportedError('Needs dart:ffi');

  /// Not available on a platform without `dart:ffi`.
  KeyfileRead read(String name) => throw UnsupportedError('Needs dart:ffi');

  /// Not available on a platform without `dart:ffi`.
  ({bool modeSet, bool ownerSet}) replace(String name, List<int> bytes,
          {OwnerAndGroup? owner}) =>
      throw UnsupportedError('Needs dart:ffi');

  /// Not available on a platform without `dart:ffi`.
  void close() => throw UnsupportedError('Needs dart:ffi');
}

/// Not available on a platform without `dart:ffi`; callers check
/// [ownerOnlyWritesAvailable] first.
({bool modeSet, bool ownerSet}) writeNewOwnerOnly(String path, List<int> bytes,
        {OwnerAndGroup? owner}) =>
    throw UnsupportedError('Owner-only file writes need dart:ffi');
