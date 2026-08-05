import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/enroll/at_enrollment_impl.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtLookUp extends Mock implements AtLookupImpl {}

/// The client half of the PQ self-retrofit (RF-2b): an
/// [AtSelfEnrollmentRequest] mints an ML-DSA-65 APKAM keypair, submits an
/// authenticated no-OTP `enroll:request` carrying `signingAlgo:mldsa65`, and
/// persists the new enrollment's material into the SAME keyfile as typed
/// materials — the legacy flat fields untouched.
void main() {
  const atSign = '@alice';
  const approvedResponse =
      'data:{"enrollmentId":"new-123","status":"approved"}';

  // AtBytes.fromString takes base64; these are recognisable strings encoded.
  String b64(String s) => base64Encode(utf8.encode(s));
  final legacyApkamPub = b64('legacy-rsa-public');
  final legacyApkamPriv = b64('legacy-rsa-private');
  final selfKey = b64('self-key');

  AtKeys legacyKeys() => AtKeys()
    ..apkamPublicKey = AtBytes.fromString(legacyApkamPub)
    ..apkamPrivateKey = AtBytes.fromString(legacyApkamPriv)
    ..defaultEncryptionPublicKey = AtBytes.fromString(b64('enc-public'))
    ..defaultEncryptionPrivateKey = AtBytes.fromString(b64('enc-private'))
    ..defaultSelfEncryptionKey = AtBytes.fromString(selfKey)
    ..enrollmentId = 'legacy-1';

  Future<(InMemoryAtKeysIo, AtAuthSession)> sessionWithLegacyKeyfile() async {
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, legacyKeys());
    return (
      keysIo,
      AtAuthSession(
          atSign: atSign,
          rootDomain: AtRootDomain.atsignDomain,
          atKeysIo: keysIo,
          enrollmentId: 'legacy-1')
    );
  }

  AtSelfEnrollmentRequest requestFor(AtAuthSession session) =>
      AtSelfEnrollmentRequest(
          session: session,
          appName: 'selfapp',
          deviceName: 'selfdevice',
          namespaces: {'app_1': 'rw'});

  MockAtLookUp approvingLookUp() {
    final mock = MockAtLookUp();
    when(() => mock.executeCommand(any(that: startsWith('enroll:')),
        auth: any(named: 'auth'))).thenAnswer((_) async => approvedResponse);
    return mock;
  }

  test('the wire shape: authenticated, no OTP, mldsa65, key material rides',
      () async {
    final (_, session) = await sessionWithLegacyKeyfile();
    final mock = approvingLookUp();

    await AtEnrollmentImpl().submit(requestFor(session), mock);

    final captured = verify(() => mock.executeCommand(captureAny(),
        auth: captureAny(named: 'auth'))).captured;
    final command = captured[0] as String;
    expect(captured[1], true,
        reason: 'the atServer discriminates this path solely by the '
            'connection authType, so a reconnect must re-authenticate');
    expect(command, startsWith('enroll:request:'));
    final params = jsonDecode(command.substring('enroll:request:'.length))
        as Map<String, dynamic>;
    expect(params['appName'], 'selfapp');
    expect(params['deviceName'], 'selfdevice');
    expect(params['signingAlgo'], 'mldsa65');
    expect(params['namespaces'], {'app_1': 'rw'});
    expect(params.containsKey('otp'), isFalse,
        reason: 'no OTP: the authenticated connection is the authority');
    expect(params.containsKey('encryptedAPKAMSymmetricKey'), isFalse,
        reason: 'nothing is conveyed: the keyfile already holds every secret '
            'an approver would otherwise seal to the new enrollment');
    // The advertised APKAM public key is a genuine raw ML-DSA-65 public key.
    expect(base64Decode(params['apkamPublicKey'] as String).length, 1952);
  });

  test(
      'the keyfile after: typed materials under the new id, flat fields '
      'untouched', () async {
    final (keysIo, session) = await sessionWithLegacyKeyfile();

    final response =
        await AtEnrollmentImpl().submit(requestFor(session), approvingLookUp());
    expect(response.enrollmentId, 'new-123');
    expect(response.enrollStatus, EnrollmentStatus.approved);

    final after = await keysIo.read(atSign);
    final signing = after.getKey(
        'apkam:new-123', CryptographicKeyType.privateSigning);
    final verification = after.getKey(
        'apkam:new-123', CryptographicKeyType.publicVerification);
    expect(signing, isNotNull);
    expect(verification, isNotNull);
    expect(signing!.enrollmentId, 'new-123');
    expect(signing.keyAlgorithmType, KeyAlgorithmType.mlDsa65);
    expect(base64Decode(signing.bytes.toString()).length, 4032,
        reason: 'the persisted private is the raw ML-DSA-65 secret key');
    expect(base64Decode(verification!.bytes.toString()).length, 1952);

    // The legacy flat fields are byte-identical: the original enrollment
    // keeps authenticating until the atServer's cap retires it.
    expect(after.enrollmentId, 'legacy-1');
    expect(after.apkamPublicKey.toString(), legacyApkamPub);
    expect(after.apkamPrivateKey.toString(), legacyApkamPriv);
    expect(after.defaultSelfEncryptionKey.toString(), selfKey);
  });

  test('mint-once per keyfile: a second submit reuses, no second request',
      () async {
    final (_, session) = await sessionWithLegacyKeyfile();
    final mock = approvingLookUp();

    final first = await AtEnrollmentImpl().submit(requestFor(session), mock);
    final second = await AtEnrollmentImpl().submit(requestFor(session), mock);

    expect(second.enrollmentId, first.enrollmentId);
    verify(() => mock.executeCommand(any(), auth: any(named: 'auth')))
        .called(1);
  });

  test('empty namespaces are refused before anything is minted or sent',
      () async {
    final (_, session) = await sessionWithLegacyKeyfile();
    final mock = approvingLookUp();

    await expectLater(
        () => AtEnrollmentImpl().submit(
            AtSelfEnrollmentRequest(
                session: session,
                appName: 'selfapp',
                deviceName: 'selfdevice',
                namespaces: {}),
            mock),
        throwsA(isA<AtEnrollmentException>()));
    verifyNever(() => mock.executeCommand(any(), auth: any(named: 'auth')));
  });

  test('a non-approved response is an error, and nothing is persisted',
      () async {
    final (keysIo, session) = await sessionWithLegacyKeyfile();
    final mock = MockAtLookUp();
    when(() => mock.executeCommand(any(that: startsWith('enroll:')),
            auth: any(named: 'auth')))
        .thenAnswer((_) async =>
            'data:{"enrollmentId":"new-123","status":"pending"}');

    await expectLater(
        () => AtEnrollmentImpl().submit(requestFor(session), mock),
        throwsA(isA<AtEnrollmentException>()));
    final after = await keysIo.read(atSign);
    expect(after.keysForEnrollment('new-123'), isEmpty);
  });

  test(
      'metadataBuilder material is persisted re-tagged with the new '
      'enrollment id, and its metadata rides the request', () async {
    final (keysIo, session) = await sessionWithLegacyKeyfile();
    final mock = approvingLookUp();
    final request = AtSelfEnrollmentRequest(
        session: session,
        appName: 'selfapp',
        deviceName: 'selfdevice',
        namespaces: {'app_1': 'rw'},
        metadataBuilder: (metadataKeysIo) async {
          final keys = await metadataKeysIo.read(atSign);
          // The handed keys carry the freshly minted ML-DSA APKAM keypair.
          expect(base64Decode(keys.apkamPublicKey.toString()).length, 1952);
          keys.addKey(AtKeysMaterial(
              keyId: 'kp-abc123',
              keyPartType: CryptographicKeyType.privateDecapsulation,
              keyAlgorithmType: KeyAlgorithmType.xWing,
              bytes: AtBytes(Uint8List.fromList([1, 2, 3])),
              createdAt: DateTime.now().toUtc()));
          return {'keyPackage': 'signed-package'};
        });

    await AtEnrollmentImpl().submit(request, mock);

    final command = verify(() =>
            mock.executeCommand(captureAny(), auth: any(named: 'auth')))
        .captured
        .first as String;
    final params = jsonDecode(command.substring('enroll:request:'.length));
    expect(params['metadata'], {'keyPackage': 'signed-package'});

    final after = await keysIo.read(atSign);
    final filed = after.getKey(
        'kp-abc123', CryptographicKeyType.privateDecapsulation);
    expect(filed, isNotNull);
    expect(filed!.enrollmentId, 'new-123',
        reason: 'the builder files material before the id exists; the '
            'persist re-tags it with the id the atServer assigned');
  });

  test(
      'the retrofitted enrollment can produce a genuine ML-DSA PKAM '
      'signature via its typed material', () async {
    final (keysIo, session) = await sessionWithLegacyKeyfile();
    await AtEnrollmentImpl().submit(requestFor(session), approvingLookUp());

    final after = await keysIo.read(atSign);
    expect(after.signingAlgorithmForEnrollment('new-123'),
        SigningAlgoType.mldsa65);
    expect(after.signingAlgorithmForEnrollment('legacy-1'), isNull,
        reason: 'the legacy enrollment has no typed signing material; its '
            'RSA keypair lives in the flat fields');

    final atChops = after.toAtChopsForEnrollment('new-123');
    const challenge = '_deadbeef@alice:cafe';
    final result = atChops.sign(AtSigningInput(challenge)
      ..signingAlgoType = SigningAlgoType.mldsa65
      ..signingMode = AtSigningMode.pkam);
    final publicKey = after
        .getKey('apkam:new-123', CryptographicKeyType.publicVerification)!
        .bytes
        .toString();
    final ok = await MlDsa65PureDartAlgo().verifyBytes(
        Uint8List.fromList(challenge.codeUnits),
        signature: base64Decode(result.result),
        publicKey: base64Decode(publicKey));
    expect(ok, true,
        reason: 'this is the atServer\'s verify side: the whole client chain '
            '(keyfile -> AtChops -> pkam dispatch) must be genuinely ML-DSA');
  });
}
