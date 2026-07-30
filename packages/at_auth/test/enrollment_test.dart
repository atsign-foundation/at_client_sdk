import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/enroll/at_enrollment_impl.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:at_demo_data/at_demo_data.dart';

class MockAtLookUp extends Mock implements AtLookupImpl {}

class MockLookupVerbBuilder extends Fake implements LookupVerbBuilder {}

void main() {
  setUpAll(() {
    AtSignLogger.root_level = 'shout';
    registerFallbackValue(MockLookupVerbBuilder());
  });

  test(
      'A test to verify submitting enrollment to server and verify enrollment status is pending',
      () async {
    String atSign = '@alice🛠';
    AtEnrollmentImpl atEnrollmentServiceImpl = AtEnrollmentImpl();
    AtLookUp mockAtLookUp = MockAtLookUp();

    String? encryptionPublicKey = encryptionPublicKeyMap[atSign]!;
    String? encryptionPrivateKey = encryptionPrivateKeyMap[atSign]!;
    String? selfEncryptionKey = aesKeyMap[atSign]!;
    String? apkamSymmetricKey = apkamSymmetricKeyMap[atSign]!;

    // Stands in for the atServer, which stores these two keys encrypted under
    // the enrollment's APKAM symmetric key. This is the exact counterpart of
    // what waitForApproval decrypts with.
    final iv = InitialisationVector.legacy();
    final apkamAes = StringAESEncryptor(AESKey(apkamSymmetricKey));

    when(() => mockAtLookUp.executeVerb(any(that: LookUpVerbBuilderMatcher())))
        .thenAnswer((_) async => 'data:$encryptionPublicKey');

    when(() => mockAtLookUp.executeCommand(any(that: startsWith('enroll:'))))
        .thenAnswer((_) => Future.value('data:${jsonEncode({
                  'enrollmentId': '123',
                  'status': 'pending'
                })}'));

    when(() => mockAtLookUp.executeCommand(
        any(
            that: startsWith(
                'keys:get:keyName:123.${AtConstants.defaultEncryptionPrivateKey}')),
        auth:
            true)).thenAnswer((_) async => Future.value(
        jsonEncode({'value': apkamAes.encrypt(encryptionPrivateKey, iv: iv)})));

    when(() => mockAtLookUp.executeCommand(
        any(
            that: startsWith(
                'keys:get:keyName:123.${AtConstants.defaultSelfEncryptionKey}')),
        auth:
            true)).thenAnswer((_) async => Future.value(
        jsonEncode({'value': apkamAes.encrypt(selfEncryptionKey, iv: iv)})));
    when(() => mockAtLookUp.pkamAuthenticate(enrollmentId: '123'))
        .thenAnswer((_) => Future.value(true));

    when(() => (mockAtLookUp as AtLookupImpl).close())
        .thenAnswer((_) async => ());

    AtEnrollmentRequest enrollmentRequest = AtEnrollmentRequest(
        session: AtAuthSession(
          atsign: atSign.toAtsign(),
          rootDomain: AtRootDomain.atsignDomain,
          atKeysIo: EphemeralAtKeysIo(),
        ),
        appName: 'wavi',
        deviceName: 'pixel',
        otp: 'A123FE',
        namespaces: {'wavi': 'rw'});

    PendingEnrollment pending =
        await atEnrollmentServiceImpl.submit(enrollmentRequest, mockAtLookUp);
    expect(pending.enrollmentId, '123');
    expect(pending.enrollStatus, EnrollmentStatus.pending);
    // submit's return type guarantees the keys waitForApproval needs: the APKAM
    // keypair it signs with and the symmetric key it decrypts the server's
    // material with, both minted here.
    expect(pending.keys.apkamPrivateKey, isNotNull);
    expect(pending.keys.apkamPublicKey, isNotNull);
    expect(pending.keys.apkamSymmetricKey, isNotNull);
    expect(pending.keys.enrollmentId, '123');
  });

  group('A group of tests related EnrollmentRequestDecision', () {
    test('A test to verify the approve enrollment', () async {
      String atSign = '@alice🛠';

      String? encryptionPublicKey = encryptionPublicKeyMap[atSign]!;
      String? encryptionPrivateKey = encryptionPrivateKeyMap[atSign]!;
      String? selfEncryptionKey = aesKeyMap[atSign]!;
      String? apkamSymmetricKey = apkamSymmetricKeyMap[atSign]!;

      String encryptedAPKAMSymmetricKey =
          RSAPublicKey.fromString(encryptionPublicKey)
              .encrypt(apkamSymmetricKey);

      // The approver's own keys, reached the way everything else reaches keys:
      // through its session's AtKeysIo.
      AtKeys approverKeys = AtKeys(atsign: atSign.toAtsign())
        ..defaultEncryptionPrivateKey = AtBytes.fromString(encryptionPrivateKey)
        ..defaultSelfEncryptionKey = AtBytes.fromString(selfEncryptionKey);
      final approverIo = EphemeralAtKeysIo();
      await approverIo.write(atSign.toAtsign(), approverKeys);
      final approverSession = AtAuthSession(
        atsign: atSign.toAtsign(),
        rootDomain: AtRootDomain.atsignDomain,
        atKeysIo: approverIo,
      );

      AtLookUp mockAtLookUp = MockAtLookUp();

      AtEnrollment atEnrollmentBase = AtEnrollmentImpl();

      when(() =>
          mockAtLookUp.executeCommand(any(that: startsWith('enroll:approve')),
              auth: true)).thenAnswer((_) => Future.value('data:${jsonEncode({
                'status': 'approved',
                'enrollmentId': '4be2d358-074d-4e3b-99f3-64c4da01532f'
              })}'));

      EnrollmentApproval approval = EnrollmentRequestDecision.approved(
        enrollmentId: '4be2d358-074d-4e3b-99f3-64c4da01532f',
        encryptedApkamSymmetricKey: encryptedAPKAMSymmetricKey,
      );

      AtEnrollmentResponse atEnrollmentResponse =
          await atEnrollmentBase.approve(approval, approverSession);

      expect(atEnrollmentResponse.enrollmentId,
          '4be2d358-074d-4e3b-99f3-64c4da01532f');
      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.approved);
    });

    test('A test to verify the deny enrollment', () async {
      String atSign = '@alice🛠';

      // deny() only forwards the enrollmentId — no keys are read from the
      // session, but the response is scoped to it.
      final denySession = AtAuthSession(
        atsign: atSign.toAtsign(),
        rootDomain: AtRootDomain.atsignDomain,
        atKeysIo: EphemeralAtKeysIo(),
      );
      AtLookUp mockAtLookUp = MockAtLookUp();

      AtEnrollment atEnrollmentBase = AtEnrollmentImpl();

      when(() => mockAtLookUp
              .executeCommand(any(that: startsWith('enroll:deny')), auth: true))
          .thenAnswer((_) => Future.value('data:${jsonEncode({
                    'status': 'denied',
                    'enrollmentId': '4be2d358-074d-4e3b-99f3-64c4da01532f'
                  })}'));

      EnrollmentDenial denial = EnrollmentRequestDecision.denied(
          '4be2d358-074d-4e3b-99f3-64c4da01532f');

      AtEnrollmentResponse atEnrollmentResponse =
          await atEnrollmentBase.deny(denial, denySession);

      expect(atEnrollmentResponse.enrollmentId,
          '4be2d358-074d-4e3b-99f3-64c4da01532f');
      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.denied);
    });
  });

  group('AtEnrollmentResponse toJson / fromJson', () {
    AtAuthSession sessionFor(String atsign) => AtAuthSession(
          atsign: atsign.toAtsign(),
          rootDomain: AtRootDomain.atsignDomain,
          atKeysIo: EphemeralAtKeysIo(),
        );

    test('toJson includes enrollmentId, enrollStatus and the session atsign',
        () {
      final response = AtEnrollmentResponse(
        'enroll-123',
        EnrollmentStatus.approved,
        session: sessionFor('@alice'),
      );

      final json = response.toJson();

      expect(json['enrollmentId'], 'enroll-123');
      expect(json['enrollStatus'], 'approved');
      expect(json['atsign'], '@alice');
    });

    test('toJson excludes the session itself', () {
      // A session holds a live AtKeysIo (and later an open connection), so it
      // cannot cross a process boundary — only its atsign does.
      final response = AtEnrollmentResponse(
        'enroll-123',
        EnrollmentStatus.approved,
        session: sessionFor('@alice'),
      );

      expect(response.toJson().containsKey('session'), isFalse);
      expect(response.toJson().keys,
          unorderedEquals(['enrollmentId', 'enrollStatus', 'atsign']));
    });

    test('toJson excludes the pending keys', () {
      final pending = PendingEnrollment(
        'enroll-123',
        EnrollmentStatus.pending,
        session: sessionFor('@alice'),
        keys: AtKeys(atsign: '@alice'.toAtsign()),
      );

      expect(pending.toJson().containsKey('keys'), isFalse);
    });

    test('fromJson restores enrollmentId and enrollStatus', () {
      final json = {
        'enrollmentId': 'enroll-456',
        'enrollStatus': 'denied',
      };

      final response =
          AtEnrollmentResponse.fromJson(json, session: sessionFor('@alice'));

      expect(response.enrollmentId, 'enroll-456');
      expect(response.enrollStatus, EnrollmentStatus.denied);
    });

    test('fromJson takes the session from the caller, not the json', () {
      final session = sessionFor('@alice');
      final json = {
        'enrollmentId': 'enroll-456',
        'enrollStatus': 'pending',
        // Even a json that names a different atsign does not get a say.
        'atsign': '@bob',
      };

      final response = AtEnrollmentResponse.fromJson(json, session: session);

      expect(response.session, same(session));
      expect(response.session.atsign, '@alice'.toAtsign());
    });

    test('fromJson throws when enrollStatus is unknown', () {
      final json = {
        'enrollmentId': 'enroll-456',
        'enrollStatus': 'invalidStatus',
      };

      expect(
        () =>
            AtEnrollmentResponse.fromJson(json, session: sessionFor('@alice')),
        throwsA(isA<StateError>()),
      );
    });

    test('fromJson throws when enrollmentId is missing', () {
      final json = {'enrollStatus': 'approved'};

      expect(
        () =>
            AtEnrollmentResponse.fromJson(json, session: sessionFor('@alice')),
        throwsA(anything),
      );
    });
  });

  group('AtEnrollmentRequest session wiring', () {
    test('session is the source of atSign and rootDomain', () {
      final session = AtAuthSession(
        atsign: '@alice🛠'.toAtsign(),
        rootDomain: const AtRootDomain('root.atsign.org', 64),
        atKeysIo: EphemeralAtKeysIo(),
      );

      final request = AtEnrollmentRequest(
        session: session,
        appName: 'wavi',
        deviceName: 'pixel',
        otp: 'A123FE',
        namespaces: {'wavi': 'rw'},
      );

      expect(request.session, same(session));
      expect(request.atsign, '@alice🛠');
      expect(request.rootDomain, same(session.rootDomain));
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
