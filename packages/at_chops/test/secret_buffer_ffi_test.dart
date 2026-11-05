@Tags(['ffi'])
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:at_chops/src/algorithm/ffi/secret_buffer.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

/// Wraps [calloc] and records, for each buffer freed, its size and whether
/// every byte was zero at the moment of the free.
class _RecordingAllocator implements Allocator {
  final Map<int, int> _live = {};
  final List<({int length, bool cleared})> freed = [];

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final Pointer<T> p = calloc.allocate<T>(byteCount, alignment: alignment);
    _live[p.address] = byteCount;
    return p;
  }

  @override
  void free(Pointer<NativeType> pointer) {
    final int length = _live.remove(pointer.address)!;
    final Uint8List bytes = pointer.cast<Uint8>().asTypedList(length);
    freed.add((length: length, cleared: bytes.every((b) => b == 0)));
    calloc.free(pointer);
  }

  int get liveCount => _live.length;
}

void main() {
  final DynamicLibrary? lib = tryLoadLibCrypto();
  late _RecordingAllocator recorder;

  setUp(() {
    recorder = _RecordingAllocator();
    secretBufferAllocator = recorder;
  });

  tearDown(() {
    secretBufferAllocator = calloc;
  });

  /// Runs [op] and returns the sizes of the secret buffers it freed, after
  /// checking that each was cleared and none was left allocated.
  Future<List<int>> freedDuring(Future<void> Function() op) async {
    recorder.freed.clear();
    await op();
    expect(recorder.liveCount, 0, reason: 'a secret buffer was not freed');
    for (final f in recorder.freed) {
      expect(f.cleared, isTrue,
          reason: 'a ${f.length}-byte secret buffer was freed uncleared');
    }
    return recorder.freed.map((f) => f.length).toList();
  }

  test('the recording allocator sees a buffer freed without clearing', () {
    final Pointer<Uint8> buf = allocSecret(4);
    buf.asTypedList(4).setAll(0, [1, 2, 3, 4]);
    secretBufferAllocator.free(buf);
    expect(recorder.freed.single.cleared, isFalse);
  });

  test('freeSecret clears the buffer before freeing it', () {
    final Pointer<Uint8> buf = allocSecret(4);
    buf.asTypedList(4).setAll(0, [1, 2, 3, 4]);
    freeSecret(buf, 4);
    expect(recorder.freed.single, (length: 4, cleared: true));
  });

  group('X25519 FFI', () {
    setUp(() {
      if (lib == null) fail('libcrypto not available on this host');
    });

    test('key generation, dh and publicKeyFromPrivate clear their buffers',
        () async {
      final algo = X25519FfiAlgo.fromLib(lib!);
      late ({Uint8List publicKey, Uint8List privateKey}) a, b;

      expect(await freedDuring(() async => a = await algo.generateKeyPair()),
          [32]);
      b = await algo.generateKeyPair();

      late Uint8List ab, ba;
      // Private key copy in, shared secret out.
      expect(
          await freedDuring(
              () async => ab = await algo.dh(a.privateKey, b.publicKey)),
          [32, 32]);
      ba = await algo.dh(b.privateKey, a.publicKey);
      expect(ab, ba);

      late Uint8List pk;
      expect(
          await freedDuring(
              () async => pk = algo.publicKeyFromPrivate(a.privateKey)),
          [32]);
      expect(pk, a.publicKey);
    });
  });

  group('ML-DSA-65 FFI', () {
    setUp(() {
      if (lib == null) fail('libcrypto not available on this host');
      if (!libCryptoSupportsMlDsa65(lib)) {
        fail('libcrypto does not support ML-DSA-65 (requires OpenSSL >= 3.5)');
      }
    });

    test('key generation, keyPairFromSeed and signing clear their buffers',
        () async {
      final algo = MlDsa65FfiAlgo.fromLib(lib!);

      expect(await freedDuring(() => algo.generateKeyPair()), [4032]);

      late ({Uint8List publicKey, Uint8List secretKey}) kp;
      expect(
          await freedDuring(
              () async => kp = await algo.keyPairFromSeed(algo.newSeed())),
          [4032, 32]);

      final Uint8List message = Uint8List.fromList('hello'.codeUnits);
      late Uint8List sig;
      expect(
          await freedDuring(() async =>
              sig = await algo.signBytes(message, secretKey: kp.secretKey)),
          [4032]);
      expect(
          await algo.verifyBytes(message,
              signature: sig, publicKey: kp.publicKey),
          isTrue);
    });
  });

  group('ML-KEM-768 FFI', () {
    setUp(() {
      if (lib == null) fail('libcrypto not available on this host');
      if (!libCryptoSupportsMlKem768(lib)) {
        fail('libcrypto does not support ML-KEM-768 (requires OpenSSL >= 3.5)');
      }
    });

    test('keyPairFromSeed, encapsulate and decapsulate clear their buffers',
        () async {
      final algo = MlKem768FfiAlgo.fromLib(lib!);

      late ({Uint8List publicKey, Uint8List secretKey}) kp;
      expect(
          await freedDuring(
              () async => kp = await algo.keyPairFromSeed(algo.newSeed())),
          [64]);

      late ({Uint8List ciphertext, Uint8List sharedSecret}) enc;
      expect(
          await freedDuring(
              () async => enc = await algo.encapsulate(kp.publicKey)),
          [32]);

      late Uint8List ss;
      expect(
          await freedDuring(() async =>
              ss = await algo.decapsulate(kp.secretKey, enc.ciphertext)),
          [32]);
      expect(ss, enc.sharedSecret);
      algo.releaseKeyPair(kp);
    });
  });
}
