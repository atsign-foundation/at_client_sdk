import 'dart:convert';
import 'dart:ffi';
import 'dart:math' show max;
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_iv.dart';
import 'package:at_chops/src/algorithm/ffi/openssl_ffi_bindings.dart';
import 'package:at_chops/src/key/impl/aes_key.dart';
import 'package:at_commons/at_commons.dart';
import 'package:ffi/ffi.dart';

/// Incremental AES-CTR, backed by OpenSSL 3 via Dart FFI, for encrypting a
/// byte stream whose chunk boundaries are not under the caller's control.
///
/// One instance owns one `EVP_CIPHER_CTX` for its whole life. `EVP_aes_*_ctr`
/// reports a block size of 1, so [update] emits exactly as many bytes as it is
/// given and the keystream offset within the current counter block is carried
/// in the context. Chunks may therefore be any size, including sizes that
/// straddle a block boundary.
///
/// **This is raw CTR: no padding, no authentication tag, no framing.** That is
/// deliberately unlike `AesCtrFfiAlgo` and `AESEncryptionAlgo`, the one-shot
/// pair, which PKCS7-pad for compatibility with data already on the wire. Do
/// not mix the two on one channel.
///
/// Encryption and decryption are the same operation in CTR, so there is one
/// class and one direction per instance. The instance that decrypts a stream
/// takes the same key and IV as the one that encrypted it.
///
/// **A duplex channel is two streams, and each needs its own IV.** Running
/// both directions of a tunnel from one (key, IV) pair XORs the two plaintexts
/// together under a single keystream, which recovers both from the ciphertext
/// alone. Derive or transmit a separate IV per direction.
///
/// ## Ownership
///
/// The context is a native resource whose lifetime outlives any single method
/// call, which nothing else in at_chops has. The caller **must** call
/// [dispose] — on the error and cancellation paths as much as the happy one. A
/// stream adapter wrapping this class belongs in a `try`/`finally`, not a bare
/// `map`. [dispose] is idempotent; [update] after it throws a [StateError].
///
/// A [Finalizer] is attached as a backstop for an instance the caller drops
/// without disposing. It is a safety net and not a mechanism: GC timing is
/// unspecified, and a leak of one context per connection will outrun it.
final class AesCtrFfiCipher {
  /// CTR's IV is the initial counter block, so it is always one AES block.
  static const int ivLength = 16;

  final _NativeState _state;
  final EvpEncryptUpdateDart _encryptUpdate;

  /// Frees the native state of an instance that was dropped without
  /// [dispose]. Detached by [dispose], which is the intended path.
  static final Finalizer<_NativeState> _finalizer =
      Finalizer<_NativeState>((_NativeState state) => state.release());

  /// Creates a cipher over [aesKey] starting from counter block [iv].
  ///
  /// [aesKey] must be 16, 24 or 32 bytes and [iv] exactly [ivLength] bytes.
  /// OpenSSL reads a whole block from the IV pointer however many bytes were
  /// allocated, so a short IV is an out-of-bounds read rather than a wrong
  /// answer — it is rejected before any native call.
  factory AesCtrFfiCipher.fromLib(
      DynamicLibrary lib, AESKey aesKey, InitialisationVector iv) {
    final Uint8List keyBytes = base64Decode(aesKey.key);
    // Both of these throw before anything is allocated.
    final Pointer<EVP_CIPHER> Function() cipherFor =
        _cipherLookup(lib, keyBytes.length);
    if (iv.ivBytes.length != ivLength) {
      throw AtEncryptionException('AES-CTR requires a $ivLength-byte IV; '
          'got ${iv.ivBytes.length} bytes');
    }

    // isLeaf: true on the hot-path calls — none of them re-enter Dart, so the
    // native call can skip the safepoint transition. Would become illegal if
    // any of these ever called back into Dart.
    final ctxNew =
        lib.lookupFunction<EvpCipherCtxNewNative, EvpCipherCtxNewDart>(
            'EVP_CIPHER_CTX_new', isLeaf: true);
    final ctxFree =
        lib.lookupFunction<EvpCipherCtxFreeNative, EvpCipherCtxFreeDart>(
            'EVP_CIPHER_CTX_free', isLeaf: true);
    final encryptInitEx =
        lib.lookupFunction<EvpEncryptInitExNative, EvpEncryptInitExDart>(
            'EVP_EncryptInit_ex');
    final encryptUpdate =
        lib.lookupFunction<EvpEncryptUpdateNative, EvpEncryptUpdateDart>(
            'EVP_EncryptUpdate', isLeaf: true);

    final Pointer<EVP_CIPHER_CTX> ctx = ctxNew();
    if (ctx == nullptr) throw StateError('EVP_CIPHER_CTX_new failed');
    final _NativeState state = _NativeState(ctx, ctxFree);

    // The state is live from here: anything that throws must release it, or
    // the caller is left with no handle to dispose.
    try {
      final Pointer<Uint8> keyPtr = calloc<Uint8>(keyBytes.length);
      final Pointer<Uint8> ivPtr = calloc<Uint8>(ivLength);
      keyPtr.asTypedList(keyBytes.length).setAll(0, keyBytes);
      ivPtr.asTypedList(ivLength).setAll(0, iv.ivBytes);
      try {
        if (encryptInitEx(ctx, cipherFor(), nullptr, keyPtr, ivPtr) <= 0) {
          throw AtEncryptionException('EVP_EncryptInit_ex (AES-CTR) failed');
        }
      } finally {
        keyPtr.asTypedList(keyBytes.length).fillRange(0, keyBytes.length, 0);
        calloc.free(keyPtr);
        calloc.free(ivPtr);
      }
    } catch (_) {
      state.release();
      rethrow;
    }

    return AesCtrFfiCipher._(state, encryptUpdate);
  }

  AesCtrFfiCipher._(this._state, this._encryptUpdate) {
    _finalizer.attach(this, _state, detach: this);
  }

  /// Transforms [input] and returns the result, advancing the keystream.
  ///
  /// Output length always equals input length. An empty [input] is a no-op
  /// and does not advance the keystream.
  Uint8List update(Uint8List input) {
    if (_state.released) {
      throw StateError('AesCtrFfiCipher.update called after dispose');
    }
    if (input.isEmpty) return Uint8List(0);
    checkInlLength(input.length, 'input', 'EVP_EncryptUpdate');

    _state.ensureCapacity(input.length);
    _state.inBuf.asTypedList(input.length).setAll(0, input);

    if (_encryptUpdate(_state.ctx, _state.outBuf, _state.outLen, _state.inBuf,
            input.length) <=
        0) {
      // `EVP_EncryptUpdate` is the call for both directions — CTR transforms
      // identically either way — so this message stays direction-neutral.
      throw AtEncryptionException('AES-CTR (FFI) transform failed');
    }
    // Block size is 1 for CTR, so OpenSSL buffers nothing and this is exact.
    // The copy is required, not incidental: the next `update` may reallocate
    // `outBuf`, and an `asTypedList` view would dangle.
    return Uint8List.fromList(_state.outBuf.asTypedList(_state.outLen.value));
  }

  /// Transforms [input] like [update], but returns a view directly onto the
  /// native output buffer instead of copying it — no per-chunk allocation.
  ///
  /// **The returned view is valid only until the next call to [update] or
  /// [updateView] on this instance.** That call may reuse or grow `outBuf`,
  /// so anything holding the view past it is reading freed or overwritten
  /// memory. The one sanctioned consumer is a synchronous `Socket.add`,
  /// which copies the bytes before this method can be called again; do not
  /// store the view, pass it across an `await`, or hand it to anything
  /// asynchronous. Everything else should use [update].
  Uint8List updateView(Uint8List input) {
    if (_state.released) {
      throw StateError('AesCtrFfiCipher.updateView called after dispose');
    }
    if (input.isEmpty) return Uint8List(0);
    checkInlLength(input.length, 'input', 'EVP_EncryptUpdate');

    _state.ensureCapacity(input.length);
    _state.inBuf.asTypedList(input.length).setAll(0, input);

    if (_encryptUpdate(_state.ctx, _state.outBuf, _state.outLen, _state.inBuf,
            input.length) <=
        0) {
      throw AtEncryptionException('AES-CTR (FFI) transform failed');
    }
    return _state.outBuf.asTypedList(_state.outLen.value);
  }

  /// Releases the context and every scratch buffer. Safe to call repeatedly.
  void dispose() {
    if (_state.released) return;
    _finalizer.detach(this);
    _state.release();
  }

  /// Mirrors `AesCtrFactory`'s key-length contract so the FFI and pure-Dart
  /// paths accept exactly the same keys.
  static Pointer<EVP_CIPHER> Function() _cipherLookup(
      DynamicLibrary lib, int keyLength) {
    switch (keyLength) {
      case 16:
        return lib.lookupFunction<EvpAes128CtrNative, EvpAes128CtrDart>(
            'EVP_aes_128_ctr');
      case 24:
        return lib.lookupFunction<EvpAes192CtrNative, EvpAes192CtrDart>(
            'EVP_aes_192_ctr');
      case 32:
        return lib.lookupFunction<EvpAes256CtrNative, EvpAes256CtrDart>(
            'EVP_aes_256_ctr');
      default:
        throw AtEncryptionException(
            'Invalid AES key length. Valid lengths are 16/24/32 bytes');
    }
  }
}

/// Every native allocation the cipher owns, in one place.
///
/// Kept separate from [AesCtrFfiCipher] so the [Finalizer] can free all of it
/// without holding the cipher itself alive — and so there is exactly one
/// [release] for both the explicit and the collected path to go through.
final class _NativeState {
  Pointer<EVP_CIPHER_CTX> ctx;
  final EvpCipherCtxFreeDart _ctxFree;
  final Pointer<Int32> outLen = calloc<Int32>();

  /// Scratch buffers reused across `update`/`updateView` calls.
  ///
  /// A socket delivers many small chunks, and a `calloc`/`free` pair per chunk
  /// is precisely the fixed per-call cost that makes FFI lose to pure-Dart at
  /// small sizes. These grow geometrically (see [ensureCapacity]) and are
  /// wiped by [release].
  Pointer<Uint8> inBuf = nullptr;
  Pointer<Uint8> outBuf = nullptr;
  int _bufLen = 0;

  bool released = false;

  _NativeState(this.ctx, this._ctxFree);

  /// Chunks arriving off a socket are bounded well under [_minCapacity], so
  /// growing geometrically (and never below it) means the first growth is
  /// normally the last: later chunks all fit the buffer [updateView] already
  /// handed a view into, so that view never dangles in practice.
  static const int _minCapacity = 256 * 1024;

  void ensureCapacity(int length) {
    if (length <= _bufLen) return;
    final int newLen = <int>[length, _bufLen * 2, _minCapacity].reduce(max);
    _freeBuffers();
    inBuf = calloc<Uint8>(newLen);
    outBuf = calloc<Uint8>(newLen);
    _bufLen = newLen;
  }

  void release() {
    if (released) return;
    released = true;
    if (ctx != nullptr) {
      _ctxFree(ctx);
      ctx = nullptr;
    }
    _freeBuffers();
    calloc.free(outLen);
  }

  void _freeBuffers() {
    if (_bufLen == 0) return;
    // Each buffer held plaintext on one side of the transform or the other.
    inBuf.asTypedList(_bufLen).fillRange(0, _bufLen, 0);
    outBuf.asTypedList(_bufLen).fillRange(0, _bufLen, 0);
    calloc.free(inBuf);
    calloc.free(outBuf);
    inBuf = nullptr;
    outBuf = nullptr;
    _bufLen = 0;
  }
}
