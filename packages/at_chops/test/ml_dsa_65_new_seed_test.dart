import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:test/test.dart';

/// `newSeed` is how a caller holding only an [AtSeededSignatureAlgorithm]
/// (such as `AtPqc.mlDsa65`) gets a valid seed without knowing its length.
void main() {
  final DynamicLibrary? lib = tryLoadLibCrypto();
  final bool ffiSupported = lib != null && libCryptoSupportsMlDsa65(lib);

  final backends = <String, AtSeededSignatureAlgorithm Function()>{
    'pure Dart': MlDsa65PureDartAlgo.new,
    'AtPqc.mlDsa65': () => AtPqc.mlDsa65,
    if (ffiSupported) 'FFI': () => MlDsa65FfiAlgo.fromLib(lib),
  };

  group('newSeed', () {
    backends.forEach((name, make) {
      test('$name: returns a seed keyPairFromSeed accepts', () async {
        final dsa = make();
        final Uint8List seed = dsa.newSeed();

        expect(seed, hasLength(MlDsa65Sizes.seedBytes));
        final kp = await dsa.keyPairFromSeed(seed);
        expect(kp.publicKey, hasLength(MlDsa65Sizes.publicKeyBytes));
      });

      test('$name: draws fresh randomness', () {
        final dsa = make();
        expect(dsa.newSeed(), isNot(dsa.newSeed()));
      });
    });
  });
}
