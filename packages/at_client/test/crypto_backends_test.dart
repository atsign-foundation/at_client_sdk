// ignore_for_file: implementation_imports
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/backends/crypto_backends.dart'
    show aesGcm256Backend;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// The post-quantum data path seals with OpenSSL where this platform loads one
/// supporting the algorithm, and what it writes stays readable by pure Dart,
/// which is what a device without OpenSSL runs.
void main() {
  final lib = tryLoadLibCrypto();
  final opensslMlKem = lib != null && libCryptoSupportsMlKem768(lib);
  final opensslAesGcm = lib != null && libCryptoSupportsAesGcm(lib);

  group('the backend in use', () {
    test('X-Wing is OpenSSL exactly when the loaded libcrypto has ML-KEM-768',
        () {
      final kem = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing);
      expect(
          kem, opensslMlKem ? isA<XWingFfiAlgo>() : isA<XWingPureDartAlgo>());
      expect(SecretSharingAlgos.kemForSuite(SecretSharingAlgos.xWingRfc9180),
          same(kem),
          reason: 'sealing and opening must pick the same instance, or an '
              'identity check between the two refuses every envelope');
    });

    test('AES-GCM is OpenSSL exactly when the loaded libcrypto supports it',
        () {
      expect(aesGcm256Backend, opensslAesGcm ? 'openssl' : 'dart');
    });

    test('ML-KEM-1024 stays pure Dart, having no OpenSSL backend', () {
      expect(SecretSharingAlgos.kemFor(SecretSharingAlgos.mlKem1024),
          same(MlKem1024PureDartAlgo.instance));
    });
  });

  group('a device without OpenSSL reads what this one writes, and back', () {
    final info = Uint8List.fromList(utf8.encode('at/nskey:@alice:app'));
    final content = Uint8List.fromList(List<int>.generate(32, (i) => i));

    test('a content key sealed here opens under pure Dart', () async {
      final here = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
      final pure = XWingPureDartAlgo.instance;
      final pair = await pure.keyPairFromSeed(pure.newSeed());
      final sealed = await pqSeal(here, pair.publicKey, content,
          info: info, version: 0x02);
      expect(await pqOpen(pure, pair.secretKey, sealed, info: info), content);
    });

    test('a content key sealed under pure Dart opens here', () async {
      final here = SecretSharingAlgos.kemFor(SecretSharingAlgos.xWing)!;
      final pure = XWingPureDartAlgo.instance;
      final pair = await here.keyPairFromSeed(here.newSeed());
      final sealed = await pqSeal(pure, pair.publicKey, content,
          info: info, version: 0x02);
      expect(await pqOpen(here, pair.secretKey, sealed, info: info), content);
    });

    late CryptoContext context;
    setUp(() {
      registerFallbackValue(AtKey());
      final client = MockAtClient();
      when(() => client.getCurrentAtSign()).thenReturn('@alice');
      context = CryptoContext(atClient: client);
    });

    AtKey record() => AtKey()
      ..key = 'note'
      ..namespace = 'app'
      ..sharedBy = '@alice'
      ..metadata = Metadata();

    ({SymmetricAesGcmProvider provider, ContentKey ck}) writer() {
      final cache = ContentKeyCache();
      final ck =
          ContentKey(Uint8List.fromList(List<int>.generate(32, (i) => 7 * i)));
      cache.putAsCurrent('@alice', 'app', ck, 'kid');
      return (provider: SymmetricAesGcmProvider(cache: cache), ck: ck);
    }

    test('a value written here opens under pure Dart', () async {
      final w = writer();
      final key = record();
      final wire = await w.provider.encrypt(context, key, 'the treaty text');
      final additional = key.metadata.appMetadata!.additional!;
      final plain = await AesGcm256EncryptionAlgo(
              SymmetricAesGcmProvider.valueKeyOf(
                  w.ck, base64Decode(additional['salt'])))
          .decrypt(Uint8List.fromList(base64Decode(wire)),
              iv: InitialisationVector(
                  Uint8List.fromList(base64Decode(additional['iv']))),
              aad: utf8
                  .encode('$symmetricAesGcmCryptoProviderId:@alice::note.app'));
      expect(utf8.decode(plain), 'the treaty text');
    });

    test('a value written under pure Dart opens here', () async {
      final w = writer();
      final salt = Uint8List.fromList(List<int>.generate(32, (i) => 255 - i));
      final iv = InitialisationVector.random(12);
      final sealed = await AesGcm256EncryptionAlgo(
              SymmetricAesGcmProvider.valueKeyOf(w.ck, salt))
          .encrypt(Uint8List.fromList(utf8.encode('from a phone')),
              iv: iv,
              aad: utf8
                  .encode('$symmetricAesGcmCryptoProviderId:@alice::note.app'));
      final key = record()
        ..metadata.appMetadata = AppMetadata(
            providerId: symmetricAesGcmCryptoProviderId,
            additional: {
              'ckKid': w.ck.ckKid,
              'salt': base64Encode(salt),
              'iv': base64Encode(iv.ivBytes),
              'ns': 'app',
              'ckNs': 'app',
            });
      expect(await w.provider.decrypt(context, key, base64Encode(sealed)),
          'from a phone');
    });
  });
}
