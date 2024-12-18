import 'dart:convert';

import 'package:at_auth/src/enroll/at_enrollment_base.dart';
import 'package:at_auth/src/enroll/at_enrollment_impl.dart';
import 'package:at_auth/src/enroll/at_enrollment_response.dart';
import 'package:at_auth/src/enroll/enrollment_request.dart';
import 'package:at_auth/src/enroll/enrollment_request_decision.dart';
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
    AtEnrollmentImpl atEnrollmentServiceImpl = AtEnrollmentImpl(atSign);
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
            auth: true)).thenAnswer((_) => Future.value(jsonEncode({
          'value': atChopsImpl
              .encryptString(encryptionPrivateKey, EncryptionKeyType.aes256,
                  keyName: 'apkamSymmetricKey', iv: iv)
              .result
        })));

    when(() =>
        mockAtLookUp.executeCommand(
            any(
                that: startsWith(
                    'keys:get:keyName:123.${AtConstants.defaultSelfEncryptionKey}')),
            auth: true)).thenAnswer((_) => Future.value(jsonEncode({
          'value': atChopsImpl
              .encryptString(selfEncryptionKey, EncryptionKeyType.aes256,
                  keyName: 'apkamSymmetricKey', iv: iv)
              .result
        })));
    when(() => mockAtLookUp.pkamAuthenticate(enrollmentId: '123'))
        .thenAnswer((_) => Future.value(true));

    when(() => (mockAtLookUp as AtLookupImpl).close())
        .thenAnswer((_) async => ());

    EnrollmentRequest enrollmentRequest = EnrollmentRequest(
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

      AtEnrollmentBase atEnrollmentBase = AtEnrollmentImpl(atSign);

      when(() => mockAtLookUp.atChops).thenReturn(atChopsImpl);

      when(() =>
          mockAtLookUp.executeCommand(any(that: startsWith('enroll:approve')),
              auth: true)).thenAnswer((_) => Future.value('data:${jsonEncode({
                'status': 'approved',
                'enrollmentId': '4be2d358-074d-4e3b-99f3-64c4da01532f'
              })}'));

      EnrollmentRequestDecision enrollmentRequestDecision =
          EnrollmentRequestDecision.approved(ApprovedRequestDecisionBuilder(
              enrollmentId: '4be2d358-074d-4e3b-99f3-64c4da01532f',
              encryptedAPKAMSymmetricKey: encryptedAPKAMSymmetricKey));

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

      AtEnrollmentBase atEnrollmentBase = AtEnrollmentImpl(atSign);

      when(() => mockAtLookUp.atChops).thenReturn(atChopsImpl);

      when(() => mockAtLookUp
              .executeCommand(any(that: startsWith('enroll:deny')), auth: true))
          .thenAnswer((_) => Future.value('data:${jsonEncode({
                    'status': 'denied',
                    'enrollmentId': '4be2d358-074d-4e3b-99f3-64c4da01532f'
                  })}'));

      EnrollmentRequestDecision enrollmentRequestDecision =
          EnrollmentRequestDecision.denied(
              '4be2d358-074d-4e3b-99f3-64c4da01532f');

      AtEnrollmentResponse atEnrollmentResponse =
          await atEnrollmentBase.deny(enrollmentRequestDecision, mockAtLookUp);

      expect(atEnrollmentResponse.enrollmentId,
          '4be2d358-074d-4e3b-99f3-64c4da01532f');
      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.denied);
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
