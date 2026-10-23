import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Zeroes [length] bytes at [buf], then frees it.
///
/// For native buffers that held key material or a shared secret.
void freeSecret(Pointer<Uint8> buf, int length) {
  buf.asTypedList(length).fillRange(0, length, 0);
  calloc.free(buf);
}
