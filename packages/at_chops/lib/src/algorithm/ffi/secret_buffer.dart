import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

/// The allocator behind [allocSecret] and [freeSecret].
///
/// Tests replace it with one that records each buffer's bytes at the moment
/// it is freed, to check that every native buffer which held key material or
/// a shared secret is cleared first.
@visibleForTesting
Allocator secretBufferAllocator = calloc;

/// Allocates a zeroed native buffer of [length] bytes for secret material.
///
/// Free it with [freeSecret], passing the same [length].
Pointer<Uint8> allocSecret(int length) => secretBufferAllocator<Uint8>(length);

/// Clears the [length] bytes at [buf], then frees it.
///
/// [length] is the size [buf] was allocated with: OpenSSL may shrink a
/// length out-parameter on its second call, so callers keep the allocated
/// size rather than re-reading that parameter.
void freeSecret(Pointer<Uint8> buf, int length) {
  buf.asTypedList(length).fillRange(0, length, 0);
  secretBufferAllocator.free(buf);
}
