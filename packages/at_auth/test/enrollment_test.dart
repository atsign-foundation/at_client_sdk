import 'dart:async' show FutureOr;
import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/enroll/at_enrollment_impl.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:at_demo_data/at_demo_data.dart';

/// Stands in for a real conveyance resolver where a request advertises a key
/// package but the test stops before `waitForApproval` would collect one.
Future<String> _unusedResolver(AtKeys keys, AtLookUp atLookUp) =>
    throw StateError('the resolver should not run in this test');

class MockAtLookUp extends Mock implements AtLookupImpl {}

class MockLookupVerbBuilder extends Fake implements LookupVerbBuilder {}

void main() {
  setUpAll(() {
    registerFallbackValue(MockLookupVerbBuilder());
  });

  test(
      'A test to verify submitting enrollment to server and verify enrollment status is pending',
      () async {
    String atSign = '@alice🛠';
    AtEnrollmentImpl atEnrollmentServiceImpl = AtEnrollmentImpl();
    AtLookUp mockAtLookUp = MockAtLookUp();

    String? apkamPrivateKey = pkamPrivateKeyMap[atSign]!;
    String? apkamPublicKey = pkamPublicKeyMap[atSign]!;
    String? encryptionPublicKey = encryptionPublicKeyMap[atSign]!;
    String? encryptionPrivateKey = encryptionPrivateKeyMap[atSign]!;
    String? selfEncryptionKey = aesKeyMap[atSign]!;
    String? apkamSymmetricKey = apkamSymmetricKeyMap[atSign]!;

    AtChopsKeys atChopsKeys = AtChopsKeys.create(
        AtEncryptionKeyPair.create(encryptionPublicKey, encryptionPrivateKey),
        AtPkamKeyPair.create(apkamPublicKey, apkamPrivateKey));
    atChopsKeys.apkamSymmetricKey = AESKey(apkamSymmetricKey);
    atChopsKeys.selfEncryptionKey = AESKey(selfEncryptionKey);
    final iv = AtChopsUtil.generateIVLegacy();

    AtChopsImpl atChopsImpl = AtChopsImpl(atChopsKeys);

    when(() => mockAtLookUp.executeVerb(any(that: LookUpVerbBuilderMatcher())))
        .thenAnswer((_) async => 'data:$encryptionPublicKey');

    when(() => mockAtLookUp.executeCommand(any(that: startsWith('enroll:'))))
        .thenAnswer((_) => Future.value('data:${jsonEncode({
                  'enrollmentId': '123',
                  'status': 'pending'
                })}'));

    when(() =>
        mockAtLookUp.executeCommand(
            any(
                that: startsWith(
                    'keys:get:keyName:123.${AtConstants.defaultEncryptionPrivateKey}')),
            auth: true)).thenAnswer((_) async => Future.value(jsonEncode({
          'value': (await atChopsImpl.encryptString(
                  encryptionPrivateKey, EncryptionKeyType.aes256,
                  keyName: 'apkamSymmetricKey', iv: iv))
              .result
        })));

    when(() =>
        mockAtLookUp.executeCommand(
            any(
                that: startsWith(
                    'keys:get:keyName:123.${AtConstants.defaultSelfEncryptionKey}')),
            auth: true)).thenAnswer((_) async => Future.value(jsonEncode({
          'value': (await atChopsImpl.encryptString(
                  selfEncryptionKey, EncryptionKeyType.aes256,
                  keyName: 'apkamSymmetricKey', iv: iv))
              .result
        })));
    when(() => mockAtLookUp.pkamAuthenticate(enrollmentId: '123'))
        .thenAnswer((_) => Future.value(true));

    when(() => (mockAtLookUp as AtLookupImpl).close())
        .thenAnswer((_) async => ());

    AtEnrollmentRequest enrollmentRequest = AtEnrollmentRequest(
        atSign: atSign,
        appName: 'wavi',
        deviceName: 'pixel',
        otp: 'A123FE',
        namespaces: {'wavi': 'rw'});

    AtEnrollmentResponse atEnrollmentResponse =
        await atEnrollmentServiceImpl.submit(enrollmentRequest, mockAtLookUp);
    expect(atEnrollmentResponse.enrollmentId, '123');
    expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.pending);
  });

  group('A group of tests related EnrollmentRequestDecision', () {
    test('A test to verify the approve enrollment', () async {
      String atSign = '@alice🛠';

      String? apkamPrivateKey = pkamPrivateKeyMap[atSign]!;
      String? apkamPublicKey = pkamPublicKeyMap[atSign]!;
      String? encryptionPublicKey = encryptionPublicKeyMap[atSign]!;
      String? encryptionPrivateKey = encryptionPrivateKeyMap[atSign]!;
      String? selfEncryptionKey = aesKeyMap[atSign]!;
      String? apkamSymmetricKey = apkamSymmetricKeyMap[atSign]!;

      String encryptedAPKAMSymmetricKey =
          RSAPublicKey.fromString(encryptionPublicKey)
              .encrypt(apkamSymmetricKey);

      AtChopsKeys atChopsKeys = AtChopsKeys.create(
          AtEncryptionKeyPair.create(encryptionPublicKey, encryptionPrivateKey),
          AtPkamKeyPair.create(apkamPublicKey, apkamPrivateKey));
      atChopsKeys.apkamSymmetricKey = AESKey(apkamSymmetricKey);
      atChopsKeys.selfEncryptionKey = AESKey(selfEncryptionKey);

      AtChopsImpl atChopsImpl = AtChopsImpl(atChopsKeys);

      AtLookUp mockAtLookUp = MockAtLookUp();

      AtEnrollment atEnrollmentBase = AtEnrollmentImpl();

      when(() => mockAtLookUp.atChops).thenReturn(atChopsImpl);

      when(() =>
          mockAtLookUp.executeCommand(any(that: startsWith('enroll:approve')),
              auth: true)).thenAnswer((_) => Future.value('data:${jsonEncode({
                'status': 'approved',
                'enrollmentId': '4be2d358-074d-4e3b-99f3-64c4da01532f'
              })}'));

      EnrollmentRequestDecision enrollmentRequestDecision =
          EnrollmentRequestDecision.approved(
        enrollmentId: '4be2d358-074d-4e3b-99f3-64c4da01532f',
        apkamSymmetricKey: AtBytes.fromString(encryptedAPKAMSymmetricKey),
        atSign: atSign,
      );

      AtEnrollmentResponse atEnrollmentResponse = await atEnrollmentBase
          .approve(enrollmentRequestDecision, mockAtLookUp);

      expect(atEnrollmentResponse.enrollmentId,
          '4be2d358-074d-4e3b-99f3-64c4da01532f');
      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.approved);
    });

    test('A test to verify the deny enrollment', () async {
      String atSign = '@alice🛠';

      String? apkamPrivateKey = pkamPrivateKeyMap[atSign]!;
      String? apkamPublicKey = pkamPublicKeyMap[atSign]!;
      String? encryptionPublicKey = encryptionPublicKeyMap[atSign]!;
      String? encryptionPrivateKey = encryptionPrivateKeyMap[atSign]!;
      String? selfEncryptionKey = aesKeyMap[atSign]!;
      String? apkamSymmetricKey = apkamSymmetricKeyMap[atSign]!;

      AtChopsKeys atChopsKeys = AtChopsKeys.create(
          AtEncryptionKeyPair.create(encryptionPublicKey, encryptionPrivateKey),
          AtPkamKeyPair.create(apkamPublicKey, apkamPrivateKey));
      atChopsKeys.apkamSymmetricKey = AESKey(apkamSymmetricKey);
      atChopsKeys.selfEncryptionKey = AESKey(selfEncryptionKey);

      AtChopsImpl atChopsImpl = AtChopsImpl(atChopsKeys);

      AtLookUp mockAtLookUp = MockAtLookUp();

      AtEnrollment atEnrollmentBase = AtEnrollmentImpl();

      when(() => mockAtLookUp.atChops).thenReturn(atChopsImpl);

      when(() => mockAtLookUp
              .executeCommand(any(that: startsWith('enroll:deny')), auth: true))
          .thenAnswer((_) => Future.value('data:${jsonEncode({
                    'status': 'denied',
                    'enrollmentId': '4be2d358-074d-4e3b-99f3-64c4da01532f'
                  })}'));

      EnrollmentRequestDecision enrollmentRequestDecision =
          EnrollmentRequestDecision.denied(
              '4be2d358-074d-4e3b-99f3-64c4da01532f', atSign);

      AtEnrollmentResponse atEnrollmentResponse =
          await atEnrollmentBase.deny(enrollmentRequestDecision, mockAtLookUp);

      expect(atEnrollmentResponse.enrollmentId,
          '4be2d358-074d-4e3b-99f3-64c4da01532f');
      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.denied);
    });
  });

  group('AtEnrollmentResponse toJson / fromJson', () {
    test('toJson includes enrollmentId and enrollStatus', () {
      final response = AtEnrollmentResponse(
        'enroll-123',
        EnrollmentStatus.approved,
      );

      final json = response.toJson();

      expect(json['enrollmentId'], 'enroll-123');
      expect(json['enrollStatus'], 'approved');
    });

    test('toJson includes atSign when set', () {
      final response = AtEnrollmentResponse(
        'enroll-123',
        EnrollmentStatus.pending,
        atSign: '@alice',
      );

      expect(response.toJson()['atSign'], '@alice');
    });

    test('toJson does not include atAuthKeys', () {
      final response = AtEnrollmentResponse(
        'enroll-123',
        EnrollmentStatus.approved,
        atAuthKeys: AtKeys(),
      );

      expect(response.toJson().containsKey('atAuthKeys'), false);
    });

    test('fromJson restores enrollmentId and enrollStatus', () {
      final json = {
        'enrollmentId': 'enroll-456',
        'enrollStatus': 'denied',
      };

      final response = AtEnrollmentResponse.fromJson(json);

      expect(response.enrollmentId, 'enroll-456');
      expect(response.enrollStatus, EnrollmentStatus.denied);
    });

    test('fromJson sets atAuthKeys to null when present', () {
      final json = {
        'enrollmentId': 'enroll-456',
        'enrollStatus': 'pending',
        'atAuthKeys': AtKeys()
      };
      expect(AtEnrollmentResponse.fromJson(json).atAuthKeys, isNull);
    });

    test('fromJson throws when enrollStatus is unknown', () {
      final json = {
        'enrollmentId': 'enroll-456',
        'enrollStatus': 'invalidStatus',
      };

      expect(
        () => AtEnrollmentResponse.fromJson(json),
        throwsA(isA<StateError>()),
      );
    });

    test('fromJson throws when enrollmentId is missing', () {
      final json = {'enrollStatus': 'approved'};

      expect(
        () => AtEnrollmentResponse.fromJson(json),
        throwsA(anything),
      );
    });
  });

  group('AtEnrollmentRequest session wiring', () {
    test('session is the source of atSign and rootDomain', () {
      final session = AtAuthSession(
        atSign: '@alice🛠',
        rootDomain: const AtRootDomain('root.atsign.org', 64),
        atKeysIo: InMemoryAtKeysIo(),
      );

      final request = AtEnrollmentRequest(
        session: session,
        appName: 'wavi',
        deviceName: 'pixel',
        otp: 'A123FE',
        namespaces: {'wavi': 'rw'},
      );

      expect(request.session, same(session));
      expect(request.atSign, '@alice🛠');
      expect(request.rootDomain, same(session.rootDomain));
    });

    test('throws when neither session nor atSign is provided', () {
      expect(
        () => AtEnrollmentRequest(
          appName: 'wavi',
          deviceName: 'pixel',
          otp: 'A123FE',
          namespaces: {'wavi': 'rw'},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('metadataBuilder', () {
    const atSign = '@alice🛠';

    /// Mocks just enough for a request to reach the atServer and come back
    /// pending, and records the enroll command that was sent.
    (AtLookUp, List<String>) mockLookUpRecordingEnrollCommands() {
      final AtLookUp mockAtLookUp = MockAtLookUp();
      final sent = <String>[];
      when(() =>
              mockAtLookUp.executeVerb(any(that: LookUpVerbBuilderMatcher())))
          .thenAnswer((_) async => 'data:${encryptionPublicKeyMap[atSign]!}');
      when(() => mockAtLookUp.executeCommand(any(that: startsWith('enroll:'))))
          .thenAnswer((inv) {
        sent.add(inv.positionalArguments[0] as String);
        return Future.value('data:${jsonEncode({
              'enrollmentId': '123',
              'status': 'pending',
            })}');
      });
      return (mockAtLookUp, sent);
    }

    AtAuthSession freshSession() => AtAuthSession(
        atSign: atSign,
        rootDomain: AtRootDomain.atsignDomain,
        atKeysIo: InMemoryAtKeysIo());

    AtEnrollmentRequest requestWith(
            FutureOr<Map<String, dynamic>?> Function(AtKeysIo)? builder) =>
        AtEnrollmentRequest(
          session: freshSession(),
          appName: 'wavi',
          deviceName: 'pixel',
          namespaces: {'wavi': 'rw'},
          otp: 'A123FE',
          metadataBuilder: builder,
        );

    AtEnrollmentRequest pqRequestWith(
            FutureOr<Map<String, dynamic>?> Function(AtKeysIo) builder) =>
        AtEnrollmentRequest.pq(
          session: freshSession(),
          appName: 'wavi',
          deviceName: 'pixel',
          namespaces: {'wavi': 'rw'},
          otp: 'A123FE',
          metadataBuilder: builder,
          // These tests stop at submit, so the resolver is never called; it is
          // here because pq mode requires one, and the conveyance it stands
          // for is covered separately.
          apkamSymmetricKeyResolver: _unusedResolver,
        );

    test(
        'receives the APKAM keypair this request will enroll, and no '
        'enrollmentId', () async {
      final (mockAtLookUp, sent) = mockLookUpRecordingEnrollCommands();
      AtKeys? seen;
      // Read at CALL time, not after: the builder is handed the live AtKeys
      // the request goes on to complete, so the enrollmentId the atServer
      // assigns does appear on that object — just not until after the builder
      // has run and signed whatever it signed.
      Object? enrollmentIdWhenCalled;

      await AtEnrollmentImpl().submit(requestWith((keysIo) async {
        seen = await keysIo.read(atSign);
        enrollmentIdWhenCalled = seen!.enrollmentId;
        return {'keyPackage': 'built-by-the-caller'};
      }), mockAtLookUp);

      expect(seen, isNotNull, reason: 'the builder must actually be called');
      expect(seen!.apkamPrivateKey, isNotNull,
          reason: 'the private half is the whole point — the caller has to be '
              'able to sign with the key this enrollment will use, and that '
              'keypair does not exist before the request is assembled');
      // The public half sent to the atServer must be the same keypair the
      // builder signed with, or a verifier fetching _apsk would check the
      // signature against a different key.
      expect(sent.single, contains(seen!.apkamPublicKey!.toString()));

      expect(enrollmentIdWhenCalled, isNull,
          reason: 'the atServer assigns it in the response to this very '
              'request, so anything the builder signs must be valid without '
              'one');
    });

    test('its result rides the enroll command', () async {
      final (mockAtLookUp, sent) = mockLookUpRecordingEnrollCommands();

      await AtEnrollmentImpl().submit(
          requestWith((_) async => {'keyPackage': 'opaque-to-at-auth'}),
          mockAtLookUp);

      expect(sent.single, contains('opaque-to-at-auth'));
    });

    test('a builder that throws costs a log line, not the enrollment',
        () async {
      final (mockAtLookUp, sent) = mockLookUpRecordingEnrollCommands();

      final response = await AtEnrollmentImpl().submit(
          requestWith((_) => throw StateError('no keys')), mockAtLookUp);

      expect(response.enrollmentId, '123',
          reason: 'the metadata is opaque and additive, so a request without '
              'it is still a valid request — failing the enrollment over an '
              'optional payload would be the worse outcome');
      expect(sent.single, isNot(contains('metadata')));
    });

    test('no builder means no metadata on the wire', () async {
      final (mockAtLookUp, sent) = mockLookUpRecordingEnrollCommands();

      await AtEnrollmentImpl().submit(requestWith(null), mockAtLookUp);

      expect(sent.single, isNot(contains('metadata')));
    });

    test('pq mode sends no RSA-wrapped symmetric key', () async {
      final (mockAtLookUp, sent) = mockLookUpRecordingEnrollCommands();

      await AtEnrollmentImpl().submit(
          pqRequestWith((_) async => {'keyPackage': 'advertised'}),
          mockAtLookUp);

      expect(sent.single, isNot(contains('encryptedAPKAMSymmetricKey')),
          reason: 'a pq enrollment never generates the symmetric key — the '
              'approver mints it and encapsulates it to the advertised public '
              'half, so there is nothing to wrap and nothing an adversary '
              'recording the request could harvest');
    });

    test('legacy mode keeps the RSA wrap even when a key package is advertised',
        () async {
      final (mockAtLookUp, sent) = mockLookUpRecordingEnrollCommands();

      await AtEnrollmentImpl().submit(
          requestWith((_) async => {'keyPackage': 'advertised'}), mockAtLookUp);

      expect(sent.single, contains('encryptedAPKAMSymmetricKey'),
          reason: 'a key package is also how an approver seals existing '
              'secrets to a new device, so advertising one must not silently '
              'change how the symmetric key travels — only the mode does');
      expect(sent.single, contains('advertised'),
          reason: 'and the package still rides the request, because secret '
              'conveyance needs it in every mode');
    });

    test('the default mode is legacy', () async {
      final (mockAtLookUp, sent) = mockLookUpRecordingEnrollCommands();

      await AtEnrollmentImpl().submit(requestWith(null), mockAtLookUp);

      expect(sent.single, contains('encryptedAPKAMSymmetricKey'),
          reason: 'existing callers must keep their present behaviour byte '
              'for byte until the default flips in the next major version');
    });

    test('the constructor decides the mode, and carries what it requires', () {
      // A pq request without a resolver used to be a submit-time refusal.
      // It is not a state any more: `.pq` requires one, and the default
      // constructor takes none and reports legacy.
      final pq = pqRequestWith((_) async => {'keyPackage': 'advertised'});
      expect(pq.keyExchangeMode, EnrollmentKeyExchangeMode.pq);
      expect(pq.apkamSymmetricKeyResolver, isNotNull);

      final legacy = requestWith(null);
      expect(legacy.keyExchangeMode, EnrollmentKeyExchangeMode.legacy);
      expect(legacy.apkamSymmetricKeyResolver, isNull,
          reason: 'a legacy request carries its own symmetric key in; there '
              'is nothing waiting to be collected');
    });

    test('pq mode without a key package is refused', () async {
      final (mockAtLookUp, sent) = mockLookUpRecordingEnrollCommands();

      await expectLater(
          AtEnrollmentImpl().submit(pqRequestWith((_) async => null),
              mockAtLookUp),
          throwsA(isA<AtEnrollmentException>()));

      expect(sent, isEmpty,
          reason: 'there would be no public half for the approver to '
              'encapsulate the symmetric key to, so the enrollment could '
              'never obtain one');
    });
  });

  group('waitForApproval decrypts the fetched keys', () {
    // The two wire shapes of an approval-time key record: a modern approver
    // stores an IV beside the value; a legacy approver stored the value
    // alone, encrypted under the zero IV ("the bad old days"). Both must
    // open — the record's vintage is the writing approver's, not this
    // client's.
    for (final legacyIv in [true, false]) {
      test(
          legacyIv
              ? 'a legacy record with no iv field opens under the zero IV'
              : 'a modern record opens under its stored IV', () async {
        String atSign = '@alice\ud83d\udee0';
        final apkamSymmetricKey = apkamSymmetricKeyMap[atSign]!;
        final encryptionPrivateKey = encryptionPrivateKeyMap[atSign]!;
        final selfEncryptionKey = aesKeyMap[atSign]!;

        final String? storedIvB64 =
            legacyIv ? null : base64Encode(List<int>.filled(16, 7));
        final iv = storedIvB64 == null
            ? AtChopsUtil.generateIVLegacy()
            : AtChopsUtil.generateIVFromBase64String(storedIvB64);

        AtChopsKeys atChopsKeys = AtChopsKeys.create(
            AtEncryptionKeyPair.create(
                encryptionPublicKeyMap[atSign]!, encryptionPrivateKey),
            AtPkamKeyPair.create(
                pkamPublicKeyMap[atSign]!, pkamPrivateKeyMap[atSign]!));
        atChopsKeys.apkamSymmetricKey = AESKey(apkamSymmetricKey);
        AtChopsImpl atChopsImpl = AtChopsImpl(atChopsKeys);

        Future<String> sealed(String value) async =>
            (await atChopsImpl.encryptString(value, EncryptionKeyType.aes256,
                    keyName: 'apkamSymmetricKey', iv: iv))
                .result;

        AtLookUp mockAtLookUp = MockAtLookUp();
        when(() => mockAtLookUp.pkamAuthenticate(enrollmentId: '123'))
            .thenAnswer((_) async => true);
        when(() => mockAtLookUp.executeCommand(
                any(
                    that: startsWith(
                        'keys:get:keyName:123.default_enc_private_key')),
                auth: any(named: 'auth')))
            .thenAnswer((_) async => 'data:${jsonEncode({
                  'value': await sealed(encryptionPrivateKey),
                  if (storedIvB64 != null) 'iv': storedIvB64,
                })}');
        when(() => mockAtLookUp.executeCommand(
                any(
                    that: startsWith(
                        'keys:get:keyName:123.default_self_enc_key')),
                auth: any(named: 'auth')))
            .thenAnswer((_) async => 'data:${jsonEncode({
                  'value': await sealed(selfEncryptionKey),
                  if (storedIvB64 != null) 'iv': storedIvB64,
                })}');

        final keys = AtKeys()
          ..apkamPublicKey = AtBytes.fromString(pkamPublicKeyMap[atSign]!)
          ..apkamPrivateKey = AtBytes.fromString(pkamPrivateKeyMap[atSign]!)
          ..defaultEncryptionPublicKey =
              AtBytes.fromString(encryptionPublicKeyMap[atSign]!)
          ..apkamSymmetricKey = AtBytes.fromString(apkamSymmetricKey);
        final response = AtEnrollmentResponse('123', EnrollmentStatus.approved,
            atSign: atSign,
            rootDomain: AtRootDomain.atsignDomain,
            atAuthKeys: keys);

        await AtEnrollmentImpl().waitForApproval(response,
            atLookup: mockAtLookUp,
            retryInterval: const Duration(milliseconds: 1),
            logProgress: false);

        expect(response.atAuthKeys!.defaultEncryptionPrivateKey!.toString(),
            encryptionPrivateKey);
        expect(response.atAuthKeys!.defaultSelfEncryptionKey!.toString(),
            selfEncryptionKey);
      });
    }
  });
}

class LookUpVerbBuilderMatcher extends Matcher {
  @override
  Description describe(Description description) {
    return description;
  }

  @override
  bool matches(item, Map matchState) {
    if (item is LookupVerbBuilder) {
      return true;
    }
    return false;
  }
}
