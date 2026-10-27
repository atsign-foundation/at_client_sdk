import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Mode 0600: read and write for the owner, nothing for anyone else.
const ownerOnlyMode = 0x180;

/// A file's owner and group, as numeric ids.
typedef OwnerAndGroup = ({int uid, int gid});

/// What [KeyfileDirectory.read] read: the file's bytes, and its owner and
/// group, or null when this libc cannot report them.
typedef KeyfileRead = ({List<int> bytes, OwnerAndGroup? owner});

/// Whether [writeNewOwnerOnly] can run here: Linux or macOS, with the libc
/// calls it makes found.
bool get ownerOnlyWritesAvailable => _Libc.instance != null;

/// Whether this process runs with an effective user id of 0.
bool get runningAsRoot => _Libc.instance?.geteuid() == 0;

/// A directory opened once, without following a symbolic link, in which a
/// keyfile and its copies are read and written by name.
final class KeyfileDirectory {
  KeyfileDirectory._(this._libc, this._fd, this.path);

  final _Libc _libc;
  final int _fd;

  /// The path the directory was opened at.
  final String path;

  /// Opens the directory at [path].
  ///
  /// Throws [FileSystemException] when [path] is a symbolic link, is not a
  /// directory, or cannot be opened.
  static KeyfileDirectory open(String path) {
    final libc = _Libc.instance!;
    final flags = libc.openDirectoryNoFollow;
    if (flags == null) {
      throw FileSystemException(
          'Cannot open a directory without following a link on this platform',
          path);
    }
    final fd = _withNative(path, (native) => libc.open(native, flags, 0));
    if (fd < 0) {
      throw FileSystemException(
          'Cannot open the directory without following a link', path);
    }
    return KeyfileDirectory._(libc, fd, path);
  }

  /// Whether anything is at [name] here, a symbolic link included, whether
  /// or not this process may open it.
  bool exists(String name) {
    // NOTE: F_OK needs search permission on the directory alone, as stat
    // does, so a keyfile root cannot open still counts as there.
    if (_withNative(
            name,
            (native) =>
                _libc.faccessat(_fd, native, 0, _libc.symlinkNoFollow)) ==
        0) {
      return true;
    }
    final fd = _openAt(name, _libc.openForReadingNoFollow!, 0);
    if (fd >= 0) {
      _libc.close(fd);
      return true;
    }
    final target = malloc<Uint8>(1);
    try {
      return _withNative(
              name, (native) => _libc.readlinkat(_fd, native, target, 1)) >=
          0;
    } finally {
      malloc.free(target);
    }
  }

  /// Reads [name] through one descriptor opened without following a symbolic
  /// link, taking its owner and group from that descriptor.
  ///
  /// Throws [FileSystemException] when [name] is a symbolic link or anything
  /// other than a regular file, or cannot be read.
  KeyfileRead read(String name) {
    final fd = _openAt(name, _libc.openForReadingNoFollow!, 0);
    if (fd < 0) {
      throw FileSystemException(
          'Cannot open the file without following a link', '$path/$name');
    }
    try {
      final owner = _fdOwnerReader?.call(fd, '$path/$name');
      return (bytes: _readAll(_libc, fd, '$path/$name'), owner: owner);
    } finally {
      _libc.close(fd);
    }
  }

  /// Replaces [name] with [bytes] through `<name>.tmp`, which this call
  /// creates readable and writable by its owner alone before any byte
  /// reaches it, gives [owner] when one is named, and renames over [name].
  ///
  /// Says whether the file system took the mode and whether the owner was
  /// set. Throws [FileSystemException] when the temporary file cannot be
  /// created or written, or cannot be renamed into place.
  ({bool modeSet, bool ownerSet}) replace(String name, List<int> bytes,
      {OwnerAndGroup? owner}) {
    final temp = '$name.tmp';
    _withNative(temp, (native) => _libc.unlinkat(_fd, native, 0));
    final fd = _openAt(temp, _libc.createNewForWriting, ownerOnlyMode);
    if (fd < 0) {
      throw FileSystemException('Cannot create the file', '$path/$temp');
    }
    final ({bool modeSet, bool ownerSet}) written;
    try {
      final ownerSet =
          owner == null || _libc.fchown(fd, owner.uid, owner.gid) == 0;
      final modeSet = _libc.fchmod(fd, ownerOnlyMode) == 0;
      _writeAll(_libc, fd, bytes, '$path/$temp');
      written = (modeSet: modeSet, ownerSet: ownerSet);
    } finally {
      _libc.close(fd);
    }
    final renamed = _withNative(
        temp,
        (from) =>
            _withNative(name, (to) => _libc.renameat(_fd, from, _fd, to)));
    if (renamed != 0) {
      throw FileSystemException(
          'Cannot rename the file into place', '$path/$name');
    }
    return written;
  }

  /// Closes the directory.
  void close() => _libc.close(_fd);

  int _openAt(String name, int flags, int mode) =>
      _withNative(name, (native) => _libc.openat(_fd, native, flags, mode));
}

T _withNative<T>(String text, T Function(Pointer<Utf8>) use) {
  final native = text.toNativeUtf8();
  try {
    return use(native);
  } finally {
    malloc.free(native);
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
typedef _OpenAtFunction = int Function(int, Pointer<Utf8>, int, int);
typedef _RenameAtFunction = int Function(
    int, Pointer<Utf8>, int, Pointer<Utf8>);
typedef _UnlinkAtFunction = int Function(int, Pointer<Utf8>, int);
typedef _ReadLinkAtFunction = int Function(
    int, Pointer<Utf8>, Pointer<Uint8>, int);
typedef _AccessAtFunction = int Function(int, Pointer<Utf8>, int, int);
typedef _FdModeFunction = int Function(int, int);
typedef _FdOwnerFunction = int Function(int, int, int);
typedef _ReadWriteFunction = int Function(int, Pointer<Uint8>, int);
typedef _CloseFunction = int Function(int);
typedef _UidFunction = int Function();

final class _Libc {
  _Libc._(
      {required this.createNewForWriting,
      required this.openForReadingNoFollow,
      required this.openDirectoryNoFollow,
      required this.open,
      required this.openat,
      required this.renameat,
      required this.unlinkat,
      required this.readlinkat,
      required this.faccessat,
      required this.symlinkNoFollow,
      required this.fchmod,
      required this.fchown,
      required this.read,
      required this.write,
      required this.close,
      required this.geteuid});

  /// `O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC`.
  final int createNewForWriting;

  /// `O_RDONLY | O_NOFOLLOW | O_CLOEXEC`, or null on an architecture whose
  /// `O_NOFOLLOW` this does not know.
  final int? openForReadingNoFollow;

  /// `O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC`, null alongside
  /// [openForReadingNoFollow].
  final int? openDirectoryNoFollow;
  final _OpenFunction open;
  final _OpenAtFunction openat;
  final _RenameAtFunction renameat;
  final _UnlinkAtFunction unlinkat;
  final _ReadLinkAtFunction readlinkat;
  final _AccessAtFunction faccessat;

  /// `AT_SYMLINK_NOFOLLOW`.
  final int symlinkNoFollow;
  final _FdModeFunction fchmod;
  final _FdOwnerFunction fchown;
  final _ReadWriteFunction read;
  final _ReadWriteFunction write;
  final _CloseFunction close;
  final _UidFunction geteuid;

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
      // NOTE: open's mode is variadic, and mode_t is 16 bits on macOS and
      // 32 bits on Linux.
      final open = libc.lookupFunction<
          Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Uint32,)>),
          _OpenFunction>('open');
      final openat = libc.lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>, Int32, VarArgs<(Uint32,)>),
          _OpenAtFunction>('openat');
      final renameat = libc.lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>, Int32, Pointer<Utf8>),
          _RenameAtFunction>('renameat');
      final unlinkat = libc.lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>, Int32),
          _UnlinkAtFunction>('unlinkat');
      final readlinkat = libc.lookupFunction<
          IntPtr Function(Int32, Pointer<Utf8>, Pointer<Uint8>, Size),
          _ReadLinkAtFunction>('readlinkat');
      final faccessat = libc.lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>, Int32, Int32),
          _AccessAtFunction>('faccessat');
      if (Platform.isMacOS) {
        return _Libc._(
            createNewForWriting: 0x1000a01,
            openForReadingNoFollow: 0x1000100,
            openDirectoryNoFollow: 0x1100100,
            open: open,
            openat: openat,
            renameat: renameat,
            unlinkat: unlinkat,
            readlinkat: readlinkat,
            faccessat: faccessat,
            symlinkNoFollow: 0x20,
            fchmod: libc.lookupFunction<Int32 Function(Int32, Uint16),
                _FdModeFunction>('fchmod'),
            fchown: fchown,
            read: read,
            write: write,
            close: close,
            geteuid: geteuid);
      }
      final noFollow = _linuxNoFollow(Abi.current());
      return _Libc._(
          createNewForWriting: 0x800c1,
          openForReadingNoFollow: noFollow?.file,
          openDirectoryNoFollow: noFollow?.directory,
          open: open,
          openat: openat,
          renameat: renameat,
          unlinkat: unlinkat,
          readlinkat: readlinkat,
          faccessat: faccessat,
          symlinkNoFollow: 0x100,
          fchmod: libc.lookupFunction<Int32 Function(Int32, Uint32),
              _FdModeFunction>('fchmod'),
          fchown: fchown,
          read: read,
          write: write,
          close: close,
          geteuid: geteuid);
    } on ArgumentError {
      return null;
    }
  }
}

/// The Linux flags that open a file, and a directory, without following a
/// symbolic link: `O_NOFOLLOW` and `O_DIRECTORY` are 0100000 and 040000 on
/// Arm, and 0400000 and 0200000 on the generic layout x86 and RISC-V use.
({int file, int directory})? _linuxNoFollow(Abi abi) {
  const cloexec = 0x80000;
  if (abi == Abi.linuxArm || abi == Abi.linuxArm64) {
    return (file: cloexec | 0x8000, directory: cloexec | 0x8000 | 0x4000);
  }
  if (abi == Abi.linuxX64 ||
      abi == Abi.linuxIA32 ||
      abi == Abi.linuxRiscv32 ||
      abi == Abi.linuxRiscv64) {
    return (file: cloexec | 0x20000, directory: cloexec | 0x20000 | 0x10000);
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
