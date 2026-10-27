import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Mode 0600: read and write for the owner, nothing for anyone else.
const ownerOnlyMode = 0x180;

/// A file's owner and group, as numeric ids.
typedef OwnerAndGroup = ({int uid, int gid});

/// Whether [writeNewOwnerOnly] can run here: Linux or macOS, with the libc
/// calls it makes found.
bool get ownerOnlyWritesAvailable => _Libc.instance != null;

/// Whether this process runs with an effective user id of 0.
bool get runningAsRoot => _Libc.instance?.geteuid() == 0;

/// The owner and group of the file at [path], following a symbolic link, or
/// null when nothing is there.
///
/// Throws [FileSystemException] when they cannot be read.
OwnerAndGroup? ownerAndGroupOf(String path) {
  final stat = FileStat.statSync(path);
  if (stat.type == FileSystemEntityType.notFound) return null;
  final read = _ownerReader;
  if (read == null) {
    throw FileSystemException(
        'Cannot look up the libc call that reads an owner', path);
  }
  return read(path, stat.mode);
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
  final nativePath = path.toNativeUtf8();
  final int fd;
  try {
    fd = libc.open(nativePath, libc.createNewForWriting, ownerOnlyMode);
  } finally {
    malloc.free(nativePath);
  }
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

typedef _OpenFunction = int Function(Pointer<Utf8>, int, int);
typedef _FdModeFunction = int Function(int, int);
typedef _FdOwnerFunction = int Function(int, int, int);
typedef _WriteFunction = int Function(int, Pointer<Uint8>, int);
typedef _CloseFunction = int Function(int);
typedef _UidFunction = int Function();

final class _Libc {
  _Libc._(this.createNewForWriting, this.open, this.fchmod, this.fchown,
      this.write, this.close, this.geteuid);

  /// `O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC`.
  final int createNewForWriting;
  final _OpenFunction open;
  final _FdModeFunction fchmod;
  final _FdOwnerFunction fchown;
  final _WriteFunction write;
  final _CloseFunction close;
  final _UidFunction geteuid;

  static final _Libc? instance = _lookUp();

  static _Libc? _lookUp() {
    if (!Platform.isLinux && !Platform.isMacOS) return null;
    final libc = DynamicLibrary.process();
    try {
      final write = libc.lookupFunction<
          IntPtr Function(Int32, Pointer<Uint8>, Size),
          _WriteFunction>('write');
      final close =
          libc.lookupFunction<Int32 Function(Int32), _CloseFunction>('close');
      final fchown = libc.lookupFunction<Int32 Function(Int32, Uint32, Uint32),
          _FdOwnerFunction>('fchown');
      final geteuid =
          libc.lookupFunction<Uint32 Function(), _UidFunction>('geteuid');
      // NOTE: open's mode is variadic, and mode_t is 16 bits on macOS and
      // 32 bits on Linux.
      final open = libc.lookupFunction<
          Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Uint32,)>),
          _OpenFunction>('open');
      return Platform.isMacOS
          ? _Libc._(
              0x1000a01,
              open,
              libc.lookupFunction<Int32 Function(Int32, Uint16),
                  _FdModeFunction>('fchmod'),
              fchown,
              write,
              close,
              geteuid)
          : _Libc._(
              0x800c1,
              open,
              libc.lookupFunction<Int32 Function(Int32, Uint32),
                  _FdModeFunction>('fchmod'),
              fchown,
              write,
              close,
              geteuid);
    } on ArgumentError {
      return null;
    }
  }
}

typedef _OwnerReader = OwnerAndGroup Function(String path, int mode);
typedef _StatFunction = int Function(Pointer<Utf8>, Pointer<Uint8>);
typedef _StatxFunction = int Function(
    int, Pointer<Utf8>, int, int, Pointer<Uint8>);

final _OwnerReader? _ownerReader = _lookUpOwnerReader();

_OwnerReader? _lookUpOwnerReader() {
  final libc = DynamicLibrary.process();
  try {
    if (Platform.isMacOS) {
      // NOTE: the offsets below are the 64-bit inode struct stat, which
      // x86_64 exports as stat$INODE64.
      final stat = libc.lookupFunction<
              Int32 Function(Pointer<Utf8>, Pointer<Uint8>), _StatFunction>(
          Abi.current() == Abi.macosX64 ? 'stat\$INODE64' : 'stat');
      return (path, mode) => _readOwner(path, mode, stat,
          size: 144, modeAt: 4, uidAt: 16, gidAt: 20);
    }
    if (Platform.isLinux) {
      final statx = libc.lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>, Int32, Uint32, Pointer<Uint8>),
          _StatxFunction>('statx');
      // AT_FDCWD, and STATX_TYPE | STATX_MODE | STATX_UID | STATX_GID.
      const atFdCwd = -100, wanted = 0x1b;
      return (path, mode) => _readOwner(
          path,
          mode,
          (nativePath, buffer) =>
              statx(atFdCwd, nativePath, 0, wanted, buffer) == 0 &&
                      buffer.cast<Uint32>().value & wanted == wanted
                  ? 0
                  : -1,
          size: 256,
          modeAt: 28,
          uidAt: 20,
          gidAt: 24);
    }
  } on ArgumentError {
    return null;
  }
  return null;
}

/// Reads the owner and group [fill] writes into a stat buffer, refusing them
/// when the mode beside them is not [mode], the one dart:io read.
OwnerAndGroup _readOwner(String path, int mode, _StatFunction fill,
    {required int size,
    required int modeAt,
    required int uidAt,
    required int gidAt}) {
  final nativePath = path.toNativeUtf8();
  final buffer = calloc<Uint8>(size);
  try {
    if (fill(nativePath, buffer) != 0) {
      throw FileSystemException('Cannot read the owner', path);
    }
    final fields = ByteData.sublistView(buffer.asTypedList(size));
    if (fields.getUint16(modeAt, Endian.host) & 0xfff != mode & 0xfff) {
      throw FileSystemException(
          'The owner read does not belong to the file', path);
    }
    return (
      uid: fields.getUint32(uidAt, Endian.host),
      gid: fields.getUint32(gidAt, Endian.host)
    );
  } finally {
    calloc.free(buffer);
    malloc.free(nativePath);
  }
}
