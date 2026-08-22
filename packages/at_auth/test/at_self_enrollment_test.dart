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

    final captured = verify(() =>
            mock.executeCommand(captureAny(), auth: captureAny(named: 'auth')))
        .captured;
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
    final signing = after.getKey('new-123', 'auth:mldsa65:1',
        CryptographicMaterialRole.privateAuthentication);
    final verification = after.getKey('new-123', 'auth:mldsa65:1',
        CryptographicMaterialRole.publicAuthentication);
    expect(signing, isNotNull);
    expect(verification, isNotNull);
    expect(signing!.enrollmentId, 'new-123');
    expect(signing.keyAlgorithmType, CryptographicMaterialAlgorithm.mlDsa65);
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

  group('the retrofit signing-algo selector', () {
    AtSelfEnrollmentRequest requestWithAlgo(
            AtAuthSession session, SigningAlgoType algo) =>
        AtSelfEnrollmentRequest(
            session: session,
            appName: 'selfapp',
            deviceName: 'selfdevice',
            namespaces: {'app_1': 'rw'},
            signingAlgo: algo);

    test('rsa2048 mints a FRESH RSA keypair and submits signingAlgo rsa2048',
        () async {
      final (keysIo, session) = await sessionWithLegacyKeyfile();
      final mock = approvingLookUp();

      final response = await AtEnrollmentImpl()
          .submit(requestWithAlgo(session, SigningAlgoType.rsa2048), mock);
      expect(response.enrollmentId, 'new-123');

      final command = verify(
              () => mock.executeCommand(captureAny(), auth: any(named: 'auth')))
          .captured
          .single as String;
      final params = jsonDecode(command.substring('enroll:request:'.length))
          as Map<String, dynamic>;
      expect(params['signingAlgo'], 'rsa2048');
      expect(params['apkamPublicKey'], isNot(legacyApkamPub),
          reason: 'a rollout-window retrofit means the same ALGORITHM, never '
              'the same key object — reuse would break '
              'one-enrollment-one-keypair and the PKAM binding');

      final after = await keysIo.read(atSign);
      // The algorithm is in the id now, so an rsa2048 retrofit files under
      // auth:rsa2048:1 — reading auth:mldsa65:1 here would find nothing.
      final signing = after.getKey('new-123', 'auth:rsa2048:1',
          CryptographicMaterialRole.privateAuthentication);
      expect(signing!.keyAlgorithmType, CryptographicMaterialAlgorithm.rsa2048);
      expect(signing.enrollmentId, 'new-123');
    });

    test('a second retrofit is refused; a re-run of the same mode reuses',
        () async {
      final (_, session) = await sessionWithLegacyKeyfile();
      final mock = MockAtLookUp();
      var calls = 0;
      when(() => mock.executeCommand(any(that: startsWith('enroll:')),
              auth: any(named: 'auth')))
          .thenAnswer((_) async =>
              'data:{"enrollmentId":"id-${++calls}","status":"approved"}');

      await AtEnrollmentImpl()
          .submit(requestWithAlgo(session, SigningAlgoType.mldsa65), mock);
      // A DIFFERENT algorithm is a second retrofit, and there is never a
      // second retrofit: two live enrollments in one keyfile leave no unique
      // answer to which one it authenticates as. Refused loudly rather than
      // quietly handed the mldsa65 enrollment, which would have the caller
      // believe it holds a mode it does not.
      await expectLater(
          () => AtEnrollmentImpl()
              .submit(requestWithAlgo(session, SigningAlgoType.rsa2048), mock),
          throwsA(isA<AtEnrollmentException>()));

      // The SAME algorithm is a re-run, and still reuses. selfRetrofit
      // documents itself as idempotent and depends on it — a failed
      // signing-root step is recovered by running the whole thing again — so
      // this arm must NOT throw.
      final rerun = await AtEnrollmentImpl()
          .submit(requestWithAlgo(session, SigningAlgoType.mldsa65), mock);
      expect(rerun.enrollmentId, 'id-1',
          reason: 're-running the original mode reuses, not re-mints');
      expect(calls, 1, reason: 'exactly one enrollment was ever minted');
    });

    test(
        'an algorithm outside the retrofit set is refused before anything '
        'is minted or sent', () async {
      final (_, session) = await sessionWithLegacyKeyfile();
      final mock = approvingLookUp();

      await expectLater(
          () => AtEnrollmentImpl()
              .submit(requestWithAlgo(session, SigningAlgoType.ed25519), mock),
          throwsA(isA<AtEnrollmentException>().having((e) => e.message,
              'message', contains('not a retrofit algorithm'))));
      verifyNever(() => mock.executeCommand(any(), auth: any(named: 'auth')));
    });
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

  test(
      'a non-approved response is an error, nothing is persisted, and the '
      'pending enrollment it created is denied', () async {
    final (keysIo, session) = await sessionWithLegacyKeyfile();
    final mock = MockAtLookUp();
    when(() => mock.executeCommand(any(that: startsWith('enroll:')),
            auth: any(named: 'auth')))
        .thenAnswer(
            (_) async => 'data:{"enrollmentId":"new-123","status":"pending"}');

    await expectLater(
        () => AtEnrollmentImpl().submit(requestFor(session), mock),
        throwsA(isA<AtEnrollmentException>().having((e) => e.message, 'message',
            contains('new-123 it created was denied'))));
    final after = await keysIo.read(atSign);
    expect(after.keysForEnrollment('new-123'), isEmpty);

    // An atServer without the self-retrofit auto-approve parks the request as
    // `pending`, so aborting without this leaves a record nobody will act on —
    // and a client that retries leaves one behind per attempt.
    final commands = verify(
            () => mock.executeCommand(captureAny(), auth: any(named: 'auth')))
        .captured
        .cast<String>();
    final denials = commands.where((c) => c.startsWith('enroll:deny')).toList();
    expect(denials, hasLength(1),
        reason: 'the abort must deny the enrollment it just created');
    expect(denials.single, contains('new-123'));
  });

  test(
      'when it cannot deny — a scoped parent — the error says the pending '
      'enrollment was left behind', () async {
    final (_, session) = await sessionWithLegacyKeyfile();
    final mock = MockAtLookUp();
    when(() => mock.executeCommand(any(that: startsWith('enroll:request')),
            auth: any(named: 'auth')))
        .thenAnswer(
            (_) async => 'data:{"enrollmentId":"new-123","status":"pending"}');
    // Denying needs `__manage`, which a scoped parent enrollment does not
    // hold. Observed live against a legacy atServer as AT0009, "The approving
    // enrollment does not have access to __manage namespace" — so the cleanup
    // is best effort and the message has to say which happened rather than
    // implying the server was left clean.
    when(() => mock.executeCommand(any(that: startsWith('enroll:deny')),
            auth: any(named: 'auth')))
        .thenThrow(AtLookUpException('AT0009', 'UnAuthorized client'));

    await expectLater(
        () => AtEnrollmentImpl().submit(requestFor(session), mock),
        throwsA(isA<AtEnrollmentException>().having(
            (e) => e.message,
            'message',
            allOf(contains('could NOT be denied'),
                contains('a retry will add another')))));
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
          keys.addKey(CryptographicMaterial(
              keyId: 'kp-abc123',
              keyPartType: CryptographicMaterialRole.privateDecapsulation,
              keyAlgorithmType: CryptographicMaterialAlgorithm.xWing,
              bytes: AtBytes(Uint8List.fromList([1, 2, 3])),
              createdAt: DateTime.now().toUtc()));
          return {'keyPackage': 'signed-package'};
        });

    await AtEnrollmentImpl().submit(request, mock);

    final command = verify(
            () => mock.executeCommand(captureAny(), auth: any(named: 'auth')))
        .captured
        .first as String;
    final params = jsonDecode(command.substring('enroll:request:'.length));
    expect(params['metadata'], {'keyPackage': 'signed-package'});

    final after = await keysIo.read(atSign);
    final filed = after.getKey(
        'new-123', 'kp-abc123', CryptographicMaterialRole.privateDecapsulation);
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
        .getKey('new-123', 'auth:mldsa65:1',
            CryptographicMaterialRole.publicAuthentication)!
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

  group('an enrollment that owns a signing key from birth', () {
    // Ruling 98: rollout 1 moves the AUTHENTICATION key to ML-DSA and mints a
    // fresh RSA-2048 SIGNING key, which is what `_apsk` advertises. The two
    // keys have different audiences — only the atServer verifies the auth key
    // and it is the operator's own, while every peer verifies the signing key
    // and the fleet is not the operator's to upgrade.
    final signingPub = b64('minted-rsa-signing-public');
    final signingPriv = b64('minted-rsa-signing-private');
    final advertised = (
      algorithm: SigningAlgoType.rsa2048,
      publicKey: signingPub,
      privateKey: signingPriv
    );

    AtSelfEnrollmentRequest requestWithSigningKey(AtAuthSession session) =>
        AtSelfEnrollmentRequest(
            session: session,
            appName: 'selfapp',
            deviceName: 'selfdevice',
            namespaces: {'app_1': 'rw'},
            advertisedSigningKey: advertised);

    Future<Map<String, dynamic>> submitAndCaptureParams(
        AtSelfEnrollmentRequest Function(AtAuthSession) build) async {
      final (_, session) = await sessionWithLegacyKeyfile();
      final mock = approvingLookUp();
      await AtEnrollmentImpl().submit(build(session), mock);
      final command = verify(
              () => mock.executeCommand(captureAny(), auth: any(named: 'auth')))
          .captured
          .single as String;
      return jsonDecode(command.substring('enroll:request:'.length))
          as Map<String, dynamic>;
    }

    test('_apsk advertises the SIGNING key, bare, not the ML-DSA APKAM key',
        () async {
      final params = await submitAndCaptureParams(requestWithSigningKey);

      // RAW comparison against the minted key, not against a constant: the
      // property is which key reached the wire.
      expect(params['apskLegacy'], signingPub);
      expect(params['apsk'], isNull,
          reason: 'bare, not the array. An un-upgraded peer base64-decodes '
              'this value as an RSA key, and a single active rsa2048 entry is '
              'the one spelling that survives that');
      expect(params['apskLegacy'], isNot(params['apkamPublicKey']),
          reason: 'the APKAM key authenticates connections and signs nothing '
              'once the enrollment owns a signing key. Advertising it here is '
              'the breakage rollout 1 exists to prevent — under 98 it is '
              'ML-DSA, which no deployed reader can parse');
      expect(params['signingAlgo'], 'mldsa65',
          reason: 'and the AUTHENTICATION key still moved to ML-DSA: the wire '
              'field names that key, which is the whole point of the stage');
    });

    test('without one, _apsk still advertises the APKAM key', () async {
      // The `now` path, unchanged — a client whose fleet has not upgraded must
      // keep publishing exactly what every released build publishes.
      final params = await submitAndCaptureParams(requestFor);

      expect(params['apskLegacy'], isNull);
      expect(jsonEncode(params['apsk']),
          contains(params['apkamPublicKey'] as String),
          reason: 'no signing key of its own, so the APKAM key both '
              'authenticates and signs, and the record names it');
    });

    test('the signing key is FILED, not merely advertised', () async {
      final keysIo = InMemoryAtKeysIo();
      await keysIo.write(atSign, legacyKeys());
      final session = AtAuthSession(
          atSign: atSign,
          rootDomain: AtRootDomain.atsignDomain,
          atKeysIo: keysIo,
          enrollmentId: 'legacy-1');

      await AtEnrollmentImpl()
          .submit(requestWithSigningKey(session), approvingLookUp());

      final keys = await keysIo.read(atSign);
      final held = keys.signingKeysFor('new-123');
      expect(held, hasLength(1));
      expect(held.single.algorithm, SigningAlgoType.rsa2048);
      expect(held.single.publicKey, signingPub);
      expect(held.single.privateKey, signingPriv,
          reason: 'advertise-without-file leaves the next start finding the '
              'in-use algorithm missing, minting a SECOND key and '
              'republishing — orphaning the key this record already named');
    });
  });
}
