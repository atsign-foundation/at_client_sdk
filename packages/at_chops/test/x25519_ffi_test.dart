@Tags(['ffi'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

void main() {
  group('X25519 FFI', () {
    final StringBuffer loadedPath = StringBuffer();
    final DynamicLibrary? lib = tryLoadLibCrypto(loadedPath: loadedPath);

    setUpAll(() {
      if (lib != null) {
        // ignore: avoid_print
        print('libcrypto loaded from: ${loadedPath.toString()}');
      }
    });

    test('DH round-trip via OpenSSL FFI', () async {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }

      final algo = X25519FfiAlgo.fromLib(lib);
      final aliceKp = await X25519FfiAlgo.fromLib(lib).generateKeyPair();
      final bobKp = await X25519FfiAlgo.fromLib(lib).generateKeyPair();

      final Uint8List ss1 = await algo.dh(aliceKp.privateKey, bobKp.publicKey);
      final Uint8List ss2 = await algo.dh(bobKp.privateKey, aliceKp.publicKey);

      expect(ss1, equals(ss2));
      expect(ss1.length, equals(32));
    });

    test('Pure-Dart and FFI interop: same keys yield the same shared secret',
        () async {
      if (lib == null) {
        fail('libcrypto not available on this host');
      }

      final pureAlgo = X25519PureDartAlgo.instance;
      final ffiAlgo = X25519FfiAlgo.fromLib(lib);

      final AtX25519KeyPair alice = await AtChopsUtil.generateX25519KeyPair();
      final AtX25519KeyPair bob = await AtChopsUtil.generateX25519KeyPair();

      final Uint8List alicePriv = base64Decode(alice.atPrivateKey.privateKey);
      final Uint8List bobPub = base64Decode(bob.atPublicKey.publicKey);

      final Uint8List ssPure = await pureAlgo.dh(alicePriv, bobPub);
      final Uint8List ssFfi = await ffiAlgo.dh(alicePriv, bobPub);

      expect(ssPure, equals(ssFfi));
    });
  });
}
