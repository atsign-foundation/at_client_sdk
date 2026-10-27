/// Mode 0600: read and write for the owner, nothing for anyone else.
const ownerOnlyMode = 0x180;

/// Whether [writeNewOwnerOnly] can run here: never, on a platform without
/// `dart:ffi`.
bool get ownerOnlyWritesAvailable => false;

/// Not available on a platform without `dart:ffi`; callers check
/// [ownerOnlyWritesAvailable] first.
bool writeNewOwnerOnly(String path, List<int> bytes) =>
    throw UnsupportedError('Owner-only file writes need dart:ffi');
