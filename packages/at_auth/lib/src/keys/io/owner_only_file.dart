import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Mode 0600: read and write for the owner, nothing for anyone else.
const ownerOnlyMode = 0x180;

/// Whether this platform has the file modes [createOwnerOnly] sets.
bool get ownerOnlyModeSupported => Platform.isLinux || Platform.isMacOS;

/// Creates [path] as an empty file with mode [ownerOnlyMode], or empties an
/// existing one, then sets its mode to exactly [ownerOnlyMode] whatever the
/// process umask.
///
/// Linux and macOS only. Throws [FileSystemException] when the file cannot be
/// created or its mode cannot be set; in the second case the file exists.
void createOwnerOnly(String path) {
  final libc = _Libc.load(path);
  final nativePath = path.toNativeUtf8();
  try {
    final fd = libc.creat(nativePath, ownerOnlyMode);
    if (fd < 0) {
      throw FileSystemException('Cannot create the file', path);
    }
    final modeSet = libc.fchmod(fd, ownerOnlyMode) == 0;
    libc.close(fd);
    if (!modeSet) {
      throw FileSystemException('Cannot set mode 0600', path);
    }
  } finally {
    malloc.free(nativePath);
  }
}

typedef _PathFunction = int Function(Pointer<Utf8>, int);
typedef _FdModeFunction = int Function(int, int);
typedef _FdFunction = int Function(int);

final class _Libc {
  _Libc._(this.creat, this.fchmod, this.close);

  final _PathFunction creat;
  final _FdModeFunction fchmod;
  final _FdFunction close;

  static _Libc? _loaded;

  /// The libc calls, looked up once; [path] names the file in the error when
  /// they cannot be.
  static _Libc load(String path) {
    final loaded = _loaded;
    if (loaded != null) return loaded;
    try {
      return _loaded = _lookUp(DynamicLibrary.process());
    } on ArgumentError catch (e) {
      throw FileSystemException(
          'Cannot look up the libc file mode calls: $e', path);
    }
  }

  // NOTE: mode_t is 16 bits on macOS and 32 bits on Linux.
  static _Libc _lookUp(DynamicLibrary libc) => Platform.isMacOS
      ? _Libc._(
          libc.lookupFunction<Int32 Function(Pointer<Utf8>, Uint16),
              _PathFunction>('creat'),
          libc.lookupFunction<Int32 Function(Int32, Uint16), _FdModeFunction>(
              'fchmod'),
          libc.lookupFunction<Int32 Function(Int32), _FdFunction>('close'))
      : _Libc._(
          libc.lookupFunction<Int32 Function(Pointer<Utf8>, Uint32),
              _PathFunction>('creat'),
          libc.lookupFunction<Int32 Function(Int32, Uint32), _FdModeFunction>(
              'fchmod'),
          libc.lookupFunction<Int32 Function(Int32), _FdFunction>('close'));
}
