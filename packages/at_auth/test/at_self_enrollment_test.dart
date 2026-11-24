import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
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
    expect(signing.algorithm, CryptographicMaterialAlgorithm.mlDsa65);
    expect(base64Decode(signing.bytes.toString()).length, 4032,
        reason: 'the persisted private is the raw ML-DSA-65 secret key');
    expect(base64Decode(verification!.bytes.toString()).length, 1952);

    // The legacy flat fields are byte-identical: the original enrollment
    // keeps authenticating until the atServer's cap retires it.
    expect(after.enrollmentId, 'legacy-1');
    expect(after.apkamPublicKey.toString(), legacyApkamPub);
    expect(after.apkamPrivateKey.toString(), legacyApkamPriv);
    expect(after.defaultSelfEncryptionKey.toString(), selfKey);

    // The two answers the document now gives, and they differ on purpose.
    // The flat field says legacy-1 because that enrollment goes on
    // authenticating; the resolver says new-123 because the typed material is
    // the only ACTIVE privateAuthentication. Asserting only the first would
    // leave the document's own account of which enrollment is live untested.
    expect(after.resolveAuthenticatingEnrollment(), 'new-123',
        reason: 'the retrofit leaves exactly one active privateAuthentication '
            'and it belongs to the new enrollment, so the resolver has one '
            'candidate and names it. A retrofit that left the legacy material '
            'active as well would make this ambiguous and the resolver would '
            'refuse rather than answer');
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
      expect(signing!.algorithm, CryptographicMaterialAlgorithm.rsa2048);
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
    // FROZEN: the same command at_client's `client.enrollments.deny` sends,
    // built through the one EnrollVerbBuilder; the atServer parses this.
    expect(denials.single, 'enroll:deny:{"enrollmentId":"new-123"}\n');
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
              role: CryptographicMaterialRole.privateDecapsulation,
              algorithm: CryptographicMaterialAlgorithm.xWing,
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

    final keyPair = after.authenticationKeyPairFor('new-123')!;
    expect(keyPair.algorithm, SigningAlgoType.mldsa65);
    const challenge = '_deadbeef@alice:cafe';
    final signature = signPkamChallenge(keyPair, challenge);
    final publicKey = after
        .getKey('new-123', 'auth:mldsa65:1',
            CryptographicMaterialRole.publicAuthentication)!
        .bytes
        .toString();
    final ok = await MlDsa65PureDartAlgo().verifyBytes(
        Uint8List.fromList(challenge.codeUnits),
        signature: base64Decode(signature),
        publicKey: base64Decode(publicKey));
    expect(ok, true,
        reason: 'this is the atServer\'s verify side: the whole client chain '
            '(keyfile -> keypair -> pkam signing) must be genuinely ML-DSA');
  });

  group('an enrollment that owns a signing key from birth', () {
    // Rollout 1 moves the AUTHENTICATION key to ML-DSA and mints a
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

    test('an advertised algorithm the keyfile cannot file refuses before the '
        'request', () async {
      final (keysIo, session) = await sessionWithLegacyKeyfile();
      final mock = approvingLookUp();

      await expectLater(
          AtEnrollmentImpl().submit(
              AtSelfEnrollmentRequest(
                  session: session,
                  appName: 'selfapp',
                  deviceName: 'selfdevice',
                  namespaces: {'app_1': 'rw'},
                  advertisedSigningKey: (
                    algorithm: SigningAlgoType.ed25519,
                    publicKey: b64('ed25519-public'),
                    privateKey: b64('ed25519-private')
                  )),
              mock),
          throwsA(isA<AtEnrollmentException>()));

      verifyNever(() => mock.executeCommand(any(that: startsWith('enroll:')),
          auth: any(named: 'auth')));
      expect((await keysIo.read(atSign)).enrollmentIds, isEmpty,
          reason: 'nothing is sent, so the atServer creates no approved '
              'enrollment whose keyfile material could not be filed — and a '
              'retry has no orphan to duplicate');
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

  /// A PRE-ENROLLMENT atSign — one that holds no enrollment at all and
  /// authenticates with the flat `at_pkam_publickey`.
  ///
  /// The atServer migrates that credential into a real enrollment named
  /// `primary` and answers a bare `pkam:` as it, so an `enroll:request` from
  /// such a connection is a retrofit of `primary` and is approved outright.
  /// The client therefore never approves its own request.
  group('a client holding no enrollment does not approve its own request', () {
    late final RsaKeyPair encryptionKeyPair;
    late final String selfEncryptionKey;

    setUpAll(() {
      // A real keypair: the submitter wraps the symmetric key to the public
      // half and the approver unwraps it with the private half, so a stub
      // would leave the round trip untested.
      encryptionKeyPair = RsaKeyPair.generate();
      selfEncryptionKey = AESKey.generate(32).key;
    });

    AtKeys keysFor({String? enrollmentId}) => AtKeys()
      ..apkamPublicKey = AtBytes.fromString(legacyApkamPub)
      ..apkamPrivateKey = AtBytes.fromString(legacyApkamPriv)
      ..defaultEncryptionPublicKey =
          AtBytes.fromString(encryptionKeyPair.atPublicKey.publicKey)
      ..defaultEncryptionPrivateKey =
          AtBytes.fromString(encryptionKeyPair.atPrivateKey.privateKey)
      ..defaultSelfEncryptionKey = AtBytes.fromString(selfEncryptionKey)
      ..enrollmentId = enrollmentId;

    /// A lookup that parks every `enroll:request` as `pending` — which is what
    /// BOTH arms meet — and approves or denies whatever is asked of it after.
    MockAtLookUp parkingLookUp() {
      final mock = MockAtLookUp();
      when(() =>
          mock.executeCommand(any(that: startsWith('enroll:request:')),
              auth: any(named: 'auth'))).thenAnswer(
          (_) async => 'data:{"enrollmentId":"new-123","status":"pending"}');
      when(() =>
          mock.executeCommand(any(that: startsWith('enroll:approve:')),
              auth: any(named: 'auth'))).thenAnswer(
          (_) async => 'data:{"enrollmentId":"new-123","status":"approved"}');
      // executeVerb is deliberately NOT stubbed: `deny` goes through it, and
      // the submitter's cleanup is best-effort and reports what happened, so
      // an unstubbed deny still leaves the control arm asserting the message
      // it cares about.
      return mock;
    }

    Future<(MockAtLookUp, AtAuthSession)> fixture(
        {String? enrollmentId}) async {
      final keysIo = InMemoryAtKeysIo();
      await keysIo.write(atSign, keysFor(enrollmentId: enrollmentId));
      return (
        parkingLookUp(),
        AtAuthSession(
            atSign: atSign,
            rootDomain: AtRootDomain.atsignDomain,
            atKeysIo: keysIo,
            enrollmentId: enrollmentId)
      );
    }

    List<String> commandsSent(MockAtLookUp mock) => verify(
            () => mock.executeCommand(captureAny(), auth: any(named: 'auth')))
        .captured
        .cast<String>();

    /// The session names no enrollment, and the atServer approves outright.
    Future<(MockAtLookUp, AtAuthSession)> approvingFixture() async {
      final keysIo = InMemoryAtKeysIo();
      await keysIo.write(atSign, keysFor());
      return (
        approvingLookUp(),
        AtAuthSession(
            atSign: atSign,
            rootDomain: AtRootDomain.atsignDomain,
            atKeysIo: keysIo)
      );
    }

    test('an approved answer is taken as it stands, with no second command',
        () async {
      final (mock, session) = await approvingFixture();

      final response = await AtEnrollmentImpl().submit(
          AtSelfEnrollmentRequest(
              session: session,
              appName: 'firstApp',
              deviceName: 'firstDevice-abc',
              namespaces: {'*': 'rw', '__manage': 'rw'}),
          mock);

      expect(response.enrollStatus, EnrollmentStatus.approved);
      final sent = commandsSent(mock);
      expect(sent, hasLength(1),
          reason: 'the atServer approves a retrofit of primary outright, so '
              'there is nothing for the client to approve. A second command '
              'here is the self-approval coming back');
      expect(sent.single, startsWith('enroll:request:'));
    });

    test('the request carries no wrapped symmetric key', () async {
      final (mock, session) = await approvingFixture();

      await AtEnrollmentImpl().submit(
          AtSelfEnrollmentRequest(
              session: session,
              appName: 'firstApp',
              deviceName: 'firstDevice-abc',
              namespaces: {'*': 'rw'}),
          mock);

      final params =
          jsonDecode(commandsSent(mock)[0].substring('enroll:request:'.length))
              as Map<String, dynamic>;
      expect(params['encryptedAPKAMSymmetricKey'], isNull,
          reason: 'a retrofit conveys nothing — the keyfile already holds '
              'every secret an approver would pass on — and nothing approves '
              'this request, so there is no approval for a symmetric key to '
              'serve. The atServer requires one only for a request carrying '
              'an otp');
    });

    /// A `pending` answer means an atServer that does not auto-approve, which
    /// this client does not support: it is denied and thrown whatever the
    /// session names.
    test('a pending answer is denied and thrown, whatever the session names',
        () async {
      final (mock, session) = await fixture(enrollmentId: 'legacy-1');

      await expectLater(
          AtEnrollmentImpl().submit(
              AtSelfEnrollmentRequest(
                  session: session,
                  appName: 'selfapp',
                  deviceName: 'selfdevice',
                  namespaces: {'app_1': 'rw'}),
              mock),
          throwsA(isA<AtEnrollmentException>().having(
              (e) => e.message,
              'message',
              contains('expected the self-enrollment to be '
                  'auto-approved'))),
          reason: 'a pending APKAM self-enrolment means an atServer without '
              'the auto-approve, which is a different situation and keeps its '
              'own answer');
      expect(commandsSent(mock).where((c) => c.startsWith('enroll:approve:')),
          isEmpty,
          reason: 'approving here would silently paper over an old atServer');
    });
  });

  group('a keyfile that cannot be written', () {
    Future<(_RefusingWritesKeysIo, AtAuthSession)> sessionRefusingWrites(
        {required int from}) async {
      final keysIo = _RefusingWritesKeysIo(refusingFrom: from);
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

    /// Approves every request, answers a revoke with [revokeAnswer], and
    /// records every command it is sent.
    MockAtLookUp recordingLookUp(List<String> sent,
        {String revokeAnswer =
            'data:{"enrollmentId":"new-123","status":"revoked"}'}) {
      final mock = MockAtLookUp();
      when(() => mock.executeCommand(any(), auth: any(named: 'auth')))
          .thenAnswer((invocation) async {
        final command = invocation.positionalArguments.first as String;
        sent.add(command);
        return command.startsWith('enroll:revoke:')
            ? revokeAnswer
            : approvedResponse;
      });
      return mock;
    }

    test('a keyfile that refuses a write sends no enrollment request',
        () async {
      final (_, session) = await sessionRefusingWrites(from: 1);
      final sent = <String>[];

      Object? thrown;
      try {
        await AtEnrollmentImpl()
            .submit(requestFor(session), recordingLookUp(sent));
      } catch (e) {
        thrown = e;
      }

      expect(sent.where((c) => c.startsWith('enroll:request:')), isEmpty,
          reason: 'a keyfile that cannot be written stops the retrofit before '
              'the atServer is asked for anything');
      expect(
          thrown,
          isA<AtEnrollmentException>().having((e) => e.message, 'message',
              contains('no self-enrollment was requested')));
    });

    test(
        'a keyfile that refuses the save after approval has the new '
        'enrollment revoked', () async {
      final (_, session) = await sessionRefusingWrites(from: 2);
      final sent = <String>[];

      Object? thrown;
      try {
        await AtEnrollmentImpl()
            .submit(requestFor(session), recordingLookUp(sent));
      } catch (e) {
        thrown = e;
      }

      final revokes = sent.where((c) => c.startsWith('enroll:revoke:'));
      expect(revokes, hasLength(1),
          reason: 'an approved enrollment whose keys were not saved is '
              'revoked over the same connection');
      // FROZEN: the same command at_client's `client.enrollments.revoke`
      // sends without force; the atServer parses this.
      expect(revokes.single, 'enroll:revoke:{"enrollmentId":"new-123"}\n',
          reason: 'it revokes the id the atServer returned, and only that');
      expect(sent.indexWhere((c) => c.startsWith('enroll:request:')),
          lessThan(sent.indexOf(revokes.single)));
      expect(
          thrown,
          isA<AtEnrollmentException>().having(
              (e) => e.message,
              'message',
              allOf(contains('could not be written'),
                  contains('new-123 it created was revoked'))),
          reason: 'the error names the enrollment and says it was revoked');
    });

    test('a revoke the atServer refuses is reported in the error', () async {
      final (_, session) = await sessionRefusingWrites(from: 2);
      final sent = <String>[];
      const refusal = 'error:AT0009-UnAuthorized Exception: Failed to revoke '
          'enrollment id: new-123. Client is not authorized for namespaces '
          'in the enrollment request';

      Object? thrown;
      try {
        await AtEnrollmentImpl().submit(
            requestFor(session), recordingLookUp(sent, revokeAnswer: refusal));
      } catch (e) {
        thrown = e;
      }

      expect(
          thrown,
          isA<AtEnrollmentException>().having(
              (e) => e.message,
              'message',
              allOf(contains('new-123 it created could NOT be revoked'),
                  contains('AT0009'), contains('__manage'))),
          reason: 'a revoke that fails is reported with the atServer\'s '
              'answer, rather than implying the atServer was left clean');
    });

    test('a keyfile that takes writes saves and returns the new enrollment',
        () async {
      final (keysIo, session) = await sessionRefusingWrites(from: 1 << 30);
      final sent = <String>[];

      final response = await AtEnrollmentImpl()
          .submit(requestFor(session), recordingLookUp(sent));

      expect(response.enrollmentId, 'new-123');
      expect(response.enrollStatus, EnrollmentStatus.approved);
      expect(
          (await keysIo.read(atSign)).keysForEnrollment('new-123'), isNotEmpty,
          reason: 'the new enrollment\'s material is in the keyfile');
      expect(sent, hasLength(1),
          reason: 'one request and nothing else: no cleanup runs when the '
              'keyfile takes the write');
      expect(sent.single, startsWith('enroll:request:'));
    });
  });

  /// @alice's keyfile on disk, holding legacy keys only, in a directory
  /// removed after the test.
  Future<String> keyfileOnDisk() async {
    final dir = Directory.systemTemp.createTempSync('self_enrollment_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/${atSign}_key.atKeys';
    await FileAtKeysIo(filePath: (_) => path).write(
        atSign,
        AtKeys.legacy(
            apkamPublicKey: legacyApkamPub,
            apkamPrivateKey: legacyApkamPriv,
            encryptionPublicKey: b64('enc-public'),
            encryptionPrivateKey: b64('enc-private'),
            selfEncryptionKey: AESKey.generate(32).key,
            enrollmentId: 'legacy-1'));
    return path;
  }

  FileAtKeysIo keysAt(String keyfile) => FileAtKeysIo(filePath: (_) => keyfile);

  AtSelfEnrollmentRequest requestOn(String keyfile) => requestFor(AtAuthSession(
      atSign: atSign,
      rootDomain: const AtRootDomain('127.0.0.1', 1),
      atKeysIo: keysAt(keyfile),
      enrollmentId: 'legacy-1'));

  /// An atServer that runs [meanwhile] before it approves the
  /// self-enrollment's request, confirms a revoke, and records every command
  /// in [sent].
  MockAtLookUp answeringAfter(
      Future<void> Function() meanwhile, List<String> sent) {
    final mock = MockAtLookUp();
    when(() => mock.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((invocation) async {
      final command = invocation.positionalArguments.first as String;
      sent.add(command);
      if (command.startsWith('enroll:request:')) {
        await meanwhile();
        return approvedResponse;
      }
      if (command.startsWith('enroll:revoke:')) {
        return 'data:{"enrollmentId":"new-123","status":"revoked"}';
      }
      throw StateError('the mocked atServer has no answer for: $command');
    });
    return mock;
  }

  const namespaceKeyId = 'nskey.app_1.kid1';

  /// Another writer's update filing an active namespace key private,
  /// atSign-scope, as at_client files one.
  Future<void> addNamespaceKey(String keyfile) =>
      keysAt(keyfile).update(atSign.toAtsign(), (keys) {
        keys.addKey(CryptographicMaterial(
            keyId: namespaceKeyId,
            role: CryptographicMaterialRole.privateDecapsulation,
            algorithm: CryptographicMaterialAlgorithm.xWing,
            bytes: AtBytes(Uint8List.fromList(List.filled(32, 7))),
            createdAt: DateTime.utc(2026, 1, 1)));
        return true;
      });

  List<String> revokesIn(List<String> sent) =>
      sent.where((c) => c.startsWith('enroll:revoke:')).toList();

  /// Catalogue: features/at_auth/self_enrollment_files_through_update.feature
  group('A self-enrollment files its keys through update', () {
    test(
        'A key another writer adds while a self-enrollment waits on the '
        'atServer is kept', () async {
      final keyfile = await keyfileOnDisk();

      final response = await AtEnrollmentImpl().submit(requestOn(keyfile),
          answeringAfter(() => addNamespaceKey(keyfile), []));

      expect(response.enrollmentId, 'new-123');
      final after = await keysAt(keyfile).read(atSign);
      expect(
          after.getAtSignKey(
              namespaceKeyId, CryptographicMaterialRole.privateDecapsulation),
          isNotNull,
          reason: 'the key the other writer added is kept');
      expect(
          after.getKey('new-123', 'auth:mldsa65:1',
              CryptographicMaterialRole.privateAuthentication),
          isNotNull);
      expect(
          after.getKey('new-123', 'auth:mldsa65:1',
              CryptographicMaterialRole.publicAuthentication),
          isNotNull);
    });

    test(
        'A keyfile removed while a self-enrollment waits on the atServer is '
        'not written again', () async {
      final keyfile = await keyfileOnDisk();
      final sent = <String>[];

      Object? thrown;
      try {
        await AtEnrollmentImpl().submit(
            requestOn(keyfile),
            answeringAfter(() async {
              await File(keyfile).delete();
            }, sent));
      } catch (e) {
        thrown = e;
      }

      expect(File(keyfile).existsSync(), isFalse,
          reason: 'a keyfile removed meanwhile stays removed');
      expect(revokesIn(sent), ['enroll:revoke:{"enrollmentId":"new-123"}\n']);
      expect(
          thrown,
          isA<AtEnrollmentException>().having(
              (e) => e.message,
              'message',
              allOf(contains('could not be written'),
                  contains('new-123 it created was revoked'))));
    });

    test(
        'A second live enrollment filed while a self-enrollment waits is '
        'refused and revoked', () async {
      final keyfile = await keyfileOnDisk();
      final sent = <String>[];
      expect(
          (await keysAt(keyfile).read(atSign)).keys.where(
              (m) => m.role == CryptographicMaterialRole.privateAuthentication),
          isEmpty);

      Object? thrown;
      try {
        await AtEnrollmentImpl().submit(
            requestOn(keyfile),
            answeringAfter(
                () => keysAt(keyfile).update(atSign.toAtsign(), (keys) {
                      keys.fileApkamMaterial(
                          enrollmentId: 'other-9',
                          algorithm: CryptographicMaterialAlgorithm.mlDsa65,
                          publicKey: b64('other-public'),
                          privateKey: b64('other-private'));
                      return true;
                    }),
                sent));
      } catch (e) {
        thrown = e;
      }

      final after = await keysAt(keyfile).read(atSign);
      expect(
          after.getKey('other-9', 'auth:mldsa65:1',
              CryptographicMaterialRole.privateAuthentication),
          isNotNull);
      expect(after.keysForEnrollment('new-123'), isEmpty);
      expect(revokesIn(sent), ['enroll:revoke:{"enrollmentId":"new-123"}\n']);
      expect(
          thrown,
          isA<AtEnrollmentException>().having(
              (e) => e.message, 'message', contains('could not be written')));
    });
  });

  group(
      'Given a store whose update runs the change twice, each on a fresh copy',
      () {
    test(
        'when a self-enrollment files its keys, then the keyfile holds one '
        'copy of each key', () async {
      final keysIo = _TwiceRunningKeysIo();
      await keysIo.write(atSign, legacyKeys());
      final mock = approvingLookUp();

      final response = await AtEnrollmentImpl().submit(
          AtSelfEnrollmentRequest(
              session: AtAuthSession(
                  atSign: atSign,
                  rootDomain: const AtRootDomain('127.0.0.1', 1),
                  atKeysIo: keysIo,
                  enrollmentId: 'legacy-1'),
              appName: 'selfapp',
              deviceName: 'selfdevice',
              namespaces: {'app_1': 'rw'},
              advertisedSigningKey: (
                algorithm: SigningAlgoType.rsa2048,
                publicKey: b64('signing-public'),
                privateKey: b64('signing-private')
              ),
              metadataBuilder: (metadataKeysIo) async {
                (await metadataKeysIo.read(atSign)).addKey(
                    CryptographicMaterial(
                        keyId: 'kp-abc123',
                        role: CryptographicMaterialRole.privateDecapsulation,
                        algorithm: CryptographicMaterialAlgorithm.xWing,
                        bytes: AtBytes(Uint8List.fromList([1, 2, 3])),
                        createdAt: DateTime.utc(2026, 1, 1)));
                return null;
              }),
          mock);

      final filed = [
        for (final m
            in (await keysIo.read(atSign)).keysForEnrollment('new-123'))
          '${m.keyId} ${m.role.value}'
      ]..sort();
      expect(filed, [
        'auth:mldsa65:1 privateAuthentication',
        'auth:mldsa65:1 publicAuthentication',
        'kp-abc123 privateDecapsulation',
        'sign:rsa2048:1 privateSigning',
        'sign:rsa2048:1 publicVerification',
      ]);
      // ignore: deprecated_member_use_from_same_package
      expect(response.atAuthKeys, same(await keysIo.read(atSign)),
          reason: 'the response carries the keys the last run of the change '
              'was handed, which are the keys the store wrote');
      verify(() => mock.executeCommand(any(that: startsWith('enroll:request:')),
          auth: any(named: 'auth'))).called(1);
    });
  });

  group(
      'Given another writer added a key to the keyfile while the '
      'self-enrollment waited', () {
    test(
        'when the self-enrollment succeeds, then response.atAuthKeys holds '
        'the added key and the new enrollment\'s keys', () async {
      final keyfile = await keyfileOnDisk();

      final response = await AtEnrollmentImpl().submit(requestOn(keyfile),
          answeringAfter(() => addNamespaceKey(keyfile), []));

      // ignore: deprecated_member_use_from_same_package
      final keys = response.atAuthKeys!;
      expect(
          keys.getAtSignKey(
              namespaceKeyId, CryptographicMaterialRole.privateDecapsulation),
          isNotNull);
      expect(
          keys.getKey('new-123', 'auth:mldsa65:1',
              CryptographicMaterialRole.privateAuthentication),
          isNotNull);
    });
  });

  group('Given a store whose update returns without running the change', () {
    test(
        'when a self-enrollment files its keys, then it revokes the '
        'enrollment it created and throws AtEnrollmentException', () async {
      final keysIo = _NeverRunsTheChangeKeysIo();
      await keysIo.write(atSign, legacyKeys());
      final sent = <String>[];

      Object? thrown;
      try {
        await AtEnrollmentImpl().submit(
            requestFor(AtAuthSession(
                atSign: atSign,
                rootDomain: const AtRootDomain('127.0.0.1', 1),
                atKeysIo: keysIo,
                enrollmentId: 'legacy-1')),
            answeringAfter(() async {}, sent));
      } catch (e) {
        thrown = e;
      }

      expect(revokesIn(sent), ['enroll:revoke:{"enrollmentId":"new-123"}\n']);
      expect(
          thrown,
          isA<AtEnrollmentException>().having(
              (e) => e.message,
              'message',
              allOf(contains('could not be written'),
                  contains('new-123 it created was revoked'))));
    });
  });
}

/// An in-memory keyfile whose [update] returns without running the change.
class _NeverRunsTheChangeKeysIo extends InMemoryAtKeysIo {
  // ignore: invalid_use_of_visible_for_testing_member
  _NeverRunsTheChangeKeysIo();

  @override
  Future<void> update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) async {}
}

/// An in-memory keyfile whose [update] runs the change twice, each time on a
/// fresh copy of what it holds, and stores what the second run left.
class _TwiceRunningKeysIo extends InMemoryAtKeysIo {
  // ignore: invalid_use_of_visible_for_testing_member
  _TwiceRunningKeysIo();

  @override
  Future<void> update(
      Atsign atsign, FutureOr<bool> Function(AtKeys keys) mutate) async {
    late AtKeys copy;
    for (var run = 0; run < 2; run++) {
      copy = AtKeys.fromJson((await read(atsign.toString())).toJson());
      if (await mutate(copy) == false) return;
    }
    await flush(atsign, copy);
  }
}

/// An in-memory keyfile whose writes are refused from the [refusingFrom]th
/// on, counting from one.
class _RefusingWritesKeysIo extends InMemoryAtKeysIo {
  final int refusingFrom;
  int _writes = 0;

  // ignore: invalid_use_of_visible_for_testing_member
  _RefusingWritesKeysIo({required this.refusingFrom});

  @override
  FutureOr<void> flush(Atsign atsign, AtKeys atKeys) {
    if (++_writes >= refusingFrom) throw _WriteRefused();
    return super.flush(atsign, atKeys);
  }
}

class _WriteRefused implements Exception {
  @override
  String toString() => '_WriteRefused: the keyfile is read-only';
}
