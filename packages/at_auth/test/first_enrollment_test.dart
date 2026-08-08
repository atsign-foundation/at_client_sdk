import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/enroll/at_enrollment_impl.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtLookUp extends Mock implements AtLookupImpl {}

/// The first enrollment — the one CRAM onboarding submits — can now name its
/// APKAM's signing algorithm and carry metadata, which is what lets an atSign
/// be PQ-native from activation rather than only after a retrofit.
///
/// `metadata.keyPackage` is written by the request that creates the enrollment
/// record and never again, so this is the only moment it can be set at all.
void main() {
  const atSign = '@alice';
  const approvedResponse = 'data:{"enrollmentId":"first-1","status":"approved"}';

  String b64(String s) => base64Encode(utf8.encode(s));

  MockAtLookUp approvingLookUp() {
    final mock = MockAtLookUp();
    when(() => mock.executeCommand(any(that: startsWith('enroll:')),
        auth: any(named: 'auth'))).thenAnswer((_) async => approvedResponse);
    return mock;
  }

  Map<String, dynamic> paramsOf(MockAtLookUp mock) {
    final command = verify(() => mock.executeCommand(captureAny(),
        auth: any(named: 'auth'))).captured.single as String;
    expect(command, startsWith('enroll:request:'));
    return jsonDecode(command.substring('enroll:request:'.length))
        as Map<String, dynamic>;
  }

  AtKeys keysWithApkam() => AtKeys()
    ..apkamPublicKey = AtBytes.fromString(b64('apkam-public'))
    ..apkamPrivateKey = AtBytes.fromString(b64('apkam-private'));

  group('FirstEnrollmentRequest', () {
    test('defaults to rsa2048 and sends no metadata — the legacy onboard is '
        'byte-unchanged', () async {
      final mock = approvingLookUp();

      final response = await AtEnrollmentImpl().submit(
          FirstEnrollmentRequest(
              atSign: atSign,
              appName: 'wavi',
              deviceName: 'iphone',
              apkamPublicKey: b64('apkam-public')),
          mock);

      expect(response.enrollmentId, 'first-1');
      expect(response.enrollStatus, EnrollmentStatus.approved);
      final params = paramsOf(mock);
      expect(params['signingAlgo'], 'rsa2048');
      expect(params.containsKey('metadata'), isFalse,
          reason: 'an empty metadata map is dropped rather than sent, so a '
              'legacy onboard puts nothing new on the wire');
    });

    test('a PQ-native first enrollment declares mldsa65', () async {
      final mock = approvingLookUp();

      await AtEnrollmentImpl().submit(
          FirstEnrollmentRequest(
              atSign: atSign,
              appName: 'wavi',
              deviceName: 'iphone',
              apkamPublicKey: b64('apkam-public'),
              signingAlgo: SigningAlgoType.mldsa65),
          mock);

      expect(paramsOf(mock)['signingAlgo'], 'mldsa65',
          reason: 'the atServer composes the tagged _apsk from '
              '(apkamPublicKey, signingAlgo), and verifies this enrollment\'s '
              'PKAM signatures with the algorithm the record names');
    });

    test('the metadataBuilder\'s result rides the request', () async {
      final mock = approvingLookUp();

      await AtEnrollmentImpl().submit(
          FirstEnrollmentRequest(
              atSign: atSign,
              appName: 'wavi',
              deviceName: 'iphone',
              apkamPublicKey: b64('apkam-public'),
              signingAlgo: SigningAlgoType.mldsa65,
              atKeys: keysWithApkam(),
              metadataBuilder: (_) async => {'keyPackage': 'signed-envelope'}),
          mock);

      final metadata = paramsOf(mock)['metadata'] as Map<String, dynamic>;
      expect(metadata['keyPackage'], 'signed-envelope');
    });

    test('the material a builder mints reaches the CALLER\'s AtKeys', () async {
      // The one property that cannot be recovered if it is wrong: the builder
      // files the key package's private half into the keys it is handed. Hand
      // over a copy and the atSign advertises an encapsulation target whose
      // private half nobody kept — every sender seals to a key that can never
      // be opened, and nothing fails until the first read.
      final callersKeys = keysWithApkam();

      await AtEnrollmentImpl().submit(
          FirstEnrollmentRequest(
              atSign: atSign,
              appName: 'wavi',
              deviceName: 'iphone',
              apkamPublicKey: b64('apkam-public'),
              atKeys: callersKeys,
              metadataBuilder: (keysIo) async {
                final handed = await keysIo.read(atSign);
                handed.addKey(AtKeysMaterial(
                    keyId: 'kpid-1',
                    keyPartType: CryptographicKeyType.privateDecapsulation,
                    keyAlgorithmType: KeyAlgorithmType.xWing,
                    bytes: AtBytes.fromString(b64('the-seed')),
                    createdAt: DateTime.now().toUtc()));
                return {'keyPackage': 'signed-envelope'};
              }),
          approvingLookUp());

      final filed = callersKeys.getKey(
          'kpid-1', CryptographicKeyType.privateDecapsulation);
      expect(filed, isNotNull,
          reason: 'the builder must mutate the caller\'s own AtKeys, not a '
              'copy — this is the only place the private half is written');
      expect(filed!.bytes.toString(), b64('the-seed'));
    });

    test('a metadataBuilder without atKeys is refused, not silently dropped',
        () async {
      expect(
          () => AtEnrollmentImpl().submit(
              FirstEnrollmentRequest(
                  atSign: atSign,
                  appName: 'wavi',
                  deviceName: 'iphone',
                  apkamPublicKey: b64('apkam-public'),
                  metadataBuilder: (_) async => {'keyPackage': 'x'}),
              approvingLookUp()),
          throwsA(isA<AtEnrollmentException>()),
          reason: 'building against a throwaway AtKeys would succeed on the '
              'wire and lose the private half, which surfaces only on a read '
              'much later');
    });
  });
}
