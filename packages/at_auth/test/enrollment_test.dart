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

    AtEnrollmentRequest requestWith(
            FutureOr<Map<String, dynamic>?> Function(AtKeysIo)? builder) =>
        AtEnrollmentRequest(
          session: AtAuthSession(
              atSign: atSign,
              rootDomain: AtRootDomain.atsignDomain,
              atKeysIo: InMemoryAtKeysIo()),
          appName: 'wavi',
          deviceName: 'pixel',
          namespaces: {'wavi': 'rw'},
          otp: 'A123FE',
          metadataBuilder: builder,
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
