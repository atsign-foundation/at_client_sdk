import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

/// Mode 0600: read and write for the owner, nothing for anyone else.
const ownerOnlyMode = 0x180;

/// A file's owner and group, as numeric ids.
typedef OwnerAndGroup = ({int uid, int gid});

/// What [readNoFollow] read: the file's bytes, and its owner and group, or
/// null when this libc cannot report them.
typedef KeyfileRead = ({List<int> bytes, OwnerAndGroup? owner});

/// Whether [writeNewOwnerOnly] can run here: Linux or macOS, with the libc
/// calls it makes found.
bool get ownerOnlyWritesAvailable => _Libc.instance != null;

/// Whether this process runs with an effective user id of 0.
bool get runningAsRoot =>
    runningAsRootForTesting ?? _Libc.instance?.geteuid() == 0;

/// Stands in for the effective user id in [runningAsRoot] when set, so a
/// test run by an account that is not root still drives the branch root
/// takes.
@visibleForTesting
bool? runningAsRootForTesting;

/// Reads the file at [path] through one descriptor opened without following
/// a symbolic link, taking its owner and group from that descriptor.
///
/// Throws [FileSystemException] when [path] is a symbolic link or anything
/// other than a regular file, or cannot be read.
///
/// NOTE: opened non-blocking, so a FIFO at [path] is refused rather than
/// blocking this isolate inside the open until something writes to it.
KeyfileRead readNoFollow(String path) {
  final libc = _Libc.instance!;
  final flags = libc.openForReadingNoFollow;
  if (flags == null) {
    throw FileSystemException(
        'Cannot open a file without following a link on this platform', path);
  }
  final nativePath = path.toNativeUtf8();
  final int fd;
  try {
    fd = libc.open(nativePath, flags, 0);
  } finally {
    malloc.free(nativePath);
  }
  if (fd < 0) {
    throw FileSystemException(
        'Cannot open the file without following a link', path);
  }
  try {
    final owner = _fdOwnerReader?.call(fd, path);
    return (bytes: _readAll(libc, fd, path), owner: owner);
  } finally {
    libc.close(fd);
  }
}

/// Writes [bytes] to a file this call creates at [path], readable and
/// writable by its owner alone before any byte reaches it, and given [owner]
/// when one is named.
///
/// Says whether the file system took the mode and whether the owner was set;
/// the bytes are written either way. Throws [FileSystemException] when
/// anything already exists at [path], a symbolic link included, or the file
/// cannot be created or written.
({bool modeSet, bool ownerSet}) writeNewOwnerOnly(String path, List<int> bytes,
    {OwnerAndGroup? owner}) {
  final libc = _Libc.instance!;
  final fd = _createNew(libc, path, ownerOnlyMode);
  if (fd < 0) {
    throw FileSystemException('Cannot create the file', path);
  }
  try {
    final ownerSet =
        owner == null || libc.fchown(fd, owner.uid, owner.gid) == 0;
    final modeSet = libc.fchmod(fd, ownerOnlyMode) == 0;
    _writeAll(libc, fd, bytes, path);
    return (modeSet: modeSet, ownerSet: ownerSet);
  } finally {
    libc.close(fd);
  }
}

/// Creates a file at [path] holding [bytes], written through the descriptor
/// that created it, so nothing put at [path] after the create is written
/// through.
///
/// Returns false, having written nothing, when anything already exists at
/// [path], a symbolic link included, or the file cannot be created. Throws
/// [FileSystemException] when the file was created but [bytes] could not be
/// written, after removing it.
bool createNewWith(String path, List<int> bytes) {
  final libc = _Libc.instance!;
  // NOTE: 0666, narrowed by the umask, as dart:io creates a file.
  final fd = _createNew(libc, path, 0x1b6);
  if (fd < 0) return false;
  try {
    _writeAll(libc, fd, bytes, path);
  } on FileSystemException {
    libc.close(fd);
    try {
      File(path).deleteSync();
    } on FileSystemException {
      // NOTE: already gone; nothing left to remove.
    }
    rethrow;
  }
  libc.close(fd);
  return true;
}

/// Sets the access and modification times of whatever is at [path] to now,
/// without following a symbolic link there; says whether they were set.
bool touchNoFollow(String path) {
  final libc = _Libc.instance!;
  final nativePath = path.toNativeUtf8();
  try {
    return libc.utimensat(
            libc.currentDirectory, nativePath, nullptr, libc.noFollow) ==
        0;
  } finally {
    malloc.free(nativePath);
  }
}

/// Opens a file this call creates at [path] with [mode] for writing, or
/// returns a negative number when anything is already there or it cannot be
/// created.
int _createNew(_Libc libc, String path, int mode) {
  final nativePath = path.toNativeUtf8();
  try {
    return libc.open(nativePath, libc.createNewForWriting, mode);
  } finally {
    malloc.free(nativePath);
  }
}

void _writeAll(_Libc libc, int fd, List<int> bytes, String path) {
  final buffer = malloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
  try {
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    var written = 0;
    while (written < bytes.length) {
      final count = libc.write(fd, buffer + written, bytes.length - written);
      if (count <= 0) {
        throw FileSystemException('Cannot write the file', path);
      }
      written += count;
    }
  } finally {
    malloc.free(buffer);
  }
}

List<int> _readAll(_Libc libc, int fd, String path) {
  const chunk = 65536;
  final buffer = malloc<Uint8>(chunk);
  final bytes = BytesBuilder(copy: true);
  try {
    while (true) {
      final count = libc.read(fd, buffer, chunk);
      if (count < 0) {
        throw FileSystemException('Cannot read the file', path);
      }
      if (count == 0) return bytes.takeBytes();
      bytes.add(buffer.asTypedList(count));
    }
  } finally {
    malloc.free(buffer);
  }
}

typedef _OpenFunction = int Function(Pointer<Utf8>, int, int);
typedef _FdModeFunction = int Function(int, int);
typedef _FdOwnerFunction = int Function(int, int, int);
typedef _ReadWriteFunction = int Function(int, Pointer<Uint8>, int);
typedef _CloseFunction = int Function(int);
typedef _UidFunction = int Function();
typedef _UtimensatFunction = int Function(
    int, Pointer<Utf8>, Pointer<Void>, int);

final class _Libc {
  _Libc._(
      {required this.createNewForWriting,
      required this.openForReadingNoFollow,
      required this.open,
      required this.fchmod,
      required this.fchown,
      required this.read,
      required this.write,
      required this.close,
      required this.geteuid,
      required this.utimensat,
      required this.currentDirectory,
      required this.noFollow});

  /// `O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC`.
  final int createNewForWriting;

  /// `O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC`, or null on an
  /// architecture whose `O_NOFOLLOW` this does not know.
  final int? openForReadingNoFollow;
  final _OpenFunction open;
  final _FdModeFunction fchmod;
  final _FdOwnerFunction fchown;
  final _ReadWriteFunction read;
  final _ReadWriteFunction write;
  final _CloseFunction close;
  final _UidFunction geteuid;
  final _UtimensatFunction utimensat;

  /// `AT_FDCWD`.
  final int currentDirectory;

  /// `AT_SYMLINK_NOFOLLOW`.
  final int noFollow;

  static final _Libc? instance = _lookUp();

  static _Libc? _lookUp() {
    if (!Platform.isLinux && !Platform.isMacOS) return null;
    final libc = DynamicLibrary.process();
    try {
      final read = libc.lookupFunction<
          IntPtr Function(Int32, Pointer<Uint8>, Size),
          _ReadWriteFunction>('read');
      final write = libc.lookupFunction<
          IntPtr Function(Int32, Pointer<Uint8>, Size),
          _ReadWriteFunction>('write');
      final close =
          libc.lookupFunction<Int32 Function(Int32), _CloseFunction>('close');
      final fchown = libc.lookupFunction<Int32 Function(Int32, Uint32, Uint32),
          _FdOwnerFunction>('fchown');
      final geteuid =
          libc.lookupFunction<Uint32 Function(), _UidFunction>('geteuid');
      final utimensat = libc.lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>, Pointer<Void>, Int32),
          _UtimensatFunction>('utimensat');
      // NOTE: open's mode is variadic, and mode_t is 16 bits on macOS and
      // 32 bits on Linux.
      final open = libc.lookupFunction<
          Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Uint32,)>),
          _OpenFunction>('open');
      if (Platform.isMacOS) {
        return _Libc._(
            createNewForWriting: 0x1000a01,
            openForReadingNoFollow: 0x1000104,
            open: open,
            fchmod: libc.lookupFunction<Int32 Function(Int32, Uint16),
                _FdModeFunction>('fchmod'),
            fchown: fchown,
            read: read,
            write: write,
            close: close,
            geteuid: geteuid,
            utimensat: utimensat,
            currentDirectory: -2,
            noFollow: 0x20);
      }
      return _Libc._(
          createNewForWriting: 0x800c1,
          openForReadingNoFollow: _linuxOpenForReadingNoFollow(Abi.current()),
          open: open,
          fchmod: libc.lookupFunction<Int32 Function(Int32, Uint32),
              _FdModeFunction>('fchmod'),
          fchown: fchown,
          read: read,
          write: write,
          close: close,
          geteuid: geteuid,
          utimensat: utimensat,
          currentDirectory: -100,
          noFollow: 0x100);
    } on ArgumentError {
      return null;
    }
  }
}

/// `O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC` on Linux, where
/// `O_NOFOLLOW` is 0100000 on Arm and 0400000 on the generic layout x86 and
/// RISC-V use, and `O_NONBLOCK` is 04000 on both.
int? _linuxOpenForReadingNoFollow(Abi abi) {
  const cloexecNonBlock = 0x80000 | 0x800;
  if (abi == Abi.linuxArm || abi == Abi.linuxArm64) {
    return cloexecNonBlock | 0x8000;
  }
  if (abi == Abi.linuxX64 ||
      abi == Abi.linuxIA32 ||
      abi == Abi.linuxRiscv32 ||
      abi == Abi.linuxRiscv64) {
    return cloexecNonBlock | 0x20000;
  }
  return null;
}

typedef _FdOwnerReader = OwnerAndGroup? Function(int fd, String path);
typedef _FdStatFunction = int Function(int, Pointer<Uint8>);
typedef _StatxFunction = int Function(
    int, Pointer<Utf8>, int, int, Pointer<Uint8>);

final _FdOwnerReader? _fdOwnerReader = _lookUpFdOwnerReader();

_FdOwnerReader? _lookUpFdOwnerReader() {
  final libc = DynamicLibrary.process();
  try {
    if (Platform.isMacOS) {
      // NOTE: the offsets below are the 64-bit inode struct stat, which
      // x86_64 exports as fstat$INODE64.
      final fstat = libc.lookupFunction<Int32 Function(Int32, Pointer<Uint8>),
              _FdStatFunction>(
          Abi.current() == Abi.macosX64 ? 'fstat\$INODE64' : 'fstat');
      return (fd, path) => _readOwner(path, (buffer) => fstat(fd, buffer),
          size: 144, modeAt: 4, uidAt: 16, gidAt: 20);
    }
    if (Platform.isLinux) {
      final statx = libc.lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>, Int32, Uint32, Pointer<Uint8>),
          _StatxFunction>('statx');
      // NOTE: AT_EMPTY_PATH, and STATX_TYPE | STATX_MODE | STATX_UID |
      // STATX_GID.
      const emptyPath = 0x1000, wanted = 0x1b;
      return (fd, path) => _readOwner(path, (buffer) {
            final empty = ''.toNativeUtf8();
            try {
              return statx(fd, empty, emptyPath, wanted, buffer) == 0 &&
                      buffer.cast<Uint32>().value & wanted == wanted
                  ? 0
                  : -1;
            } finally {
              malloc.free(empty);
            }
          }, size: 256, modeAt: 28, uidAt: 20, gidAt: 24);
    }
  } on ArgumentError {
    return null;
  }
  return null;
}

/// Reads the owner and group [fill] writes into a stat buffer, or null when
/// [fill] fails. Throws [FileSystemException] unless the mode beside them is
/// a regular file's.
OwnerAndGroup? _readOwner(String path, int Function(Pointer<Uint8>) fill,
    {required int size,
    required int modeAt,
    required int uidAt,
    required int gidAt}) {
  final buffer = calloc<Uint8>(size);
  try {
    if (fill(buffer) != 0) return null;
    final fields = ByteData.sublistView(buffer.asTypedList(size));
    if (fields.getUint16(modeAt, Endian.host) & 0xf000 != 0x8000) {
      throw FileSystemException('Not a regular file', path);
    }
    return (
      uid: fields.getUint32(uidAt, Endian.host),
      gid: fields.getUint32(gidAt, Endian.host)
    );
  } finally {
    calloc.free(buffer);
  }
}
