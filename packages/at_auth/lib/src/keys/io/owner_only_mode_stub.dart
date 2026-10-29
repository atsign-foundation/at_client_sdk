/// Mode 0600: read and write for the owner, nothing for anyone else.
const ownerOnlyMode = 0x180;

/// A file's owner and group, as numeric ids.
typedef OwnerAndGroup = ({int uid, int gid});

/// What [readNoFollow] read: the file's bytes, and its owner and group, or
/// null when they cannot be reported.
typedef KeyfileRead = ({List<int> bytes, OwnerAndGroup? owner});

/// Whether [writeNewOwnerOnly] can run here: never, on a platform without
/// `dart:ffi`.
bool get ownerOnlyWritesAvailable => false;

/// Whether this process runs with an effective user id of 0; never reported
/// on a platform without `dart:ffi`.
bool get runningAsRoot => false;

/// Not available on a platform without `dart:ffi`; callers check
/// [ownerOnlyWritesAvailable] first.
KeyfileRead readNoFollow(String path) =>
    throw UnsupportedError('Reading a file without following a link needs '
        'dart:ffi');

/// Not available on a platform without `dart:ffi`; callers check
/// [ownerOnlyWritesAvailable] first.
({bool modeSet, bool ownerSet}) writeNewOwnerOnly(String path, List<int> bytes,
        {OwnerAndGroup? owner}) =>
    throw UnsupportedError('Owner-only file writes need dart:ffi');

/// Not available on a platform without `dart:ffi`; callers check
/// [ownerOnlyWritesAvailable] first.
bool createNewWith(String path, List<int> bytes) =>
    throw UnsupportedError('Creating a file through one descriptor needs '
        'dart:ffi');

/// Not available on a platform without `dart:ffi`; callers check
/// [ownerOnlyWritesAvailable] first.
bool touchNoFollow(String path) =>
    throw UnsupportedError('Setting the times of a file without following a '
        'link needs dart:ffi');
