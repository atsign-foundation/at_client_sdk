import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Mode 0600: read and write for the owner, nothing for anyone else.
const ownerOnlyMode = 0x180;

/// Whether this platform has the file modes [writeNewOwnerOnly] sets.
bool get ownerOnlyModeSupported => Platform.isLinux || Platform.isMacOS;

/// Whether [writeNewOwnerOnly] can run here: a platform with file modes, and
/// the libc calls it makes found.
bool get ownerOnlyWritesAvailable => _Libc.instance != null;

/// Writes [bytes] to a file this call creates at [path], readable and
/// writable by its owner alone before any byte reaches it.
///
/// Returns false when the file system did not take the mode; the bytes are
/// written either way. Throws [FileSystemException] when anything already
/// exists at [path], a symbolic link included, or the file cannot be created
/// or written.
bool writeNewOwnerOnly(String path, List<int> bytes) {
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
    final modeSet = libc.fchmod(fd, ownerOnlyMode) == 0;
    _writeAll(libc, fd, bytes, path);
    return modeSet;
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
typedef _WriteFunction = int Function(int, Pointer<Uint8>, int);
typedef _CloseFunction = int Function(int);

final class _Libc {
  _Libc._(
      this.createNewForWriting, this.open, this.fchmod, this.write, this.close);

  /// `O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC`.
  final int createNewForWriting;
  final _OpenFunction open;
  final _FdModeFunction fchmod;
  final _WriteFunction write;
  final _CloseFunction close;

  static final _Libc? instance = _lookUp();

  static _Libc? _lookUp() {
    if (!ownerOnlyModeSupported) return null;
    final libc = DynamicLibrary.process();
    try {
      final write = libc.lookupFunction<
          IntPtr Function(Int32, Pointer<Uint8>, Size),
          _WriteFunction>('write');
      final close =
          libc.lookupFunction<Int32 Function(Int32), _CloseFunction>('close');
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
              write,
              close)
          : _Libc._(
              0x800c1,
              open,
              libc.lookupFunction<Int32 Function(Int32, Uint32),
                  _FdModeFunction>('fchmod'),
              write,
              close);
    } on ArgumentError {
      return null;
    }
  }
}
