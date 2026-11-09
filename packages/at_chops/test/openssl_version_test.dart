import 'dart:ffi';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:at_chops/src/algorithm/ffi/openssl_version.dart';
import 'package:test/test.dart';

void main() {
  group('ML-KEM-768 through FFI needs OpenSSL 3.5.1 or later', () {
    test('3.5.0 is refused', () {
      expect(openSslVersionSupportsMlKem768(0x30500000), isFalse);
    });

    test('3.5.1 is accepted', () {
      expect(openSslVersionSupportsMlKem768(0x30500010), isTrue);
    });

    test('3.6.3 is accepted', () {
      expect(openSslVersionSupportsMlKem768(0x30600030), isTrue);
    });
  });

  group('on a libcrypto older than 3.5.1', () {
    final DynamicLibrary? lib = tryLoadLibCrypto();
    final Object skip = lib == null
        ? 'libcrypto not available on this host'
        : libCryptoVersionSupportsMlKem768(lib)
            ? 'libcrypto is OpenSSL 3.5.1 or later'
            : false;

    test('MlKem768FfiAlgo.fromLib throws', () {
      expect(() => MlKem768FfiAlgo.fromLib(lib!), throwsUnsupportedError);
    }, skip: skip);

    test('XWingFfiAlgo.fromLib throws', () {
      expect(() => XWingFfiAlgo.fromLib(lib!), throwsUnsupportedError);
    }, skip: skip);
  });
}
